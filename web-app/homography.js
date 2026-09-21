/**
 * homography.js — projective geometry for the photo decode path (spec §6.3).
 * Port of app/lib/core/decode/homography.dart (Homography, HomographyGridModel)
 * and app/lib/core/decode/grid_model.dart (ExactGridModel). Loads after
 * format.js (ExactGridModel reads CimbarFormat.SPEC.grid). IIFE; exposes
 * window.CimbarHomography / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const Fmt = isNode ? require('./format.js') : window.CimbarFormat;

/**
 * 3x3 projective transform, row-major, h[8] === 1.
 * map(x, y) = ((h0 x + h1 y + h2) / w, (h3 x + h4 y + h5) / w), w = h6 x + h7 y + 1.
 */
class Homography {
  constructor(h) { this.h = h; }

  map(x, y) {
    const h = this.h;
    const w = h[6] * x + h[7] * y + h[8];
    const iw = Math.abs(w) < 1e-12 ? 0 : 1 / w;
    return [(h[0] * x + h[1] * y + h[2]) * iw, (h[3] * x + h[4] * y + h[5]) * iw];
  }

  /** Direct linear transform from four point correspondences. Null if singular. */
  static solve(from, to) {
    if (from.length !== 4 || to.length !== 4) throw new Error('need exactly 4 correspondences');
    const a = new Float64Array(64);
    const b = new Float64Array(8);
    for (let i = 0; i < 4; i++) {
      const [sx, sy] = from[i];
      const [dx, dy] = to[i];
      const r0 = i * 2, r1 = r0 + 1;
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
    const x = _solve8(a, b);
    if (x === null) return null;
    const out = new Float64Array(9);
    for (let i = 0; i < 8; i++) out[i] = x[i];
    out[8] = 1.0;
    return new Homography(out);
  }
}

function _solve8(a, b) {
  const n = 8;
  const m = Float64Array.from(a);
  const r = Float64Array.from(b);
  for (let col = 0; col < n; col++) {
    let maxRow = col;
    let maxVal = Math.abs(m[col * n + col]);
    for (let row = col + 1; row < n; row++) {
      const v = Math.abs(m[row * n + col]);
      if (v > maxVal) {
        maxVal = v;
        maxRow = row;
      }
    }
    if (maxVal < 1e-10) return null;
    if (maxRow !== col) {
      for (let j = 0; j < n; j++) {
        const t = m[col * n + j];
        m[col * n + j] = m[maxRow * n + j];
        m[maxRow * n + j] = t;
      }
      const t = r[col];
      r[col] = r[maxRow];
      r[maxRow] = t;
    }
    const pivot = m[col * n + col];
    for (let row = col + 1; row < n; row++) {
      const f = m[row * n + col] / pivot;
      if (f === 0) continue;
      for (let j = col; j < n; j++) {
        m[row * n + j] -= f * m[col * n + j];
      }
      r[row] -= f * r[col];
    }
  }
  const x = new Float64Array(n);
  for (let row = n - 1; row >= 0; row--) {
    let s = r[row];
    for (let j = row + 1; j < n; j++) {
      s -= m[row * n + j] * x[j];
    }
    x[row] = s / m[row * n + row];
  }
  return x;
}

/** Grid model from four finder centers in source pixels (spec §6.3). */
class HomographyGridModel {
  constructor(h) { this.h = h; }

  static fromFinders({ tl, tr, bl, br }) {
    const h = Homography.solve(HomographyGridModel.finderCells, [tl, tr, bl, br]);
    return h === null ? null : new HomographyGridModel(h);
  }

  toSource(cx, cy) { return this.h.map(cx, cy); }
}

HomographyGridModel.finderCells = [[3.5, 3.5], [60.5, 3.5], [3.5, 60.5], [60.5, 60.5]];

/** Identity model for frames whose pixels are at exact spec positions (GIF path). */
class ExactGridModel {
  toSource(cx, cy) {
    const grid = Fmt.SPEC.grid;
    return [grid.quietPx + cx * grid.pitchPx, grid.quietPx + cy * grid.pitchPx];
  }
}

const API = { Homography, HomographyGridModel, ExactGridModel };
if (isNode) module.exports = API; else window.CimbarHomography = API;
})();
