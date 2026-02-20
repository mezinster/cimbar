import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';

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
}
