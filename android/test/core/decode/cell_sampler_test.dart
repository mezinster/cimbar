import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/tiles.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

String repoPath(String rel) => '../$rel';

void main() {
  test('RgbBuffer.fromImage copies pixels and clamps at edges', () {
    final im = img.Image(width: 4, height: 3);
    im.setPixelRgb(1, 2, 10, 20, 30);
    final buf = RgbBuffer.fromImage(im);
    expect(buf.width, 4);
    expect(buf.height, 3);
    expect([buf.r(1, 2), buf.g(1, 2), buf.b(1, 2)], [10, 20, 30]);
    expect(buf.r(0, 0), 0);
  });

  test('RgbBuffer.fromImage bulk path reproduces every channel of a non-paletted image', () {
    final im = img.Image(width: 3, height: 2);
    var v = 0;
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        im.setPixelRgb(x, y, v, v + 1, v + 2);
        v += 3;
      }
    }
    expect(im.hasPalette, isFalse);
    final buf = RgbBuffer.fromImage(im);
    v = 0;
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        expect([buf.r(x, y), buf.g(x, y), buf.b(x, y)], [v, v + 1, v + 2], reason: '($x,$y)');
        v += 3;
      }
    }
  });

  test('RgbBuffer.fromImage on a paletted GIF frame still decodes with hammingMax 0', () {
    final jsonPath = repoPath('test-data/goldens/hello.json');
    final golden = GoldenSidecar.load(jsonPath);
    final frame = GifParser.parseFrames(File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync()).first;
    expect(frame.hasPalette, isTrue, reason: 'this test guards the palette->RGB expansion branch');
    final buf = RgbBuffer.fromImage(frame);
    final r = FrameDecoder().decodeExact(buf);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.diag.hammingMax, 0);
    expect(r.cells, golden.frames[0].cells);
  });

  test('bilinear at a pixel center is exact; halfway blends', () {
    final im = img.Image(width: 2, height: 1);
    im.setPixelRgb(0, 0, 0, 0, 0);
    im.setPixelRgb(1, 0, 200, 100, 50);
    final buf = RgbBuffer.fromImage(im);
    final out = Float32List(3);
    buf.bilinear(1.5, 0.5, out, 0);
    expect(out, [200, 100, 50]);
    buf.bilinear(1.0, 0.5, out, 0);
    expect(out[0], closeTo(100, 0.01));
    expect(out[2], closeTo(25, 0.01));
  });

  test('ExactGridModel maps cell units to quiet + pitch * units', () {
    const g = ExactGridModel();
    expect(g.toSource(0, 0), (16.0, 16.0));
    expect(g.toSource(3.5, 3.5), (47.5, 47.5));
    expect(g.toSource(8, 1), (88.0, 25.0));
  });

  test('CellSampler reads an exact tile rendered at cell (8,0)', () {
    final im = img.Image(width: CimbarSpec.framePx, height: CimbarSpec.framePx);
    final t = Tiles.bits[5];
    final ox = CimbarSpec.cellOriginX(8), oy = CimbarSpec.cellOriginY(0);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (t[y * 8 + x] == 1) im.setPixelRgb(ox + x, oy + y, 255, 255, 0);
      }
    }
    final sampler = CellSampler(RgbBuffer.fromImage(im), const ExactGridModel());
    final patch = CellPatch();
    sampler.sample(8, 0, patch);
    for (var p = 0; p < 64; p++) {
      final lit = t[p] == 1;
      expect(patch.rgb[p * 3], lit ? 255 : 0, reason: 'r at $p');
      expect(patch.rgb[p * 3 + 1], lit ? 255 : 0, reason: 'g at $p');
      expect(patch.rgb[p * 3 + 2], 0, reason: 'b at $p');
      expect(patch.luma[p] > 100, lit, reason: 'luma at $p');
    }
  });
}
