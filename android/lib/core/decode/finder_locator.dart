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

class _Run {
  final int start;
  final int length;
  final bool dark;
  const _Run(this.start, this.length, this.dark);
}

/// Finds the four QR-style 7x7-cell finders (spec §6.2).
class FinderLocator {
  final int downscale;
  final double maxDevNorm;
  final double tlMargin;
  final int maxClusters;

  const FinderLocator({this.downscale = 2, this.maxDevNorm = 0.09, this.tlMargin = 40, this.maxClusters = 12});

  LocateResult locate(LumaPlane full) {
    final ds = downscale == 2 ? full.downscale2() : full;
    if (ds.width < 16 || ds.height < 16) return const LocateResult(failReason: 'image too small');
    final bin = _binarize(ds);
    final w = ds.width, h = ds.height;

    // Phase 1+2: row scan with vertical confirmation.
    final clusters = <_Cluster>[];
    var candidates = 0;
    for (var y = 0; y < h; y++) {
      final runs = _rowRuns(bin, w, y);
      for (var i = 0; i + 4 < runs.length; i++) {
        if (runs[i].dark) continue; // pattern starts with a light run
        if (i == 0 || i + 5 >= runs.length) continue; // need dark on both sides
        final total = runs[i].length + runs[i + 1].length + runs[i + 2].length + runs[i + 3].length + runs[i + 4].length;
        final m = total / 7;
        if (m < 1.5) continue;
        if (!_ratiosOk(runs, i, m)) continue;
        final cx = runs[i].start + total / 2;
        final vy = _confirmVertical(bin, w, h, cx.floor(), y, m);
        if (vy == null) continue;
        candidates++;
        final (cy, mv) = vy;
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
        best ??= (() {
          final c = _Cluster();
          clusters.add(c);
          return c;
        })();
        best.sx += cx;
        best.sy += cy;
        best.sm += mod;
        best.hits++;
      }
    }

    final strong = clusters.where((c) => c.hits >= 2).toList()..sort((a, b) => b.hits.compareTo(a.hits));
    final top = strong.take(maxClusters).toList();
    if (top.length < 4) {
      return LocateResult(candidates: candidates, clusters: strong.length, failReason: 'fewer than 4 finder candidates (${top.length})');
    }

    // Phase 4: parallelogram selection over diagonal pairs.
    var bestDev = double.infinity;
    List<_Cluster>? bestQuad; // [P, R, Q, S] cyclic order; diagonals PQ and RS
    final n = top.length;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        for (var k = 0; k < n; k++) {
          if (k == i || k == j) continue;
          for (var l = k + 1; l < n; l++) {
            if (l == i || l == j) continue;
            final p = top[i], q = top[j], r = top[k], s = top[l];
            final mods = [p.m, q.m, r.m, s.m];
            final mMax = mods.reduce(math.max), mMin = mods.reduce(math.min);
            if (mMax > 2 * mMin) continue;
            final side = (_dist(p, r) + _dist(r, q) + _dist(q, s) + _dist(s, p)) / 4;
            if (side <= 0) continue;
            final ex = (p.x + q.x) - (r.x + s.x), ey = (p.y + q.y) - (r.y + s.y);
            final dev = math.sqrt(ex * ex + ey * ey) / side;
            final ratio = side / ((mMax + mMin) / 2);
            if (ratio < 40 || ratio > 75) continue; // finder centers are 57 modules apart
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

    // Phase 5: classify TL by full-res core brightness; BR is TL's diagonal partner.
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
    final brIdx = (tlIdx + 2) % 4; // cyclic order P,R,Q,S: diagonal partner is two steps away
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
    return LocateResult(tl: tl, tr: tr, bl: bl, br: br, candidates: candidates, clusters: strong.length, devNorm: bestDev, tlLuma: lum[tlIdx], secondLuma: second);
  }

  static double _dist(_Cluster a, _Cluster b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

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

  /// 1:1:3:1:1 with each run within 50% of its expected length.
  static bool _ratiosOk(List<_Run> runs, int i, double m) {
    const expected = [1.0, 1.0, 3.0, 1.0, 1.0];
    for (var k = 0; k < 5; k++) {
      final e = expected[k] * m;
      if ((runs[i + k].length - e).abs() > 0.5 * e) return false;
    }
    return true;
  }

  /// Vertical confirmation at column x around row y: returns (centerY, module) or null.
  static (double, double)? _confirmVertical(Uint8List bin, int w, int h, int x, int y, double m) {
    if (x < 0 || x >= w) return null;
    final y0 = math.max(0, (y - 6 * m).floor()), y1 = math.min(h, (y + 6 * m).ceil());
    final runs = _colRuns(bin, w, x, y0, y1);
    for (var i = 1; i + 5 < runs.length; i++) {
      if (runs[i].dark) continue;
      final mid = runs[i + 2];
      if (y < mid.start - m || y >= mid.start + mid.length + m) continue;
      final total = runs[i].length + runs[i + 1].length + mid.length + runs[i + 3].length + runs[i + 4].length;
      final mv = total / 7;
      if (mv < 0.5 * m || mv > 2 * m) continue;
      if (!_ratiosOk(runs, i, mv)) continue;
      return (runs[i].start + total / 2, mv);
    }
    return null;
  }
}
