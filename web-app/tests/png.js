/**
 * png.js — minimal PNG reader for the Node test suite (no dependencies).
 *
 * PNG.decode(buffer) -> {width, height, data} where `data` is RGBA in the same
 * shape a browser canvas ImageData carries, so it can be handed straight to
 * RgbBuffer.fromImageData. Supports 8-bit non-interlaced truecolour (colour
 * type 2) and truecolour+alpha (colour type 6) only — what the scene and
 * golden fixtures use. This is a test helper, not a page script: no IIFE, not
 * staged for deploy.
 */
'use strict';
const zlib = require('zlib');

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

function paeth(a, b, c) {
  // a = left, b = above, c = upper-left
  const p = a + b - c;
  const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/** Undoes the five per-row filters in place over `raw`, returning the unfiltered scanlines. */
function unfilter(raw, width, height, bpp) {
  const stride = width * bpp;
  const out = new Uint8Array(stride * height);
  let pos = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[pos++];
    const rowOff = y * stride;
    const prevOff = rowOff - stride;
    for (let i = 0; i < stride; i++) {
      const x = raw[pos + i];
      const a = i >= bpp ? out[rowOff + i - bpp] : 0;      // left
      const b = y > 0 ? out[prevOff + i] : 0;              // above
      const c = (y > 0 && i >= bpp) ? out[prevOff + i - bpp] : 0; // upper-left
      let v;
      switch (filter) {
        case 0: v = x; break;                                  // None
        case 1: v = x + a; break;                              // Sub
        case 2: v = x + b; break;                              // Up
        case 3: v = x + ((a + b) >> 1); break;                 // Average
        case 4: v = x + paeth(a, b, c); break;                 // Paeth
        default: throw new Error(`unsupported PNG row filter ${filter} on row ${y}`);
      }
      out[rowOff + i] = v & 0xff;
    }
    pos += stride;
  }
  return out;
}

const PNG = {
  decode(buffer) {
    const buf = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer);
    for (let i = 0; i < 8; i++) {
      if (buf[i] !== PNG_SIGNATURE[i]) throw new Error('not a PNG (bad signature)');
    }
    let width = 0, height = 0, bitDepth = 0, colorType = 0, interlace = 0;
    let sawIHDR = false;
    const idat = [];
    let off = 8;
    while (off + 8 <= buf.length) {
      const len = buf.readUInt32BE(off);
      const type = buf.toString('latin1', off + 4, off + 8);
      const dataOff = off + 8;
      if (type === 'IHDR') {
        width = buf.readUInt32BE(dataOff);
        height = buf.readUInt32BE(dataOff + 4);
        bitDepth = buf[dataOff + 8];
        colorType = buf[dataOff + 9];
        // buf[dataOff + 10] compression, [+11] filter method — both always 0
        interlace = buf[dataOff + 12];
        sawIHDR = true;
      } else if (type === 'IDAT') {
        idat.push(buf.subarray(dataOff, dataOff + len));
      } else if (type === 'IEND') {
        break;
      }
      off = dataOff + len + 4; // + CRC
    }
    if (!sawIHDR) throw new Error('PNG has no IHDR');
    if (bitDepth !== 8) throw new Error(`unsupported PNG bit depth ${bitDepth} (8 only)`);
    if (colorType !== 2 && colorType !== 6) throw new Error(`unsupported PNG colour type ${colorType} (2 or 6 only)`);
    if (interlace !== 0) throw new Error('interlaced PNG not supported');
    if (idat.length === 0) throw new Error('PNG has no IDAT');

    const raw = zlib.inflateSync(Buffer.concat(idat));
    const bpp = colorType === 6 ? 4 : 3;
    const expected = (width * bpp + 1) * height;
    if (raw.length < expected) throw new Error(`PNG data short: ${raw.length} < ${expected}`);
    const px = unfilter(raw, width, height, bpp);

    const data = new Uint8ClampedArray(width * height * 4);
    if (bpp === 4) {
      data.set(px.subarray(0, width * height * 4));
    } else {
      for (let i = 0, s = 0, d = 0; i < width * height; i++, s += 3, d += 4) {
        data[d] = px[s]; data[d + 1] = px[s + 1]; data[d + 2] = px[s + 2]; data[d + 3] = 255;
      }
    }
    return { width, height, data };
  },
};

module.exports = { PNG };
