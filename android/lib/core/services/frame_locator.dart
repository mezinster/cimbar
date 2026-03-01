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
  final Point<double>? trFinderCenter;
  final Point<double>? blFinderCenter;
  final Point<double>? brFinderCenter;

  const LocateResult({
    required this.cropped,
    required this.boundingBox,
    this.tlFinderCenter,
    this.trFinderCenter,
    this.blFinderCenter,
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

    // Downsample for fast scanning (phases 1-3 only need coarse luma)
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

    // Phase 1: Horizontal row scan
    final candidates = _scanHorizontal(luma, smallW, smallH);

    // Phase 2: Vertical confirmation
    _confirmVertical(candidates, luma, smallW, smallH);

    // Phase 3: Deduplication
    final mergeRadius = max(smallW, smallH) / 30.0;
    final merged = _deduplicateCandidates(candidates, mergeRadius);

    // Phase 4: Selection & classification (samples full-res photo on
    // demand — only ~25 pixels per candidate for brightness-based TL
    // identification, vs 2M pixels for a full-res luma buffer)
    final finders = _selectAndClassify(merged, photo);

    // Phase 5: Crop from anchors or fallback
    if (finders != null) {
      return _computeCropFromAnchors(
          photo, finders.tl, finders.br, origW, origH,
          tr: finders.tr, bl: finders.bl);
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
  ///
  /// Scans only a LOCAL vertical region around the candidate's y position
  /// (±3× the horizontal pattern width) to avoid interference from colored
  /// cells or other finders elsewhere in the column.
  static void _confirmVertical(
      List<_FinderCandidate> candidates, List<int> luma, int w, int h) {
    candidates.removeWhere((c) {
      final x = c.centerX.round().clamp(0, w - 1);

      // Limit vertical scan to local region around the candidate
      final scanRadius = (c.hSize * 3).ceil();
      final yStart = max(0, c.centerY.round() - scanRadius);
      final yEnd = min(h, c.centerY.round() + scanRadius);

      // Scan vertical column at x within [yStart, yEnd)
      var runStart = yStart;
      var runBright = luma[yStart * w + x] >= _brightThreshold;
      final runs = <(int, int, bool)>[];

      for (var y = yStart + 1; y <= yEnd; y++) {
        final bright =
            y < yEnd ? luma[y * w + x] >= _brightThreshold : !runBright;
        if (bright != runBright || y == yEnd) {
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

  /// Phase 4: Classify finders as TL/TR/BL/BR using brightness-based TL
  /// identification + cross-product geometry.
  ///
  /// The TL finder has no inner white dot (solid dark center), making it
  /// darker than the other three finders. This allows rotation-invariant
  /// classification:
  /// 1. Sample center brightness of each candidate in full-res luma
  /// 2. Darkest center = TL
  /// 3. BR = farthest from TL (Euclidean distance)
  /// 4. TR vs BL: cross product sign of (BR-TL) × (C-TL)
  /// 5. Fallback: if no distinctly dark candidate, use coordinate extremes
  ///
  /// Returns null if fewer than 2 candidates found.
  static ({
    _FinderCandidate tl,
    _FinderCandidate br,
    _FinderCandidate? tr,
    _FinderCandidate? bl,
  })? _selectAndClassify(
    List<_FinderCandidate> candidates,
    img.Image photo,
  ) {
    if (candidates.length < 2) return null;

    final lumaW = photo.width;
    final lumaH = photo.height;

    // Sample center brightness of each candidate directly from full-res
    // photo — only ~25 getPixel calls per candidate (vs 2M for full buffer)
    final centerLumas = <double>[];
    for (final c in candidates) {
      // Scale from downscaled to full-res coordinates
      final cx = (c.centerX * _downscale).round().clamp(0, lumaW - 1);
      final cy = (c.centerY * _downscale).round().clamp(0, lumaH - 1);

      // Sample a 5×5 patch around the center for robustness
      var sum = 0.0;
      var count = 0;
      for (var dy = -2; dy <= 2; dy++) {
        final sy = cy + dy;
        if (sy < 0 || sy >= lumaH) continue;
        for (var dx = -2; dx <= 2; dx++) {
          final sx = cx + dx;
          if (sx < 0 || sx >= lumaW) continue;
          final p = photo.getPixel(sx, sy);
          sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          count++;
        }
      }
      centerLumas.add(count > 0 ? sum / count : 255.0);
    }

    // Find darkest and second-darkest center luma
    var darkestIdx = 0;
    var darkestLuma = centerLumas[0];
    var secondDarkest = double.infinity;
    for (var i = 1; i < centerLumas.length; i++) {
      if (centerLumas[i] < darkestLuma) {
        secondDarkest = darkestLuma;
        darkestLuma = centerLumas[i];
        darkestIdx = i;
      } else if (centerLumas[i] < secondDarkest) {
        secondDarkest = centerLumas[i];
      }
    }

    // If no distinctly dark candidate (gap < 20 luma), fall back to
    // coordinate-extreme classification (backward compat with old barcodes)
    if (secondDarkest - darkestLuma < 20) {
      return _selectAndClassifyByCoordinates(candidates);
    }

    // Brightness-based classification: darkest = TL
    final tl = candidates[darkestIdx];
    final remaining = <_FinderCandidate>[
      for (var i = 0; i < candidates.length; i++)
        if (i != darkestIdx) candidates[i],
    ];

    // BR = farthest from TL
    _FinderCandidate br = remaining[0];
    var maxDist = 0.0;
    for (final c in remaining) {
      final dx = c.centerX - tl.centerX;
      final dy = c.centerY - tl.centerY;
      final dist = dx * dx + dy * dy;
      if (dist > maxDist) {
        maxDist = dist;
        br = c;
      }
    }

    if (remaining.length == 1) {
      return (tl: tl, br: br, tr: null, bl: null);
    }

    // TR vs BL: cross product sign of (BR-TL) × (C-TL)
    // In screen coords (y-down): negative = TR side, positive = BL side
    final bx = br.centerX - tl.centerX;
    final by = br.centerY - tl.centerY;

    _FinderCandidate? tr;
    _FinderCandidate? bl;
    for (final c in remaining) {
      if (identical(c, br)) continue;
      final cx = c.centerX - tl.centerX;
      final cy = c.centerY - tl.centerY;
      final cross = bx * cy - by * cx;
      if (cross < 0) {
        tr = c;
      } else {
        bl = c;
      }
    }

    return (tl: tl, br: br, tr: tr, bl: bl);
  }

  /// Fallback coordinate-extreme classification for old barcodes without
  /// asymmetric finders.
  static ({
    _FinderCandidate tl,
    _FinderCandidate br,
    _FinderCandidate? tr,
    _FinderCandidate? bl,
  })? _selectAndClassifyByCoordinates(List<_FinderCandidate> candidates) {
    if (candidates.length < 2) return null;

    _FinderCandidate tl = candidates[0];
    _FinderCandidate br = candidates[0];
    var minSum = tl.centerX + tl.centerY;
    var maxSum = minSum;

    for (final c in candidates) {
      final s = c.centerX + c.centerY;
      if (s < minSum) {
        minSum = s;
        tl = c;
      }
      if (s > maxSum) {
        maxSum = s;
        br = c;
      }
    }

    if (identical(tl, br)) return null;

    if (candidates.length == 2) {
      return (tl: tl, br: br, tr: null, bl: null);
    }

    final midX = (tl.centerX + br.centerX) / 2;
    final midY = (tl.centerY + br.centerY) / 2;
    final spanX = (br.centerX - tl.centerX).abs();
    final spanY = (br.centerY - tl.centerY).abs();
    final span = max(spanX, spanY);

    _FinderCandidate? tr;
    _FinderCandidate? bl;
    var maxXminusY = double.negativeInfinity;
    var minXminusY = double.infinity;

    for (final c in candidates) {
      if (identical(c, tl) || identical(c, br)) continue;

      if ((c.centerX - midX).abs() > span ||
          (c.centerY - midY).abs() > span) {
        continue;
      }

      final d = c.centerX - c.centerY;
      if (d > maxXminusY) {
        maxXminusY = d;
        tr = c;
      }
      if (d < minXminusY) {
        minXminusY = d;
        bl = c;
      }
    }

    if (tr != null && bl != null && identical(tr, bl)) {
      if (tr.centerX > midX) {
        bl = null;
      } else {
        tr = null;
      }
    }

    return (tl: tl, br: br, tr: tr, bl: bl);
  }

  /// Phase 5: Compute crop region from TL and BR finder centers,
  /// with optional TR and BL finders.
  static LocateResult _computeCropFromAnchors(
    img.Image photo,
    _FinderCandidate tl,
    _FinderCandidate br,
    int origW,
    int origH, {
    _FinderCandidate? tr,
    _FinderCandidate? bl,
  }) {
    // Scale finder centers back to original coordinates
    final tlX = tl.centerX * _downscale;
    final tlY = tl.centerY * _downscale;
    final brX = br.centerX * _downscale;
    final brY = br.centerY * _downscale;
    final trX = tr != null ? tr.centerX * _downscale : null;
    final trY = tr != null ? tr.centerY * _downscale : null;
    final blX = bl != null ? bl.centerX * _downscale : null;
    final blY = bl != null ? bl.centerY * _downscale : null;

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

    // Compute bounding box from all available finder centers
    var minFinderX = min(tlX, brX);
    var minFinderY = min(tlY, brY);
    var maxFinderX = max(tlX, brX);
    var maxFinderY = max(tlY, brY);
    if (trX != null && trY != null) {
      minFinderX = min(minFinderX, trX);
      minFinderY = min(minFinderY, trY);
      maxFinderX = max(maxFinderX, trX);
      maxFinderY = max(maxFinderY, trY);
    }
    if (blX != null && blY != null) {
      minFinderX = min(minFinderX, blX);
      minFinderY = min(minFinderY, blY);
      maxFinderX = max(maxFinderX, blX);
      maxFinderY = max(maxFinderY, blY);
    }

    var cropLeft = (minFinderX - padding).round();
    var cropTop = (minFinderY - padding).round();
    var cropRight = (maxFinderX + padding).round();
    var cropBottom = (maxFinderY + padding).round();

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
      trFinderCenter: trX != null && trY != null ? Point(trX, trY) : null,
      blFinderCenter: blX != null && blY != null ? Point(blX, blY) : null,
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
