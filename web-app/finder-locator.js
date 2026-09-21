/**
 * finder-locator.js — finds the four QR-style 7x7-cell finders (spec §6.2) in
 * a photograph.
 *
 * Transliteration of app/lib/core/decode/finder_locator.dart. Every constant
 * here was tuned against real camera captures on the Android side and is
 * copied verbatim; the two suites share the `test-data/scenes/` fixtures, so a
 * locator that finds different centres than the Dart one is a bug.
 *
 * 1. Downscale 2x, binarize with a local mean.
 * 2. Row scan: sliding 1:1:3:1:1 windows (strict) give candidate x positions.
 * 3. For each hit, the finder's full 7-module extent along the column through
 *    it is matched *anchored* at the run containing the hit row — one of four
 *    interpretations (solid core, or the tr/bl/br core dot left of / at /
 *    right of the anchor run), best fit wins. This is dot-tolerant and, being
 *    a chord through the center, rotation-invariant.
 * 4. Cluster hits within one module; refine each strong cluster by
 *    alternating row/column extents through its center (3 iterations).
 * 5. Choose four by parallelogram closure, classify TL by core brightness in
 *    the FULL-RESOLUTION plane, orient TR/BL by cross product, correct the
 *    module for rotation.
 *
 * Loads after luma-plane.js. IIFE; exposes window.CimbarFinderLocator /
 * module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;

const P5 = [1, 1, 3, 1, 1];
const P7 = [1, 1, 1, 1, 1, 1, 1];
const P7_TOL = 0.25;

/**
 * Minimum downscaled module. Below ~3 px a ring is 2 px wide and, after
 * binarization, integer quantization makes a +-25% tolerance accept any
 * exact-2 px run, so ordinary photo texture matches the pattern. It also
 * bounds the barcode at >=57*2*3 = 342 full-res px across, under which the
 * 64-cell grid is not sampleable anyway.
 */
const MIN_MODULE = 3.0;

function clampInt(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

/** Dart's `%` on doubles is a Euclidean modulo — always >= 0 for a positive divisor. */
function dartMod(a, m) { const r = a % m; return r < 0 ? r + m : r; }

/** Local-mean binarization (integral image). dark = v < mean - 8 || v < 24. */
function binarize(p) {
  const w = p.width, h = p.height, luma = p.luma;
  const win = Math.max(15, Math.floor(Math.min(w, h) / 10));
  const half = Math.floor(win / 2);
  const iw = w + 1;
  const integral = new Int32Array(iw * (h + 1));
  for (let y = 1; y <= h; y++) {
    let rowSum = 0;
    const rowOff = y * iw, prevOff = (y - 1) * iw, srcOff = (y - 1) * w;
    for (let x = 1; x <= w; x++) {
      rowSum += luma[srcOff + x - 1];
      integral[rowOff + x] = integral[prevOff + x] + rowSum;
    }
  }
  const out = new Uint8Array(w * h); // 1 = dark
  for (let y = 0; y < h; y++) {
    const y0 = Math.max(0, y - half), y1 = Math.min(h, y + half + 1);
    const i0 = y0 * iw, i1 = y1 * iw, srcOff = y * w;
    for (let x = 0; x < w; x++) {
      const x0 = Math.max(0, x - half), x1 = Math.min(w, x + half + 1);
      const sum = integral[i1 + x1] - integral[i0 + x1] - integral[i1 + x0] + integral[i0 + x0];
      const mean = sum / ((y1 - y0) * (x1 - x0));
      const v = luma[srcOff + x];
      out[srcOff + x] = (v < mean - 8 || v < 24) ? 1 : 0;
    }
  }
  return out;
}

/** A maximal same-colour run. `end` is exclusive. */
function makeRun(start, length, dark) { return { start, length, dark, end: start + length }; }

function rowRuns(bin, w, y) {
  const runs = [];
  const off = y * w;
  let start = 0;
  let dark = bin[off] === 1;
  for (let x = 1; x <= w; x++) {
    const d = x < w ? bin[off + x] === 1 : !dark;
    if (d !== dark) {
      runs.push(makeRun(start, x - start, dark));
      start = x;
      dark = d;
    }
  }
  return runs;
}

function colRuns(bin, w, x, y0, y1) {
  const runs = [];
  let start = y0;
  let dark = bin[y0 * w + x] === 1;
  for (let y = y0 + 1; y <= y1; y++) {
    const d = y < y1 ? bin[y * w + x] === 1 : !dark;
    if (d !== dark) {
      runs.push(makeRun(start, y - start, dark));
      start = y;
      dark = d;
    }
  }
  return runs;
}

/**
 * Sliding match starting at light run [i], bounded by dark runs on both
 * sides. Tries the solid core (1:1:3:1:1, 50% per-run tolerance) and then
 * the dotted core (1:1:1:1:1:1:1) at a much tighter tolerance.
 *
 * The dotted pattern is needed because an axis-aligned chord through an
 * obliquely rotated finder cannot avoid the core dot: the core's clean-chord
 * band is half-width (3m/2)|sin t - cos t| while the dot's shadow is
 * (m/2)(sin t + cos t), and for t near 37 deg the shadow is 2.4x the band.
 * Its tolerance is P7_TOL, not 0.5, because a uniform 7-run pattern at 50%
 * also admits windows shifted by one run where a merged ~2-module run stands
 * in for a 1-module one.
 *
 * Returns [total, m] or null.
 */
function slidingMatch(runs, i) {
  const five = fitAt(runs, i, P5, 0.5);
  if (five !== null) return five;
  return fitAt(runs, i, P7, P7_TOL);
}

function fitAt(runs, i, pat, tol) {
  const n = pat.length;
  if (i + n >= runs.length) return null; // dark run required on both sides
  let total = 0;
  for (let k = 0; k < n; k++) total += runs[i + k].length;
  const m = total / 7;
  for (let k = 0; k < n; k++) {
    const e = pat[k] * m;
    if (Math.abs(runs[i + k].length - e) > tol * e) return null;
  }
  return [total, m];
}

/**
 * Relative fit error of pattern [pat] over runs[start..start+n) with module
 * total/7; null when colors do not alternate light-first or bounds fail.
 */
function fit(runs, start, pat) {
  const n = pat.length;
  if (start < 1 || start + n >= runs.length) return null;
  if (runs[start].dark) return null;
  let total = 0;
  for (let k = 0; k < n; k++) total += runs[start + k].length;
  const m = total / 7;
  let worst = 0.0;
  for (let k = 0; k < n; k++) {
    const e = pat[k] * m;
    const err = Math.abs(runs[start + k].length - e) / e;
    if (err > worst) worst = err;
  }
  return worst;
}

const ANCHOR_TRIES = [[-2, P5], [-2, P7], [-3, P7], [-4, P7]];

/**
 * Finder extent [start, end) along a run list, anchored at the run that
 * contains position [p]. Tries: solid core (5 runs starting two runs before
 * the anchor), and the dotted core with the anchor being the left core half,
 * the dot, or the right core half (7 runs). Best fit <= 0.5 wins; the module
 * must be within 0.5-2x of [m]. Returns [start, end] or null.
 */
function anchoredExtent(runs, p, m) {
  let j = -1;
  for (let i = 0; i < runs.length; i++) {
    if (p >= runs[i].start && p < runs[i].end) { j = i; break; }
  }
  if (j < 0) return null;
  let bestErr = 0.5;
  let best = null;
  for (let t = 0; t < ANCHOR_TRIES.length; t++) {
    const off = ANCHOR_TRIES[t][0], pat = ANCHOR_TRIES[t][1];
    const start = j + off;
    const err = fit(runs, start, pat);
    if (err === null || err > bestErr) continue;
    const end = runs[start + pat.length - 1].end;
    const mm = (end - runs[start].start) / 7;
    if (mm < 0.5 * m || mm > 2 * m) continue;
    bestErr = err;
    best = [runs[start].start, end];
  }
  return best;
}

/**
 * Alternate row/column extents through the current center (3 iterations).
 * Returns [x, y, module] or null.
 */
function refine(bin, w, h, cx, cy, m) {
  let x = cx, y = cy, mod = m;
  for (let iter = 0; iter < 3; iter++) {
    const yi = clampInt(Math.floor(y), 0, h - 1), xi = clampInt(Math.floor(x), 0, w - 1);
    const ex = anchoredExtent(rowRuns(bin, w, yi), xi, mod);
    if (ex === null) return null;
    // Same +-7 module bound as the initial scan, recentered on this
    // iteration's row.
    const cy0 = Math.max(0, Math.floor(yi - 7 * mod)), cy1 = Math.min(h, Math.ceil(yi + 7 * mod));
    const ey = anchoredExtent(colRuns(bin, w, xi, cy0, cy1), yi, mod);
    if (ey === null) return null;
    x = (ex[0] + ex[1]) / 2;
    y = (ey[0] + ey[1]) / 2;
    mod = ((ex[1] - ex[0]) + (ey[1] - ey[0])) / 14;
  }
  return [x, y, mod];
}

function dist(a, b) { return Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)); }

function failure(reason, extra) {
  return Object.assign({
    ok: false, tl: null, tr: null, bl: null, br: null,
    candidates: 0, clusters: 0, devNorm: -1, tlLuma: 0, secondLuma: 0,
    module: 0, failReason: reason, failDetail: reason,
  }, extra || {});
}

class FinderLocator {
  constructor(opts) {
    const o = opts || {};
    this.downscale = o.downscale === undefined ? 2 : o.downscale;
    this.maxDevNorm = o.maxDevNorm === undefined ? 0.35 : o.maxDevNorm;
    this.tlMargin = o.tlMargin === undefined ? 40 : o.tlMargin;
    this.maxClusters = o.maxClusters === undefined ? 12 : o.maxClusters;
  }

  /** Locates with the default parameters. */
  static locate(full) { return DEFAULT.locate(full); }

  locate(full) {
    const ds = this.downscale === 2 ? full.downscale2() : full;
    if (ds.width < 16 || ds.height < 16) return failure('tooSmall', { failDetail: 'image too small' });
    const bin = binarize(ds);
    const w = ds.width, h = ds.height;

    // Phases 2-4: row scan, anchored column extent, clustering.
    // Every row is scanned: a stride of 2 loses hits on small, rotated
    // finders (37 deg at 1.8x dropped to 2 clusters) and the row scan is
    // cheap next to sampling.
    const clusters = [];
    let candidates = 0;
    for (let y = 0; y < h; y++) {
      const runs = rowRuns(bin, w, y);
      for (let i = 1; i < runs.length; i++) {
        if (runs[i].dark) continue;
        const match = slidingMatch(runs, i);
        if (match === null) continue;
        const total = match[0], m = match[1];
        if (m < MIN_MODULE) continue;
        const cx = runs[i].start + total / 2;
        // Bound the column scan to +-7 modules around the row being
        // confirmed: a finder's full extent is 7 modules, so this always
        // contains it while avoiding a full-height column scan per hit.
        const cy0 = Math.max(0, Math.floor(y - 7 * m)), cy1 = Math.min(h, Math.ceil(y + 7 * m));
        const col = colRuns(bin, w, clampInt(Math.floor(cx), 0, w - 1), cy0, cy1);
        const ey = anchoredExtent(col, y, m);
        if (ey === null) continue;
        const cy = (ey[0] + ey[1]) / 2;
        const mv = (ey[1] - ey[0]) / 7;
        candidates++;
        const mod = (m + mv) / 2;
        let best = null;
        let bestD = Infinity;
        for (let c = 0; c < clusters.length; c++) {
          const cl = clusters[c];
          const clx = cl.sx / cl.hits, cly = cl.sy / cl.hits, clm = cl.sm / cl.hits;
          const d = Math.sqrt((clx - cx) * (clx - cx) + (cly - cy) * (cly - cy));
          if (d <= Math.max(2.0, clm) && d < bestD) { best = cl; bestD = d; }
        }
        if (best === null) {
          best = { sx: 0, sy: 0, sm: 0, hits: 0 };
          clusters.push(best);
        }
        best.sx += cx;
        best.sy += cy;
        best.sm += mod;
        best.hits++;
      }
    }

    const strong = clusters.filter((c) => c.hits >= 2);
    strong.sort((a, b) => b.hits - a.hits);
    const refined = [];
    const unrefined = [];
    for (const c of strong.slice(0, this.maxClusters)) {
      const cx = c.sx / c.hits, cy = c.sy / c.hits, cm = c.sm / c.hits;
      const r = refine(bin, w, h, cx, cy, cm);
      if (r !== null) refined.push({ x: r[0], y: r[1], m: r[2] });
      else unrefined.push({ x: cx, y: cy, m: cm });
    }
    if (refined.length < 4) {
      // refinement can fail one module off the core on textured scenes; the
      // centroid is still a usable corner. Only fall back to it when the
      // successfully-refined pool is otherwise too small — an unrefined
      // centroid competing on parallelogram fit alone can look deceptively
      // clean and out-rank a real, refined corner.
      for (const c of unrefined) refined.push(c);
    }
    if (refined.length < 4) {
      return failure('candidates', {
        candidates, clusters: strong.length,
        failDetail: `fewer than 4 finder candidates (${refined.length} after refinement, ${strong.length} clusters)`,
      });
    }

    // Phase 5: parallelogram selection over diagonal pairs.
    let bestDev = Infinity;
    let bestQuad = null; // [P, R, Q, S] cyclic; diagonals PQ and RS
    const n = refined.length;
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        for (let k = 0; k < n; k++) {
          if (k === i || k === j) continue;
          for (let l = k + 1; l < n; l++) {
            if (l === i || l === j) continue;
            const p = refined[i], q = refined[j], r = refined[k], s = refined[l];
            const mMax = Math.max(p.m, q.m, r.m, s.m), mMin = Math.min(p.m, q.m, r.m, s.m);
            if (mMax > 2 * mMin) continue;
            const side = (dist(p, r) + dist(r, q) + dist(q, s) + dist(s, p)) / 4;
            if (side <= 0) continue;
            const ex = (p.x + q.x) - (r.x + s.x), ey = (p.y + q.y) - (r.y + s.y);
            const dev = Math.sqrt(ex * ex + ey * ey) / side;
            const ratio = side / ((mMax + mMin) / 2);
            // finder centers are 57 modules apart; the module here is still
            // 1/cos(theta)-inflated (57*cos45 ~= 40), so the floor is 36
            if (ratio < 36 || ratio > 75) continue;
            if (dev < bestDev) { bestDev = dev; bestQuad = [p, r, q, s]; }
          }
        }
      }
    }
    if (bestQuad === null || bestDev > this.maxDevNorm) {
      return failure('parallelogram', {
        candidates, clusters: strong.length, devNorm: bestQuad === null ? -1 : bestDev,
        failDetail: `no parallelogram of finders (devNorm ${isFinite(bestDev) ? bestDev.toFixed(3) : '-'})`,
      });
    }

    // Phase 6: classify TL by full-res core brightness; BR is TL's diagonal
    // partner. The cores MUST be sampled in the full-resolution plane: after
    // the 2x downscale the ~8 px core cell is only ~4 px, too coarse to tell
    // a dotted centre from a solid one.
    const scale = this.downscale;
    const pts = bestQuad.map((c) => ({ x: c.x * scale, y: c.y * scale, module: c.m * scale }));
    const lum = pts.map((f) => full.mean3x3(Math.floor(f.x), Math.floor(f.y)));
    let tlIdx = 0;
    for (let i = 1; i < 4; i++) if (lum[i] > lum[tlIdx]) tlIdx = i;
    let second = -1.0;
    for (let i = 0; i < 4; i++) if (i !== tlIdx && lum[i] > second) second = lum[i];
    if (lum[tlIdx] - second < this.tlMargin) {
      return failure('tlMargin', {
        candidates, clusters: strong.length, devNorm: bestDev,
        tlLuma: lum[tlIdx], secondLuma: second,
        failDetail: `TL core not distinct (${lum[tlIdx].toFixed(0)} vs ${second.toFixed(0)})`,
      });
    }
    const brIdx = (tlIdx + 2) % 4;
    const tl = pts[tlIdx], br = pts[brIdx];
    let tr = null, bl = null;
    for (const i of [(tlIdx + 1) % 4, (tlIdx + 3) % 4]) {
      const p = pts[i];
      const cross = (br.x - tl.x) * (p.y - tl.y) - (br.y - tl.y) * (p.x - tl.x);
      if (cross < 0) tr = p; else bl = p;
    }
    if (tr === null || bl === null) {
      return failure('orientation', {
        candidates, clusters: strong.length, devNorm: bestDev,
        tlLuma: lum[tlIdx], secondLuma: second,
        failDetail: 'TR/BL orientation ambiguous',
      });
    }
    // Axis-aligned chords through a finder rotated by theta are 1/cos(theta)
    // longer than the true module: correct with the grid rotation folded into
    // +-45 deg. Dart's `%` is Euclidean, hence dartMod here.
    let folded = dartMod(Math.atan2(tr.y - tl.y, tr.x - tl.x), Math.PI / 2);
    if (folded > Math.PI / 4) folded -= Math.PI / 2;
    const cosF = Math.cos(folded);
    // pts are in the (possibly cropped) plane's local coordinates; the
    // returned finders must be absolute full-frame pixels.
    const ox = full.originX, oy = full.originY;
    const modules = [tl, tr, bl, br].map((f) => f.module * cosF);
    return {
      ok: true,
      tl: [tl.x + ox, tl.y + oy],
      tr: [tr.x + ox, tr.y + oy],
      bl: [bl.x + ox, bl.y + oy],
      br: [br.x + ox, br.y + oy],
      candidates,
      clusters: strong.length,
      devNorm: bestDev,
      tlLuma: lum[tlIdx],
      secondLuma: second,
      module: (modules[0] + modules[1] + modules[2] + modules[3]) / 4,
      modules,
      failReason: null,
      failDetail: null,
    };
  }
}

const DEFAULT = new FinderLocator();

const API = { FinderLocator };
if (isNode) module.exports = API; else window.CimbarFinderLocator = API;
})();
