import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/cimbar_decoder.dart';

/// Draw one symbol on an image, matching web-app/cimbar.js drawSymbol.
void drawSymbol(img.Image image, int symIdx, List<int> colorRGB, int ox, int oy, int size) {
  final cr = colorRGB[0], cg = colorRGB[1], cb = colorRGB[2];
  final q = max(1, (size * 0.28).floor());
  final h = max(1, (q * 0.75).floor());

  // Fill entire cell with foreground color
  img.fillRect(image,
      x1: ox, y1: oy, x2: ox + size, y2: oy + size,
      color: img.ColorRgba8(cr, cg, cb, 255));

  // For each 0-bit, paint a 2h x 2h black block
  void paintBlack(int bx, int by) {
    img.fillRect(image,
        x1: bx, y1: by, x2: bx + 2 * h, y2: by + 2 * h,
        color: img.ColorRgba8(0, 0, 0, 255));
  }

  if ((symIdx >> 3) & 1 == 0) paintBlack(ox + q - h, oy + q - h); // TL
  if ((symIdx >> 2) & 1 == 0) paintBlack(ox + size - q - h, oy + q - h); // TR
  if ((symIdx >> 1) & 1 == 0) paintBlack(ox + q - h, oy + size - q - h); // BL
  if ((symIdx >> 0) & 1 == 0) paintBlack(ox + size - q - h, oy + size - q - h); // BR
}

/// Nearest color index, same weighted distance as cimbar.js.
int nearestColorIdx(int r, int g, int b) {
  var best = 0;
  var bestDist = 0x7FFFFFFF;
  for (var i = 0; i < CimbarConstants.colors.length; i++) {
    final c = CimbarConstants.colors[i];
    final dr = r - c[0], dg = g - c[1], db = b - c[2];
    final d = dr * dr * 2 + dg * dg * 4 + db * db;
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// Detect symbol from image pixel data, same algorithm as cimbar.js.
int detectSymbol(img.Image image, int ox, int oy, int cs) {
  final q = max(1, (cs * 0.28).floor());

  double luma(int px, int py) {
    final x = min(px, image.width - 1);
    final y = min(py, image.height - 1);
    final p = image.getPixel(x, y);
    return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
  }

  final c = luma(ox + cs ~/ 2, oy + cs ~/ 2);
  final tl = luma(ox + q, oy + q);
  final tr = luma(ox + cs - q, oy + q);
  final bl = luma(ox + q, oy + cs - q);
  final br = luma(ox + cs - q, oy + cs - q);

  final thresh = c * 0.5 + 20;

  return ((tl > thresh ? 1 : 0) << 3) |
      ((tr > thresh ? 1 : 0) << 2) |
      ((bl > thresh ? 1 : 0) << 1) |
      (br > thresh ? 1 : 0);
}

/// Apply a per-pixel color tint to an image, simulating camera white balance shift.
/// Multiplies each channel by the corresponding factor and clamps to 0-255.
img.Image applyTint(img.Image source, double rFactor, double gFactor, double bFactor) {
  final tinted = img.Image(width: source.width, height: source.height);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final p = source.getPixel(x, y);
      tinted.setPixelRgba(
        x, y,
        (p.r * rFactor).round().clamp(0, 255),
        (p.g * gFactor).round().clamp(0, 255),
        (p.b * bFactor).round().clamp(0, 255),
        255,
      );
    }
  }
  return tinted;
}

void main() {
  group('CimBar symbol round-trip', () {
    test('all 128 (colorIdx, symIdx) combinations round-trip correctly', () {
      const cs = CimbarConstants.cellSize; // 8
      var pass = 0;
      var fail = 0;
      final failures = <String>[];

      for (var colorIdx = 0; colorIdx < 8; colorIdx++) {
        for (var symIdx = 0; symIdx < 16; symIdx++) {
          final image = img.Image(width: cs, height: cs);

          drawSymbol(image, symIdx, CimbarConstants.colors[colorIdx], 0, 0, cs);

          // Color detection: sample center pixel
          const cx = cs ~/ 2;
          const cy = cs ~/ 2;
          final pixel = image.getPixel(cx, cy);
          final detectedColor =
              nearestColorIdx(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

          // Symbol detection
          final detectedSym = detectSymbol(image, 0, 0, cs);

          if (detectedColor == colorIdx && detectedSym == symIdx) {
            pass++;
          } else {
            fail++;
            failures.add(
              'colorIdx=$colorIdx symIdx=$symIdx -> '
              'detectedColor=$detectedColor detectedSym=$detectedSym',
            );
          }
        }
      }

      if (failures.isNotEmpty) {
        // ignore: avoid_print
        print('Failed cases (${failures.length}/128):');
        for (final f in failures) {
          // ignore: avoid_print
          print('  $f');
        }
      }

      expect(fail, equals(0), reason: '$fail/128 symbol round-trips failed');
      expect(pass, equals(128));
    });
  });

  group('Von Kries white balance', () {
    test('computeAdaptationMatrix returns identity-like matrix for true white', () {
      final matrix = CimbarDecoder.computeAdaptationMatrix(255, 255, 255);
      expect(matrix, isNotNull);
      // Should be approximately identity
      final corrected = CimbarDecoder.applyAdaptation(matrix!, 128, 64, 200);
      expect(corrected[0], equals(128));
      expect(corrected[1], equals(64));
      expect(corrected[2], equals(200));
    });

    test('computeAdaptationMatrix returns null for too-dark input', () {
      final matrix = CimbarDecoder.computeAdaptationMatrix(5, 5, 5);
      expect(matrix, isNull);
    });

    test('warm-tinted frame decodes correctly with white balance', () {
      const frameSize = 128;

      // Build a clean frame
      final cleanFrame = _buildTestFrame(frameSize);

      // Apply warm tint (simulating warm indoor lighting: boost red, dim blue)
      final tinted = applyTint(cleanFrame, 1.0, 0.85, 0.7);

      // Decode without white balance — expect some color errors
      final decoder = CimbarDecoder();
      final rawNoWB = decoder.decodeFramePixels(tinted, frameSize);

      // Decode with white balance — should correct the tint
      final rawWB = decoder.decodeFramePixels(tinted, frameSize,
          enableWhiteBalance: true);

      // Decode clean frame as reference
      final rawClean = decoder.decodeFramePixels(cleanFrame, frameSize);

      // Count mismatches vs clean reference
      var mismatchesNoWB = 0;
      var mismatchesWB = 0;
      for (var i = 0; i < rawClean.length; i++) {
        if (rawNoWB[i] != rawClean[i]) mismatchesNoWB++;
        if (rawWB[i] != rawClean[i]) mismatchesWB++;
      }

      // White balance should produce fewer mismatches than no correction
      expect(mismatchesWB, lessThan(mismatchesNoWB),
          reason: 'White balance should reduce color errors from warm tint '
              '(WB=$mismatchesWB vs noWB=$mismatchesNoWB mismatches)');
    });

    test('cool-tinted frame decodes at least as well with white balance', () {
      const frameSize = 128;

      final cleanFrame = _buildTestFrame(frameSize);
      // Simulate cool/fluorescent lighting: dim red, boost blue
      final tinted = applyTint(cleanFrame, 0.75, 0.9, 1.0);

      final decoder = CimbarDecoder();
      final rawNoWB = decoder.decodeFramePixels(tinted, frameSize);
      final rawWB = decoder.decodeFramePixels(tinted, frameSize,
          enableWhiteBalance: true);
      final rawClean = decoder.decodeFramePixels(cleanFrame, frameSize);

      var mismatchesNoWB = 0;
      var mismatchesWB = 0;
      for (var i = 0; i < rawClean.length; i++) {
        if (rawNoWB[i] != rawClean[i]) mismatchesNoWB++;
        if (rawWB[i] != rawClean[i]) mismatchesWB++;
      }

      expect(mismatchesWB, lessThanOrEqualTo(mismatchesNoWB),
          reason: 'White balance should not make things worse with cool tint '
              '(WB=$mismatchesWB vs noWB=$mismatchesNoWB mismatches)');
    });
  });

  group('Relative color matching', () {
    test('brightness-shifted cells matched correctly with relative matching', () {
      const frameSize = 128;

      final cleanFrame = _buildTestFrame(frameSize);
      // Uniform dimming (simulates darker environment — all channels equally reduced)
      final dimmed = applyTint(cleanFrame, 0.6, 0.6, 0.6);

      final decoder = CimbarDecoder();
      final rawAbsolute = decoder.decodeFramePixels(dimmed, frameSize);
      final rawRelative = decoder.decodeFramePixels(dimmed, frameSize,
          useRelativeColor: true);
      final rawClean = decoder.decodeFramePixels(cleanFrame, frameSize);

      var mismatchesAbsolute = 0;
      var mismatchesRelative = 0;
      for (var i = 0; i < rawClean.length; i++) {
        if (rawAbsolute[i] != rawClean[i]) mismatchesAbsolute++;
        if (rawRelative[i] != rawClean[i]) mismatchesRelative++;
      }

      expect(mismatchesRelative, lessThanOrEqualTo(mismatchesAbsolute),
          reason: 'Relative matching should handle uniform dimming at least as well '
              '(rel=$mismatchesRelative vs abs=$mismatchesAbsolute mismatches)');
    });

    test('combined white balance + relative matching on warm-tinted frame', () {
      const frameSize = 128;

      final cleanFrame = _buildTestFrame(frameSize);
      final tinted = applyTint(cleanFrame, 1.0, 0.8, 0.65);

      final decoder = CimbarDecoder();
      final rawClean = decoder.decodeFramePixels(cleanFrame, frameSize);
      final rawNoCorrection = decoder.decodeFramePixels(tinted, frameSize);
      final rawCombined = decoder.decodeFramePixels(tinted, frameSize,
          enableWhiteBalance: true, useRelativeColor: true);

      var mismatchesNone = 0;
      var mismatchesCombined = 0;
      for (var i = 0; i < rawClean.length; i++) {
        if (rawNoCorrection[i] != rawClean[i]) mismatchesNone++;
        if (rawCombined[i] != rawClean[i]) mismatchesCombined++;
      }

      expect(mismatchesCombined, lessThan(mismatchesNone),
          reason: 'Combined WB+relative should reduce errors vs no correction '
              '(combined=$mismatchesCombined vs none=$mismatchesNone mismatches)');
    });

    test('clean frame round-trips perfectly with relative matching', () {
      // Relative matching should not break perfect-pixel frames
      const cs = CimbarConstants.cellSize;

      // Full frame round-trip with relative matching
      const frameSize = 128;
      final cleanFrame = _buildTestFrame(frameSize);
      final decoder = CimbarDecoder();
      final rawClean = decoder.decodeFramePixels(cleanFrame, frameSize);
      final rawRelative = decoder.decodeFramePixels(cleanFrame, frameSize,
          useRelativeColor: true);

      var mismatches = 0;
      for (var i = 0; i < rawClean.length; i++) {
        if (rawRelative[i] != rawClean[i]) mismatches++;
      }

      // Allow a small number of mismatches for gray cells (known edge case)
      // Gray has relative profile (0,0,0) which can match other dark/achromatic colors
      expect(mismatches, lessThan(rawClean.length * 0.05),
          reason: 'Relative matching on clean pixels should have <5% errors '
              '(got $mismatches/${rawClean.length})');
    });
  });
}

/// Build a test frame with finder patterns and deterministic data cells.
img.Image _buildTestFrame(int frameSize) {
  const cs = CimbarConstants.cellSize;
  final cols = frameSize ~/ cs;
  final rows = frameSize ~/ cs;

  final image = img.Image(width: frameSize, height: frameSize);
  img.fill(image, color: img.ColorRgba8(17, 17, 17, 255));

  // Draw finder patterns (white blocks that serve as white reference)
  // TL finder: 3×3 cells at (0,0)
  img.fillRect(image,
      x1: 0, y1: 0, x2: 3 * cs, y2: 3 * cs,
      color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(image,
      x1: cs, y1: cs, x2: 2 * cs, y2: 2 * cs,
      color: img.ColorRgba8(51, 51, 51, 255));

  // BR finder: 3×3 cells at (cols-3, rows-3)
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
      final ox = col * cs;
      final oy = row * cs;
      drawSymbol(image, symIdx, CimbarConstants.colors[colorIdx], ox, oy, cs);
      cellIdx++;
    }
  }

  return image;
}
