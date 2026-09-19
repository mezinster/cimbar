import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/cell_classifier.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/tiles.dart';

void main() {
  test('fromRgb uses BT.601 integer weights', () {
    final buf = RgbBuffer(3, 1, Uint8List.fromList([255, 255, 255, 0, 0, 0, 0, 255, 0]));
    final l = LumaPlane.fromRgb(buf);
    expect(l.width, 3);
    expect(l.at(0, 0), 255);
    expect(l.at(1, 0), 0);
    expect(l.at(2, 0), (150 * 255) >> 8);
  });

  test('downscale2 averages 2x2 blocks and floors odd sizes', () {
    final l = LumaPlane(5, 2, Uint8List.fromList([0, 100, 200, 200, 9, 0, 100, 200, 200, 9]));
    final d = l.downscale2();
    expect(d.width, 2);
    expect(d.height, 1);
    expect(d.at(0, 0), 50);
    expect(d.at(1, 0), 200);
  });

  test('bilinear is exact at centers and clamps at edges', () {
    final l = LumaPlane(2, 1, Uint8List.fromList([0, 200]));
    expect(l.bilinear(1.5, 0.5), 200);
    expect(l.bilinear(1.0, 0.5), closeTo(100, 1e-6));
    expect(l.bilinear(-5, -5), 0);
    expect(l.bilinear(50, 50), 200);
  });

  test('mean3x3 clamps at the corner', () {
    final l = LumaPlane(2, 2, Uint8List.fromList([10, 20, 30, 40]));
    expect(l.mean3x3(0, 0), closeTo((10 * 4 + 20 * 2 + 30 * 2 + 40) / 9, 1e-6));
  });

  test('sampleLuma through a LumaPlane matches the RGB path and bestSymbol is exact', () {
    final im = img.Image(width: CimbarSpec.framePx, height: CimbarSpec.framePx);
    final t = Tiles.bits[11];
    final ox = CimbarSpec.cellOriginX(8), oy = CimbarSpec.cellOriginY(0);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (t[y * 8 + x] == 1) im.setPixelRgb(ox + x, oy + y, 0, 255, 255);
      }
    }
    final rgb = RgbBuffer.fromImage(im);
    final luma = LumaPlane.fromRgb(rgb);
    final viaLuma = CellSampler(rgb, const ExactGridModel(), luma: luma);
    final viaRgb = CellSampler(rgb, const ExactGridModel());
    final a = Float32List(64), b = Float32List(64);
    viaLuma.sampleLuma(8, 0, a);
    viaRgb.sampleLuma(8, 0, b);
    for (var p = 0; p < 64; p++) {
      expect((a[p] > 100), t[p] == 1, reason: 'luma path pixel $p');
      expect((a[p] - b[p]).abs() < 2, isTrue, reason: 'paths agree within rounding at $p');
    }
    final (sym, ham) = CellClassifier().bestSymbol(a);
    expect(sym, 11);
    expect(ham, 0);
    // shifting by one pixel must raise the distance (drift search relies on this)
    viaLuma.sampleLuma(8, 0, a, dx: 1);
    final (_, ham2) = CellClassifier().bestSymbol(a);
    expect(ham2 > 0, isTrue, reason: 'shifted hamming $ham2');
  });
}
