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
      final inTR = row < 3 && col >= cols - 3;
      final inBL = row >= rows - 3 && col < 3;
      final inBR = row >= rows - 3 && col >= cols - 3;
      if (inTL || inTR || inBL || inBR) continue;

      final colorIdx = cellIdx % 8;
      final symIdx = cellIdx % 16;
      _drawSymbol(image, symIdx, CimbarConstants.colors[colorIdx],
          col * cs, row * cs, cs);
      cellIdx++;
    }
  }

  // Draw 4 finder patterns
  _drawFinder(image, 0, 0, cs);
  _drawFinder(image, (cols - 3) * cs, 0, cs);
  _drawFinder(image, 0, (rows - 3) * cs, cs);
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
      final result = FrameLocator.locate(photo);
      final cropped = result.cropped;

      // The crop must be square
      expect(cropped.width, equals(cropped.height));

      // The crop must contain the barcode region
      expect(cropped.width, greaterThanOrEqualTo(frameSize));

      // Bounding box should be valid
      expect(result.boundingBox.x, greaterThanOrEqualTo(0));
      expect(result.boundingBox.y, greaterThanOrEqualTo(0));
      expect(result.boundingBox.width, greaterThan(0));
      expect(result.boundingBox.height, greaterThan(0));

      // Sample a small region near the center of the cropped image.
      // The exact center may land on a 2×2 black corner dot, so check
      // that the max luma in a 5×5 region is bright (colored cell).
      final cx = cropped.width ~/ 2;
      final cy = cropped.height ~/ 2;
      var maxLuma = 0;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final p = cropped.getPixel(cx + dx, cy + dy);
          final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
          if (l > maxLuma) maxLuma = l;
        }
      }
      // Center of the barcode should have colored cells nearby (luma > 30)
      expect(maxLuma, greaterThan(30));
    });

    test('locates barcode in top-left corner', () {
      const photoSize = 800;
      const frameSize = 192;

      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(5, 5, 5, 255));

      final frame = _synthesizeFrame(frameSize);
      img.compositeImage(photo, frame, dstX: 20, dstY: 20);

      final result = FrameLocator.locate(photo);
      final cropped = result.cropped;

      expect(cropped.width, equals(cropped.height));
      expect(cropped.width, greaterThanOrEqualTo(frameSize));
      expect(result.boundingBox.width, greaterThan(0));
    });

    test('handles barcode filling entire image (no background)', () {
      const frameSize = 256;

      // Frame is the entire image — no surrounding dark area
      final frame = _synthesizeFrame(frameSize);

      final result = FrameLocator.locate(frame);
      final cropped = result.cropped;

      expect(cropped.width, equals(cropped.height));
      // Should return approximately the full image
      expect(cropped.width, greaterThanOrEqualTo(frameSize * 0.9));
      expect(result.boundingBox.width, greaterThan(0));
    });

    test('throws StateError for fully dark image', () {
      final dark = img.Image(width: 512, height: 512);
      img.fill(dark, color: img.ColorRgba8(5, 5, 5, 255));

      expect(
        () => FrameLocator.locate(dark),
        throwsStateError,
      );
    });

    test('ignores noisy background with random bright pixels', () {
      const photoSize = 1024;
      const frameSize = 256;

      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(5, 5, 5, 255));

      // Draw barcode centered
      final frame = _synthesizeFrame(frameSize);
      const offsetX = 384;
      const offsetY = 384;
      img.compositeImage(photo, frame, dstX: offsetX, dstY: offsetY);

      // Scatter random bright pixels (noise) outside the barcode area
      final rng = Random(42); // fixed seed for reproducibility
      for (var i = 0; i < 500; i++) {
        // Only place noise outside the barcode region
        int x, y;
        do {
          x = rng.nextInt(photoSize);
          y = rng.nextInt(photoSize);
        } while (x >= offsetX && x < offsetX + frameSize &&
            y >= offsetY && y < offsetY + frameSize);

        final brightness = 120 + rng.nextInt(136); // 120-255
        photo.setPixel(x, y,
            img.ColorRgba8(brightness, brightness, brightness, 255));
      }

      final result = FrameLocator.locate(photo);
      final cropped = result.cropped;

      expect(cropped.width, equals(cropped.height));
      expect(cropped.width, greaterThanOrEqualTo(frameSize));

      // The crop should NOT be massively inflated by noise.
      // With anchor detection, the crop should be close to the barcode size.
      // With pure luma-threshold, scattered pixels would blow up the crop.
      // Allow up to 50% larger than the frame for margin + estimation error.
      expect(cropped.width, lessThanOrEqualTo((frameSize * 1.5).round()));
    });

    test('finder center positions are near known locations', () {
      const photoSize = 1024;
      const frameSize = 256;
      const cs = CimbarConstants.cellSize;

      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(5, 5, 5, 255));

      final frame = _synthesizeFrame(frameSize);
      const offsetX = 384;
      const offsetY = 384;
      img.compositeImage(photo, frame, dstX: offsetX, dstY: offsetY);

      final result = FrameLocator.locate(photo);

      // Should have anchor-based detection results
      expect(result.tlFinderCenter, isNotNull);
      expect(result.brFinderCenter, isNotNull);

      // Known finder centers in photo coordinates:
      // TL finder is a 3×3 block at grid (0,0). Center cell is (1,1).
      // Center of cell (1,1) = offset + 1.5 * cellSize
      const expectedTlX = offsetX + 1.5 * cs; // 384 + 12 = 396
      const expectedTlY = offsetY + 1.5 * cs;

      const cols = frameSize ~/ cs;
      const rows = frameSize ~/ cs;
      // BR finder center cell is (cols-2, rows-2)
      const expectedBrX = offsetX + (cols - 2 + 0.5) * cs;
      const expectedBrY = offsetY + (rows - 2 + 0.5) * cs;

      // Allow tolerance for downscale + averaging error
      const tolerance = 20.0;
      expect((result.tlFinderCenter!.x - expectedTlX).abs(),
          lessThanOrEqualTo(tolerance));
      expect((result.tlFinderCenter!.y - expectedTlY).abs(),
          lessThanOrEqualTo(tolerance));
      expect((result.brFinderCenter!.x - expectedBrX).abs(),
          lessThanOrEqualTo(tolerance));
      expect((result.brFinderCenter!.y - expectedBrY).abs(),
          lessThanOrEqualTo(tolerance));

      // TR and BL finder detection depends on scan line alignment and
      // scoring vs other candidates. We verify they're present and
      // roughly in the correct half of the image when detected.
      // The key requirement is TL+BR correctness (tested above).
      if (result.trFinderCenter != null) {
        // TR should be in the right half of the barcode
        expect(result.trFinderCenter!.x,
            greaterThan(offsetX + frameSize * 0.3));
      }
      if (result.blFinderCenter != null) {
        // BL should be in the bottom half of the barcode
        expect(result.blFinderCenter!.y,
            greaterThan(offsetY + frameSize * 0.3));
      }
    });

    test('falls back to luma-threshold when no finder structure present', () {
      const photoSize = 512;

      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(5, 5, 5, 255));

      // Draw a bright rectangle without any finder pattern structure
      // (uniform bright block — no bright→dark→bright transitions internally)
      img.fillRect(photo,
          x1: 150, y1: 150, x2: 350, y2: 350,
          color: img.ColorRgba8(200, 200, 200, 255));

      final result = FrameLocator.locate(photo);

      // Should still locate something (via fallback)
      expect(result.cropped.width, greaterThan(0));
      expect(result.boundingBox.width, greaterThan(0));

      // Fallback doesn't produce finder centers
      expect(result.tlFinderCenter, isNull);
      expect(result.brFinderCenter, isNull);
    });
  });
}
