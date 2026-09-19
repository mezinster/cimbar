import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/cell_classifier.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/tiles.dart';

CellPatch patchFor(int sym, List<int> color, {double scale = 1.0}) {
  final p = CellPatch();
  final t = Tiles.bits[sym];
  for (var i = 0; i < 64; i++) {
    final lit = t[i] == 1;
    final r = lit ? color[0] * scale : 0.0;
    final g = lit ? color[1] * scale : 0.0;
    final b = lit ? color[2] * scale : 0.0;
    p.rgb[i * 3] = r;
    p.rgb[i * 3 + 1] = g;
    p.rgb[i * 3 + 2] = b;
    p.luma[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }
  return p;
}

void main() {
  final c = CellClassifier();

  test('all 64 symbol/color combinations classify exactly', () {
    for (var s = 0; s < 16; s++) {
      for (var k = 0; k < 4; k++) {
        final r = c.classify(patchFor(s, CimbarSpec.palette[k]));
        expect(r.symbol, s, reason: 'sym $s color $k');
        expect(r.color, k, reason: 'sym $s color $k');
        expect(r.hamming, 0);
        expect(r.colorMargin > 0.3, isTrue);
      }
    }
  });

  test('dimmed cells still classify (chroma is brightness-normalized)', () {
    for (var k = 0; k < 4; k++) {
      final r = c.classify(patchFor(3, CimbarSpec.palette[k], scale: 0.4));
      expect(r.color, k);
      expect(r.symbol, 3);
    }
  });

  test('white point rescales channels before chroma', () {
    // A strong blue deficit (blue x0.3) turns cyan (0,255,255) into (0,255,77),
    // whose chroma is closer to green than to cyan without white balance.
    final p = patchFor(7, [0, 255, 77]);
    expect(c.classify(p).color, 0, reason: 'without WB the cast reads as green');
    final r = c.classify(p, whitePoint: [255, 255, 77]);
    expect(r.color, 1, reason: 'with WB it reads as cyan');
    expect(r.symbol, 7);
  });

  test('a flipped-bit patch still finds the nearest tile with hamming > 0', () {
    final p = patchFor(9, CimbarSpec.palette[2]);
    p.luma[0] = p.luma[0] > 100 ? 0 : 255;
    p.luma[1] = p.luma[1] > 100 ? 0 : 255;
    final r = c.classify(p);
    expect(r.symbol, 9);
    expect(r.hamming, 2);
  });
}
