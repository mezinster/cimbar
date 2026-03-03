import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Image preprocessing for camera decode: adaptive threshold + sharpening.
///
/// Ports the C++ libcimbar CimbReader preprocessing pipeline to Dart.
/// Converts a warped/resized barcode image to a binary (0/255) grayscale
/// buffer suitable for average-hash symbol detection.
///
/// Color detection still uses the original RGB image — preprocessing is
/// only for symbol detection (Pass 1 of two-pass decode).
class ImagePreprocessing {
  /// Convert an RGB image to BT.601 grayscale.
  /// Returns a flat [Uint8List] of [image.width * image.height] luma values.
  static Uint8List rgbToGrayscale(img.Image image) {
    final w = image.width;
    final h = image.height;
    final gray = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        gray[y * w + x] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      }
    }
    return gray;
  }

  /// Apply 3×3 high-pass sharpening kernel (matching C++ libcimbar):
  /// ```
  ///  0    -1     0
  /// -1    4.5   -1
  ///  0    -1     0
  /// ```
  /// Output clamped to [0, 255]. Border pixels are unchanged.
  static Uint8List sharpen3x3(Uint8List gray, int width, int height) {
    final out = Uint8List(width * height);
    // Copy borders unchanged
    for (var x = 0; x < width; x++) {
      out[x] = gray[x];
      out[(height - 1) * width + x] = gray[(height - 1) * width + x];
    }
    for (var y = 0; y < height; y++) {
      out[y * width] = gray[y * width];
      out[y * width + width - 1] = gray[y * width + width - 1];
    }

    // Interior pixels: apply kernel
    for (var y = 1; y < height - 1; y++) {
      final rowAbove = (y - 1) * width;
      final rowCur = y * width;
      final rowBelow = (y + 1) * width;
      for (var x = 1; x < width - 1; x++) {
        // center * 4.5 - top - bottom - left - right
        final val = (gray[rowCur + x] * 4.5 -
                gray[rowAbove + x] -
                gray[rowBelow + x] -
                gray[rowCur + x - 1] -
                gray[rowCur + x + 1])
            .round();
        out[rowCur + x] = val.clamp(0, 255);
      }
    }
    return out;
  }

  /// Adaptive threshold using local mean (MEAN_C method).
  ///
  /// For each pixel, computes the mean of its [blockSize]×[blockSize]
  /// neighborhood. If pixel > mean - [delta], output is 255, else 0.
  ///
  /// Uses an integral image (summed area table) for O(1) per-pixel mean
  /// computation. [blockSize] must be odd.
  static Uint8List adaptiveThresholdMean(
    Uint8List gray,
    int width,
    int height, {
    int blockSize = 5,
    int delta = 0,
  }) {
    // Build integral image using Int32 to avoid overflow
    // integral[y][x] = sum of gray[0..y-1][0..x-1]
    // We use (height+1) × (width+1) with zero borders for simpler indexing.
    final iw = width + 1;
    final integral = Int32List(iw * (height + 1));

    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      final iRow = (y + 1) * iw;
      final iRowAbove = y * iw;
      final gRow = y * width;
      for (var x = 0; x < width; x++) {
        rowSum += gray[gRow + x];
        integral[iRow + x + 1] = rowSum + integral[iRowAbove + x + 1];
      }
    }

    // Apply threshold
    final out = Uint8List(width * height);
    final halfBlock = blockSize ~/ 2;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Clamp neighborhood to image bounds
        final y1 = (y - halfBlock).clamp(0, height - 1);
        final y2 = (y + halfBlock).clamp(0, height - 1);
        final x1 = (x - halfBlock).clamp(0, width - 1);
        final x2 = (x + halfBlock).clamp(0, width - 1);

        // Sum from integral image: S(x1,y1,x2,y2) =
        //   integral[y2+1][x2+1] - integral[y1][x2+1]
        //   - integral[y2+1][x1] + integral[y1][x1]
        final sum = integral[(y2 + 1) * iw + x2 + 1] -
            integral[y1 * iw + x2 + 1] -
            integral[(y2 + 1) * iw + x1] +
            integral[y1 * iw + x1];

        final count = (y2 - y1 + 1) * (x2 - x1 + 1);
        // mean = sum / count; threshold = mean - delta
        // pixel > mean - delta  ⟺  pixel * count > sum - delta * count
        final threshold = sum - delta * count;
        out[y * width + x] = (gray[y * width + x] * count > threshold) ? 255 : 0;
      }
    }

    return out;
  }

  /// Full preprocessing pipeline: RGB → grayscale → optional sharpen →
  /// adaptive threshold → binary (0/255) grayscale buffer.
  ///
  /// When [needsSharpen] is true (source region was smaller than target
  /// frame size, meaning upscaling occurred), applies 3×3 sharpening and
  /// uses blockSize=7. Otherwise uses blockSize=5.
  static Uint8List preprocessSymbolGrid(img.Image image,
      {bool needsSharpen = false}) {
    var gray = rgbToGrayscale(image);

    if (needsSharpen) {
      gray = sharpen3x3(gray, image.width, image.height);
    }

    final blockSize = needsSharpen ? 7 : 5;
    return adaptiveThresholdMean(gray, image.width, image.height,
        blockSize: blockSize);
  }
}
