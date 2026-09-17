import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Flat 8-bit RGB buffer with bilinear sampling.
/// Continuous coordinates: pixel k covers [k, k+1), center at k + 0.5.
class RgbBuffer {
  final int width;
  final int height;
  final Uint8List rgb; // width * height * 3

  RgbBuffer(this.width, this.height, this.rgb) {
    if (rgb.length != width * height * 3) {
      throw ArgumentError('rgb length ${rgb.length} != $width*$height*3');
    }
  }

  factory RgbBuffer.fromImage(img.Image image) {
    final w = image.width, h = image.height;
    final out = Uint8List(w * h * 3);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        out[i++] = p.r.toInt();
        out[i++] = p.g.toInt();
        out[i++] = p.b.toInt();
      }
    }
    return RgbBuffer(w, h, out);
  }

  int r(int x, int y) => rgb[(y * width + x) * 3];
  int g(int x, int y) => rgb[(y * width + x) * 3 + 1];
  int b(int x, int y) => rgb[(y * width + x) * 3 + 2];

  /// Bilinear sample at continuous (x, y); writes r,g,b to out[outOff..outOff+2].
  void bilinear(double x, double y, Float32List out, int outOff) {
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
    final i00 = (y0 * width + x0) * 3, i10 = (y0 * width + x1) * 3;
    final i01 = (y1 * width + x0) * 3, i11 = (y1 * width + x1) * 3;
    final w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
    for (var c = 0; c < 3; c++) {
      out[outOff + c] = rgb[i00 + c] * w00 + rgb[i10 + c] * w10 + rgb[i01 + c] * w01 + rgb[i11 + c] * w11;
    }
  }
}
