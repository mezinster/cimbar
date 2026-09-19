import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/decode/yuv_frame.dart';

import '../../test_utils/synthetic_scene.dart';

/// NV12 as iOS delivers it: plane 0 = Y (16..235), plane 1 = interleaved
/// CbCr (16..240), both rows padded by [pad] bytes.
({List<Uint8List> planes, List<int> rowStrides, List<int?> pixelStrides}) rgbToNv12VideoRange(
    RgbBuffer src, {int pad = 0}) {
  final w = src.width, h = src.height, yStride = w + pad;
  final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2, uvStride = cw * 2 + pad;
  final y = Uint8List(yStride * h), uv = Uint8List(uvStride * ch);
  for (var yy = 0; yy < h; yy++) {
    for (var x = 0; x < w; x++) {
      final i = (yy * w + x) * 3;
      final full = ((77 * src.rgb[i] + 150 * src.rgb[i + 1] + 29 * src.rgb[i + 2]) >> 8).clamp(0, 255);
      y[yy * yStride + x] = 16 + (full * 219 + 127) ~/ 255;
    }
  }
  for (var cy = 0; cy < ch; cy++) {
    for (var cx = 0; cx < cw; cx++) {
      var rs = 0, gs = 0, bs = 0, n = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final px = cx * 2 + dx, py = cy * 2 + dy;
          if (px >= w || py >= h) continue;
          final i = (py * w + px) * 3;
          rs += src.rgb[i];
          gs += src.rgb[i + 1];
          bs += src.rgb[i + 2];
          n++;
        }
      }
      final r = rs / n, g = gs / n, b = bs / n;
      final cb = -0.168736 * r - 0.331264 * g + 0.5 * b; // -128..127
      final cr = 0.5 * r - 0.418688 * g - 0.081312 * b;
      uv[cy * uvStride + cx * 2] = (128 + cb * 224 / 255).round().clamp(16, 240);
      uv[cy * uvStride + cx * 2 + 1] = (128 + cr * 224 / 255).round().clamp(16, 240);
    }
  }
  return (planes: [y, uv], rowStrides: [yStride, uvStride], pixelStrides: [1, 2]);
}

RgbBuffer gradient(int w, int h) {
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      out[i] = (x * 255) ~/ (w - 1);
      out[i + 1] = (y * 255) ~/ (h - 1);
      out[i + 2] = ((x + y) * 255) ~/ (w + h - 2);
    }
  }
  return RgbBuffer(w, h, out);
}

void main() {
  group('YuvFrame.fromPlanes', () {
    test('three planes (Android YUV_420_888) keep the plugin strides, full range', () {
      final y = Uint8List(16), u = Uint8List(8), v = Uint8List(8);
      final f = YuvFrame.fromPlanes(
          planes: [y, u, v], rowStrides: [4, 4, 4], pixelStrides: [1, 2, 2], width: 4, height: 4)!;
      expect(f.uvPixelStride, 2);
      expect(f.uvRowStride, 4);
      expect(f.yRowStride, 4);
      expect(f.videoRange, isFalse);
    });

    test('a missing pixel stride on a three-plane frame means planar (1)', () {
      final f = YuvFrame.fromPlanes(
          planes: [Uint8List(16), Uint8List(4), Uint8List(4)],
          rowStrides: [4, 2, 2],
          pixelStrides: [1, null, null],
          width: 4,
          height: 4)!;
      expect(f.uvPixelStride, 1);
    });

    test('two planes (iOS NV12): U = even CbCr bytes, V = odd, video range, copied', () {
      final y = Uint8List(16);
      final cbcr = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      final f = YuvFrame.fromPlanes(
          planes: [y, cbcr], rowStrides: [4, 4], pixelStrides: [1, 2], width: 4, height: 4)!;
      expect(f.uvPixelStride, 2);
      expect(f.videoRange, isTrue);
      expect([f.uPlane[0], f.vPlane[0], f.uPlane[2], f.vPlane[2]], [10, 20, 30, 40]);
      cbcr[0] = 99; // camera buffers are reused: the frame must own a copy
      expect(f.uPlane[0], 10);
    });

    test('any other plane count is rejected', () {
      expect(
          YuvFrame.fromPlanes(planes: [Uint8List(16)], rowStrides: [4], pixelStrides: [1], width: 4, height: 4),
          isNull);
      expect(
          YuvFrame.fromPlanes(
              planes: List.generate(4, (_) => Uint8List(16)),
              rowStrides: [4, 4, 4, 4],
              pixelStrides: [1, 1, 1, 1],
              width: 4,
              height: 4),
          isNull);
    });
  });

  test('video-range tables map the studio-swing ends to 0/255 and ±128', () {
    expect(videoRangeLuma[16], 0);
    expect(videoRangeLuma[235], 255);
    expect(videoRangeLuma[0], 0);
    expect(videoRangeLuma[255], 255);
    expect(videoRangeChroma[128], 0);
    expect(videoRangeChroma[240], 128);
    expect(videoRangeChroma[16], -128);
  });

  test('LumaPlane.fromYPlane expands video range and honours the row stride', () {
    final y = Uint8List.fromList([16, 235, 0, 0, 126, 16, 0, 0]); // 2x2, stride 4
    final p = LumaPlane.fromYPlane(y, width: 2, height: 2, rowStride: 4, videoRange: true);
    expect(p.luma, [0, 255, 128, 0]);
  });

  test('NV12 video-range round-trips through RgbBuffer.fromYuv420 within ±8', () {
    final src = gradient(64, 48);
    final nv12 = rgbToNv12VideoRange(src, pad: 8);
    final f = YuvFrame.fromPlanes(
        planes: nv12.planes, rowStrides: nv12.rowStrides, pixelStrides: nv12.pixelStrides, width: 64, height: 48)!;
    final back = RgbBuffer.fromYuv420(f);
    var worst = 0;
    for (var i = 0; i < src.rgb.length; i++) {
      final d = (src.rgb[i] - back.rgb[i]).abs();
      if (d > worst) worst = d;
    }
    // Video range quantizes luma to 219 levels and chroma to 224 (vs. 256 full
    // range), on top of the ±4 the full-range round-trip already allows (see
    // roi_buffers_test.dart) — ±8 covers that extra quantization loss.
    expect(worst, lessThanOrEqualTo(8));
  });

  test('a golden frame decodes from iOS-style NV12 video-range input', () {
    final frame = loadGoldenFrame('lorem_12k', 1);
    final truth = GoldenSidecar.load('../test-data/goldens/lorem_12k.json').frames[1].data;
    final scene = renderScene(frame, 1280, 720, SceneSpec()..scale = 1.0..rotationDeg = 8..centerX = 700..centerY = 360);
    final nv12 = rgbToNv12VideoRange(scene.image, pad: 32);
    final f = YuvFrame.fromPlanes(
        planes: nv12.planes, rowStrides: nv12.rowStrides, pixelStrides: nv12.pixelStrides, width: 1280, height: 720)!;
    final r = FrameDecoder().decodeYuv420(f);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, truth);
  });
}
