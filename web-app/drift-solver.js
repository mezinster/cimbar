/**
 * drift-solver.js — per-cell sub-pixel drift correction, the flood-fill hot
 * path that corrects residual misalignment a single homography can't model
 * (spec §6.5). Port of app/lib/core/decode/drift_solver.dart.
 *
 * BFS from the eight seed cells adjacent to the four finder corners; each
 * cell starts from the mean drift of its decided 4-neighbours, hill-climbs
 * over the 3x3 offsets for up to 3 iterations (breaking early once no offset
 * improves), widens to the +-2 ring when the best hamming exceeds
 * wideThreshold (always for seed cells, which have no decided neighbour), and
 * clamps to +-clampPx. Sampling is luma-only and matching is symbol-only
 * (bestSymbol) — this runs on every one of the 3840 usable cells per frame
 * and must not do RGB reads or colour matching.
 *
 * Loads after cell-sampler.js and cell-classifier.js (only used via the
 * instances passed in; not required directly). IIFE; exposes
 * window.CimbarDriftSolver / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const Fmt = isNode ? require('./format.js') : window.CimbarFormat;

// 3x3 neighbourhood searched every hill-climb iteration, center first.
const NEAR = [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

// +-2 px ring (the 3x3 square minus the inner 3x3), searched when the best
// hamming from NEAR is still above wideThreshold, or for seed cells always.
const RING2 = [
  [-2, -2], [-1, -2], [0, -2], [1, -2], [2, -2],
  [-2, -1], [2, -1],
  [-2, 0], [2, 0],
  [-2, 1], [2, 1],
  [-2, 2], [-1, 2], [0, 2], [1, 2], [2, 2],
];

// Eight cells adjacent to the four finder corners: the BFS starting points.
const SEEDS = [[8, 0], [0, 8], [55, 0], [63, 8], [0, 55], [8, 63], [63, 55], [55, 63]];

// 4-connected neighbourhood, used both to average decided neighbours' drift
// and to expand the BFS frontier. Order matters: it fixes the summation
// order of the neighbour-average, matching Dart's iteration order exactly.
const NEIGH4 = [[1, 0], [-1, 0], [0, 1], [0, -1]];

class DriftSolver {
  constructor(sampler, classifier, opts) {
    const o = opts || {};
    this.sampler = sampler;
    this.classifier = classifier;
    this.wideThreshold = o.wideThreshold === undefined ? 20 : o.wideThreshold;
    this.clampPx = o.clampPx === undefined ? 6 : o.clampPx;
  }

  solve() {
    const n = Fmt.SPEC.grid.gridCells;
    const sampler = this.sampler, classifier = this.classifier;
    const clampPx = this.clampPx, wideThreshold = this.wideThreshold;

    const dx = new Float32Array(n * n);
    const dy = new Float32Array(n * n);
    let widened = 0;

    const visited = new Uint8Array(n * n);
    const queue = [];
    for (const [c, r] of SEEDS) {
      const k = r * n + c;
      if (visited[k] === 0) {
        visited[k] = 1;
        queue.push(k);
      }
    }

    const luma = new Float32Array(64);
    let sumAbs = 0.0;
    let maxAbs = 0.0;
    let count = 0;

    let head = 0;
    while (head < queue.length) {
      const k = queue[head++];
      const col = k % n, row = Math.floor(k / n);

      // Initial drift = mean of decided 4-neighbours.
      let ix = 0.0, iy = 0.0, nn = 0;
      for (const [dc, dr] of NEIGH4) {
        const c2 = col + dc, r2 = row + dr;
        if (c2 < 0 || c2 >= n || r2 < 0 || r2 >= n) continue;
        const k2 = r2 * n + c2;
        if (visited[k2] === 2) {
          ix += dx[k2];
          iy += dy[k2];
          nn++;
        }
      }
      if (nn > 0) {
        ix /= nn;
        iy /= nn;
      }

      // Hill-climb over the 3x3 neighbourhood: re-center on the best offset
      // until the center wins (bounded by the clamp), so a 2 px error is
      // reached in two steps rather than stalling one pixel short.
      let bestX = ix, bestY = iy;
      sampler.sampleLuma(col, row, luma, bestX, bestY);
      let bestH = classifier.bestSymbol(luma)[1];
      // max 3 steps; measured drift <= 2.1 px
      for (let iter = 0; iter < 3; iter++) {
        let moved = false;
        const cx = bestX, cy = bestY;
        for (const [ox, oy] of NEAR) {
          if (ox === 0 && oy === 0) continue;
          const tx = cx + ox, ty = cy + oy;
          if (Math.abs(tx) > clampPx || Math.abs(ty) > clampPx) continue;
          sampler.sampleLuma(col, row, luma, tx, ty);
          const h = classifier.bestSymbol(luma)[1];
          if (h < bestH) {
            bestH = h;
            bestX = tx;
            bestY = ty;
            moved = true;
          }
        }
        if (!moved) break;
      }

      const needWide = bestH > wideThreshold;
      if (needWide || nn === 0) {
        if (needWide) widened++;
        const cx = bestX, cy = bestY;
        for (const [ox, oy] of RING2) {
          const tx = cx + ox, ty = cy + oy;
          if (Math.abs(tx) > clampPx || Math.abs(ty) > clampPx) continue;
          sampler.sampleLuma(col, row, luma, tx, ty);
          const h = classifier.bestSymbol(luma)[1];
          if (h < bestH) {
            bestH = h;
            bestX = tx;
            bestY = ty;
          }
        }
      }

      bestX = Math.max(-clampPx, Math.min(clampPx, bestX));
      bestY = Math.max(-clampPx, Math.min(clampPx, bestY));
      // dx/dy are Float32Array, matching Dart's Float32List: drift stays
      // fractional, not rounded to an integer. This matters beyond output
      // precision — a cell's initial drift is the mean of its already-decided
      // neighbours' stored dx/dy (read back a few lines up), so rounding here
      // would change the starting point every later cell in the flood fill
      // hill-climbs from, compounding across the BFS.
      dx[k] = bestX;
      dy[k] = bestY;
      visited[k] = 2;
      const a = (Math.abs(bestX) + Math.abs(bestY)) / 2;
      sumAbs += a;
      if (a > maxAbs) maxAbs = a;
      count++;

      for (const [dc, dr] of NEIGH4) {
        const c2 = col + dc, r2 = row + dr;
        if (c2 < 0 || c2 >= n || r2 < 0 || r2 >= n) continue;
        if (Fmt.isReservedCell(c2, r2)) continue;
        const k2 = r2 * n + c2;
        if (visited[k2] === 0) {
          visited[k2] = 1;
          queue.push(k2);
        }
      }
    }

    const meanAbs = count === 0 ? 0 : sumAbs / count;
    return { dx, dy, widened, meanAbs, maxAbs };
  }
}

const API = { DriftSolver };
if (isNode) module.exports = API; else window.CimbarDriftSolver = API;
})();
