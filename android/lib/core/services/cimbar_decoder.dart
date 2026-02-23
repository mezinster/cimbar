import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import 'reed_solomon.dart';

/// Decode CimBar frames from pixel data.
/// Port of decode-side functions from web-app/cimbar.js.
class CimbarDecoder {
  final ReedSolomon _rs;

  CimbarDecoder([ReedSolomon? rs]) : _rs = rs ?? ReedSolomon(CimbarConstants.eccBytes);

  // ── Von Kries chromatic adaptation matrices ──

  /// Von Kries cone response matrix (RGB → LMS).
  static const _vonKriesM = [
    [0.4002400, 0.7076000, -0.0808100],
    [-0.2263000, 1.1653200, 0.0457000],
    [0.0000000, 0.0000000, 0.9182200],
  ];

  /// Inverse Von Kries matrix (LMS → RGB).
  static const _vonKriesMInv = [
    [1.8599364, -1.1293816, 0.2198974],
    [0.3611914, 0.6388086, -0.0000064],
    [0.0000000, 0.0000000, 1.0890636],
  ];

  // ── Pre-computed relative color palette ──

  /// Palette colors in normalized relative form: (R-G, G-B, B-R) after applying
  /// the same brightness normalization used on pixel values.
  static final List<List<double>> _paletteRelative = CimbarConstants.colors.map((c) {
    final r = c[0].toDouble(), g = c[1].toDouble(), b = c[2].toDouble();
    // Apply same normalization as _nearestColorIdxRelative
    var maxVal = max(r, max(g, b));
    if (maxVal < 1.0) maxVal = 1.0;
    var minVal = min(r, min(g, b));
    if (minVal > 48.0) minVal = 48.0;
    if (minVal >= maxVal) minVal = 0;
    final scale = 255.0 / (maxVal - minVal);
    double norm(double ch) {
      if (ch > 245.0 - minVal) return 255.0;
      return ((ch - minVal) * scale).clamp(0, 255);
    }
    final rn = norm(r), gn = norm(g), bn = norm(b);
    return [rn - gn, gn - bn, bn - rn];
  }).toList();

  /// Compute the Von Kries 3×3 adaptation matrix that maps [obsR, obsG, obsB]
  /// (observed white) to true white (255, 255, 255).
  ///
  /// Returns a flat 9-element list in row-major order, or null if the observed
  /// white is too dark to be reliable.
  static List<double>? computeAdaptationMatrix(double obsR, double obsG, double obsB) {
    // Reject if too dark — no reliable white reference
    final luma = 0.299 * obsR + 0.587 * obsG + 0.114 * obsB;
    if (luma < 30) return null;

    // src_cone = M * observed_white
    final srcL = _vonKriesM[0][0] * obsR + _vonKriesM[0][1] * obsG + _vonKriesM[0][2] * obsB;
    final srcM = _vonKriesM[1][0] * obsR + _vonKriesM[1][1] * obsG + _vonKriesM[1][2] * obsB;
    final srcS = _vonKriesM[2][0] * obsR + _vonKriesM[2][1] * obsG + _vonKriesM[2][2] * obsB;

    // Avoid division by zero
    if (srcL.abs() < 1e-6 || srcM.abs() < 1e-6 || srcS.abs() < 1e-6) return null;

    // dst_cone = M * (255, 255, 255)
    final dstL = _vonKriesM[0][0] * 255 + _vonKriesM[0][1] * 255 + _vonKriesM[0][2] * 255;
    final dstM = _vonKriesM[1][0] * 255 + _vonKriesM[1][1] * 255 + _vonKriesM[1][2] * 255;
    final dstS = _vonKriesM[2][0] * 255 + _vonKriesM[2][1] * 255 + _vonKriesM[2][2] * 255;

    // Diagonal scale factors
    final dL = dstL / srcL;
    final dM = dstM / srcM;
    final dS = dstS / srcS;

    // Combined: M_inv * diag(d) * M → 3×3 result in row-major flat list
    final result = List<double>.filled(9, 0.0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        result[i * 3 + j] = _vonKriesMInv[i][0] * dL * _vonKriesM[0][j] +
            _vonKriesMInv[i][1] * dM * _vonKriesM[1][j] +
            _vonKriesMInv[i][2] * dS * _vonKriesM[2][j];
      }
    }
    return result;
  }

  /// Apply a 3×3 adaptation matrix to an (r, g, b) triplet.
  /// Returns clamped [r, g, b] as integers.
  static List<int> applyAdaptation(List<double> matrix, int r, int g, int b) {
    final rf = matrix[0] * r + matrix[1] * g + matrix[2] * b;
    final gf = matrix[3] * r + matrix[4] * g + matrix[5] * b;
    final bf = matrix[6] * r + matrix[7] * g + matrix[8] * b;
    return [
      rf.round().clamp(0, 255),
      gf.round().clamp(0, 255),
      bf.round().clamp(0, 255),
    ];
  }

  /// Sample the observed white point from finder pattern outer cells.
  ///
  /// The finder pattern is 3×3 cells: a white outer ring with a dark center cell.
  /// We sample the top-left corner cell of each finder (grid 0,0 for TL finder,
  /// grid cols-3,rows-3 for BR finder) which is guaranteed to be solid white.
  /// Takes per-channel maximum across both samples (like libcimbar — handles
  /// partially occluded finders).
  static List<double>? _sampleFinderWhite(img.Image frame, int frameSize) {
    const cs = CimbarConstants.cellSize;
    final cols = frameSize ~/ cs;
    final rows = frameSize ~/ cs;

    List<double> sampleRegion(int gridCol, int gridRow) {
      final centerX = gridCol * cs + cs ~/ 2;
      final centerY = gridRow * cs + cs ~/ 2;
      double rSum = 0, gSum = 0, bSum = 0;
      var count = 0;
      for (var dy = -2; dy < 2; dy++) {
        for (var dx = -2; dx < 2; dx++) {
          final px = (centerX + dx).clamp(0, frame.width - 1);
          final py = (centerY + dy).clamp(0, frame.height - 1);
          final p = frame.getPixel(px, py);
          rSum += p.r;
          gSum += p.g;
          bSum += p.b;
          count++;
        }
      }
      return [rSum / count, gSum / count, bSum / count];
    }

    // Sample outer corner cells of each finder (known to be solid white)
    final tlSample = sampleRegion(0, 0);
    final brSample = sampleRegion(cols - 1, rows - 1);

    // Per-channel max (like libcimbar — handles partially occluded finders)
    return [
      max(tlSample[0], brSample[0]),
      max(tlSample[1], brSample[1]),
      max(tlSample[2], brSample[2]),
    ];
  }

  /// Find nearest color index using relative color matching with normalization.
  ///
  /// Normalizes brightness by stretching the channel range to 0-255, then
  /// compares (R-G, G-B, B-R) differences against the palette.
  static int _nearestColorIdxRelative(int r, int g, int b) {
    // Normalize brightness (from libcimbar get_best_color)
    var rd = r.toDouble(), gd = g.toDouble(), bd = b.toDouble();
    var maxVal = max(rd, max(gd, bd));
    if (maxVal < 1.0) maxVal = 1.0;
    var minVal = min(rd, min(gd, bd));
    if (minVal > 48.0) minVal = 48.0;
    if (minVal >= maxVal) minVal = 0;
    final scale = 255.0 / (maxVal - minVal);

    double norm(double c) {
      if (c > 245.0 - minVal) return 255.0;
      return (c - minVal) * scale;
    }

    rd = norm(rd).clamp(0, 255);
    gd = norm(gd).clamp(0, 255);
    bd = norm(bd).clamp(0, 255);

    // Relative color differences
    final relRG = rd - gd;
    final relGB = gd - bd;
    final relBR = bd - rd;

    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < _paletteRelative.length; i++) {
      final p = _paletteRelative[i];
      final d0 = relRG - p[0];
      final d1 = relGB - p[1];
      final d2 = relBR - p[2];
      final d = d0 * d0 + d1 * d1 + d2 * d2;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// Decode raw bytes from a frame image.
  /// [frame] must be a square image of [frameSize] pixels.
  ///
  /// When [enableWhiteBalance] is true, samples finder patterns to compute
  /// a Von Kries chromatic adaptation matrix and applies it to all pixels.
  /// When [useRelativeColor] is true, uses normalized relative color matching
  /// instead of absolute RGB distance.
  Uint8List decodeFramePixels(
    img.Image frame,
    int frameSize, {
    bool enableWhiteBalance = false,
    bool useRelativeColor = false,
    double? symbolThreshold,
    double? quadrantOffset,
  }) {
    const cs = CimbarConstants.cellSize;
    final cols = frameSize ~/ cs;
    final rows = frameSize ~/ cs;
    final totalBits = CimbarConstants.usableCells(frameSize) * 7;
    final totalBytes = (totalBits + 7) ~/ 8; // ceil
    final outBytes = Uint8List(totalBytes);

    // Compute white balance adaptation matrix if enabled
    List<double>? adaptation;
    if (enableWhiteBalance) {
      final whitePoint = _sampleFinderWhite(frame, frameSize);
      if (whitePoint != null) {
        adaptation = computeAdaptationMatrix(
            whitePoint[0], whitePoint[1], whitePoint[2]);
      }
    }

    var bitBuf = 0;
    var bitCount = 0;
    var byteIdx = 0;
    var cellCount = 0;
    // Diagnostic counters
    final colorHist = List<int>.filled(8, 0);
    var sym15count = 0;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        // Skip finder pattern cells
        final inTL = row < 3 && col < 3;
        final inBR = row >= rows - 3 && col >= cols - 3;
        if (inTL || inBR) continue;

        final ox = col * cs;
        final oy = row * cs;

        // Color detection: sample center pixel
        final cx = ox + cs ~/ 2;
        final cy = oy + cs ~/ 2;
        final pixel = frame.getPixel(cx, cy);
        var pr = pixel.r.toInt(), pg = pixel.g.toInt(), pb = pixel.b.toInt();

        // Apply white balance correction
        if (adaptation != null) {
          final corrected = applyAdaptation(adaptation, pr, pg, pb);
          pr = corrected[0];
          pg = corrected[1];
          pb = corrected[2];
        }

        final colorIdx = useRelativeColor
            ? _nearestColorIdxRelative(pr, pg, pb)
            : _nearestColorIdx(pr, pg, pb);

        // Symbol detection: sample 4 quadrant points
        final symIdx = _detectSymbol(frame, ox, oy, cs,
            symbolThreshold: symbolThreshold, quadrantOffset: quadrantOffset);

        // Log first 5 cells for diagnostics
        if (cellCount < 5) {
          final qFraction = quadrantOffset ?? 0.28;
          final q = (cs * qFraction).floor().clamp(1, cs);
          final cLuma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
          final tlP = frame.getPixel(ox + q, oy + q);
          final tlLuma = 0.299 * tlP.r + 0.587 * tlP.g + 0.114 * tlP.b;
          debugPrint('[cell_diag] row=$row col=$col '
              'rawRGB=(${pixel.r.toInt()},${pixel.g.toInt()},${pixel.b.toInt()}) '
              'wbRGB=($pr,$pg,$pb) '
              'colorIdx=$colorIdx symIdx=$symIdx '
              'centerLuma=${cLuma.toStringAsFixed(0)} '
              'tlCornerLuma=${tlLuma.toStringAsFixed(0)}');
        }
        colorHist[colorIdx]++;
        if (symIdx == 15) sym15count++;
        cellCount++;

        final bits = ((colorIdx & 0x7) << 4) | (symIdx & 0xF);

        bitBuf = (bitBuf << 7) | bits;
        bitCount += 7;

        while (bitCount >= 8 && byteIdx < totalBytes) {
          bitCount -= 8;
          outBytes[byteIdx++] = (bitBuf >> bitCount) & 0xFF;
        }
      }
    }

    // Diagnostic summary
    debugPrint('[decode_diag] frameSize=$frameSize cells=$cellCount '
        'sym15=$sym15count/$cellCount '
        'colorHist=$colorHist '
        'wb=${adaptation != null} relColor=$useRelativeColor '
        'symThresh=$symbolThreshold');
    if (adaptation != null) {
      debugPrint('[decode_diag] adaptMatrix=[${adaptation.map((v) => v.toStringAsFixed(3)).join(', ')}]');
    }

    return outBytes;
  }

  /// RS-decode one frame's raw bytes back to data bytes.
  /// Matches web-app/cimbar.js decodeRSFrame exactly.
  Uint8List decodeRSFrame(Uint8List rawBytes, int frameSize) {
    final raw = CimbarConstants.rawBytesPerFrame(frameSize);
    final result = <int>[];
    var off = 0;

    while (off < raw) {
      final spaceLeft = raw - off;
      if (spaceLeft <= CimbarConstants.eccBytes) break;

      final blockTotal = min(CimbarConstants.blockTotal, spaceLeft);
      final blockData = blockTotal - CimbarConstants.eccBytes;
      final block = rawBytes.sublist(off, off + blockTotal);
      off += blockTotal;

      try {
        final decoded = _rs.decode(block);
        result.addAll(decoded);
      } catch (_) {
        // If RS decode fails, push zeros
        for (var i = 0; i < blockData; i++) {
          result.add(0);
        }
      }
    }

    return Uint8List.fromList(result);
  }

  /// Find nearest color index using weighted distance.
  static int _nearestColorIdx(int r, int g, int b) {
    var best = 0;
    var bestDist = 0x7FFFFFFF; // max int
    for (var i = 0; i < CimbarConstants.colors.length; i++) {
      final c = CimbarConstants.colors[i];
      final dr = r - c[0];
      final dg = g - c[1];
      final db = b - c[2];
      final d = dr * dr * 2 + dg * dg * 4 + db * db;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// Detect 4-bit symbol from quadrant luma sampling.
  ///
  /// When [symbolThreshold] is provided (camera path), uses a multiplicative-only
  /// threshold: `c * symbolThreshold`. A corner must be at least this fraction
  /// of center brightness to read as 1. Default 0.85 cleanly separates blurred
  /// black dots (~130 luma at c=200) from undotted corners (~195).
  ///
  /// When [symbolThreshold] is null (GIF path), uses the original `c * 0.5 + 20`.
  ///
  /// When [quadrantOffset] is provided, overrides the default 0.28 cell fraction
  /// for corner sample positioning.
  static int _detectSymbol(img.Image image, int ox, int oy, int cs, {
    double? symbolThreshold,
    double? quadrantOffset,
  }) {
    final qFraction = quadrantOffset ?? 0.28;
    final q = max(1, (cs * qFraction).floor());

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

    final thresh = symbolThreshold != null ? c * symbolThreshold : c * 0.5 + 20;

    return ((tl > thresh ? 1 : 0) << 3) |
        ((tr > thresh ? 1 : 0) << 2) |
        ((bl > thresh ? 1 : 0) << 1) |
        (br > thresh ? 1 : 0);
  }
}
