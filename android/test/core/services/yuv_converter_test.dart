import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/services/yuv_converter.dart';

void main() {
  group('YuvConverter', () {
    test('pure white (Y=255, U=128, V=128) → RGB(255, 255, 255)', () {
      const w = 4, h = 4;
      final yPlane = Uint8List.fromList(List.filled(w * h, 255));
      final uPlane = Uint8List.fromList(List.filled((w ~/ 2) * (h ~/ 2), 128));
      final vPlane = Uint8List.fromList(List.filled((w ~/ 2) * (h ~/ 2), 128));

      final image = YuvConverter.yuv420ToImage(
        width: w,
        height: h,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: w,
        uvRowStride: w ~/ 2,
        uvPixelStride: 1,
      );

      expect(image.width, equals(w));
      expect(image.height, equals(h));

      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          expect(p.r.toInt(), equals(255), reason: 'R at ($x,$y)');
          expect(p.g.toInt(), equals(255), reason: 'G at ($x,$y)');
          expect(p.b.toInt(), equals(255), reason: 'B at ($x,$y)');
        }
      }
    });

    test('pure black (Y=0, U=128, V=128) → RGB(0, 0, 0)', () {
      const w = 4, h = 4;
      final yPlane = Uint8List.fromList(List.filled(w * h, 0));
      final uPlane = Uint8List.fromList(List.filled((w ~/ 2) * (h ~/ 2), 128));
      final vPlane = Uint8List.fromList(List.filled((w ~/ 2) * (h ~/ 2), 128));

      final image = YuvConverter.yuv420ToImage(
        width: w,
        height: h,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: w,
        uvRowStride: w ~/ 2,
        uvPixelStride: 1,
      );

      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          expect(p.r.toInt(), equals(0), reason: 'R at ($x,$y)');
          expect(p.g.toInt(), equals(0), reason: 'G at ($x,$y)');
          expect(p.b.toInt(), equals(0), reason: 'B at ($x,$y)');
        }
      }
    });

    test('UV subsampling: 2x2 blocks share same chroma', () {
      // 4x4 image with uniform Y but different UV per 2x2 block
      const w = 4, h = 4;
      final yPlane = Uint8List.fromList(List.filled(w * h, 200));

      // 2x2 UV planes: top-left neutral, top-right red-ish, etc.
      final uPlane = Uint8List.fromList([128, 100, 128, 100]);
      final vPlane = Uint8List.fromList([128, 200, 128, 200]);

      final image = YuvConverter.yuv420ToImage(
        width: w,
        height: h,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: w,
        uvRowStride: w ~/ 2,
        uvPixelStride: 1,
      );

      // Top-left 2x2 block (U=128, V=128) should be neutral gray
      final tl00 = image.getPixel(0, 0);
      final tl11 = image.getPixel(1, 1);
      expect(tl00.r.toInt(), equals(tl11.r.toInt()));
      expect(tl00.g.toInt(), equals(tl11.g.toInt()));
      expect(tl00.b.toInt(), equals(tl11.b.toInt()));

      // Top-right 2x2 block (U=100, V=200) should have more red
      final tr = image.getPixel(2, 0);
      expect(tr.r.toInt(), greaterThan(tl00.r.toInt()));
    });

    test('stride configuration: yRowStride > width', () {
      const w = 4, h = 2;
      const yRowStride = 8; // padded stride
      // Y plane with padding bytes (value 0 in padding area)
      final yPlane = Uint8List(yRowStride * h);
      for (var r = 0; r < h; r++) {
        for (var c = 0; c < w; c++) {
          yPlane[r * yRowStride + c] = 200;
        }
      }

      final uPlane = Uint8List.fromList(List.filled((w ~/ 2) * (h ~/ 2), 128));
      final vPlane = Uint8List.fromList(List.filled((w ~/ 2) * (h ~/ 2), 128));

      final image = YuvConverter.yuv420ToImage(
        width: w,
        height: h,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: yRowStride,
        uvRowStride: w ~/ 2,
        uvPixelStride: 1,
      );

      // All visible pixels should be the same (Y=200, neutral chroma)
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          expect(p.r.toInt(), equals(200), reason: 'R at ($x,$y)');
          expect(p.g.toInt(), equals(200), reason: 'G at ($x,$y)');
          expect(p.b.toInt(), equals(200), reason: 'B at ($x,$y)');
        }
      }
    });

    test('semi-planar UV (uvPixelStride=2)', () {
      // Simulates NV21-like interleaved UV where stride is 2
      const w = 4, h = 4;
      final yPlane = Uint8List.fromList(List.filled(w * h, 180));

      // Interleaved UV: U0,V0,U1,V1 per row
      // 2 UV rows, each with 2 UV samples, stride=2
      const uvRowStride = 4; // 2 samples * pixelStride 2
      final uPlane = Uint8List.fromList([128, 0, 128, 0, 128, 0, 128, 0]);
      final vPlane = Uint8List.fromList([128, 0, 128, 0, 128, 0, 128, 0]);

      final image = YuvConverter.yuv420ToImage(
        width: w,
        height: h,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: w,
        uvRowStride: uvRowStride,
        uvPixelStride: 2,
      );

      // All pixels should be neutral (U=128, V=128)
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          expect(p.r.toInt(), equals(180), reason: 'R at ($x,$y)');
          expect(p.g.toInt(), equals(180), reason: 'G at ($x,$y)');
          expect(p.b.toInt(), equals(180), reason: 'B at ($x,$y)');
        }
      }
    });
  });
}
