/**
 * luma-plane.js — 8-bit luma plane, same continuous-coordinate convention as
 * RgbBuffer: pixel k covers [k, k+1), center at k + 0.5.
 * Port of app/lib/core/decode/luma_plane.dart (omitting fromYPlane, which has
 * no browser equivalent; fromRgb replaces it). Loads after rgb-buffer.js.
 * IIFE; exposes window.CimbarLumaPlane / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;

class LumaPlane {
  constructor(width, height, luma, originX = 0, originY = 0) {
    if (luma.length !== width * height) throw new Error(`luma length ${luma.length} != ${width}*${height}`);
    this.width = width; this.height = height; this.luma = luma;
    this.originX = originX; this.originY = originY;
  }

  /** BT.601 with integer weights (77, 150, 29) / 256. */
  static fromRgb(rgb) {
    const out = new Uint8Array(rgb.width * rgb.height);
    const s = rgb.rgb;
    let j = 0;
    for (let i = 0; i < out.length; i++) {
      out[i] = (77 * s[j] + 150 * s[j + 1] + 29 * s[j + 2]) >> 8;
      j += 3;
    }
    return new LumaPlane(rgb.width, rgb.height, out, rgb.originX, rgb.originY);
  }

  /** Buffer-local pixel lookup (not offset by origin). */
  at(x, y) { return this.luma[y * this.width + x]; }

  /** Sub-plane (clamped) whose origin is the absolute offset of its (0,0). */
  crop(x0, y0, w, h) {
    const width = this.width, height = this.height, luma = this.luma;
    let cx0 = Math.min(Math.max(x0, 0), width - 1);
    let cy0 = Math.min(Math.max(y0, 0), height - 1);
    let cx1 = Math.min(Math.max(x0 + w, cx0 + 1), width);
    let cy1 = Math.min(Math.max(y0 + h, cy0 + 1), height);
    const cw = cx1 - cx0, ch = cy1 - cy0;
    const out = new Uint8Array(cw * ch);
    for (let r = 0; r < ch; r++) {
      const srcStart = (cy0 + r) * width + cx0;
      out.set(luma.subarray(srcStart, srcStart + cw), r * cw);
    }
    return new LumaPlane(cw, ch, out, this.originX + cx0, this.originY + cy0);
  }

  /**
   * Area-average 2x downscale (odd trailing row/column dropped). Always
   * returns origin (0, 0): the locator only ever downscales a plane it then
   * treats locally, regardless of that plane's own origin.
   */
  downscale2() {
    const width = this.width, height = this.height, luma = this.luma;
    const w = Math.floor(width / 2), h = Math.floor(height / 2);
    const out = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) {
      const r0 = (2 * y) * width, r1 = r0 + width;
      for (let x = 0; x < w; x++) {
        const x0 = 2 * x;
        out[y * w + x] = (luma[r0 + x0] + luma[r0 + x0 + 1] + luma[r1 + x0] + luma[r1 + x0 + 1]) >> 2;
      }
    }
    return new LumaPlane(w, h, out);
  }

  /**
   * Bilinear sample at ABSOLUTE (x, y) — subtracts originX/originY before
   * sampling, so a cropped/offset plane can be read through the same grid
   * model as the full frame.
   */
  bilinear(x, y) {
    const width = this.width, height = this.height, luma = this.luma;
    const fx = x - this.originX - 0.5, fy = y - this.originY - 0.5;
    let x0 = Math.floor(fx), y0 = Math.floor(fy);
    const tx = fx - x0, ty = fy - y0;
    let x1 = x0 + 1, y1 = y0 + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x0 >= width) x0 = width - 1;
    if (x1 >= width) x1 = width - 1;
    if (y0 >= height) y0 = height - 1;
    if (y1 >= height) y1 = height - 1;
    const a = luma[y0 * width + x0], b = luma[y0 * width + x1];
    const c = luma[y1 * width + x0], d = luma[y1 * width + x1];
    return a * (1 - tx) * (1 - ty) + b * tx * (1 - ty) + c * (1 - tx) * ty + d * tx * ty;
  }

  /**
   * Mean of the 3x3 neighbourhood around integer pixel (cx, cy), clamped.
   * Buffer-local coordinates (not offset by origin), like at.
   */
  mean3x3(cx, cy) {
    const width = this.width, height = this.height, luma = this.luma;
    let sum = 0;
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        const x = Math.min(Math.max(cx + dx, 0), width - 1);
        const y = Math.min(Math.max(cy + dy, 0), height - 1);
        sum += luma[y * width + x];
      }
    }
    return sum / 9;
  }
}

const API = { LumaPlane };
if (isNode) module.exports = API; else window.CimbarLumaPlane = API;
})();
