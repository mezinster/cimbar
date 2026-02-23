import 'dart:math';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';

/// Perspective transform utilities for correcting tilted camera captures
/// of CimBar barcodes.
///
/// Given 2 finder pattern centers (TL and BR), derives 4 barcode corners
/// and computes a projective warp to map the tilted barcode back to a
/// perfect square grid.
class PerspectiveTransform {
  PerspectiveTransform._();

  /// Minimum diagonal length (in pixels) to consider valid.
  static const double _minDiagonal = 10.0;

  /// Compute 4 barcode corners in source image coordinates from the
  /// TL and BR finder pattern centers.
  ///
  /// The barcode is assumed square. TL finder center is at grid cell (1,1),
  /// BR finder center is at grid cell (cols-2, rows-2), where cols=rows=frameSize/cellSize.
  ///
  /// Returns [TL, TR, BL, BR] corners or null if the geometry is degenerate.
  static List<Point<double>>? computeBarcodeCorners(
    Point<double> tlFinder,
    Point<double> brFinder,
    int frameSize,
  ) {
    const cs = CimbarConstants.cellSize;
    final cols = frameSize ~/ cs;
    // Diagonal spans (cols-3) cells in both x and y directions
    final n = (cols - 3) * cs;
    if (n <= 0) return null;

    final dx = brFinder.x - tlFinder.x;
    final dy = brFinder.y - tlFinder.y;

    // Check for degenerate cases
    final diag = sqrt(dx * dx + dy * dy);
    if (diag < _minDiagonal) return null;

    // Unit vectors along the barcode's x and y axes in image space.
    // The diagonal from TL finder to BR finder goes along direction (1,1)
    // in barcode space, spanning n pixels in each axis.
    // So: D = n*ux + n*uy, and uy is ux rotated 90° CW.
    //   ux = ((dx+dy)/(2n), (dy-dx)/(2n))
    //   uy = (-(dy-dx)/(2n), (dx+dy)/(2n))
    final uxX = (dx + dy) / (2.0 * n);
    final uxY = (dy - dx) / (2.0 * n);
    final uyX = -(dy - dx) / (2.0 * n);
    final uyY = (dx + dy) / (2.0 * n);

    // Origin: TL finder center is at grid position (1.5*cs, 1.5*cs) from
    // the barcode's top-left corner. So:
    //   origin = tlFinder - 1.5*cs*(ux + uy)
    const pad = 1.5 * cs;
    final originX = tlFinder.x - pad * (uxX + uyX);
    final originY = tlFinder.y - pad * (uxY + uyY);

    final s = frameSize.toDouble();

    return [
      Point(originX, originY),                             // TL
      Point(originX + s * uxX, originY + s * uxY),         // TR
      Point(originX + s * uyX, originY + s * uyY),         // BL
      Point(originX + s * uxX + s * uyX,
            originY + s * uxY + s * uyY),                  // BR
    ];
  }

  /// Warp a quadrilateral region from [source] defined by [srcCorners]
  /// (TL, TR, BL, BR) into a [destSize] × [destSize] square image.
  ///
  /// Uses inverse mapping with bilinear interpolation.
  static img.Image warpPerspective(
    img.Image source,
    List<Point<double>> srcCorners,
    int destSize,
  ) {
    // Destination corners: (0,0), (S,0), (0,S), (S,S)
    final s = destSize.toDouble();
    final dstCorners = [
      const Point(0.0, 0.0),
      Point(s, 0.0),
      Point(0.0, s),
      Point(s, s),
    ];

    // Compute homography: dst → src (inverse mapping)
    // We want: for each dst pixel, find the corresponding src pixel.
    // So the homography maps dst coordinates to src coordinates.
    final h = _computeHomography(dstCorners, srcCorners);
    if (h == null) {
      // Fallback: return a simple resize if homography fails
      return img.copyResize(source,
          width: destSize, height: destSize,
          interpolation: img.Interpolation.nearest);
    }

    final output = img.Image(width: destSize, height: destSize);
    final srcW = source.width;
    final srcH = source.height;

    for (var dy = 0; dy < destSize; dy++) {
      for (var dx = 0; dx < destSize; dx++) {
        // Map destination pixel to source coordinates
        final px = dx + 0.5; // pixel center
        final py = dy + 0.5;
        final w = h[6] * px + h[7] * py + h[8];
        if (w.abs() < 1e-10) {
          output.setPixelRgba(dx, dy, 0, 0, 0, 255);
          continue;
        }
        final srcX = (h[0] * px + h[1] * py + h[2]) / w;
        final srcY = (h[3] * px + h[4] * py + h[5]) / w;

        // Nearest-neighbor sampling: preserves sharp cell boundaries
        // (bilinear blurs 8px cells, defeating color/symbol detection)
        final srcXr = srcX.round().clamp(0, srcW - 1);
        final srcYr = srcY.round().clamp(0, srcH - 1);
        final p = source.getPixel(srcXr, srcYr);
        output.setPixelRgba(dx, dy, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
      }
    }

    return output;
  }

  /// Compute the 3×3 homography matrix that maps [src] points to [dst] points.
  ///
  /// Uses the Direct Linear Transform (DLT) algorithm: 4 point pairs yield
  /// an 8×8 linear system (h₈ = 1 normalization).
  ///
  /// Returns a 9-element list (row-major 3×3) or null if the system is singular.
  static List<double>? _computeHomography(
    List<Point<double>> src,
    List<Point<double>> dst,
  ) {
    // Build 8×8 matrix A and 8-vector b from 4 point correspondences.
    // For each pair (x,y) → (x',y'):
    //   x' = (h0*x + h1*y + h2) / (h6*x + h7*y + 1)
    //   y' = (h3*x + h4*y + h5) / (h6*x + h7*y + 1)
    // Rearranged:
    //   h0*x + h1*y + h2 - h6*x*x' - h7*y*x' = x'
    //   h3*x + h4*y + h5 - h6*x*y' - h7*y*y' = y'
    final a = List<double>.filled(64, 0.0); // 8×8
    final bVec = List<double>.filled(8, 0.0);

    for (var i = 0; i < 4; i++) {
      final sx = src[i].x;
      final sy = src[i].y;
      final dx = dst[i].x;
      final dy = dst[i].y;

      final row0 = i * 2;
      final row1 = row0 + 1;

      // Row for x' equation
      a[row0 * 8 + 0] = sx;
      a[row0 * 8 + 1] = sy;
      a[row0 * 8 + 2] = 1;
      a[row0 * 8 + 3] = 0;
      a[row0 * 8 + 4] = 0;
      a[row0 * 8 + 5] = 0;
      a[row0 * 8 + 6] = -sx * dx;
      a[row0 * 8 + 7] = -sy * dx;
      bVec[row0] = dx;

      // Row for y' equation
      a[row1 * 8 + 0] = 0;
      a[row1 * 8 + 1] = 0;
      a[row1 * 8 + 2] = 0;
      a[row1 * 8 + 3] = sx;
      a[row1 * 8 + 4] = sy;
      a[row1 * 8 + 5] = 1;
      a[row1 * 8 + 6] = -sx * dy;
      a[row1 * 8 + 7] = -sy * dy;
      bVec[row1] = dy;
    }

    final solution = _solveLinearSystem(a, bVec, 8);
    if (solution == null) return null;

    return [
      solution[0], solution[1], solution[2],
      solution[3], solution[4], solution[5],
      solution[6], solution[7], 1.0,
    ];
  }

  /// Solve an n×n linear system Ax = b using Gaussian elimination
  /// with partial pivoting. Returns null if the matrix is singular.
  static List<double>? _solveLinearSystem(
    List<double> a,
    List<double> b,
    int n,
  ) {
    // Work on copies
    final mat = List<double>.of(a);
    final rhs = List<double>.of(b);

    // Forward elimination with partial pivoting
    for (var col = 0; col < n; col++) {
      // Find pivot
      var maxVal = mat[col * n + col].abs();
      var maxRow = col;
      for (var row = col + 1; row < n; row++) {
        final val = mat[row * n + col].abs();
        if (val > maxVal) {
          maxVal = val;
          maxRow = row;
        }
      }

      if (maxVal < 1e-12) return null; // singular

      // Swap rows
      if (maxRow != col) {
        for (var j = 0; j < n; j++) {
          final tmp = mat[col * n + j];
          mat[col * n + j] = mat[maxRow * n + j];
          mat[maxRow * n + j] = tmp;
        }
        final tmp = rhs[col];
        rhs[col] = rhs[maxRow];
        rhs[maxRow] = tmp;
      }

      // Eliminate below
      final pivot = mat[col * n + col];
      for (var row = col + 1; row < n; row++) {
        final factor = mat[row * n + col] / pivot;
        for (var j = col; j < n; j++) {
          mat[row * n + j] -= factor * mat[col * n + j];
        }
        rhs[row] -= factor * rhs[col];
      }
    }

    // Back substitution
    final x = List<double>.filled(n, 0.0);
    for (var row = n - 1; row >= 0; row--) {
      var sum = rhs[row];
      for (var j = row + 1; j < n; j++) {
        sum -= mat[row * n + j] * x[j];
      }
      final diag = mat[row * n + row];
      if (diag.abs() < 1e-12) return null;
      x[row] = sum / diag;
    }

    return x;
  }
}
