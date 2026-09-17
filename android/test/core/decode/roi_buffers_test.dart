import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final frame = loadGoldenFrame('hello', 0);
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));

  // NOTE ON INPUT CHOICE: the raw `hello` golden is not used here. Its cells
  // are drawn from a genuine 2x2-pixel "module" (every cell-local 2x2 block
  // is internally uniform), and quietPx (16, even) + pitchPx (9, odd) means
  // module boundaries straddle the absolute 4:2:0 chroma grid for about half
  // of all cells — an unavoidable, large per-pixel chroma-bleed under ANY
  // box-average 4:2:0 encoder applied to that pixel-perfect, hard-edged
  // pattern (real camera captures don't hit this: optics low-pass filter
  // edges before YUV subsampling). A slowly-varying gradient is what the
  // round trip is actually meant to certify.
  final gradient = _gradientImage(256, 256);
  test('rgbToYuv420 round-trips within ±4 through fromYuv420 (planar and semi-planar, padded)', () {
    for (final semi in [false, true]) {
      final yuv = rgbToYuv420(gradient, semiPlanar: semi, yPad: 16);
      expect(yuv.yRowStride, gradient.width + 16);
      final back = RgbBuffer.fromYuv420(yuv);
      expect(back.width, gradient.width);
      var maxErr = 0;
      for (var i = 0; i < back.rgb.length; i++) {
        final e = (back.rgb[i] - gradient.rgb[i]).abs();
        if (e > maxErr) maxErr = e;
      }
      expect(maxErr, lessThanOrEqualTo(4), reason: 'semiPlanar=$semi maxErr=$maxErr');
    }
  });

  test('ROI conversion carries an origin and bilinear reads absolute coordinates', () {
    final yuv = rgbToYuv420(frame);
    final roi = RgbBuffer.fromYuv420(yuv, x0: 100, y0: 50, w: 200, h: 120);
    expect(roi.width, 200);
    expect(roi.originX, 100);
    expect(roi.originY, 50);
    final out = Float32List(3);
    roi.bilinear(100 + 10.5, 50 + 20.5, out, 0);
    expect(out[0], closeTo(frame.r(110, 70), 3));
    expect(out[1], closeTo(frame.g(110, 70), 3));
    // ROI clamps at the frame edge
    final edge = RgbBuffer.fromYuv420(yuv, x0: 600, y0: 600, w: 100, h: 100);
    expect(edge.width, 8);
    expect(edge.height, 8);
  });

  test('LumaPlane.fromYPlane honours rowStride; crop keeps an origin; bilinear is absolute', () {
    final yuv = rgbToYuv420(frame, yPad: 8);
    final l = LumaPlane.fromYPlane(yuv.yPlane, width: yuv.width, height: yuv.height, rowStride: yuv.yRowStride);
    expect(l.width, frame.width);
    expect(l.at(16, 16), greaterThan(240)); // TL finder outer ring
    final c = l.crop(10, 20, 100, 50);
    expect(c.originX, 10);
    expect(c.at(6, 0), l.at(16, 20));
    expect(c.bilinear(16.5, 20.5), closeTo(l.bilinear(16.5, 20.5), 1e-6));
  });

  test('corner-interpolated sampling stays exact on a golden frame (RGB and luma)', () {
    final r = FrameDecoder().decodeExact(frame);
    expect(r.status, DecodeStatus.ok);
    expect(r.diag.hammingMax, 0);
    expect(r.cells, golden.frames[0].cells);
    final luma = LumaPlane.fromRgb(frame);
    final s = CellSampler(frame, const ExactGridModel(), luma: luma);
    final a = Float32List(64);
    s.sampleLuma(8, 0, a);
    final p = CellPatch();
    s.sample(8, 0, p);
    for (var i = 0; i < 64; i++) {
      expect((a[i] - p.luma[i]).abs(), lessThan(2));
    }
  });

  test('decoding through an ROI buffer equals decoding the full buffer', () {
    final scene = renderScene(frame, 900, 900, SceneSpec()..centerX = 450..centerY = 450..scale = 1.2);
    final yuv = rgbToYuv420(scene.image);
    final full = FrameDecoder().decode(RgbBuffer.fromYuv420(yuv), useDrift: false);
    expect(full.status, DecodeStatus.ok, reason: '${full.diag.toMap()}');
    // ROI = finder bbox ± pad, decoded with the same grid model the full decode found.
    // Finder CENTERS bound the finder cores, but usable data cells start at
    // col/row 8 (finders reserve an 8-cell corner block centered at 3.5) —
    // i.e. up to 4.5 cells, plus the corner-interpolated tile reach (8/9
    // cell), beyond each finder center toward the frame edge. A flat 20 px
    // pad is only enough at small module sizes; scale module by the decode's
    // own module estimate so the ROI actually covers all usable cells.
    final pad = 6 * full.diag.module;
    final c = full.diag.corners!;
    final xs = [c[0], c[2], c[4], c[6]], ys = [c[1], c[3], c[5], c[7]];
    final x0 = (xs.reduce((a, b) => a < b ? a : b) - pad).floor(), y0 = (ys.reduce((a, b) => a < b ? a : b) - pad).floor();
    final x1 = (xs.reduce((a, b) => a > b ? a : b) + pad).ceil(), y1 = (ys.reduce((a, b) => a > b ? a : b) + pad).ceil();
    final roi = RgbBuffer.fromYuv420(yuv, x0: x0, y0: y0, w: x1 - x0, h: y1 - y0);
    final gm = HomographyGridModelFromDiag.build(c)!;
    // The full decode applied a white point sampled from the finders; pass
    // the same one here so this test isolates ROI equivalence (not WB) —
    // matching what the full decode would compute for this ROI anyway,
    // since the finder cores lie inside it.
    final viaRoi = FrameDecoder().decodeWithGrid(
      roi,
      gm,
      useDrift: false,
      luma: LumaPlane.fromYPlane(yuv.yPlane, width: yuv.width, height: yuv.height, rowStride: yuv.yRowStride),
      whitePoint: full.diag.whitePoint,
    );
    expect(viaRoi.status, DecodeStatus.ok, reason: '${viaRoi.diag.toMap()}');
    expect(viaRoi.data, full.data);
  });
}

/// Test helper: rebuild the grid model from the corners a decode reported.
class HomographyGridModelFromDiag {
  static GridModel? build(Float64List c) => HomographyGridModel.fromFinders(
        tl: (c[0], c[1]), tr: (c[2], c[3]), bl: (c[4], c[5]), br: (c[6], c[7]),
      );
}

/// A slowly-varying r=x, g=y, b=128 gradient — chroma varies smoothly, so
/// 4:2:0 box-average subsampling introduces only a few levels of error, unlike
/// the hard-edged, module-quantized barcode content used elsewhere in this file.
RgbBuffer _gradientImage(int w, int h) {
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      rgb[i] = x.clamp(0, 255);
      rgb[i + 1] = y.clamp(0, 255);
      rgb[i + 2] = 128;
    }
  }
  return RgbBuffer(w, h, rgb);
}
