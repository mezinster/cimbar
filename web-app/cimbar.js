/**
 * cimbar.js â€” CimBar frame encoding and decoding
 *
 * Encoding per cell:
 *   - 3 bits â†’ color index (8 colors)
 *   - 4 bits â†’ symbol index (16 shapes)
 *   = 7 bits per cell
 *
 * Reed-Solomon is applied per chunk before frame layout.
 * Each "block" is RS(255, ECC_BYTES) over GF(256):
 *   dataBytes = 255 - ECC_BYTES, eccBytes = ECC_BYTES
 *
 * Frame payload capacity:
 *   cells = floor(frameSize/CELL_SIZE)^2
 *   raw bits = cells * 7
 *   raw bytes = floor(raw bits / 8)
 *   data bytes per frame = raw bytes * (1 - ECC_RATIO)
 */

'use strict';

const CELL_SIZE = 8;   // pixels per cell side
const ECC_BYTES = 64;  // RS check bytes per block
const BLOCK_TOTAL = 255; // max RS codeword length in GF(256)
const BLOCK_DATA = BLOCK_TOTAL - ECC_BYTES; // 191 data bytes per block

// 8 perceptually distinct colors, chosen to survive GIF palette quantization
const COLORS = [
  [  0, 200, 200],  // 0 cyan
  [220,  40,  40],  // 1 red
  [ 30, 100, 220],  // 2 blue
  [255, 130,  20],  // 3 orange
  [200,  40, 200],  // 4 magenta
  [ 40, 200,  60],  // 5 green
  [230, 220,  40],  // 6 yellow
  [100,  20, 200],  // 7 indigo
];

// Pre-parse hexâ†’RGB for fast nearest-color lookup
const COLORS_HEX = COLORS.map(
  ([r,g,b]) => '#' + [r,g,b].map(x => x.toString(16).padStart(2,'0')).join('')
);

/**
 * Draw one of 16 symbols on a 2D canvas context.
 * ox,oy = top-left corner of cell, size = cell pixel size
 */
function drawSymbol(ctx, symIdx, colorRGB, ox, oy, size) {
  const [cr, cg, cb] = colorRGB;
  const color = `rgb(${cr},${cg},${cb})`;

  // Quadrant sample offsets — must match detectSymbol's q computation exactly
  const q = Math.max(1, Math.floor(size * 0.28));
  const h = Math.max(1, Math.floor(q * 0.75));

  // Fill entire cell with the foreground color.
  // The center pixel (size/2, size/2) is never covered by a quadrant block,
  // so it stays as the foreground color and is used by nearestColorIdx for
  // color detection.
  ctx.fillStyle = color;
  ctx.fillRect(ox, oy, size, size);

  // For each 0-bit, paint a black 2h×2h block centered on the detector's
  // sample point.  A foreground-colored region reads as 1; black reads as 0.
  ctx.fillStyle = '#000000';
  if (!((symIdx >> 3) & 1)) ctx.fillRect(ox + q - h,        oy + q - h,        2*h, 2*h); // b3: TL
  if (!((symIdx >> 2) & 1)) ctx.fillRect(ox + size - q - h, oy + q - h,        2*h, 2*h); // b2: TR
  if (!((symIdx >> 1) & 1)) ctx.fillRect(ox + q - h,        oy + size - q - h, 2*h, 2*h); // b1: BL
  if (!((symIdx >> 0) & 1)) ctx.fillRect(ox + size - q - h, oy + size - q - h, 2*h, 2*h); // b0: BR
}

/**
 * Render a finder pattern (3Ã—3 cells) at corner ox,oy.
 * Used to orient/detect frames.
 */
function drawFinder(ctx, ox, oy, size, drawDot = true) {
  const s = size * 3;
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(ox, oy, s, s);
  ctx.fillStyle = '#333333';
  ctx.fillRect(ox+size, oy+size, size, size);
  if (drawDot) {
    ctx.fillStyle = '#ffffff';
    const inner = size * 0.4;
    ctx.fillRect(ox+size+(size-inner)/2, oy+size+(size-inner)/2, inner, inner);
  }
}

/**
 * Encode a single frame onto a canvas.
 * data: full encrypted byte array
 * byteOffset: start byte for this frame's RS-encoded block
 * capacity: bytes this frame holds (post-RS)
 */
function encodeFrame(canvas, ctx, rsData, byteOffset, frameCapacity) {
  const size = canvas.width;
  const cs = CELL_SIZE;
  const cols = Math.floor(size / cs);
  const rows = Math.floor(size / cs);

  // Black background
  ctx.fillStyle = '#111111';
  ctx.fillRect(0, 0, size, size);

  let cellIdx = 0;

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      // Skip finder pattern cells (top-left 3Ã—3 and bottom-right 3Ã—3)
      const inTL = row < 3 && col < 3;
      const inTR = row < 3 && col >= cols - 3;
      const inBL = row >= rows - 3 && col < 3;
      const inBR = row >= rows-3 && col >= cols-3;
      if (inTL || inTR || inBL || inBR) {
        continue;
      }

      const globalBit = cellIdx * 7;
      const bytePos   = Math.floor(globalBit / 8);
      const bitShift  = globalBit % 8;

      // Read 7 bits (may span two bytes)
      let bits = 0;
      const absPos = byteOffset + bytePos;
      for (let b = 0; b < 7; b++) {
        const absBit = (byteOffset + bytePos) * 8 + bitShift + b;
        const aB = Math.floor(absBit / 8);
        const aBit = 7 - (absBit % 8);
        const dataBit = (aB < rsData.length) ? ((rsData[aB] >> aBit) & 1) : 0;
        bits = (bits << 1) | dataBit;
      }

      const colorIdx = (bits >> 4) & 0x7;
      const symIdx   = bits & 0xF;

      const ox = col * cs;
      const oy = row * cs;

      ctx.beginPath();
      drawSymbol(ctx, symIdx, COLORS[colorIdx], ox, oy, cs);

      cellIdx++;
    }
  }

  // Draw finder patterns (four corners) — TL has no inner dot (asymmetric)
  drawFinder(ctx, 0, 0, cs, false);
  drawFinder(ctx, (cols-3)*cs, 0, cs);
  drawFinder(ctx, 0, (rows-3)*cs, cs);
  drawFinder(ctx, (cols-3)*cs, (rows-3)*cs, cs);
}

/**
 * Compute how many usable (non-finder) cells a frame of `frameSize` has.
 */
function usableCells(frameSize) {
  const cs = CELL_SIZE;
  const cols = Math.floor(frameSize / cs);
  const rows = Math.floor(frameSize / cs);
  const total = cols * rows;
  const finderCells = 9 * 4; // four 3Ã—3 corner blocks
  return total - finderCells;
}

/**
 * Raw byte capacity of a frame (before RS overhead).
 */
function rawBytesPerFrame(frameSize) {
  return Math.floor((usableCells(frameSize) * 7) / 8);
}

/**
 * Effective data bytes per frame (after RS overhead).
 * Each block: BLOCK_TOTAL bytes total, BLOCK_DATA data bytes.
 */
function dataBytesPerFrame(frameSize) {
  const raw = rawBytesPerFrame(frameSize);
  const fullBlocks = Math.floor(raw / BLOCK_TOTAL);
  const remainder  = raw % BLOCK_TOTAL;
  // remainder < ECC_BYTES â†’ can't fit even ECC; treat as 0
  const partialData = remainder > ECC_BYTES ? remainder - ECC_BYTES : 0;
  return fullBlocks * BLOCK_DATA + partialData;
}

/**
 * Apply RS encoding to a chunk of data bytes to fill one frame's raw capacity.
 * Returns a Uint8Array of length rawBytesPerFrame(frameSize).
 */
function encodeRSFrame(dataChunk, frameSize, rs) {
  const raw = rawBytesPerFrame(frameSize);

  // Phase 1: RS-encode each block into a temporary array
  const blocks = [];
  let inOff = 0, totalOut = 0;
  while (totalOut < raw) {
    const spaceLeft = raw - totalOut;
    if (spaceLeft <= ECC_BYTES) break;
    const blockTotal = Math.min(BLOCK_TOTAL, spaceLeft);
    const blockData  = blockTotal - ECC_BYTES;
    const chunk = new Uint8Array(blockData);
    const take  = Math.min(blockData, dataChunk.length - inOff);
    if (take > 0) chunk.set(dataChunk.slice(inOff, inOff + take));
    inOff += take;
    const encoded = rs.encode(chunk);
    blocks.push(encoded.slice(0, blockTotal));
    totalOut += blockTotal;
  }

  // Phase 2: Interleave — byte j of block i → position j * N + i
  const output = new Uint8Array(raw);
  const N = blocks.length;
  const maxBlockLen = blocks.reduce((m, b) => Math.max(m, b.length), 0);
  let pos = 0;
  for (let j = 0; j < maxBlockLen; j++) {
    for (let i = 0; i < N; i++) {
      if (j < blocks[i].length) {
        output[pos++] = blocks[i][j];
      }
    }
  }
  return output;
}

/**
 * Decode RS from one frame's raw bytes back to data bytes.
 * Returns Uint8Array of data bytes (length = dataBytesPerFrame).
 */
function decodeRSFrame(rawBytes, frameSize, rs) {
  // Use the canonical frame capacity, not rawBytes.length.
  // decodeFramePixels returns ceil(cells*7/8) bytes, but encodeRSFrame used
  // floor(cells*7/8) bytes, so the block boundaries must match the encoder.
  const raw = rawBytesPerFrame(frameSize);

  // Phase 1: Determine block structure
  const blockSizes = [];
  let totalOut = 0;
  while (totalOut < raw) {
    const spaceLeft = raw - totalOut;
    if (spaceLeft <= ECC_BYTES) break;
    const blockTotal = Math.min(BLOCK_TOTAL, spaceLeft);
    blockSizes.push(blockTotal);
    totalOut += blockTotal;
  }
  const N = blockSizes.length;

  // Phase 2: De-interleave — position j * N + i → byte j of block i
  const blocks = blockSizes.map(sz => new Uint8Array(sz));
  const maxBlockLen = Math.max(...blockSizes);
  let pos = 0;
  for (let j = 0; j < maxBlockLen; j++) {
    for (let i = 0; i < N; i++) {
      if (j < blockSizes[i]) {
        blocks[i][j] = (pos < rawBytes.length) ? rawBytes[pos] : 0;
        pos++;
      }
    }
  }

  // Phase 3: RS-decode each block
  const result = [];
  for (let i = 0; i < N; i++) {
    const blockData = blockSizes[i] - ECC_BYTES;
    try {
      const decoded = rs.decode(blocks[i]);
      for (let k = 0; k < decoded.length; k++) result.push(decoded[k]);
    } catch (e) {
      // If RS decode fails, push zeros (frame may be unrecoverable)
      for (let k = 0; k < blockData; k++) result.push(0);
    }
  }
  return new Uint8Array(result);
}

/**
 * Sample and decode a frame's canvas pixels back to raw bytes.
 * imageData: ImageData of the frame canvas
 * frameSize: expected frame pixel size
 */
function decodeFramePixels(imageData, frameSize) {
  const cs = CELL_SIZE;
  const cols = Math.floor(frameSize / cs);
  const rows = Math.floor(frameSize / cs);
  const W = imageData.width;

  const totalBits = usableCells(frameSize) * 7;
  const totalBytes = Math.ceil(totalBits / 8);
  const outBytes = new Uint8Array(totalBytes);

  let bitBuf = 0, bitCount = 0, byteIdx = 0;

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const inTL = row < 3 && col < 3;
      const inTR = row < 3 && col >= cols - 3;
      const inBL = row >= rows - 3 && col < 3;
      const inBR = row >= rows-3 && col >= cols-3;
      if (inTL || inTR || inBL || inBR) continue;

      const ox = col * cs;
      const oy = row * cs;

      // Detect color: sample center pixel
      const sampleX = ox + Math.floor(cs/2);
      const sampleY = oy + Math.floor(cs/2);
      const pi = (sampleY * W + sampleX) * 4;
      const colorIdx = nearestColorIdx(
        imageData.data[pi], imageData.data[pi+1], imageData.data[pi+2]
      );

      // Detect symbol: sample 5 points in a quincunx pattern
      const symIdx = detectSymbol(imageData, ox, oy, cs, W);

      const bits = ((colorIdx & 0x7) << 4) | (symIdx & 0xF);

      bitBuf = (bitBuf << 7) | bits;
      bitCount += 7;

      while (bitCount >= 8 && byteIdx < totalBytes) {
        bitCount -= 8;
        outBytes[byteIdx++] = (bitBuf >> bitCount) & 0xFF;
      }
    }
  }

  return outBytes;
}

function nearestColorIdx(r, g, b) {
  let best = 0, bestDist = Infinity;
  for (let i = 0; i < COLORS.length; i++) {
    const [cr, cg, cb] = COLORS[i];
    const dr = r-cr, dg = g-cg, db = b-cb;
    const d = dr*dr*2 + dg*dg*4 + db*db; // weight green more (luminance)
    if (d < bestDist) { bestDist = d; best = i; }
  }
  return best;
}

function detectSymbol(imageData, ox, oy, cs, W) {
  // Sample 4 quadrant points and center; build 4-bit code from brightness
  const q = Math.max(1, Math.floor(cs * 0.28));

  function luma(px, py) {
    const i = (Math.min(py, imageData.height-1) * W + Math.min(px, W-1)) * 4;
    const r = imageData.data[i], g = imageData.data[i+1], b = imageData.data[i+2];
    return 0.299*r + 0.587*g + 0.114*b;
  }

  const c  = luma(ox + Math.floor(cs/2), oy + Math.floor(cs/2));
  const tl = luma(ox + q, oy + q);
  const tr = luma(ox + cs - q, oy + q);
  const bl = luma(ox + q, oy + cs - q);
  const br = luma(ox + cs - q, oy + cs - q);

  // Use center brightness as threshold
  const thresh = c * 0.5 + 20;

  return ((tl > thresh ? 1 : 0) << 3) |
         ((tr > thresh ? 1 : 0) << 2) |
         ((bl > thresh ? 1 : 0) << 1) |
          (br > thresh ? 1 : 0);
}

if (typeof module !== 'undefined') {
  module.exports = {
    encodeFrame, decodeFramePixels,
    encodeRSFrame, decodeRSFrame,
    rawBytesPerFrame, dataBytesPerFrame, usableCells,
    CELL_SIZE, ECC_BYTES, BLOCK_DATA, COLORS,
    // Exported for unit testing
    drawSymbol, detectSymbol, nearestColorIdx,
  };
} else {
  window.Cimbar = {
    encodeFrame, decodeFramePixels,
    encodeRSFrame, decodeRSFrame,
    rawBytesPerFrame, dataBytesPerFrame, usableCells,
    CELL_SIZE, ECC_BYTES, BLOCK_DATA, COLORS,
  };
}
