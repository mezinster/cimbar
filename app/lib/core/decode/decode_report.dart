import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import 'diagnostics.dart';
import 'golden_sidecar.dart';

class TruthComparison {
  final int cells;
  final int symbolCorrect;
  final int colorCorrect;
  final int cellCorrect;
  final List<int> wrongCellIndices;
  const TruthComparison(this.cells, this.symbolCorrect, this.colorCorrect, this.cellCorrect, this.wrongCellIndices);
  double get symbolAccuracy => symbolCorrect / cells;
  double get colorAccuracy => colorCorrect / cells;
  double get cellAccuracy => cellCorrect / cells;
}

/// Structured `frame=N stage=… key=value` lines and ground-truth comparison.
class DecodeReport {
  DecodeReport._();

  static TruthComparison compare(Uint8List cells, Uint8List truth) {
    var sym = 0, col = 0, both = 0;
    final wrong = <int>[];
    for (var k = 0; k < truth.length; k++) {
      final s = BitPacking.cellSymbol(cells[k]) == BitPacking.cellSymbol(truth[k]);
      final c = BitPacking.cellColor(cells[k]) == BitPacking.cellColor(truth[k]);
      if (s) sym++;
      if (c) col++;
      if (s && c) {
        both++;
      } else {
        wrong.add(k);
      }
    }
    return TruthComparison(truth.length, sym, col, both, wrong);
  }

  static String _kv(Map<String, String> m) => m.entries.map((e) => '${e.key}=${e.value}').join(' ');

  static List<String> lines(FrameResult r, {int frameIndex = 0, GoldenFrame? truth}) {
    final d = r.diag.toMap();
    final out = <String>[];
    final p = 'frame=$frameIndex';
    if (r.diag.locateRan) {
      out.add('$p stage=locate ${_kv({
            'ok': '${r.diag.locateFail.isEmpty}',
            'candidates': d['candidates']!,
            'clusters': d['clusters']!,
            'module': d['module']!,
            'corners': d['corners']!,
            'tlLuma': d['tlLuma']!,
            'secondLuma': d['secondLuma']!,
            'devNorm': d['devNorm']!,
            'locateMs': d['locateMs']!,
            if (r.diag.locateFail.isNotEmpty) 'fail': r.diag.locateFail,
          })}');
      if (r.diag.locateFail.isEmpty) {
        out.add('$p stage=grid estimate=${d['gridEstimate']}');
        out.add('$p stage=wb rgb=${d['wb']}');
      }
    }
    if (r.diag.driftUsed) {
      out.add('$p stage=drift ${_kv({
            'meanAbs': d['driftMeanAbs']!,
            'maxAbs': d['driftMaxAbs']!,
            'widened': d['driftWidened']!,
            'driftMs': d['driftMs']!,
          })}');
    }
    // nothing was sampled (e.g. notLocated / unsupportedGrid before cells ran)
    if (r.diag.rsBlocks > 0 || r.cells != null) {
      out.add('$p stage=cells ${_kv({
            'hammingMax': d['hammingMax']!,
            'hammingMean': d['hammingMean']!,
            'hammingHist': d['hammingHist']!,
            'colorMarginMin': d['colorMarginMin']!,
            'sampleMs': d['sampleMs']!,
          })}');
      out.add('$p stage=rs ${_kv({'blocks': d['rsBlocks']!, 'ok': d['rsOk']!, 'failed': d['rsFailed']!, 'rsMs': d['rsMs']!})}');
    }
    final h = r.header;
    if (h != null && r.diag.headerReason.isEmpty && r.status != DecodeStatus.rsFailed) {
      out.add('$p stage=header ${_kv({
            'valid': 'true',
            'version': '${h.version}',
            'fileId': '0x${h.fileId.toRadixString(16)}',
            'seq': '${h.seq}',
            'total': '${h.total}',
            'encrypted': '${h.encrypted}',
          })}');
    } else {
      out.add('$p stage=header valid=false reason=${r.diag.headerReason.isEmpty ? '-' : r.diag.headerReason}');
    }
    out.add('$p stage=result status=${r.status.name}${r.diag.note.isEmpty ? '' : ' note=${r.diag.note}'}');
    if (truth != null && r.cells != null) {
      final c = compare(r.cells!, truth.cells);
      out.add('$p stage=truth ${_kv({
            'symbolAcc': c.symbolAccuracy.toStringAsFixed(3),
            'colorAcc': c.colorAccuracy.toStringAsFixed(3),
            'cellAcc': c.cellAccuracy.toStringAsFixed(3),
            'wrongCells': '${c.wrongCellIndices.length}',
          })}');
    }
    return out;
  }

  /// 608x608 image: correct cells gray, wrong symbol red, wrong color blue, both magenta.
  static img.Image heatmap(Uint8List cells, Uint8List truth) {
    final im = img.Image(width: CimbarSpec.framePx, height: CimbarSpec.framePx);
    final positions = CimbarSpec.usableCellPositions;
    for (var k = 0; k < positions.length; k++) {
      final s = BitPacking.cellSymbol(cells[k]) == BitPacking.cellSymbol(truth[k]);
      final c = BitPacking.cellColor(cells[k]) == BitPacking.cellColor(truth[k]);
      final r = s ? (c ? 96 : 0) : 230;
      final g = s && c ? 96 : 0;
      final b = c ? (s ? 96 : 0) : 230;
      final ox = CimbarSpec.cellOriginX(positions[k].col), oy = CimbarSpec.cellOriginY(positions[k].row);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          im.setPixelRgb(ox + x, oy + y, r, g, b);
        }
      }
    }
    return im;
  }
}
