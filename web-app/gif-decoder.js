/**
 * gif-decoder.js — Pure JavaScript GIF89a frame extractor
 *
 * Parses a GIF binary and returns each frame as a canvas-rendered ImageData.
 *
 * API:
 *   const decoder = new GifDecoder(uint8Array);
 *   const frames = decoder.decode();
 *   // frames: Array of { imageData: ImageData, delay: number(ms), width, height }
 */

'use strict';

class GifDecoder {
  constructor(data) {
    this.data = data instanceof Uint8Array ? data : new Uint8Array(data);
    this.pos  = 0;
  }

  readByte()  { return this.data[this.pos++]; }
  readWord()  { const lo = this.readByte(), hi = this.readByte(); return lo | (hi << 8); }

  readBytes(n) {
    const slice = this.data.slice(this.pos, this.pos + n);
    this.pos += n;
    return slice;
  }

  skipSubBlocks() {
    let size;
    while ((size = this.readByte()) !== 0) this.pos += size;
  }

  readSubBlockData() {
    const chunks = [];
    let size;
    while ((size = this.readByte()) !== 0) {
      chunks.push(this.data.slice(this.pos, this.pos + size));
      this.pos += size;
    }
    const total = chunks.reduce((s, c) => s + c.length, 0);
    const out = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) { out.set(c, off); off += c.length; }
    return out;
  }

  decode() {
    const sig = String.fromCharCode(...this.data.slice(0, 6));
    if (sig !== 'GIF89a' && sig !== 'GIF87a') {
      throw new Error('Not a valid GIF file');
    }
    this.pos = 6;

    const screenWidth  = this.readWord();
    const screenHeight = this.readWord();
    const packed       = this.readByte();
    const hasGCT       = (packed >> 7) & 1;
    const gctSize      = 3 * (1 << ((packed & 0x07) + 1));
    this.readByte(); // bg color index
    this.readByte(); // pixel aspect ratio

    let globalCT = null;
    if (hasGCT) {
      globalCT = this.readBytes(gctSize);
    }

    const frames = [];
    // Screen buffer for disposal handling
    const screenBuf = new Uint8Array(screenWidth * screenHeight * 4);

    let disposal = 0, delay = 100, transparentIdx = -1;

    while (this.pos < this.data.length) {
      const sentinel = this.readByte();

      if (sentinel === 0x3B) break; // trailer

      if (sentinel === 0x21) {
        // Extension
        const label = this.readByte();
        if (label === 0xF9) {
          // Graphic Control Extension
          this.readByte(); // block size = 4
          const gcPacked    = this.readByte();
          disposal          = (gcPacked >> 2) & 0x07;
          const hasTransp   = gcPacked & 0x01;
          delay             = this.readWord() * 10; // cs → ms
          transparentIdx    = hasTransp ? this.readByte() : (this.readByte(), -1);
          this.readByte();   // block terminator
        } else {
          this.skipSubBlocks();
        }

      } else if (sentinel === 0x2C) {
        // Image descriptor
        const left   = this.readWord();
        const top    = this.readWord();
        const width  = this.readWord();
        const height = this.readWord();
        const imgP   = this.readByte();
        const hasLCT = (imgP >> 7) & 1;
        const lctSize = 3 * (1 << ((imgP & 0x07) + 1));
        const interlaced = (imgP >> 6) & 1;

        let colorTable = globalCT;
        if (hasLCT) {
          colorTable = this.readBytes(lctSize);
        }

        const lzwMin = this.readByte();
        const lzwData = this.readSubBlockData();

        // Decode LZW
        const pixels = lzwDecode(lzwData, lzwMin, width * height);

        // De-interlace if needed
        const finalPixels = interlaced
          ? deinterlace(pixels, width, height)
          : pixels;

        // Compose onto screen buffer
        const imageData = new ImageData(screenWidth, screenHeight);

        // Copy previous screen state
        imageData.data.set(screenBuf);

        // Paint this frame's pixels
        for (let py = 0; py < height; py++) {
          for (let px = 0; px < width; px++) {
            const pidx = py * width + px;
            const ci   = finalPixels[pidx];
            if (ci === transparentIdx) continue;

            const sx = left + px;
            const sy = top  + py;
            if (sx >= screenWidth || sy >= screenHeight) continue;

            const si = (sy * screenWidth + sx) * 4;
            if (colorTable && ci * 3 + 2 < colorTable.length) {
              imageData.data[si]   = colorTable[ci*3];
              imageData.data[si+1] = colorTable[ci*3+1];
              imageData.data[si+2] = colorTable[ci*3+2];
              imageData.data[si+3] = 255;
            }
          }
        }

        frames.push({
          imageData,
          width:  screenWidth,
          height: screenHeight,
          delay:  delay || 100,
        });

        // Handle disposal
        if (disposal === 2) {
          // Restore to background
          screenBuf.fill(0);
        } else {
          // Dispose none / leave in place
          screenBuf.set(imageData.data);
        }

        // Reset per-frame settings
        transparentIdx = -1;
        delay = 100;
        disposal = 0;

      } else {
        // Unknown sentinel, try to skip
        if (this.pos >= this.data.length) break;
      }
    }

    return frames;
  }
}

// ---- LZW Decoder ----

function lzwDecode(data, minCodeSize, pixelCount) {
  const clearCode = 1 << minCodeSize;
  const eofCode   = clearCode + 1;

  let codeSize = minCodeSize + 1;
  let nextCode = eofCode + 1;

  // Initialize dictionary
  const dict = new Array(4096);
  for (let i = 0; i < clearCode; i++) dict[i] = [i];
  dict[clearCode] = [];
  dict[eofCode]   = [];

  const output = [];
  let dataPos  = 0, bitBuf = 0, bitCount = 0;
  let prevCode = -1;

  function readCode() {
    while (bitCount < codeSize) {
      if (dataPos >= data.length) return -1;
      bitBuf |= data[dataPos++] << bitCount;
      bitCount += 8;
    }
    const code = bitBuf & ((1 << codeSize) - 1);
    bitBuf  >>= codeSize;
    bitCount -= codeSize;
    return code;
  }

  while (output.length < pixelCount) {
    const code = readCode();
    if (code < 0 || code === eofCode) break;

    if (code === clearCode) {
      codeSize = minCodeSize + 1;
      nextCode = eofCode + 1;
      prevCode = -1;
      for (let i = 0; i < clearCode; i++) dict[i] = [i];
      continue;
    }

    let entry;
    if (code < nextCode) {
      entry = dict[code];
    } else if (code === nextCode && prevCode >= 0) {
      const prev = dict[prevCode];
      entry = prev ? [...prev, prev[0]] : [0];
    } else {
      break; // corrupted
    }

    if (!entry) break;
    for (const p of entry) {
      output.push(p);
      if (output.length >= pixelCount) break;
    }

    if (prevCode >= 0 && nextCode < 4096) {
      const prev = dict[prevCode];
      dict[nextCode++] = prev ? [...prev, entry[0]] : [entry[0]];
      if (nextCode >= (1 << codeSize) && codeSize < 12) codeSize++;
    }

    prevCode = code;
  }

  return output;
}

function deinterlace(pixels, width, height) {
  const result = new Array(pixels.length);
  const passes = [
    { start: 0, step: 8 },
    { start: 4, step: 8 },
    { start: 2, step: 4 },
    { start: 1, step: 2 },
  ];
  let src = 0;
  for (const { start, step } of passes) {
    for (let y = start; y < height; y += step) {
      for (let x = 0; x < width; x++) {
        result[y * width + x] = pixels[src++];
      }
    }
  }
  return result;
}

if (typeof module !== 'undefined') module.exports = { GifDecoder };
else window.GifDecoder = GifDecoder;
