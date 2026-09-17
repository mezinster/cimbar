import 'dart:typed_data';

import 'grid_model.dart';

/// 3x3 projective transform, row-major, h[8] == 1.
/// map(x, y) = ((h0 x + h1 y + h2) / w, (h3 x + h4 y + h5) / w), w = h6 x + h7 y + 1.
class Homography {
  final Float64List h;
  const Homography(this.h);

  (double, double) map(double x, double y) {
    final w = h[6] * x + h[7] * y + h[8];
    final iw = w.abs() < 1e-12 ? 0.0 : 1.0 / w;
    return ((h[0] * x + h[1] * y + h[2]) * iw, (h[3] * x + h[4] * y + h[5]) * iw);
  }

  /// Direct linear transform from four point correspondences. Null if singular.
  static Homography? solve(List<(double, double)> from, List<(double, double)> to) {
    if (from.length != 4 || to.length != 4) throw ArgumentError('need exactly 4 correspondences');
    final a = Float64List(64);
    final b = Float64List(8);
    for (var i = 0; i < 4; i++) {
      final (sx, sy) = from[i];
      final (dx, dy) = to[i];
      final r0 = i * 2, r1 = r0 + 1;
      a[r0 * 8 + 0] = sx;
      a[r0 * 8 + 1] = sy;
      a[r0 * 8 + 2] = 1;
      a[r0 * 8 + 6] = -sx * dx;
      a[r0 * 8 + 7] = -sy * dx;
      b[r0] = dx;
      a[r1 * 8 + 3] = sx;
      a[r1 * 8 + 4] = sy;
      a[r1 * 8 + 5] = 1;
      a[r1 * 8 + 6] = -sx * dy;
      a[r1 * 8 + 7] = -sy * dy;
      b[r1] = dy;
    }
    final x = _solve8(a, b);
    if (x == null) return null;
    final out = Float64List(9);
    for (var i = 0; i < 8; i++) {
      out[i] = x[i];
    }
    out[8] = 1.0;
    return Homography(out);
  }

  static Float64List? _solve8(Float64List a, Float64List b) {
    const n = 8;
    final m = Float64List.fromList(a);
    final r = Float64List.fromList(b);
    for (var col = 0; col < n; col++) {
      var maxRow = col;
      var maxVal = m[col * n + col].abs();
      for (var row = col + 1; row < n; row++) {
        final v = m[row * n + col].abs();
        if (v > maxVal) {
          maxVal = v;
          maxRow = row;
        }
      }
      if (maxVal < 1e-10) return null;
      if (maxRow != col) {
        for (var j = 0; j < n; j++) {
          final t = m[col * n + j];
          m[col * n + j] = m[maxRow * n + j];
          m[maxRow * n + j] = t;
        }
        final t = r[col];
        r[col] = r[maxRow];
        r[maxRow] = t;
      }
      final pivot = m[col * n + col];
      for (var row = col + 1; row < n; row++) {
        final f = m[row * n + col] / pivot;
        if (f == 0) continue;
        for (var j = col; j < n; j++) {
          m[row * n + j] -= f * m[col * n + j];
        }
        r[row] -= f * r[col];
      }
    }
    final x = Float64List(n);
    for (var row = n - 1; row >= 0; row--) {
      var s = r[row];
      for (var j = row + 1; j < n; j++) {
        s -= m[row * n + j] * x[j];
      }
      x[row] = s / m[row * n + row];
    }
    return x;
  }
}

/// Grid model from four finder centers in source pixels (spec §6.3).
class HomographyGridModel extends GridModel {
  final Homography h;
  const HomographyGridModel(this.h);

  static const List<(double, double)> finderCells = [(3.5, 3.5), (60.5, 3.5), (3.5, 60.5), (60.5, 60.5)];

  static HomographyGridModel? fromFinders({
    required (double, double) tl,
    required (double, double) tr,
    required (double, double) bl,
    required (double, double) br,
  }) {
    final h = Homography.solve(finderCells, [tl, tr, bl, br]);
    return h == null ? null : HomographyGridModel(h);
  }

  @override
  (double, double) toSource(double cx, double cy) => h.map(cx, cy);
}
