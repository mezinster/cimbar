import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'yuv_frame.dart';

/// Flat 8-bit RGB buffer with bilinear sampling. May cover only a region of a
/// larger source frame: [originX]/[originY] are the buffer's absolute position,
/// and [bilinear] takes ABSOLUTE source coordinates (pixel k covers [k, k+1),
/// center at k + 0.5). [r]/[g]/[b] index the buffer itself (local coordinates).
class RgbBuffer {
  final int width;
  final int height;
  final Uint8List rgb; // width * height * 3
  final int originX;
  final int originY;

  RgbBuffer(this.width, this.height, this.rgb, {this.originX = 0, this.originY = 0}) {
    if (rgb.length != width * height * 3) {
      throw ArgumentError('rgb length ${rgb.length} != $width*$height*3');
    }
  }

  /// Convert a region of a YUV_420_888 frame (BT.601, integer math). The
  /// region is clamped to the frame; the result records its origin.
  factory RgbBuffer.fromYuv420(YuvFrame f, {int x0 = 0, int y0 = 0, int? w, int? h}) {
    final rx0 = x0.clamp(0, f.width - 1), ry0 = y0.clamp(0, f.height - 1);
    final rx1 = (x0 + (w ?? f.width)).clamp(rx0 + 1, f.width);
    final ry1 = (y0 + (h ?? f.height)).clamp(ry0 + 1, f.height);
    final rw = rx1 - rx0, rh = ry1 - ry0;
    final out = Uint8List(rw * rh * 3);
    var o = 0;
    for (var y = ry0; y < ry1; y++) {
      final yRow = y * f.yRowStride;
      final uvRow = (y >> 1) * f.uvRowStride;
      for (var x = rx0; x < rx1; x++) {
        final yv = f.yPlane[yRow + x];
        final uvIdx = uvRow + (x >> 1) * f.uvPixelStride;
        final u = f.uPlane[uvIdx] - 128, v = f.vPlane[uvIdx] - 128;
        final r = yv + ((359 * v) >> 8);
        final g = yv - ((88 * u + 183 * v) >> 8);
        final b = yv + ((454 * u) >> 8);
        out[o++] = r < 0 ? 0 : (r > 255 ? 255 : r);
        out[o++] = g < 0 ? 0 : (g > 255 ? 255 : g);
        out[o++] = b < 0 ? 0 : (b > 255 ? 255 : b);
      }
    }
    return RgbBuffer(rw, rh, out, originX: rx0, originY: ry0);
  }

  factory RgbBuffer.fromImage(img.Image image) {
    final w = image.width, h = image.height;
    // `getBytes(order: rgb)` only expands to true RGB bytes for non-paletted
    // images: on a paletted image (e.g. a decoded GIF frame) the underlying
    // storage is still 1-byte-per-pixel palette indices, so the bulk path
    // would silently return the wrong length/content. Verified against
    // image 4.8.0's GifDecoder output (see final-fix-report.md, I1).
    if (!image.hasPalette) {
      final bytes = image.getBytes(order: img.ChannelOrder.rgb);
      if (bytes.length == w * h * 3) {
        return RgbBuffer(w, h, Uint8List.fromList(bytes));
      }
    }
    // Fallback (paletted image, or unexpected layout): per-pixel copy.
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
    final fx = x - originX - 0.5, fy = y - originY - 0.5;
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
