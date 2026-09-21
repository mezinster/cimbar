/**
 * rgb-buffer.js — flat 8-bit RGB buffer with bilinear sampling.
 * Port of app/lib/core/decode/rgb_buffer.dart (omitting fromYuv420/fromImage,
 * which have no browser equivalent; fromImageData replaces them). May cover
 * only a region of a larger source frame: originX/originY are the buffer's
 * absolute position, and bilinear takes ABSOLUTE source coordinates (pixel k
 * covers [k, k+1), center at k + 0.5). r/g/b index the buffer itself (local
 * coordinates). Loads after format.js. IIFE; exposes window.CimbarRgbBuffer /
 * module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;

class RgbBuffer {
  constructor(width, height, rgb, originX = 0, originY = 0) {
    if (rgb.length !== width * height * 3) throw new Error(`rgb length ${rgb.length} != ${width}*${height}*3`);
    this.width = width; this.height = height; this.rgb = rgb;
    this.originX = originX; this.originY = originY;
  }

  /** Copies a browser ImageData-like object ({width, height, data}), dropping alpha. */
  static fromImageData(d) {
    const out = new Uint8Array(d.width * d.height * 3);
    const src = d.data;
    for (let i = 0, j = 0, k = 0; i < d.width * d.height; i++, j += 4, k += 3) {
      out[k] = src[j]; out[k + 1] = src[j + 1]; out[k + 2] = src[j + 2];
    }
    return new RgbBuffer(d.width, d.height, out);
  }

  r(x, y) { return this.rgb[(y * this.width + x) * 3]; }
  g(x, y) { return this.rgb[(y * this.width + x) * 3 + 1]; }
  b(x, y) { return this.rgb[(y * this.width + x) * 3 + 2]; }

  /** Bilinear sample at continuous (x, y); writes r,g,b to out[outOff..outOff+2]. */
  bilinear(x, y, out, outOff) {
    const fx = x - this.originX - 0.5, fy = y - this.originY - 0.5;
    let x0 = Math.floor(fx), y0 = Math.floor(fy);
    const tx = fx - x0, ty = fy - y0;
    let x1 = x0 + 1, y1 = y0 + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x0 >= this.width) x0 = this.width - 1;
    if (x1 >= this.width) x1 = this.width - 1;
    if (y0 >= this.height) y0 = this.height - 1;
    if (y1 >= this.height) y1 = this.height - 1;
    const rgb = this.rgb, width = this.width;
    const i00 = (y0 * width + x0) * 3, i10 = (y0 * width + x1) * 3;
    const i01 = (y1 * width + x0) * 3, i11 = (y1 * width + x1) * 3;
    const w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
    for (let c = 0; c < 3; c++) {
      out[outOff + c] = rgb[i00 + c] * w00 + rgb[i10 + c] * w10 + rgb[i01 + c] * w01 + rgb[i11 + c] * w11;
    }
  }
}

const API = { RgbBuffer };
if (isNode) module.exports = API; else window.CimbarRgbBuffer = API;
})();
