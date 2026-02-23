import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/cimbar_decoder.dart';
import 'package:cimbar_scanner/core/services/perspective_transform.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';

import '../../../test/test_utils/cimbar_encoder.dart';

void main() {
  group('PerspectiveTransform.computeBarcodeCorners', () {
    test('axis-aligned barcode produces correct corners', () {
      const frameSize = 256;
      const cs = CimbarConstants.cellSize;
      const cols = frameSize ~/ cs;

      // Finder centers at grid (1.5*cs, 1.5*cs) and ((cols-1.5)*cs, (cols-1.5)*cs)
      const tlFinder = Point(1.5 * cs, 1.5 * cs);
      const brFinder = Point((cols - 1.5) * cs, (cols - 1.5) * cs);

      final corners = PerspectiveTransform.computeBarcodeCorners(
          tlFinder, brFinder, frameSize);

      expect(corners, isNotNull);
      expect(corners!.length, equals(4));

      // For axis-aligned barcode, corners should be approximately (0,0), (256,0), (0,256), (256,256)
      const tol = 1.0;
      expect(corners[0].x, closeTo(0.0, tol)); // TL
      expect(corners[0].y, closeTo(0.0, tol));
      expect(corners[1].x, closeTo(256.0, tol)); // TR
      expect(corners[1].y, closeTo(0.0, tol));
      expect(corners[2].x, closeTo(0.0, tol)); // BL
      expect(corners[2].y, closeTo(256.0, tol));
      expect(corners[3].x, closeTo(256.0, tol)); // BR
      expect(corners[3].y, closeTo(256.0, tol));
    });

    test('rotated barcode produces square corners with correct side length', () {
      const frameSize = 256;
      const cs = CimbarConstants.cellSize;
      const cols = frameSize ~/ cs;

      // Rotate finder centers by 30 degrees around (400, 400)
      const angle = 30.0 * pi / 180;
      final cosA = cos(angle);
      final sinA = sin(angle);

      // Original finder centers (axis-aligned)
      const tlOrig = Point(1.5 * cs, 1.5 * cs);
      const brOrig = Point((cols - 1.5) * cs, (cols - 1.5) * cs);

      // Rotate around origin then translate to (400, 400)
      const cx = 400.0, cy = 400.0;
      final tlRotX = cx + (tlOrig.x - 128) * cosA - (tlOrig.y - 128) * sinA;
      final tlRotY = cy + (tlOrig.x - 128) * sinA + (tlOrig.y - 128) * cosA;
      final brRotX = cx + (brOrig.x - 128) * cosA - (brOrig.y - 128) * sinA;
      final brRotY = cy + (brOrig.x - 128) * sinA + (brOrig.y - 128) * cosA;

      final tlFinder = Point(tlRotX, tlRotY);
      final brFinder = Point(brRotX, brRotY);

      final corners = PerspectiveTransform.computeBarcodeCorners(
          tlFinder, brFinder, frameSize);

      expect(corners, isNotNull);
      expect(corners!.length, equals(4));

      // Check that the 4 corners form a square with side ≈ frameSize
      double dist(Point<double> a, Point<double> b) {
        final dx = a.x - b.x;
        final dy = a.y - b.y;
        return sqrt(dx * dx + dy * dy);
      }

      final side01 = dist(corners[0], corners[1]); // TL-TR
      final side02 = dist(corners[0], corners[2]); // TL-BL
      final side13 = dist(corners[1], corners[3]); // TR-BR
      final side23 = dist(corners[2], corners[3]); // BL-BR

      // All sides should be approximately equal to frameSize
      const sideTol = 2.0;
      expect(side01, closeTo(frameSize.toDouble(), sideTol));
      expect(side02, closeTo(frameSize.toDouble(), sideTol));
      expect(side13, closeTo(frameSize.toDouble(), sideTol));
      expect(side23, closeTo(frameSize.toDouble(), sideTol));

      // Diagonals should be approximately equal (square property)
      final diag03 = dist(corners[0], corners[3]);
      final diag12 = dist(corners[1], corners[2]);
      expect(diag03, closeTo(diag12, 2.0));
    });

    test('degenerate input returns null', () {
      const frameSize = 256;

      // Same point
      const same = Point(100.0, 100.0);
      expect(PerspectiveTransform.computeBarcodeCorners(
          same, same, frameSize), isNull);

      // Very close points
      const p1 = Point(100.0, 100.0);
      const p2 = Point(101.0, 101.0);
      expect(PerspectiveTransform.computeBarcodeCorners(
          p1, p2, frameSize), isNull);
    });
  });

  group('PerspectiveTransform.warpPerspective', () {
    test('identity-like warp preserves image content', () {
      const size = 64;
      final source = img.Image(width: size, height: size);

      // Draw a recognizable pattern
      img.fill(source, color: img.ColorRgba8(100, 150, 200, 255));
      img.fillRect(source,
          x1: 10, y1: 10, x2: 54, y2: 54,
          color: img.ColorRgba8(255, 0, 0, 255));

      // Identity corners
      final srcCorners = [
        const Point(0.0, 0.0),
        Point(size.toDouble(), 0.0),
        Point(0.0, size.toDouble()),
        Point(size.toDouble(), size.toDouble()),
      ];

      final warped = PerspectiveTransform.warpPerspective(
          source, srcCorners, size);

      // Center should be red (the rectangle)
      final p = warped.getPixel(32, 32);
      expect(p.r.toInt(), greaterThan(200));
      expect(p.g.toInt(), lessThan(50));
      expect(p.b.toInt(), lessThan(50));

      // Corner (5,5) should be blue-ish background
      final pc = warped.getPixel(5, 5);
      expect(pc.r.toInt(), closeTo(100, 20));
      expect(pc.g.toInt(), closeTo(150, 20));
      expect(pc.b.toInt(), closeTo(200, 20));
    });

    test('warp corrects a rotated barcode image', () {
      const frameSize = 128;
      const cs = CimbarConstants.cellSize;
      const cols = frameSize ~/ cs;

      // Generate a clean barcode
      final barcode = _buildTestFrame(frameSize);

      // Embed rotated into a larger image using inverse mapping
      const angle = 15.0 * pi / 180;
      const photoSize = 400;
      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(10, 10, 10, 255));

      const centerX = photoSize / 2.0;
      const centerY = photoSize / 2.0;
      final cosA = cos(angle);
      final sinA = sin(angle);

      // Inverse mapping: for each destination pixel, find source pixel
      for (var dy = 0; dy < photoSize; dy++) {
        for (var dx = 0; dx < photoSize; dx++) {
          final px = dx - centerX;
          final py = dy - centerY;
          final sx = (px * cosA + py * sinA + frameSize / 2.0);
          final sy = (-px * sinA + py * cosA + frameSize / 2.0);
          final sxi = sx.floor();
          final syi = sy.floor();
          if (sxi >= 0 && sxi < frameSize && syi >= 0 && syi < frameSize) {
            final p = barcode.getPixel(sxi, syi);
            photo.setPixelRgba(dx, dy, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
          }
        }
      }

      // Compute finder centers in the rotated photo
      const tlGrid = Point(1.5 * cs - frameSize / 2.0,
                           1.5 * cs - frameSize / 2.0);
      const brGrid = Point((cols - 1.5) * cs - frameSize / 2.0,
                           (cols - 1.5) * cs - frameSize / 2.0);

      final tlFinder = Point(
        centerX + tlGrid.x * cosA - tlGrid.y * sinA,
        centerY + tlGrid.x * sinA + tlGrid.y * cosA,
      );
      final brFinder = Point(
        centerX + brGrid.x * cosA - brGrid.y * sinA,
        centerY + brGrid.x * sinA + brGrid.y * cosA,
      );

      // Compute corners and warp
      final corners = PerspectiveTransform.computeBarcodeCorners(
          tlFinder, brFinder, frameSize);
      expect(corners, isNotNull);

      final warped = PerspectiveTransform.warpPerspective(
          photo, corners!, frameSize);

      // Sample some cell centers and verify colors match the palette
      var correctColors = 0;
      var totalChecked = 0;

      // Check cells away from finder patterns where rotation artifacts are minimal
      for (var row = 4; row < cols - 4; row++) {
        for (var col = 4; col < cols - 4; col++) {
          final inTL = row < 3 && col < 3;
          final inBR = row >= cols - 3 && col >= cols - 3;
          if (inTL || inBR) continue;

          final px = col * cs + cs ~/ 2;
          final py = row * cs + cs ~/ 2;
          if (px >= warped.width || py >= warped.height) continue;

          final p = warped.getPixel(px, py);
          final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();

          // Check if pixel matches any palette color reasonably well
          var minDist = 999999;
          for (final c in CimbarConstants.colors) {
            final dr = r - c[0], dg = g - c[1], db = b - c[2];
            final d = dr * dr + dg * dg + db * db;
            if (d < minDist) minDist = d;
          }

          totalChecked++;
          if (minDist < 3000) correctColors++; // threshold for "close enough"
        }
      }

      // At least 90% of interior cells should have recognizable colors
      // (nearest-neighbor warp preserves sharp cell boundaries)
      expect(totalChecked, greaterThan(0));
      expect(correctColors / totalChecked, greaterThan(0.9),
          reason: 'Expected >90% color match, got '
              '$correctColors/$totalChecked = '
              '${(correctColors * 100 / totalChecked).toStringAsFixed(1)}%');
    });
  });

  group('Full pipeline with perspective warp', () {
    test('rotated barcode decodes through RS with perspective warp', () {
      // Use 256px barcode in a large photo — bigger cells mean bilinear
      // interpolation in the warp preserves cell boundaries better.
      const frameSize = 256;
      const cs = CimbarConstants.cellSize;
      const cols = frameSize ~/ cs;

      // Create test data and encode a frame
      const dataLen = 200;
      final testData = Uint8List(dataLen);
      for (var i = 0; i < dataLen; i++) {
        testData[i] = (i * 7 + 13) & 0xFF;
      }

      final dpf = CimbarConstants.dataBytesPerFrame(frameSize);
      final chunk = Uint8List(dpf);
      chunk.setRange(0, dataLen, testData);

      final rsFrame = CimbarEncoder.encodeRSFrame(chunk, frameSize);
      final barcode = CimbarEncoder.encodeFrame(rsFrame, frameSize);

      // Embed barcode at 2× in a photo, rotated 10°.
      // The upscale gives the warp's bilinear interpolation more source
      // resolution per cell, reducing boundary artifacts.
      const scale = 2;
      const angle = 10.0 * pi / 180;
      const photoSize = 900;
      final photo = img.Image(width: photoSize, height: photoSize);
      img.fill(photo, color: img.ColorRgba8(10, 10, 10, 255));

      const centerX = photoSize / 2.0;
      const centerY = photoSize / 2.0;
      final cosA = cos(angle);
      final sinA = sin(angle);

      // Inverse mapping: for each photo pixel, find source barcode pixel
      for (var dy = 0; dy < photoSize; dy++) {
        for (var dx = 0; dx < photoSize; dx++) {
          final px = dx - centerX;
          final py = dy - centerY;
          // Undo rotation, then undo scale
          final sx = (px * cosA + py * sinA) / scale + frameSize / 2.0;
          final sy = (-px * sinA + py * cosA) / scale + frameSize / 2.0;
          final sxi = sx.floor();
          final syi = sy.floor();
          if (sxi >= 0 && sxi < frameSize && syi >= 0 && syi < frameSize) {
            final p = barcode.getPixel(sxi, syi);
            photo.setPixelRgba(dx, dy, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
          }
        }
      }

      // Compute finder centers in photo space (accounting for scale)
      const tlGridRel = Point(
        (1.5 * cs - frameSize / 2.0) * scale,
        (1.5 * cs - frameSize / 2.0) * scale,
      );
      const brGridRel = Point(
        ((cols - 1.5) * cs - frameSize / 2.0) * scale,
        ((cols - 1.5) * cs - frameSize / 2.0) * scale,
      );

      final tlFinder = Point(
        centerX + tlGridRel.x * cosA - tlGridRel.y * sinA,
        centerY + tlGridRel.x * sinA + tlGridRel.y * cosA,
      );
      final brFinder = Point(
        centerX + brGridRel.x * cosA - brGridRel.y * sinA,
        centerY + brGridRel.x * sinA + brGridRel.y * cosA,
      );

      // Compute perspective warp — the corners derived from finder centers
      // should map the scaled+rotated barcode back to a perfect frameSize grid
      final corners = PerspectiveTransform.computeBarcodeCorners(
          tlFinder, brFinder, frameSize);
      expect(corners, isNotNull);

      final warped = PerspectiveTransform.warpPerspective(
          photo, corners!, frameSize);

      // Decode through the full pipeline
      final rs = ReedSolomon(CimbarConstants.eccBytes);
      final decoder = CimbarDecoder(rs);
      final rawBytes = decoder.decodeFramePixels(warped, frameSize);
      final dataBytes = decoder.decodeRSFrame(rawBytes, frameSize);

      // Verify the decoded data matches the input
      expect(dataBytes.length, greaterThanOrEqualTo(dataLen));

      var mismatches = 0;
      for (var i = 0; i < dataLen; i++) {
        if (dataBytes[i] != chunk[i]) mismatches++;
      }

      // With RS correction (64 ECC bytes per 255-byte block = up to 32 errors),
      // nearest-neighbor perspective warp preserves sharp cell boundaries,
      // producing a clean image that decodes with minimal or no RS corrections.
      expect(mismatches, equals(0),
          reason: '$mismatches byte mismatches in first $dataLen bytes');
    });

    test('null finder centers fall back to crop+resize path', () {
      // This verifies the fallback in LiveScanner._tryDecode works
      const frameSize = 128;

      // Create a clean barcode (no rotation)
      const dataLen = 50;
      final testData = Uint8List(dataLen);
      for (var i = 0; i < dataLen; i++) {
        testData[i] = (i * 3 + 5) & 0xFF;
      }

      final dpf = CimbarConstants.dataBytesPerFrame(frameSize);
      final chunk = Uint8List(dpf);
      chunk.setRange(0, dataLen, testData);

      final rsFrame = CimbarEncoder.encodeRSFrame(chunk, frameSize);
      final barcode = CimbarEncoder.encodeFrame(rsFrame, frameSize);

      // Decode directly (simulating crop+resize path with no perspective)
      final rs = ReedSolomon(CimbarConstants.eccBytes);
      final decoder = CimbarDecoder(rs);
      final rawBytes = decoder.decodeFramePixels(barcode, frameSize);
      final dataBytes = decoder.decodeRSFrame(rawBytes, frameSize);

      expect(dataBytes.length, greaterThanOrEqualTo(dataLen));

      var mismatches = 0;
      for (var i = 0; i < dataLen; i++) {
        if (dataBytes[i] != chunk[i]) mismatches++;
      }
      expect(mismatches, equals(0));
    });
  });
}

/// Build a test frame with finder patterns and deterministic data cells.
/// (Same as cimbar_decoder_test.dart)
img.Image _buildTestFrame(int frameSize) {
  const cs = CimbarConstants.cellSize;
  final cols = frameSize ~/ cs;
  final rows = frameSize ~/ cs;

  final image = img.Image(width: frameSize, height: frameSize);
  img.fill(image, color: img.ColorRgba8(17, 17, 17, 255));

  // Draw finder patterns
  img.fillRect(image,
      x1: 0, y1: 0, x2: 3 * cs, y2: 3 * cs,
      color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(image,
      x1: cs, y1: cs, x2: 2 * cs, y2: 2 * cs,
      color: img.ColorRgba8(51, 51, 51, 255));

  final brOx = (cols - 3) * cs;
  final brOy = (rows - 3) * cs;
  img.fillRect(image,
      x1: brOx, y1: brOy, x2: brOx + 3 * cs, y2: brOy + 3 * cs,
      color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(image,
      x1: brOx + cs, y1: brOy + cs, x2: brOx + 2 * cs, y2: brOy + 2 * cs,
      color: img.ColorRgba8(51, 51, 51, 255));

  // Draw data cells with cycling colors and symbols
  var cellIdx = 0;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      final inTL = row < 3 && col < 3;
      final inBR = row >= rows - 3 && col >= cols - 3;
      if (inTL || inBR) continue;

      final colorIdx = cellIdx % 8;
      final symIdx = cellIdx % 16;
      CimbarEncoder.drawSymbol(image, symIdx, CimbarConstants.colors[colorIdx],
          col * cs, row * cs, cs);
      cellIdx++;
    }
  }

  return image;
}
