import 'dart:math';

import 'package:image/image.dart' as img;

import '../models/barcode_rect.dart';

/// Result of [FrameLocator.locate]: the cropped image plus bounding box.
class LocateResult {
  final img.Image cropped;
  final BarcodeRect boundingBox;

  /// Optional finder pattern center coordinates (in original image space).
  /// Present when anchor-based detection succeeds; null on fallback.
  final Point<double>? tlFinderCenter;
  final Point<double>? brFinderCenter;

  const LocateResult({
    required this.cropped,
    required this.boundingBox,
    this.tlFinderCenter,
    this.brFinderCenter,
  });
}

/// Internal candidate from the horizontal/vertical scan.
class _FinderCandidate {
  double centerX;
  double centerY;
  double hSize; // horizontal run total width
  double vSize; // vertical run total width
  double contrast; // bright-dark luma difference
  int hitCount;

  _FinderCandidate({
    required this.centerX,
    required this.centerY,
    required this.hSize,
    this.vSize = 0,
    this.contrast = 0,
    this.hitCount = 1,
  });
}

/// Finds the CimBar barcode region in a camera photo and returns a cropped
/// square image suitable for decoding.
class FrameLocator {
  FrameLocator._();

  // --- Tuning constants ---
  /// High threshold to match only the white finder cells (luma ~255),
  /// not colored barcode cells (luma 64-171).
  static const int _brightThreshold = 180;
  /// Minimum pattern total width in downscaled pixels.
  static const int _minFinderPx = 6;
  /// Bright-dark luma difference must be meaningful.
  static const int _minContrast = 30;
  static const int _downscale = 2;

  /// Locate and crop the CimBar barcode region from a camera [photo].
  ///
  /// Uses anchor-based finder pattern detection: scans for the
  /// bright→dark→bright pattern of CimBar's 3×3 finder blocks.
  /// Falls back to luma-threshold bounding box if fewer than 2 finders found.
  ///
  /// Throws [StateError] if no barcode region is found.
  static LocateResult locate(img.Image photo) {
    final origW = photo.width;
    final origH = photo.height;

    // Downscale for fast scanning
    final smallW = max(1, origW ~/ _downscale);
    final smallH = max(1, origH ~/ _downscale);
    final small = img.copyResize(photo, width: smallW, height: smallH,
        interpolation: img.Interpolation.average);

    // Build luma buffer
    final luma = List<int>.filled(smallW * smallH, 0);
    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        final p = small.getPixel(x, y);
        luma[y * smallW + x] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      }
    }

    // Phase 1: Horizontal row scan
    final candidates = _scanHorizontal(luma, smallW, smallH);

    // Phase 2: Vertical confirmation
    _confirmVertical(candidates, luma, smallW, smallH);

    // Phase 3: Deduplication
    final mergeRadius = max(smallW, smallH) / 30.0;
    final merged = _deduplicateCandidates(candidates, mergeRadius);

    // Phase 4: Selection & classification
    final finders = _selectAndClassify(merged);

    // Phase 5: Crop from anchors or fallback
    if (finders != null) {
      return _computeCropFromAnchors(
          photo, finders.$1, finders.$2, origW, origH);
    }

    // Fallback to luma-threshold approach
    return _locateFallback(photo, luma, smallW, smallH, origW, origH);
  }

  /// Phase 1: Scan horizontal rows for bright→dark→bright patterns.
  ///
  /// Uses a high bright threshold (180) so only the white finder regions
  /// register as "bright" — colored barcode cells (luma 64-171) read as
  /// "not bright." Scans every 2 rows for density: the finder's dark center
  /// is only ~4px tall after 2× downscale, so sparse scanning misses it.
  static List<_FinderCandidate> _scanHorizontal(
      List<int> luma, int w, int h) {
    final candidates = <_FinderCandidate>[];
    // Scan every 2 rows — fast enough (O(w*h/2)) and ensures we hit
    // the ~4px dark center of finders at any scale.
    const step = 2;

    for (var y = 0; y < h; y += step) {
      // Track runs: each run is (startX, length, isBright)
      var runStart = 0;
      var runBright = luma[y * w] >= _brightThreshold;
      final runs = <(int, int, bool)>[]; // (startX, length, isBright)

      for (var x = 1; x <= w; x++) {
        final bright = x < w ? luma[y * w + x] >= _brightThreshold : !runBright;
        if (bright != runBright || x == w) {
          runs.add((runStart, x - runStart, runBright));
          runStart = x;
          runBright = bright;
        }
      }

      // Look for bright→dark→bright sequences
      for (var i = 0; i < runs.length - 2; i++) {
        final r0 = runs[i]; // should be bright
        final r1 = runs[i + 1]; // should be dark
        final r2 = runs[i + 2]; // should be bright

        if (!r0.$3 || r1.$3 || !r2.$3) continue; // wrong polarity

        final brightLen0 = r0.$2;
        final darkLen = r1.$2;
        final brightLen2 = r2.$2;
        final totalLen = brightLen0 + darkLen + brightLen2;

        if (totalLen < _minFinderPx) continue;

        // Relaxed ratio check: the shorter bright run must be within 4× of
        // the dark run. The longer bright run can be anything — when the
        // finder is near a bright background (wall, etc.), one side extends
        // far beyond the finder boundary.
        final minBright = min(brightLen0, brightLen2);
        final ratio = minBright / darkLen;
        if (ratio < 0.25 || ratio > 4.0) continue;

        // Compute contrast: average luma of bright vs dark portions
        var brightSum = 0;
        var darkSum = 0;
        for (var x = r0.$1; x < r0.$1 + brightLen0; x++) {
          brightSum += luma[y * w + x];
        }
        for (var x = r1.$1; x < r1.$1 + darkLen; x++) {
          darkSum += luma[y * w + x];
        }
        final brightAvg = brightSum / brightLen0;
        final darkAvg = darkSum / darkLen;
        final contrast = brightAvg - darkAvg;

        if (contrast < _minContrast) continue;

        final centerX = r0.$1 + totalLen / 2.0;
        candidates.add(_FinderCandidate(
          centerX: centerX,
          centerY: y.toDouble(),
          hSize: totalLen.toDouble(),
          contrast: contrast,
        ));
      }
    }
    return candidates;
  }

  /// Phase 2: Confirm each horizontal hit with a vertical scan at centerX.
  static void _confirmVertical(
      List<_FinderCandidate> candidates, List<int> luma, int w, int h) {
    candidates.removeWhere((c) {
      final x = c.centerX.round().clamp(0, w - 1);

      // Scan vertical column at x
      var runStart = 0;
      var runBright = luma[x] >= _brightThreshold;
      final runs = <(int, int, bool)>[];

      for (var y = 1; y <= h; y++) {
        final bright =
            y < h ? luma[y * w + x] >= _brightThreshold : !runBright;
        if (bright != runBright || y == h) {
          runs.add((runStart, y - runStart, runBright));
          runStart = y;
          runBright = bright;
        }
      }

      // Find the bright→dark→bright triplet closest to c.centerY
      double bestDist = double.infinity;
      double bestVSize = 0;
      bool found = false;

      for (var i = 0; i < runs.length - 2; i++) {
        final r0 = runs[i];
        final r1 = runs[i + 1];
        final r2 = runs[i + 2];

        if (!r0.$3 || r1.$3 || !r2.$3) continue;

        final totalLen = r0.$2 + r1.$2 + r2.$2;
        if (totalLen < _minFinderPx) continue;

        // Same relaxed ratio: shorter bright run within 4× of dark
        final minBright = min(r0.$2, r2.$2);
        final ratio = minBright / r1.$2;
        if (ratio < 0.25 || ratio > 4.0) continue;

        // Check that vertical width is within 2× of horizontal
        final sizeRatio = totalLen / c.hSize;
        if (sizeRatio < 0.5 || sizeRatio > 2.0) continue;

        final vCenter = r0.$1 + totalLen / 2.0;
        final dist = (vCenter - c.centerY).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestVSize = totalLen.toDouble();
          found = true;
          c.centerY = vCenter;
        }
      }

      if (found) {
        c.vSize = bestVSize;
      }
      return !found; // remove if no vertical confirmation
    });
  }

  /// Phase 3: Merge candidates whose centers are within [radius] of each other.
  static List<_FinderCandidate> _deduplicateCandidates(
      List<_FinderCandidate> candidates, double radius) {
    if (candidates.isEmpty) return [];

    final merged = <_FinderCandidate>[];
    final used = List<bool>.filled(candidates.length, false);

    for (var i = 0; i < candidates.length; i++) {
      if (used[i]) continue;

      var sumX = candidates[i].centerX;
      var sumY = candidates[i].centerY;
      var maxH = candidates[i].hSize;
      var maxV = candidates[i].vSize;
      var maxContrast = candidates[i].contrast;
      var count = 1;

      for (var j = i + 1; j < candidates.length; j++) {
        if (used[j]) continue;
        final dx = candidates[i].centerX - candidates[j].centerX;
        final dy = candidates[i].centerY - candidates[j].centerY;
        if (sqrt(dx * dx + dy * dy) <= radius) {
          sumX += candidates[j].centerX;
          sumY += candidates[j].centerY;
          maxH = max(maxH, candidates[j].hSize);
          maxV = max(maxV, candidates[j].vSize);
          maxContrast = max(maxContrast, candidates[j].contrast);
          count++;
          used[j] = true;
        }
      }

      merged.add(_FinderCandidate(
        centerX: sumX / count,
        centerY: sumY / count,
        hSize: maxH,
        vSize: maxV,
        contrast: maxContrast,
        hitCount: count,
      ));
    }

    return merged;
  }

  /// Phase 4: Score and select top 2, classify as TL/BR.
  /// Returns (tl, br) or null if fewer than 2 candidates.
  static (_FinderCandidate, _FinderCandidate)? _selectAndClassify(
      List<_FinderCandidate> candidates) {
    if (candidates.length < 2) return null;

    // Score: hitCount (most important), aspect ratio closeness, contrast
    candidates.sort((a, b) {
      final aScore = _score(a);
      final bScore = _score(b);
      return bScore.compareTo(aScore); // descending
    });

    final c0 = candidates[0];
    final c1 = candidates[1];

    // Classify: smaller (x+y) sum → TL, larger → BR
    final sum0 = c0.centerX + c0.centerY;
    final sum1 = c1.centerX + c1.centerY;

    if (sum0 <= sum1) {
      return (c0, c1);
    } else {
      return (c1, c0);
    }
  }

  static double _score(_FinderCandidate c) {
    final aspectRatio =
        c.vSize > 0 ? min(c.hSize, c.vSize) / max(c.hSize, c.vSize) : 0.5;
    return c.hitCount * 10.0 + aspectRatio * 5.0 + c.contrast / 50.0;
  }

  /// Phase 5: Compute crop region from TL and BR finder centers.
  static LocateResult _computeCropFromAnchors(
    img.Image photo,
    _FinderCandidate tl,
    _FinderCandidate br,
    int origW,
    int origH,
  ) {
    // Scale finder centers back to original coordinates
    final tlX = tl.centerX * _downscale;
    final tlY = tl.centerY * _downscale;
    final brX = br.centerX * _downscale;
    final brY = br.centerY * _downscale;

    // TL finder center is at grid cell (1,1), BR at (cols-2, rows-2).
    // The diagonal distance spans (cols-3) cells in both x and y.
    // Full barcode is (cols) cells wide, so:
    //   barcode_side = diagonal_component * cols / (cols - 3)
    //
    // We estimate cell size from the diagonal:
    //   diagonal_dx = (cols - 3) * cellSize
    //   cellSize ≈ dx / (cols - 3)
    //
    // But we don't know cols yet. Use the finder sizes to estimate.
    // Each finder is 3 cells wide, so:
    //   cellSize ≈ finderWidth / 3
    final finderWidthPx =
        (max(tl.hSize, tl.vSize) + max(br.hSize, br.vSize)) / 2.0 *
            _downscale;
    final cellSize = finderWidthPx / 3.0;

    if (cellSize < 1) {
      // Finders too tiny — fall back
      return _locateFallbackFromPhoto(photo, origW, origH);
    }

    // The barcode extends 1.5 cells beyond the finder centers on each side.
    // TL finder center is at cell (1,1), so barcode starts at cell (-0.5, -0.5)
    //   relative to finder center → 1.5 cells before the center.
    // BR finder center is at cell (cols-2, rows-2), barcode ends at
    //   cell (cols-0.5, rows-0.5) → 1.5 cells after the center.
    final padding = cellSize * 1.5;

    var cropLeft = (tlX - padding).round();
    var cropTop = (tlY - padding).round();
    var cropRight = (brX + padding).round();
    var cropBottom = (brY + padding).round();

    // Make square
    var cropW = cropRight - cropLeft;
    var cropH = cropBottom - cropTop;
    final side = max(cropW, cropH);
    final cx = (cropLeft + cropRight) ~/ 2;
    final cy = (cropTop + cropBottom) ~/ 2;

    // Add 2% margin
    final margin = (side * 0.02).round();
    final totalSide = side + 2 * margin;

    var cropX = cx - totalSide ~/ 2;
    var cropY = cy - totalSide ~/ 2;

    // Clamp to image bounds
    cropX = max(0, min(cropX, origW - totalSide));
    cropY = max(0, min(cropY, origH - totalSide));
    final cropSide = min(totalSide, min(origW - cropX, origH - cropY));

    return LocateResult(
      cropped: img.copyCrop(photo,
          x: cropX, y: cropY, width: cropSide, height: cropSide),
      boundingBox:
          BarcodeRect(x: cropX, y: cropY, width: cropSide, height: cropSide),
      tlFinderCenter: Point(tlX, tlY),
      brFinderCenter: Point(brX, brY),
    );
  }

  /// Fallback: luma-threshold bounding box (original algorithm).
  static LocateResult _locateFallback(
    img.Image photo,
    List<int> luma,
    int smallW,
    int smallH,
    int origW,
    int origH,
  ) {
    const lumaThreshold = 30;
    var minX = smallW;
    var minY = smallH;
    var maxX = 0;
    var maxY = 0;
    var found = false;

    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        if (luma[y * smallW + x] > lumaThreshold) {
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

    var oMinX = minX * _downscale;
    var oMinY = minY * _downscale;
    var oMaxX = min((maxX + 1) * _downscale, origW);
    var oMaxY = min((maxY + 1) * _downscale, origH);

    var bw = oMaxX - oMinX;
    var bh = oMaxY - oMinY;

    final margin = (max(bw, bh) * 0.02).round();
    oMinX = max(0, oMinX - margin);
    oMinY = max(0, oMinY - margin);
    oMaxX = min(origW, oMaxX + margin);
    oMaxY = min(origH, oMaxY + margin);

    bw = oMaxX - oMinX;
    bh = oMaxY - oMinY;

    final side = max(bw, bh);
    final cx = oMinX + bw ~/ 2;
    final cy = oMinY + bh ~/ 2;

    var cropX = cx - side ~/ 2;
    var cropY = cy - side ~/ 2;

    cropX = max(0, min(cropX, origW - side));
    cropY = max(0, min(cropY, origH - side));
    final cropSide = min(side, min(origW - cropX, origH - cropY));

    return LocateResult(
      cropped: img.copyCrop(photo,
          x: cropX, y: cropY, width: cropSide, height: cropSide),
      boundingBox:
          BarcodeRect(x: cropX, y: cropY, width: cropSide, height: cropSide),
    );
  }

  /// Convenience fallback when we don't have a pre-computed luma buffer.
  static LocateResult _locateFallbackFromPhoto(
      img.Image photo, int origW, int origH) {
    final smallW = max(1, origW ~/ _downscale);
    final smallH = max(1, origH ~/ _downscale);
    final small = img.copyResize(photo, width: smallW, height: smallH,
        interpolation: img.Interpolation.average);

    final luma = List<int>.filled(smallW * smallH, 0);
    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        final p = small.getPixel(x, y);
        luma[y * smallW + x] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      }
    }

    return _locateFallback(photo, luma, smallW, smallH, origW, origH);
  }
}
