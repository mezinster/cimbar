import 'dart:typed_data';

import 'rgb_buffer.dart';

/// 8-bit luma plane. Same continuous-coordinate convention as RgbBuffer:
/// pixel k covers [k, k+1), center at k + 0.5.
class LumaPlane {
  final int width;
  final int height;
  final Uint8List luma;

  LumaPlane(this.width, this.height, this.luma) {
    if (luma.length != width * height) {
      throw ArgumentError('luma length ${luma.length} != $width*$height');
    }
  }

  /// BT.601 with integer weights (77, 150, 29) / 256.
  factory LumaPlane.fromRgb(RgbBuffer rgb) {
    final out = Uint8List(rgb.width * rgb.height);
    final s = rgb.rgb;
    var j = 0;
    for (var i = 0; i < out.length; i++) {
      out[i] = (77 * s[j] + 150 * s[j + 1] + 29 * s[j + 2]) >> 8;
      j += 3;
    }
    return LumaPlane(rgb.width, rgb.height, out);
  }

  int at(int x, int y) => luma[y * width + x];

  /// Area-average 2x downscale (odd trailing row/column dropped).
  LumaPlane downscale2() {
    final w = width ~/ 2, h = height ~/ 2;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final r0 = (2 * y) * width, r1 = r0 + width;
      for (var x = 0; x < w; x++) {
        final x0 = 2 * x;
        out[y * w + x] = (luma[r0 + x0] + luma[r0 + x0 + 1] + luma[r1 + x0] + luma[r1 + x0 + 1]) >> 2;
      }
    }
    return LumaPlane(w, h, out);
  }

  double bilinear(double x, double y) {
    final fx = x - 0.5, fy = y - 0.5;
    var x0 = fx.floor(), y0 = fy.floor();
    final tx = fx - x0, ty = fy - y0;
    var x1 = x0 + 1, y1 = y0 + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x0 >= width) x0 = width - 1;
    if (x1 >= width) x1 = width - 1;
    if (y0 >= height) y0 = height - 1;
    if (y1 >= height) y1 = height - 1;
    final a = luma[y0 * width + x0], b = luma[y0 * width + x1];
    final c = luma[y1 * width + x0], d = luma[y1 * width + x1];
    return a * (1 - tx) * (1 - ty) + b * tx * (1 - ty) + c * (1 - tx) * ty + d * tx * ty;
  }

  /// Mean of the 3x3 neighbourhood around integer pixel (cx, cy), clamped.
  double mean3x3(int cx, int cy) {
    var sum = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = (cx + dx).clamp(0, width - 1), y = (cy + dy).clamp(0, height - 1);
        sum += luma[y * width + x];
      }
    }
    return sum / 9;
  }
}
