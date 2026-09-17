import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import '../format/rs_framing.dart';
import '../services/reed_solomon.dart';
import 'cell_classifier.dart';
import 'cell_sampler.dart';
import 'diagnostics.dart';
import 'grid_model.dart';
import 'rgb_buffer.dart';

/// The single v2 frame decoder (spec §6.1). GIF paths call [decodeExact];
/// camera paths call [decode] and (from Plan 3) get a located grid model.
class FrameDecoder {
  final ReedSolomon _rs = ReedSolomon(CimbarSpec.rsEccBytes);
  final CellClassifier _classifier = CellClassifier();

  FrameResult decode(RgbBuffer image, {GridModel? grid}) {
    if (grid == null) {
      return FrameResult(
        status: DecodeStatus.notLocated,
        diag: Diagnostics()..note = 'locator not implemented (Plan 3)',
      );
    }
    return decodeWithGrid(image, grid);
  }

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

  FrameResult decodeWithGrid(RgbBuffer image, GridModel grid, {List<double>? whitePoint}) {
    final diag = Diagnostics();
    final sw = Stopwatch()..start();
    final sampler = CellSampler(image, grid);
    final patch = CellPatch();
    final positions = CimbarSpec.usableCellPositions;
    final cells = Uint8List(positions.length);
    var hammingSum = 0;
    for (var k = 0; k < positions.length; k++) {
      final pos = positions[k];
      sampler.sample(pos.col, pos.row, patch);
      final c = _classifier.classify(patch, whitePoint: whitePoint);
      cells[k] = BitPacking.cellValue(c.symbol, c.color);
      hammingSum += c.hamming;
      diag.addHamming(c.hamming);
      if (c.colorMargin < diag.colorMarginMin) diag.colorMarginMin = c.colorMargin;
    }
    diag.hammingMean = hammingSum / positions.length;
    diag.sampleMs = sw.elapsedMilliseconds;

    sw.reset();
    final raw = BitPacking.unpackCells(cells);
    final rs = RsFraming.decodeFrame(raw, _rs);
    diag.rsMs = sw.elapsedMilliseconds;
    diag.rsBlocks = rs.blocksOk + rs.blocksFailed;
    diag.rsOk = rs.blocksOk;
    diag.rsFailed = rs.blocksFailed;
    if (rs.blocksFailed > 0) {
      return FrameResult(status: DecodeStatus.rsFailed, diag: diag, cells: cells, raw: raw, data: rs.data);
    }

    final hd = FrameHeader.decode(rs.data);
    if (!hd.valid) {
      diag.headerReason = hd.reason;
      return FrameResult(status: DecodeStatus.badHeader, diag: diag, cells: cells, raw: raw, data: rs.data, header: hd.header);
    }
    return FrameResult(status: DecodeStatus.ok, diag: diag, cells: cells, raw: raw, data: rs.data, header: hd.header);
  }
}
