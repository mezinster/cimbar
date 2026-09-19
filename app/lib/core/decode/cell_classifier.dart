import 'dart:math' as math;
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/tiles.dart';
import 'cell_sampler.dart';

class CellClassification {
  final int symbol;
  final int hamming;
  final int color;
  final double colorMargin;
  const CellClassification(this.symbol, this.hamming, this.color, this.colorMargin);
}

/// Symbol by average hash + Hamming distance to the 16 tiles; color by
/// brightness-normalized chroma over the winning tile's lit pixels (spec §6.6–6.7).
/// Note: colorMargin is in normalized-chroma units (palette entries are ≥1.41
/// apart), not RGB units like the JS exact path's diagnostic.
class CellClassifier {
  late final List<List<double>> _paletteChroma;

  CellClassifier() {
    _paletteChroma = [
      for (final c in CimbarSpec.palette) _chroma(c[0].toDouble(), c[1].toDouble(), c[2].toDouble()),
    ];
  }

  static List<double> _chroma(double r, double g, double b) {
    final m = math.max(1.0, math.max(r, math.max(g, b)));
    return [(r - g) / m, (g - b) / m, (b - r) / m];
  }

  /// Symbol-only classification of a 64-entry luma patch: (symbol, hamming).
  (int, int) bestSymbol(Float32List luma) {
    var mean = 0.0;
    for (var i = 0; i < 64; i++) {
      mean += luma[i];
    }
    mean /= 64;
    var bestSym = 0, bestDist = 65;
    for (var s = 0; s < 16; s++) {
      final t = Tiles.bits[s];
      var d = 0;
      for (var i = 0; i < 64; i++) {
        d += ((luma[i] > mean) ? 1 : 0) ^ t[i];
      }
      if (d < bestDist) {
        bestDist = d;
        bestSym = s;
      }
    }
    return (bestSym, bestDist);
  }

  CellClassification classify(CellPatch p, {List<double>? whitePoint}) {
    final (bestSym, bestDist) = bestSymbol(p.luma);
    final t = Tiles.bits[bestSym];
    var r = 0.0, g = 0.0, b = 0.0, n = 0;
    for (var i = 0; i < 64; i++) {
      if (t[i] == 1) {
        r += p.rgb[i * 3];
        g += p.rgb[i * 3 + 1];
        b += p.rgb[i * 3 + 2];
        n++;
      }
    }
    if (n > 0) {
      r /= n;
      g /= n;
      b /= n;
    }
    if (whitePoint != null) {
      r = r * 255 / math.max(1.0, whitePoint[0]);
      g = g * 255 / math.max(1.0, whitePoint[1]);
      b = b * 255 / math.max(1.0, whitePoint[2]);
    }
    final ch = _chroma(r, g, b);
    var bestC = 0;
    var bestD = double.infinity, secondD = double.infinity;
    for (var c = 0; c < _paletteChroma.length; c++) {
      final pc = _paletteChroma[c];
      final dd = (ch[0] - pc[0]) * (ch[0] - pc[0]) + (ch[1] - pc[1]) * (ch[1] - pc[1]) + (ch[2] - pc[2]) * (ch[2] - pc[2]);
      if (dd < bestD) {
        secondD = bestD;
        bestD = dd;
        bestC = c;
      } else if (dd < secondD) {
        secondD = dd;
      }
    }
    return CellClassification(bestSym, bestDist, bestC, math.sqrt(secondD) - math.sqrt(bestD));
  }
}
