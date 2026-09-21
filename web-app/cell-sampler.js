/**
 * cell-sampler.js — samples a cell's 8x8 tile through a GridModel, bilinear,
 * at the source resolution. Port of app/lib/core/decode/cell_sampler.dart.
 * Loads after format.js. IIFE; exposes window.CimbarCellSampler /
 * module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const Fmt = isNode ? require('./format.js') : window.CimbarFormat;

/** One sampled 8x8 tile: luma[64] and rgb[192], row-major. */
function newPatch() {
  return { luma: new Float32Array(64), rgb: new Float32Array(192) };
}

/**
 * Samples the 64 tile pixels of a cell through a GridModel, bilinear, at the
 * source resolution. dx/dy shift the sample position in source pixels. When
 * a luma plane is given, sampleLuma reads it (one channel, cheaper than RGB)
 * — the drift search's hot path.
 */
class CellSampler {
  constructor(image, grid, luma = null) {
    this.image = image;
    this.grid = grid;
    this.luma = luma;
    this._tmp = new Float32Array(3);
    this._corners = new Float64Array(8); // x00,y00,x10,y10,x01,y01,x11,y11
    this._pos = new Float64Array(128); // 64 sample positions, x,y interleaved
  }

  /**
   * Corners of the cell's tile region in source pixels, computed once per
   * cell: (col,row), (col+t,row), (col,row+t), (col+t,row+t) where t is the
   * tile extent in cell units (8/9). The 64 sample positions are then
   * bilinearly interpolated between these four corners — exact for affine
   * grid models, and the projective error over a 9 px cell is far below the
   * 0.5 px bilinear sampling resolution.
   */
  _cellCorners(col, row) {
    const t = Fmt.SPEC.grid.cellPx / Fmt.SPEC.grid.pitchPx; // tile extent in cell units (8/9)
    const [x00, y00] = this.grid.toSource(col, row);
    const [x10, y10] = this.grid.toSource(col + t, row);
    const [x01, y01] = this.grid.toSource(col, row + t);
    const [x11, y11] = this.grid.toSource(col + t, row + t);
    const c = this._corners;
    c[0] = x00; c[1] = y00;
    c[2] = x10; c[3] = y10;
    c[4] = x01; c[5] = y01;
    c[6] = x11; c[7] = y11;
  }

  /**
   * Fills _pos with the 64 source-pixel sample positions for a cell (x,y
   * interleaved, row-major, same order as the patch): corner-computation
   * shared by sample and sampleLuma, which then only need to do their own
   * per-position read (RGB or luma) and any luma conversion.
   */
  _samplePositions(col, row, dx, dy) {
    this._cellCorners(col, row);
    const c = this._corners, pos = this._pos;
    for (let j = 0; j < 8; j++) {
      const v = (j + 0.5) / 8;
      for (let i = 0; i < 8; i++) {
        const u = (i + 0.5) / 8;
        const w00 = (1 - u) * (1 - v), w10 = u * (1 - v), w01 = (1 - u) * v, w11 = u * v;
        const p = j * 8 + i;
        pos[p * 2] = w00 * c[0] + w10 * c[2] + w01 * c[4] + w11 * c[6] + dx;
        pos[p * 2 + 1] = w00 * c[1] + w10 * c[3] + w01 * c[5] + w11 * c[7] + dy;
      }
    }
  }

  sample(col, row, out, dx = 0, dy = 0) {
    this._samplePositions(col, row, dx, dy);
    const pos = this._pos, image = this.image;
    for (let p = 0; p < 64; p++) {
      image.bilinear(pos[p * 2], pos[p * 2 + 1], out.rgb, p * 3);
      out.luma[p] = 0.299 * out.rgb[p * 3] + 0.587 * out.rgb[p * 3 + 1] + 0.114 * out.rgb[p * 3 + 2];
    }
  }

  /** Luma-only sample of the 64 tile pixels into out[0..63]. */
  sampleLuma(col, row, out, dx = 0, dy = 0) {
    this._samplePositions(col, row, dx, dy);
    const pos = this._pos, lp = this.luma, tmp = this._tmp, image = this.image;
    for (let p = 0; p < 64; p++) {
      const sx = pos[p * 2], sy = pos[p * 2 + 1];
      if (lp !== null) {
        out[p] = lp.bilinear(sx, sy);
      } else {
        image.bilinear(sx, sy, tmp, 0);
        out[p] = 0.299 * tmp[0] + 0.587 * tmp[1] + 0.114 * tmp[2];
      }
    }
  }
}

const API = { CellSampler, newPatch };
if (isNode) module.exports = API; else window.CimbarCellSampler = API;
})();
