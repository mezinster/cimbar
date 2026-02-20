import 'dart:math';

import 'package:image/image.dart' as img;

/// Finds the CimBar barcode region in a camera photo and returns a cropped
/// square image suitable for decoding.
class FrameLocator {
  FrameLocator._();

  /// Locate and crop the CimBar barcode region from a camera [photo].
  ///
  /// Algorithm:
  /// 1. Downscale 4x for speed
  /// 2. Convert to grayscale, threshold at luma > 30 to separate barcode
  ///    (colored cells on dark background) from photo background
  /// 3. Find bounding box of all above-threshold pixels
  /// 4. Add 2% margin, make square, center
  /// 5. Scale coordinates back to original resolution
  /// 6. Crop from original full-res image
  ///
  /// Throws [StateError] if no barcode region is found.
  static img.Image locate(img.Image photo) {
    final origW = photo.width;
    final origH = photo.height;

    // 1. Downscale 4x for fast scanning
    const scale = 4;
    final smallW = max(1, origW ~/ scale);
    final smallH = max(1, origH ~/ scale);
    final small = img.copyResize(photo, width: smallW, height: smallH,
        interpolation: img.Interpolation.average);

    // 2-3. Find bounding box of bright pixels (luma > 30)
    const lumaThreshold = 30;
    var minX = smallW;
    var minY = smallH;
    var maxX = 0;
    var maxY = 0;
    var found = false;

    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        final p = small.getPixel(x, y);
        final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        if (luma > lumaThreshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          found = true;
        }
      }
    }

    if (!found) {
      throw StateError('No barcode region found in image');
    }

    // 4. Scale back to original coordinates
    var oMinX = minX * scale;
    var oMinY = minY * scale;
    var oMaxX = min((maxX + 1) * scale, origW);
    var oMaxY = min((maxY + 1) * scale, origH);

    var bw = oMaxX - oMinX;
    var bh = oMaxY - oMinY;

    // Add 2% margin
    final margin = (max(bw, bh) * 0.02).round();
    oMinX = max(0, oMinX - margin);
    oMinY = max(0, oMinY - margin);
    oMaxX = min(origW, oMaxX + margin);
    oMaxY = min(origH, oMaxY + margin);

    bw = oMaxX - oMinX;
    bh = oMaxY - oMinY;

    // Make square (use max of width/height, centered)
    final side = max(bw, bh);
    final cx = oMinX + bw ~/ 2;
    final cy = oMinY + bh ~/ 2;

    var cropX = cx - side ~/ 2;
    var cropY = cy - side ~/ 2;

    // Clamp to image bounds
    cropX = max(0, min(cropX, origW - side));
    cropY = max(0, min(cropY, origH - side));
    final cropSide = min(side, min(origW - cropX, origH - cropY));

    // 5. Crop from original full-res image
    return img.copyCrop(photo,
        x: cropX, y: cropY, width: cropSide, height: cropSide);
  }
}
