import 'dart:math' as math;
import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import '../format/rs_framing.dart';
import '../services/reed_solomon.dart';
import 'cell_classifier.dart';
import 'cell_sampler.dart';
import 'diagnostics.dart';
import 'drift_solver.dart';
import 'finder_locator.dart';
import 'grid_model.dart';
import 'homography.dart';
import 'luma_plane.dart';
import 'rgb_buffer.dart';
import 'white_point.dart';

/// The single v2 frame decoder (spec §6.1). GIF paths call [decodeExact];
/// camera paths call [decode], which locates the finders, fits a homography
/// grid, white-balances from the finder cores and decodes the cells.
class FrameDecoder {
  final ReedSolomon _rs = ReedSolomon(CimbarSpec.rsEccBytes);
  final CellClassifier _classifier = CellClassifier();
  final FinderLocator locator;

  // no supported grid size lies within ±10 of 64
  static const int gridTolerance = 10;

  FrameDecoder({this.locator = const FinderLocator()});

  FrameResult decode(RgbBuffer image, {GridModel? grid, bool? useDrift}) {
    final drift = useDrift ?? (grid == null);
    if (grid != null) return decodeWithGrid(image, grid, useDrift: drift);
    final diag = Diagnostics()..locateRan = true;
    final sw = Stopwatch()..start();
    final luma = LumaPlane.fromRgb(image);
    final loc = locator.locate(luma);
    diag.locateMs = sw.elapsedMilliseconds;
    diag.candidates = loc.candidates;
    diag.clusters = loc.clusters;
    diag.devNorm = loc.devNorm;
    diag.tlLuma = loc.tlLuma;
    diag.secondLuma = loc.secondLuma;
    if (!loc.ok) {
      diag.locateFail = loc.failReason;
      return FrameResult(status: DecodeStatus.notLocated, diag: diag..note = loc.failReason);
    }
    final tl = loc.tl!, tr = loc.tr!, bl = loc.bl!, br = loc.br!;
    diag.corners = Float64List.fromList([tl.x, tl.y, tr.x, tr.y, bl.x, bl.y, br.x, br.y]);
    diag.module = loc.module;

    final gm = HomographyGridModel.fromFinders(tl: (tl.x, tl.y), tr: (tr.x, tr.y), bl: (bl.x, bl.y), br: (br.x, br.y));
    if (gm == null) {
      diag.locateFail = 'homography singular';
      return FrameResult(status: DecodeStatus.notLocated, diag: diag..note = diag.locateFail);
    }
    // keystone compresses opposite sides oppositely; averaging all four
    // sides cancels it to first order
    final side = (_dist(tl, tr) + _dist(bl, br) + _dist(tl, bl) + _dist(tr, br)) / 4;
    final estimate = (side / loc.module).round() + CimbarSpec.finderCells;
    diag.gridEstimate = estimate;
    if ((estimate - CimbarSpec.gridCells).abs() > gridTolerance) {
      return FrameResult(status: DecodeStatus.unsupportedGrid, diag: diag..note = 'grid estimate $estimate cells (supported: ${CimbarSpec.gridCells})');
    }
    final wp = WhitePoint.fromFinders(image, gm);
    diag.whitePoint = wp;
    return decodeWithGrid(image, gm, whitePoint: wp, useDrift: drift, luma: luma, diag: diag);
  }

  static double _dist(Finder a, Finder b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  FrameResult decodeExact(RgbBuffer image) {
    const size = CimbarSpec.framePx;
    if (image.width != size || image.height != size) {
      return FrameResult(
        status: DecodeStatus.unsupportedGrid,
        diag: Diagnostics()
          ..note = 'expected ${size}x$size, got ${image.width}x${image.height} (v1 GIF?)',
      );
    }
    return decodeWithGrid(image, const ExactGridModel());
  }

  FrameResult decodeWithGrid(
    RgbBuffer image,
    GridModel grid, {
    List<double>? whitePoint,
    bool useDrift = false,
    LumaPlane? luma,
    Diagnostics? diag,
  }) {
    final d = diag ?? Diagnostics();
    final sw = Stopwatch()..start();
    final sampler = CellSampler(image, grid, luma: luma);
    final patch = CellPatch();
    final positions = CimbarSpec.usableCellPositions;
    final cells = Uint8List(positions.length);
    var hammingSum = 0;
    DriftField? drift;
    if (useDrift) {
      final lp = luma ?? LumaPlane.fromRgb(image);
      final dsw = Stopwatch()..start();
      drift = DriftSolver(CellSampler(image, grid, luma: lp), _classifier).solve();
      d.driftUsed = true;
      d.driftMs = dsw.elapsedMilliseconds;
      d.driftMeanAbs = drift.meanAbs;
      d.driftMaxAbs = drift.maxAbs;
      d.driftWidened = drift.widened;
    } else {
      d.driftUsed = false;
    }
    for (var k = 0; k < positions.length; k++) {
      final pos = positions[k];
      if (drift != null) {
        final idx = pos.row * CimbarSpec.gridCells + pos.col;
        sampler.sample(pos.col, pos.row, patch, dx: drift.dx[idx], dy: drift.dy[idx]);
      } else {
        sampler.sample(pos.col, pos.row, patch);
      }
      final c = _classifier.classify(patch, whitePoint: whitePoint);
      cells[k] = BitPacking.cellValue(c.symbol, c.color);
      hammingSum += c.hamming;
      d.addHamming(c.hamming);
      if (c.colorMargin < d.colorMarginMin) d.colorMarginMin = c.colorMargin;
    }
    d.hammingMean = hammingSum / positions.length;
    d.sampleMs = sw.elapsedMilliseconds;

    sw.reset();
    final raw = BitPacking.unpackCells(cells);
    final rs = RsFraming.decodeFrame(raw, _rs);
    d.rsMs = sw.elapsedMilliseconds;
    d.rsBlocks = rs.blocksOk + rs.blocksFailed;
    d.rsOk = rs.blocksOk;
    d.rsFailed = rs.blocksFailed;
    if (rs.blocksFailed > 0) {
      return FrameResult(status: DecodeStatus.rsFailed, diag: d, cells: cells, raw: raw, data: rs.data);
    }
    final hd = FrameHeader.decode(rs.data);
    if (!hd.valid) {
      d.headerReason = hd.reason;
      return FrameResult(status: DecodeStatus.badHeader, diag: d, cells: cells, raw: raw, data: rs.data, header: hd.header);
    }
    return FrameResult(status: DecodeStatus.ok, diag: d, cells: cells, raw: raw, data: rs.data, header: hd.header);
  }
}
