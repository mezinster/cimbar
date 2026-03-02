import 'dart:math';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';

/// Average-hash symbol detector for camera decode.
///
/// Pre-computes 64-bit average hashes for each of the 16 CimBar symbols,
/// then matches camera cells via Hamming distance. Tolerates ~20 bits of
/// noise per cell (~31% pixel corruption), far more robust than the 5-pixel
/// threshold approach used for GIF decode.
class SymbolHashDetector {
  /// 64-bit reference hash for each symbol index 0-15.
  final List<int> _referenceHashes;

  /// Pre-computed at construction time.
  SymbolHashDetector() : _referenceHashes = _buildReferenceHashes();

  /// Access reference hashes (for testing).
  List<int> get referenceHashes => List.unmodifiable(_referenceHashes);

  /// Build reference hashes for all 16 symbols.
  ///
  /// Renders each symbol on a white-ish foreground (luma ~186) to match
  /// the average CimBar palette color, then computes the average hash.
  static List<int> _buildReferenceHashes() {
    const cs = CimbarConstants.cellSize; // 8
    final hashes = <int>[];

    for (var symIdx = 0; symIdx < 16; symIdx++) {
      // Render symbol using a mid-brightness gray foreground.
      // We use (180, 180, 180) — close to average palette luma — so the
      // hash captures the dot pattern (black vs not-black), not color.
      final cell = _renderSymbol(symIdx, 180, 180, 180, cs);
      hashes.add(_computeHash(cell, cs));
    }

    return hashes;
  }

  /// Render a single symbol into an 8x8 luma buffer.
  /// Returns a flat list of [cs*cs] luma values.
  static List<int> _renderSymbol(int symIdx, int fr, int fg, int fb, int cs) {
    final luma = List<int>.filled(cs * cs, 0);
    final fgLuma = (0.299 * fr + 0.587 * fg + 0.114 * fb).round();

    // Fill with foreground luma
    for (var i = 0; i < cs * cs; i++) {
      luma[i] = fgLuma;
    }

    // Paint black dots at corners where bit is 0
    final q = max(1, (cs * 0.28).floor());
    final h = max(1, (q * 0.75).floor());

    void paintBlack(int bx, int by) {
      for (var dy = 0; dy < 2 * h; dy++) {
        for (var dx = 0; dx < 2 * h; dx++) {
          final px = bx + dx;
          final py = by + dy;
          if (px >= 0 && px < cs && py >= 0 && py < cs) {
            luma[py * cs + px] = 0;
          }
        }
      }
    }

    if ((symIdx >> 3) & 1 == 0) paintBlack(q - h, q - h);           // TL
    if ((symIdx >> 2) & 1 == 0) paintBlack(cs - q - h, q - h);      // TR
    if ((symIdx >> 1) & 1 == 0) paintBlack(q - h, cs - q - h);      // BL
    if ((symIdx >> 0) & 1 == 0) paintBlack(cs - q - h, cs - q - h); // BR

    return luma;
  }

  /// Compute 64-bit average hash from an 8x8 luma buffer.
  /// Bit 63 = pixel (0,0), bit 0 = pixel (7,7).
  /// Each bit is 1 if pixel luma > mean, else 0.
  static int _computeHash(List<int> luma, int cs) {
    // Compute mean
    var sum = 0;
    final total = cs * cs;
    for (var i = 0; i < total; i++) {
      sum += luma[i];
    }
    final mean = sum / total;

    // Build hash
    var hash = 0;
    for (var i = 0; i < total; i++) {
      hash = (hash << 1) | (luma[i] > mean ? 1 : 0);
    }
    return hash;
  }

  /// Count differing bits between two 64-bit values (Hamming distance).
  static int popcount(int x) {
    // Kernighan's bit counting
    var count = 0;
    while (x != 0) {
      x &= x - 1;
      count++;
    }
    return count;
  }

  /// Detect symbol from an image cell using average hash matching.
  ///
  /// Extracts 8x8 luma values from [frame] at position ([ox], [oy]),
  /// computes the average hash, and finds the symbol with minimum
  /// Hamming distance.
  ///
  /// Returns the best-matching symbol index (0-15).
  int detectSymbol(img.Image frame, int ox, int oy, int cellSize) {
    final luma = _extractLuma(frame, ox, oy, cellSize);
    final hash = _computeHash(luma, cellSize);
    return _bestMatch(hash);
  }

  /// Detect symbol with adaptive fuzzy drift-aware matching.
  ///
  /// First tries ±1 (9 positions). If the best match has h > [wideThreshold],
  /// expands to ±[wideRadius] (default 3 → 49 positions) to handle larger
  /// camera misalignments. This adaptive approach keeps well-aligned images
  /// precise (no spurious drift from finder pattern bleed) while allowing
  /// fast convergence on misaligned camera captures.
  ///
  /// [driftX] and [driftY] are accumulated drift offsets from previous cells.
  ///
  /// Returns (symbolIndex, bestDriftDx, bestDriftDy, hammingDistance).
  (int, int, int, int) detectSymbolFuzzy(
    img.Image frame,
    int ox,
    int oy,
    int cellSize, {
    int driftX = 0,
    int driftY = 0,
    int wideRadius = 3,
    int wideThreshold = 20,
  }) {
    // Apply accumulated drift
    final baseX = ox + driftX;
    final baseY = oy + driftY;

    var bestSym = 0;
    var bestDist = 65; // max possible is 64
    var bestDx = 0;
    var bestDy = 0;

    // Phase 1: narrow search (±1), center first for fast early exit
    for (final off in _narrowOffsets) {
      final dx = off[0], dy = off[1];
      final sx = baseX + dx;
      final sy = baseY + dy;

      if (sx < 0 || sy < 0 ||
          sx + cellSize > frame.width ||
          sy + cellSize > frame.height) {
        continue;
      }

      final luma = _extractLuma(frame, sx, sy, cellSize);
      final hash = _computeHash(luma, cellSize);

      for (var i = 0; i < 16; i++) {
        final dist = popcount(hash ^ _referenceHashes[i]);
        if (dist < bestDist) {
          bestDist = dist;
          bestSym = i;
          bestDx = dx;
          bestDy = dy;
          if (dist == 0) return (bestSym, bestDx, bestDy, 0);
        }
      }
    }

    // Phase 2: if narrow search gave a poor match, widen to ±wideRadius
    if (bestDist > wideThreshold) {
      for (var dy = -wideRadius; dy <= wideRadius; dy++) {
        for (var dx = -wideRadius; dx <= wideRadius; dx++) {
          // Skip offsets already covered in phase 1
          if (dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1) continue;

          final sx = baseX + dx;
          final sy = baseY + dy;

          if (sx < 0 || sy < 0 ||
              sx + cellSize > frame.width ||
              sy + cellSize > frame.height) {
            continue;
          }

          final luma = _extractLuma(frame, sx, sy, cellSize);
          final hash = _computeHash(luma, cellSize);

          for (var i = 0; i < 16; i++) {
            final dist = popcount(hash ^ _referenceHashes[i]);
            if (dist < bestDist) {
              bestDist = dist;
              bestSym = i;
              bestDx = dx;
              bestDy = dy;
              if (dist == 0) return (bestSym, bestDx, bestDy, 0);
            }
          }
        }
      }
    }

    return (bestSym, bestDx, bestDy, bestDist);
  }

  /// Narrow search offsets: center first, then 4 sides, then 4 corners.
  /// Center-first ordering enables fast early exit on well-aligned images.
  static const _narrowOffsets = [
    [0, 0],   // center
    [-1, 0],  // left
    [1, 0],   // right
    [0, -1],  // up
    [0, 1],   // down
    [-1, -1], // top-left
    [1, -1],  // top-right
    [-1, 1],  // bottom-left
    [1, 1],   // bottom-right
  ];

  /// Find symbol index with minimum Hamming distance to [hash].
  int _bestMatch(int hash) {
    var bestSym = 0;
    var bestDist = 65;
    for (var i = 0; i < 16; i++) {
      final dist = popcount(hash ^ _referenceHashes[i]);
      if (dist < bestDist) {
        bestDist = dist;
        bestSym = i;
        if (dist == 0) return bestSym;
      }
    }
    return bestSym;
  }

  /// Extract 8x8 luma values from an image at position (ox, oy).
  static List<int> _extractLuma(img.Image frame, int ox, int oy, int cs) {
    final luma = List<int>.filled(cs * cs, 0);
    for (var row = 0; row < cs; row++) {
      for (var col = 0; col < cs; col++) {
        final px = min(ox + col, frame.width - 1);
        final py = min(oy + row, frame.height - 1);
        final p = frame.getPixel(px, py);
        luma[row * cs + col] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      }
    }
    return luma;
  }
}
