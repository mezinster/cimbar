import 'dart:math' as math;
import 'dart:typed_data';

import 'luma_plane.dart';

/// A located finder pattern center in full-resolution continuous pixels.
class Finder {
  final double x;
  final double y;
  final double module; // px per pitch (one finder ring width)
  const Finder(this.x, this.y, this.module);
}

class LocateResult {
  final Finder? tl, tr, bl, br;
  final int candidates;
  final int clusters;
  final double devNorm;
  final double tlLuma;
  final double secondLuma;
  final String failReason;

  const LocateResult({
    this.tl,
    this.tr,
    this.bl,
    this.br,
    this.candidates = 0,
    this.clusters = 0,
    this.devNorm = -1,
    this.tlLuma = 0,
    this.secondLuma = 0,
    this.failReason = '',
  });

  bool get ok => tl != null && tr != null && bl != null && br != null;
  double get module => ok ? (tl!.module + tr!.module + bl!.module + br!.module) / 4 : 0;
}

class _Cluster {
  double sx = 0, sy = 0, sm = 0;
  int hits = 0;
  double get x => sx / hits;
  double get y => sy / hits;
  double get m => sm / hits;
}

class _Refined {
  final double x, y, m;
  const _Refined(this.x, this.y, this.m);
}

class _Run {
  final int start;
  final int length;
  final bool dark;
  const _Run(this.start, this.length, this.dark);
  int get end => start + length;
}

/// Finds the four QR-style 7x7-cell finders (spec §6.2).
///
/// 1. Downscale 2x, binarize with a local mean.
/// 2. Row scan: sliding 1:1:3:1:1 windows (strict) give candidate x positions.
/// 3. For each hit, the finder's full 7-module extent along the column through
///    it is matched *anchored* at the run containing the hit row — one of four
///    interpretations (solid core, or the tr/bl/br core dot left of / at /
///    right of the anchor run), best fit wins. This is dot-tolerant and, being
///    a chord through the center, rotation-invariant.
/// 4. Cluster hits within one module; refine each strong cluster by
///    alternating row/column extents through its center (3 iterations).
/// 5. Choose four by parallelogram closure, classify TL by core brightness,
///    orient TR/BL by cross product, correct the module for rotation.
class FinderLocator {
  final int downscale;
  final double maxDevNorm;
  final double tlMargin;
  final int maxClusters;

  const FinderLocator({this.downscale = 2, this.maxDevNorm = 0.35, this.tlMargin = 40, this.maxClusters = 12});

  static const List<double> _p5 = [1, 1, 3, 1, 1];
  static const List<double> _p7 = [1, 1, 1, 1, 1, 1, 1];
  static const double _p7Tol = 0.25;

  /// Minimum downscaled module. Below ~3 px a ring is 2 px wide and, after
  /// binarization, integer quantization makes a +-25% tolerance accept any
  /// exact-2 px run, so ordinary photo texture matches the pattern. It also
  /// bounds the barcode at >=57*2*3 = 342 full-res px across, under which the
  /// 64-cell grid is not sampleable anyway.
  static const double _minModule = 3.0;

  LocateResult locate(LumaPlane full) {
    final ds = downscale == 2 ? full.downscale2() : full;
    if (ds.width < 16 || ds.height < 16) return const LocateResult(failReason: 'image too small');
    final bin = _binarize(ds);
    final w = ds.width, h = ds.height;

    // Phases 2–4: row scan, anchored column extent, clustering.
    // Every row is scanned: a stride of 2 loses hits on small, rotated
    // finders (37° at 1.8x dropped to 2 clusters) and the row scan is cheap
    // next to sampling.
    final clusters = <_Cluster>[];
    var candidates = 0;
    for (var y = 0; y < h; y++) {
      final runs = _rowRuns(bin, w, y);
      for (var i = 1; i < runs.length; i++) {
        if (runs[i].dark) continue;
        final match = _slidingMatch(runs, i);
        if (match == null) continue;
        final (total, m) = match;
        if (m < _minModule) continue;
        final cx = runs[i].start + total / 2;
        // Bound the column scan to +-7 modules around the row being
        // confirmed: a finder's full extent is 7 modules, so this always
        // contains it while avoiding a full-height column scan per hit.
        final cy0 = math.max(0, (y - 7 * m).floor()), cy1 = math.min(h, (y + 7 * m).ceil());
        final col = _colRuns(bin, w, cx.floor().clamp(0, w - 1), cy0, cy1);
        final ey = _anchoredExtent(col, y, m);
        if (ey == null) continue;
        final cy = (ey.$1 + ey.$2) / 2;
        final mv = (ey.$2 - ey.$1) / 7;
        candidates++;
        final mod = (m + mv) / 2;
        _Cluster? best;
        var bestD = double.infinity;
        for (final c in clusters) {
          final d = math.sqrt((c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy));
          if (d <= math.max(2.0, c.m) && d < bestD) {
            best = c;
            bestD = d;
          }
        }
        if (best == null) {
          best = _Cluster();
          clusters.add(best);
        }
        best.sx += cx;
        best.sy += cy;
        best.sm += mod;
        best.hits++;
      }
    }

    final strong = clusters.where((c) => c.hits >= 2).toList()..sort((a, b) => b.hits.compareTo(a.hits));
    final refined = <_Refined>[];
    final unrefined = <_Cluster>[];
    for (final c in strong.take(maxClusters)) {
      final r = _refine(bin, w, h, c.x, c.y, c.m);
      if (r != null) {
        refined.add(_Refined(r.$1, r.$2, r.$3));
      } else {
        unrefined.add(c);
      }
    }
    if (refined.length < 4) {
      // refinement can fail one module off the core on textured scenes; the
      // centroid is still a usable corner. Only fall back to it when the
      // successfully-refined pool is otherwise too small — an unrefined
      // centroid competing on parallelogram fit alone can look deceptively
      // clean and out-rank a real, refined corner. (Ranking clusters by fit
      // quality is deferred to Plan 4.)
      for (final c in unrefined) {
        refined.add(_Refined(c.x, c.y, c.m));
      }
    }
    if (refined.length < 4) {
      return LocateResult(candidates: candidates, clusters: strong.length, failReason: 'fewer than 4 finder candidates (${refined.length} after refinement, ${strong.length} clusters)');
    }

    // Phase 5: parallelogram selection over diagonal pairs.
    var bestDev = double.infinity;
    List<_Refined>? bestQuad; // [P, R, Q, S] cyclic; diagonals PQ and RS
    final n = refined.length;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        for (var k = 0; k < n; k++) {
          if (k == i || k == j) continue;
          for (var l = k + 1; l < n; l++) {
            if (l == i || l == j) continue;
            final p = refined[i], q = refined[j], r = refined[k], s = refined[l];
            final mods = [p.m, q.m, r.m, s.m];
            final mMax = mods.reduce(math.max), mMin = mods.reduce(math.min);
            if (mMax > 2 * mMin) continue;
            final side = (_dist(p, r) + _dist(r, q) + _dist(q, s) + _dist(s, p)) / 4;
            if (side <= 0) continue;
            final ex = (p.x + q.x) - (r.x + s.x), ey = (p.y + q.y) - (r.y + s.y);
            final dev = math.sqrt(ex * ex + ey * ey) / side;
            final ratio = side / ((mMax + mMin) / 2);
            // finder centers are 57 modules apart; the module here is still 1/cosθ-inflated
            // (57·cos45° ≈ 40), so the floor is 36
            if (ratio < 36 || ratio > 75) continue;
            if (dev < bestDev) {
              bestDev = dev;
              bestQuad = [p, r, q, s];
            }
          }
        }
      }
    }
    if (bestQuad == null || bestDev > maxDevNorm) {
      return LocateResult(candidates: candidates, clusters: strong.length, devNorm: bestQuad == null ? -1 : bestDev, failReason: 'no parallelogram of finders (devNorm ${bestDev.isFinite ? bestDev.toStringAsFixed(3) : '-'})');
    }

    // Phase 6: classify TL by full-res core brightness; BR is TL's diagonal partner.
    final scale = downscale.toDouble();
    final pts = [for (final c in bestQuad) Finder(c.x * scale, c.y * scale, c.m * scale)];
    final lum = [for (final f in pts) full.mean3x3(f.x.floor(), f.y.floor())];
    var tlIdx = 0;
    for (var i = 1; i < 4; i++) {
      if (lum[i] > lum[tlIdx]) tlIdx = i;
    }
    var second = -1.0;
    for (var i = 0; i < 4; i++) {
      if (i != tlIdx && lum[i] > second) second = lum[i];
    }
    if (lum[tlIdx] - second < tlMargin) {
      return LocateResult(candidates: candidates, clusters: strong.length, devNorm: bestDev, tlLuma: lum[tlIdx], secondLuma: second, failReason: 'TL core not distinct (${lum[tlIdx].toStringAsFixed(0)} vs ${second.toStringAsFixed(0)})');
    }
    final brIdx = (tlIdx + 2) % 4;
    final tl = pts[tlIdx], br = pts[brIdx];
    Finder? tr, bl;
    for (final i in [(tlIdx + 1) % 4, (tlIdx + 3) % 4]) {
      final p = pts[i];
      final cross = (br.x - tl.x) * (p.y - tl.y) - (br.y - tl.y) * (p.x - tl.x);
      if (cross < 0) {
        tr = p;
      } else {
        bl = p;
      }
    }
    if (tr == null || bl == null) {
      return LocateResult(candidates: candidates, clusters: strong.length, devNorm: bestDev, tlLuma: lum[tlIdx], secondLuma: second, failReason: 'TR/BL orientation ambiguous');
    }
    // Axis-aligned chords through a finder rotated by θ are 1/cos θ longer than
    // the true module: correct with the grid rotation folded into ±45°.
    var folded = math.atan2(tr.y - tl.y, tr.x - tl.x) % (math.pi / 2);
    if (folded > math.pi / 4) folded -= math.pi / 2;
    final cosF = math.cos(folded);
    // pts are in the (possibly cropped) plane's local coordinates; the
    // returned finders must be absolute full-frame pixels.
    Finder fix(Finder f) => Finder(f.x + full.originX, f.y + full.originY, f.module * cosF);
    return LocateResult(tl: fix(tl), tr: fix(tr), bl: fix(bl), br: fix(br), candidates: candidates, clusters: strong.length, devNorm: bestDev, tlLuma: lum[tlIdx], secondLuma: second);
  }

  static double _dist(_Refined a, _Refined b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  /// Local-mean binarization (integral image). dark = v < mean - 8 || v < 24.
  static Uint8List _binarize(LumaPlane p) {
    final w = p.width, h = p.height;
    final win = math.max(15, math.min(w, h) ~/ 10);
    final half = win ~/ 2;
    final integral = Int32List((w + 1) * (h + 1));
    for (var y = 1; y <= h; y++) {
      var rowSum = 0;
      for (var x = 1; x <= w; x++) {
        rowSum += p.luma[(y - 1) * w + (x - 1)];
        integral[y * (w + 1) + x] = integral[(y - 1) * (w + 1) + x] + rowSum;
      }
    }
    final out = Uint8List(w * h); // 1 = dark
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - half), y1 = math.min(h, y + half + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - half), x1 = math.min(w, x + half + 1);
        final sum = integral[y1 * (w + 1) + x1] - integral[y0 * (w + 1) + x1] - integral[y1 * (w + 1) + x0] + integral[y0 * (w + 1) + x0];
        final mean = sum / ((y1 - y0) * (x1 - x0));
        final v = p.luma[y * w + x];
        out[y * w + x] = (v < mean - 8 || v < 24) ? 1 : 0;
      }
    }
    return out;
  }

  static List<_Run> _rowRuns(Uint8List bin, int w, int y) {
    final runs = <_Run>[];
    var start = 0;
    var dark = bin[y * w] == 1;
    for (var x = 1; x <= w; x++) {
      final d = x < w ? bin[y * w + x] == 1 : !dark;
      if (d != dark) {
        runs.add(_Run(start, x - start, dark));
        start = x;
        dark = d;
      }
    }
    return runs;
  }

  static List<_Run> _colRuns(Uint8List bin, int w, int x, int y0, int y1) {
    final runs = <_Run>[];
    var start = y0;
    var dark = bin[y0 * w + x] == 1;
    for (var y = y0 + 1; y <= y1; y++) {
      final d = y < y1 ? bin[y * w + x] == 1 : !dark;
      if (d != dark) {
        runs.add(_Run(start, y - start, dark));
        start = y;
        dark = d;
      }
    }
    return runs;
  }

  /// Sliding match starting at light run [i], bounded by dark runs on both
  /// sides. Tries the solid core (1:1:3:1:1, 50% per-run tolerance) and then
  /// the dotted core (1:1:1:1:1:1:1) at a much tighter tolerance.
  ///
  /// The dotted pattern is needed because an axis-aligned chord through an
  /// obliquely rotated finder cannot avoid the core dot: the core's
  /// clean-chord band is half-width (3m/2)|sin t - cos t| while the dot's
  /// shadow is (m/2)(sin t + cos t), and for t near 37 deg the shadow is 2.4x
  /// the band. Its tolerance is [_p7Tol], not 0.5, because a uniform 7-run
  /// pattern at 50% also admits windows shifted by one run where a merged
  /// ~2-module run stands in for a 1-module one.
  static (int, double)? _slidingMatch(List<_Run> runs, int i) {
    final five = _fitAt(runs, i, _p5, 0.5);
    if (five != null) return five;
    return _fitAt(runs, i, _p7, _p7Tol);
  }

  static (int, double)? _fitAt(List<_Run> runs, int i, List<double> pat, double tol) {
    final n = pat.length;
    if (i + n >= runs.length) return null; // dark run required on both sides
    var total = 0;
    for (var k = 0; k < n; k++) {
      total += runs[i + k].length;
    }
    final m = total / 7;
    for (var k = 0; k < n; k++) {
      final e = pat[k] * m;
      if ((runs[i + k].length - e).abs() > tol * e) return null;
    }
    return (total, m);
  }

  /// Relative fit error of pattern [pat] over runs[start..start+n) with module
  /// total/7; null when colors do not alternate light-first or bounds fail.
  static double? _fit(List<_Run> runs, int start, List<double> pat) {
    final n = pat.length;
    if (start < 1 || start + n >= runs.length) return null;
    if (runs[start].dark) return null;
    var total = 0;
    for (var k = 0; k < n; k++) {
      total += runs[start + k].length;
    }
    final m = total / 7;
    var worst = 0.0;
    for (var k = 0; k < n; k++) {
      final e = pat[k] * m;
      final err = (runs[start + k].length - e).abs() / e;
      if (err > worst) worst = err;
    }
    return worst;
  }

  /// Finder extent [start, end) along a run list, anchored at the run that
  /// contains position [p]. Tries: solid core (5 runs starting two runs before
  /// the anchor), and the dotted core with the anchor being the left core
  /// half, the dot, or the right core half (7 runs). Best fit ≤ 0.5 wins; the
  /// module must be within 0.5–2x of [m].
  static (int, int)? _anchoredExtent(List<_Run> runs, int p, double m) {
    var j = -1;
    for (var i = 0; i < runs.length; i++) {
      if (p >= runs[i].start && p < runs[i].end) {
        j = i;
        break;
      }
    }
    if (j < 0) return null;
    const tries = [(-2, _p5), (-2, _p7), (-3, _p7), (-4, _p7)];
    double bestErr = 0.5;
    (int, int)? best;
    for (final (off, pat) in tries) {
      final start = j + off;
      final err = _fit(runs, start, pat);
      if (err == null || err > bestErr) continue;
      final end = runs[start + pat.length - 1].end;
      final mm = (end - runs[start].start) / 7;
      if (mm < 0.5 * m || mm > 2 * m) continue;
      bestErr = err;
      best = (runs[start].start, end);
    }
    return best;
  }

  /// Alternate row/column extents through the current center (3 iterations).
  static (double, double, double)? _refine(Uint8List bin, int w, int h, double cx, double cy, double m) {
    var x = cx, y = cy, mod = m;
    for (var iter = 0; iter < 3; iter++) {
      final yi = y.floor().clamp(0, h - 1), xi = x.floor().clamp(0, w - 1);
      final ex = _anchoredExtent(_rowRuns(bin, w, yi), xi, mod);
      if (ex == null) return null;
      // Same +-7 module bound as the initial scan, recentered on this
      // iteration's row.
      final cy0 = math.max(0, (yi - 7 * mod).floor()), cy1 = math.min(h, (yi + 7 * mod).ceil());
      final ey = _anchoredExtent(_colRuns(bin, w, xi, cy0, cy1), yi, mod);
      if (ey == null) return null;
      x = (ex.$1 + ex.$2) / 2;
      y = (ey.$1 + ey.$2) / 2;
      mod = ((ex.$2 - ex.$1) + (ey.$2 - ey.$1)) / 14;
    }
    return (x, y, mod);
  }
}
