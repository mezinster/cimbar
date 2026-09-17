/**
 * gif-encoder.js â€” Pure JavaScript Animated GIF encoder
 *
 * Produces a standards-compliant GIF89a binary from an array of canvas frames.
 * Uses LZW compression with a fixed global color table derived from the v2 spec palette (format.js must be loaded first).
 *
 * API:
 *   const enc = new GifEncoder(width, height, delayMs);
 *   enc.addFrame(canvas);     // add a canvas element
 *   const blob = enc.finish(); // returns Blob
 */

'use strict';

const GifFmt = (typeof module !== 'undefined' && module.exports)
  ? require('./format.js')
  : window.CimbarFormat;

class GifEncoder {
  constructor(width, height, delayCs = 10) {
    this.width   = width;
    this.height  = height;
    this.delayCs = delayCs; // centiseconds (10 = 100ms)
    this.frames  = [];
  }

  addFrame(canvas) {
    const ctx = canvas.getContext('2d');
    const imageData = ctx.getImageData(0, 0, this.width, this.height);
    this.frames.push(imageData);
  }

  finish() {
    const parts = [];

    // --- Build a 256-color global palette ---
    // We use CimBar's 8 base colors + their variants + fill rest with grayscale
    const palette = buildPalette();

    // GIF Header
    parts.push(strBytes('GIF89a'));
    // Logical Screen Descriptor
    parts.push(word(this.width));
    parts.push(word(this.height));
    parts.push([0xF7, 0, 0]); // Global CT, 8-bit color, 256 entries
    // Global Color Table (256 Ã— 3 bytes)
    parts.push(palette);

    // Netscape Application Extension â€" loop forever
    parts.push([0x21, 0xFF, 0x0B]); // extension introducer, app ext label, block size
    parts.push(strBytes('NETSCAPE2.0'));
    parts.push([0x03, 0x01, 0x00, 0x00, 0x00]); // sub-block size, loop index, loop count (0=forever), terminator

    for (const imageData of this.frames) {
      // Graphic Control Extension (delay + disposal)
      parts.push([0x21, 0xF9, 0x04, 0x04]); // disposal=1 (do not dispose)
      parts.push(word(this.delayCs)); // delay in centiseconds
      parts.push([0x00, 0x00]); // transparent color index (none), block terminator

      // Quantize frame to palette
      const indices = quantizeFrame(imageData, palette);

      // Image Descriptor
      parts.push([0x2C]);
      parts.push(word(0), word(0));       // left, top
      parts.push(word(this.width), word(this.height));
      parts.push([0x00]);                 // no local CT, not interlaced

      // LZW Minimum Code Size
      const lzwMin = 8;
      parts.push([lzwMin]);

      // LZW compressed image data in sub-blocks
      const compressed = lzwCompress(indices, lzwMin);
      parts.push(compressed);
    }

    // Trailer
    parts.push([0x3B]);

    // Flatten to Uint8Array
    let totalLen = 0;
    const flat = parts.map(p => {
      if (typeof p === 'string') return new TextEncoder().encode(p);
      if (p instanceof Uint8Array) return p;
      return new Uint8Array(p);
    });
    flat.forEach(a => totalLen += a.length);

    const result = new Uint8Array(totalLen);
    let off = 0;
    flat.forEach(a => { result.set(a, off); off += a.length; });

    return new Blob([result], { type: 'image/gif' });
  }
}

// ---- Helpers ----

function strBytes(s) {
  return new TextEncoder().encode(s);
}

function word(n) {
  return [n & 0xFF, (n >> 8) & 0xFF];
}

/**
 * Build a 256-color palette (768 bytes).
 * Slots 0-3: the v2 palette, slot 4: black, slot 5: white,
 * then a grayscale ramp and a 6x6x6 cube so non-barcode pixels quantize sanely.
 */
function buildPalette() {
  const pal = new Uint8Array(256 * 3);
  let idx = 0;
  const fixed = GifFmt.SPEC.palette.concat([[0, 0, 0], [255, 255, 255]]);
  for (const [r, g, b] of fixed) {
    pal[idx * 3] = r; pal[idx * 3 + 1] = g; pal[idx * 3 + 2] = b;
    idx++;
  }
  for (let v = 0; v <= 255 && idx < 256; v += 8) {
    pal[idx * 3] = pal[idx * 3 + 1] = pal[idx * 3 + 2] = v;
    idx++;
  }
  for (let r = 0; r < 6 && idx < 256; r++) {
    for (let g = 0; g < 6 && idx < 256; g++) {
      for (let b = 0; b < 6 && idx < 256; b++) {
        pal[idx * 3] = r * 51; pal[idx * 3 + 1] = g * 51; pal[idx * 3 + 2] = b * 51;
        idx++;
      }
    }
  }
  return pal;
}



/**
 * Map each RGBA pixel to nearest palette index.
 * Returns Uint8Array of length width*height.
 */
function quantizeFrame(imageData, palette) {
  const n = imageData.width * imageData.height;
  const out = new Uint8Array(n);
  const palLen = 256;

  for (let i = 0; i < n; i++) {
    const r = imageData.data[i*4];
    const g = imageData.data[i*4+1];
    const b = imageData.data[i*4+2];

    let best = 0, bestDist = Infinity;
    for (let p = 0; p < palLen; p++) {
      const dr = r - palette[p*3];
      const dg = g - palette[p*3+1];
      const db = b - palette[p*3+2];
      const d = dr*dr*2 + dg*dg*4 + db*db;
      if (d < bestDist) { bestDist = d; best = p; if (d === 0) break; }
    }
    out[i] = best;
  }
  return out;
}

/**
 * LZW compress pixel indices into GIF sub-blocks.
 * Returns Uint8Array.
 */
function lzwCompress(indices, minCodeSize) {
  const clearCode = 1 << minCodeSize;
  const eofCode   = clearCode + 1;

  let codeSize  = minCodeSize + 1;
  let nextCode  = eofCode + 1;
  let codeMask  = (1 << codeSize) - 1;

  // Output bit stream
  const out = [];
  let bitBuf  = 0, bitCount = 0;

  // Current sub-block accumulator
  const subBlock = new Uint8Array(256);
  let subLen = 0;

  function emitBits(code, n) {
    bitBuf |= code << bitCount;
    bitCount += n;
    while (bitCount >= 8) {
      subBlock[subLen++] = bitBuf & 0xFF;
      bitBuf >>= 8;
      bitCount -= 8;
      if (subLen === 255) {
        out.push(255);
        for (let i = 0; i < 255; i++) out.push(subBlock[i]);
        subLen = 0;
      }
    }
  }

  function flushBits() {
    if (bitCount > 0) {
      subBlock[subLen++] = bitBuf & 0xFF;
      bitBuf = 0; bitCount = 0;
    }
    if (subLen > 0) {
      out.push(subLen);
      for (let i = 0; i < subLen; i++) out.push(subBlock[i]);
      subLen = 0;
    }
    out.push(0); // block terminator
  }

  // Build code table as a Map: string key "prefix,suffix" â†’ code
  const table = new Map();

  function reset() {
    table.clear();
    emitBits(clearCode, codeSize);
    codeSize = minCodeSize + 1;
    codeMask = (1 << codeSize) - 1;
    nextCode = eofCode + 1;
  }

  reset();

  let prefix = indices[0];

  for (let i = 1; i < indices.length; i++) {
    const suffix = indices[i];
    const key    = (prefix << 8) | suffix;

    if (table.has(key)) {
      prefix = table.get(key);
    } else {
      emitBits(prefix, codeSize);

      if (nextCode <= 4095) {
        table.set(key, nextCode++);
        if (nextCode > (1 << codeSize) && codeSize < 12) codeSize++;
      } else {
        reset();
      }
      prefix = suffix;
    }
  }

  emitBits(prefix, codeSize);
  emitBits(eofCode, codeSize);
  flushBits();

  return new Uint8Array(out);
}

if (typeof module !== 'undefined') module.exports = { GifEncoder };
else window.GifEncoder = GifEncoder;
