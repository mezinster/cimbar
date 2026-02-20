import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/frame_locator.dart';

/// Draw one symbol on an image (matches cimbar.js drawSymbol).
void _drawSymbol(
    img.Image image, int symIdx, List<int> colorRGB, int ox, int oy, int size) {
  final cr = colorRGB[0], cg = colorRGB[1], cb = colorRGB[2];
  final q = max(1, (size * 0.28).floor());
  final h = max(1, (q * 0.75).floor());

  img.fillRect(image,
      x1: ox, y1: oy, x2: ox + size, y2: oy + size,
      color: img.ColorRgba8(cr, cg, cb, 255));

  void paintBlack(int bx, int by) {
    img.fillRect(image,
        x1: bx, y1: by, x2: bx + 2 * h, y2: by + 2 * h,
        color: img.ColorRgba8(0, 0, 0, 255));
  }

  if ((symIdx >> 3) & 1 == 0) paintBlack(ox + q - h, oy + q - h);
  if ((symIdx >> 2) & 1 == 0) paintBlack(ox + size - q - h, oy + q - h);
  if ((symIdx >> 1) & 1 == 0) paintBlack(ox + q - h, oy + size - q - h);
  if ((symIdx >> 0) & 1 == 0) paintBlack(ox + size - q - h, oy + size - q - h);
}

/// Draw finder pattern.
void _drawFinder(img.Image image, int ox, int oy, int size) {
  final s = size * 3;
  img.fillRect(image,
      x1: ox, y1: oy, x2: ox + s, y2: oy + s,
      color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(image,
      x1: ox + size, y1: oy + size, x2: ox + 2 * size, y2: oy + 2 * size,
      color: img.ColorRgba8(51, 51, 51, 255));
  final inner = (size * 0.4).floor();
  final offset = ((size - inner) / 2).floor();
  img.fillRect(image,
      x1: ox + size + offset,
      y1: oy + size + offset,
      x2: ox + size + offset + inner,
      y2: oy + size + offset + inner,
      color: img.ColorRgba8(255, 255, 255, 255));
}

/// Synthesize a CimBar frame image at a given size with colored cells.
img.Image _synthesizeFrame(int frameSize) {
  const cs = CimbarConstants.cellSize;
  final cols = frameSize ~/ cs;
  final rows = frameSize ~/ cs;
  final image = img.Image(width: frameSize, height: frameSize);

  // Dark background (same as real CimBar)
  img.fill(image, color: img.ColorRgba8(17, 17, 17, 255));

  // Draw colored cells (arbitrary pattern)
  var cellIdx = 0;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      final inTL = row < 3 && col < 3;
      final inBR = row >= rows - 3 && col >= cols - 3;
      if (inTL || inBR) continue;

      final colorIdx = cellIdx % 8;
      final symIdx = cellIdx % 16;
      _drawSymbol(image, symIdx, CimbarConstants.colors[colorIdx],
          col * cs, row * cs, cs);
      cellIdx++;
    }
  }

  // Draw finder patterns
  _drawFinder(image, 0, 0, cs);
  _drawFinder(image, (cols - 3) * cs, (rows - 3) * cs, cs);

  return image;
}

void main() {
  group('FrameLocator', () {
    test('locates barcode centered in a larger dark image', () {
      const photoSize = 1024;
      const frameSize = 256;

      // Create large dark photo
      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(5, 5, 5, 255));

      // Draw a CimBar frame at offset (384, 384) — centered in 1024x1024
      final frame = _synthesizeFrame(frameSize);
      const offsetX = 384;
      const offsetY = 384;
      img.compositeImage(photo, frame, dstX: offsetX, dstY: offsetY);

      // Locate
      final cropped = FrameLocator.locate(photo);

      // The crop must be square
      expect(cropped.width, equals(cropped.height));

      // The crop must contain the barcode region
      // Since the frame is at (384, 384) with size 256, its center is at (512, 512)
      // The crop should be roughly centered around the barcode
      expect(cropped.width, greaterThanOrEqualTo(frameSize));

      // Sample a pixel from the center of the cropped image
      // It should be a bright colored cell, not the dark background
      final cx = cropped.width ~/ 2;
      final cy = cropped.height ~/ 2;
      final centerPixel = cropped.getPixel(cx, cy);
      final centerLuma = (0.299 * centerPixel.r +
              0.587 * centerPixel.g +
              0.114 * centerPixel.b)
          .round();
      // Center of the barcode should have colored cells (luma > 30)
      expect(centerLuma, greaterThan(30));
    });

    test('locates barcode in top-left corner', () {
      const photoSize = 800;
      const frameSize = 192;

      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(5, 5, 5, 255));

      final frame = _synthesizeFrame(frameSize);
      img.compositeImage(photo, frame, dstX: 20, dstY: 20);

      final cropped = FrameLocator.locate(photo);

      expect(cropped.width, equals(cropped.height));
      expect(cropped.width, greaterThanOrEqualTo(frameSize));
    });

    test('handles barcode filling entire image (no background)', () {
      const frameSize = 256;

      // Frame is the entire image — no surrounding dark area
      final frame = _synthesizeFrame(frameSize);

      final cropped = FrameLocator.locate(frame);

      expect(cropped.width, equals(cropped.height));
      // Should return approximately the full image
      expect(cropped.width, greaterThanOrEqualTo(frameSize * 0.9));
    });

    test('throws StateError for fully dark image', () {
      final dark = img.Image(width: 512, height: 512);
      img.fill(dark, color: img.ColorRgba8(5, 5, 5, 255));

      expect(
        () => FrameLocator.locate(dark),
        throwsStateError,
      );
    });
  });
}
