/**
 * cimbar.js — CimBar v2 frame rendering, exact decoding, RS framing and
 * frame assembly. All constants come from format.js (spec/cimbar-v2.json).
 *
 * Frame layout: 64x64 cells, 8 px tiles with 1 px gaps, four 7x7-cell finders,
 * 6 bits per cell (4 symbol + 2 color), 2880 raw bytes per frame, RS(255,191).
 */
'use strict';

// Classic <script> files share one global lexical scope, so this file's
// top-level consts (SPEC, API) must not leak: format.js declares the same
// names. The IIFE keeps them private; only window.Cimbar / module.exports
// escape. tests/test_browser_load.js enforces this for every script.
(function () {

const Fmt = (typeof module !== 'undefined' && module.exports)
  ? require('./format.js')
  : window.CimbarFormat;
const Rateless = (typeof module !== 'undefined' && module.exports) ? require('./rateless.js') : window.CimbarRateless;
const SPEC = Fmt.SPEC;

// ── Rendering ────────────────────────────────────────────────────────────

function rgbStr(c) { return `rgb(${c[0]},${c[1]},${c[2]})`; }

function drawTile(ctx, sym, colorIdx, ox, oy) {
  const t = Fmt.tileBits(sym);
  ctx.fillStyle = rgbStr(SPEC.palette[colorIdx]);
  for (let y = 0; y < 8; y++) {
    let x = 0;
    while (x < 8) {
      if (t[y * 8 + x]) {
        let x2 = x;
        while (x2 < 8 && t[y * 8 + x2]) x2++;
        ctx.fillRect(ox + x, oy + y, x2 - x, 1);
        x = x2;
      } else {
        x++;
      }
    }
  }
}

function finderOrigin(corner) {
  const [cx, cy] = SPEC.finder.centers[corner];
  const half = SPEC.finder.outerPx / 2;
  return [
    Math.round(SPEC.grid.quietPx + cx * SPEC.grid.pitchPx - half),
    Math.round(SPEC.grid.quietPx + cy * SPEC.grid.pitchPx - half),
  ];
}

function drawFinder(ctx, corner) {
  const F = SPEC.finder;
  const [ox, oy] = finderOrigin(corner);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(ox, oy, F.outerPx, F.outerPx);
  ctx.fillStyle = '#000000';
  ctx.fillRect(ox + F.ringInsetPx, oy + F.ringInsetPx, F.outerPx - 2 * F.ringInsetPx, F.outerPx - 2 * F.ringInsetPx);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(ox + F.coreInsetPx, oy + F.coreInsetPx, F.corePx, F.corePx);
  if (F.dotOn.indexOf(corner) >= 0) {
    ctx.fillStyle = '#000000';
    ctx.fillRect(ox + F.dotInsetPx, oy + F.dotInsetPx, F.dotPx, F.dotPx);
  }
}

/** Draw one full 608x608 frame from 2880 raw (RS-encoded, interleaved) bytes. */
function renderFrame(ctx, raw) {
  const size = SPEC.grid.framePx;
  ctx.fillStyle = '#000000';
  ctx.fillRect(0, 0, size, size);
  const cells = Fmt.packCells(raw);
  const pos = Fmt.usableCellPositions();
  for (let k = 0; k < pos.length; k++) {
    const [ox, oy] = Fmt.cellOrigin(pos[k][0], pos[k][1]);
    drawTile(ctx, Fmt.cellSymbol(cells[k]), Fmt.cellColor(cells[k]), ox, oy);
  }
  for (const corner of ['tl', 'tr', 'bl', 'br']) drawFinder(ctx, corner);
}

// ── Exact decoding (GIF path: pixels are exactly where the encoder put them) ──

function lumaAt(d, i) { return 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]; }

/**
 * Decode a frame whose pixels are at exact spec positions (an ImageData of at
 * least framePx x framePx). Returns raw bytes, cell values and diagnostics.
 */
function decodeFrameExact(imageData) {
  const size = SPEC.grid.framePx;
  if (imageData.width !== size || imageData.height !== size) {
    throw new Error(`Not a CimBar v2 GIF: frames must be ${size}×${size} px, got ${imageData.width}×${imageData.height}. v1 GIFs must be re-encoded.`);
  }
  const W = imageData.width, d = imageData.data;
  const pos = Fmt.usableCellPositions();
  const cells = new Uint8Array(pos.length);
  const lum = new Float32Array(64);
  const rgb = new Float32Array(192);
  let hammingMax = 0, hammingSum = 0, colorMarginMin = Infinity;

  for (let k = 0; k < pos.length; k++) {
    const [ox, oy] = Fmt.cellOrigin(pos[k][0], pos[k][1]);
    let mean = 0;
    for (let y = 0; y < 8; y++) {
      for (let x = 0; x < 8; x++) {
        const i = ((oy + y) * W + (ox + x)) * 4;
        const p = y * 8 + x;
        lum[p] = lumaAt(d, i);
        mean += lum[p];
        rgb[p * 3] = d[i]; rgb[p * 3 + 1] = d[i + 1]; rgb[p * 3 + 2] = d[i + 2];
      }
    }
    mean /= 64;

    let bestSym = 0, bestDist = 65;
    for (let s = 0; s < 16; s++) {
      const t = Fmt.tileBits(s);
      let dist = 0;
      for (let p = 0; p < 64; p++) dist += (lum[p] > mean ? 1 : 0) ^ t[p];
      if (dist < bestDist) { bestDist = dist; bestSym = s; }
    }
    hammingSum += bestDist;
    if (bestDist > hammingMax) hammingMax = bestDist;

    const t = Fmt.tileBits(bestSym);
    let r = 0, g = 0, b = 0, n = 0;
    for (let p = 0; p < 64; p++) {
      if (t[p]) { r += rgb[p * 3]; g += rgb[p * 3 + 1]; b += rgb[p * 3 + 2]; n++; }
    }
    r /= n; g /= n; b /= n;
    let bestC = 0, bestD = Infinity, secondD = Infinity;
    for (let c = 0; c < SPEC.palette.length; c++) {
      const pc = SPEC.palette[c];
      const dd = (r - pc[0]) * (r - pc[0]) + (g - pc[1]) * (g - pc[1]) + (b - pc[2]) * (b - pc[2]);
      if (dd < bestD) { secondD = bestD; bestD = dd; bestC = c; }
      else if (dd < secondD) { secondD = dd; }
    }
    const margin = Math.sqrt(secondD) - Math.sqrt(bestD);
    if (margin < colorMarginMin) colorMarginMin = margin;

    cells[k] = Fmt.cellValue(bestSym, bestC);
  }

  return {
    raw: Fmt.unpackCells(cells),
    cells,
    diag: { hammingMax, hammingMean: hammingSum / pos.length, colorMarginMin },
  };
}

// ── Reed-Solomon framing ─────────────────────────────────────────────────

function interleave(blocks, rawLen) {
  const out = new Uint8Array(rawLen);
  const N = blocks.length;
  let maxLen = 0;
  for (const b of blocks) if (b.length > maxLen) maxLen = b.length;
  let pos = 0;
  for (let j = 0; j < maxLen; j++) {
    for (let i = 0; i < N; i++) {
      if (j < blocks[i].length) out[pos++] = blocks[i][j];
    }
  }
  return out;
}

/** RS-encode up to dataBytesPerFrame() bytes into the frame's raw bytes. */
function encodeRSFrame(data, rs) {
  const sizes = Fmt.rsBlockSizes();
  const blocks = [];
  let off = 0;
  for (const bt of sizes) {
    const bd = bt - SPEC.rs.eccBytes;
    const chunk = new Uint8Array(bd);
    const take = Math.max(0, Math.min(bd, data.length - off));
    if (take > 0) chunk.set(data.subarray(off, off + take));
    off += take;
    blocks.push(rs.encode(chunk));
  }
  return interleave(blocks, Fmt.rawBytesPerFrame());
}

/** Inverse of encodeRSFrame. Failed blocks are zero-filled and counted. */
function decodeRSFrame(raw, rs) {
  const sizes = Fmt.rsBlockSizes();
  const N = sizes.length;
  const blocks = sizes.map(s => new Uint8Array(s));
  let maxLen = 0;
  for (const s of sizes) if (s > maxLen) maxLen = s;
  let pos = 0;
  for (let j = 0; j < maxLen; j++) {
    for (let i = 0; i < N; i++) {
      if (j < sizes[i]) { blocks[i][j] = pos < raw.length ? raw[pos] : 0; pos++; }
    }
  }
  const data = new Uint8Array(Fmt.dataBytesPerFrame());
  let off = 0, blocksOk = 0, blocksFailed = 0;
  for (let i = 0; i < N; i++) {
    const bd = sizes[i] - SPEC.rs.eccBytes;
    try {
      const dec = rs.decode(blocks[i]);
      data.set(dec.subarray(0, bd), off);
      blocksOk++;
    } catch (e) {
      blocksFailed++;
    }
    off += bd;
  }
  return { data, blocksOk, blocksFailed };
}

// ── Frame split and assembly ─────────────────────────────────────────────

function frameOpts(opts) {
  if (typeof opts === 'boolean') return { encrypted: opts, compressed: false };
  return { encrypted: !!(opts && opts.encrypted), compressed: !!(opts && opts.compressed) };
}

/** Split framed data into N source frames (header + body, zero padded). */
function splitIntoFrames(framedData, fileId, opts) {
  const o = frameOpts(opts);
  const per = Fmt.fileBytesPerFrame();
  const total = Math.max(1, Math.ceil(framedData.length / per));
  if (total > 65535) throw new Error(`File too large: needs ${total} frames (max 65535)`);
  const frames = [];
  for (let seq = 0; seq < total; seq++) {
    const f = new Uint8Array(Fmt.dataBytesPerFrame());
    f.set(Fmt.encodeHeader({ encrypted: o.encrypted, compressed: o.compressed, fileId, seq, total }), 0);
    const start = seq * per, end = Math.min(framedData.length, start + per);
    if (end > start) f.set(framedData.subarray(start, end), Fmt.HEADER_LEN);
    frames.push(f);
  }
  return frames;
}

/** Repair frame r for the N source bodies (each fileBytesPerFrame long). */
function repairFrame(bodies, fileId, r, opts) {
  const o = frameOpts(opts);
  const n = bodies.length;
  const coef = Fmt.codingCoefficients(fileId, r, n);
  if (coef.every(c => c === 0)) { const e = new Error('degenerate repair id ' + r); e.degenerate = true; throw e; }
  const f = new Uint8Array(Fmt.dataBytesPerFrame());
  f.set(Fmt.encodeHeader({ encrypted: o.encrypted, compressed: o.compressed, repair: true, fileId, seq: r, total: n }), 0);
  f.set(Rateless.combineBodies(bodies, coef), Fmt.HEADER_LEN);
  return f;
}

/** Bodies of source frames produced by splitIntoFrames. */
function frameBodies(frames) { return frames.map(f => f.subarray(Fmt.HEADER_LEN)); }

function gifRepairCount(n) { return n <= 1 ? 0 : Math.ceil(n * SPEC.coding.gifRepairRatio); }

// ── File container helpers ───────────────────────────────────────────────

function buildPayload(fileName, fileBytes) {
  const nameBytes = new TextEncoder().encode(fileName);
  const out = new Uint8Array(4 + nameBytes.length + fileBytes.length);
  new DataView(out.buffer).setUint32(0, nameBytes.length, false);
  out.set(nameBytes, 4);
  out.set(fileBytes, 4 + nameBytes.length);
  return out;
}

function parsePayload(bytes) {
  if (bytes.length < 4) throw new Error('Header corrupt: payload too short');
  const nameLen = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, false);
  if (nameLen > 512 || 4 + nameLen > bytes.length) throw new Error('Header corrupt: filename length invalid');
  return {
    fileName: new TextDecoder().decode(bytes.subarray(4, 4 + nameLen)),
    fileBytes: bytes.slice(4 + nameLen),
  };
}

function withLengthPrefix(bytes) {
  const out = new Uint8Array(4 + bytes.length);
  new DataView(out.buffer).setUint32(0, bytes.length, false);
  out.set(bytes, 4);
  return out;
}

function stripLengthPrefix(bytes) {
  if (bytes.length < 4) throw new Error('Header corrupt: missing length prefix');
  const len = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, false);
  if (len < 1 || len > bytes.length - 4) throw new Error(`Header corrupt: payload length ${len} is invalid`);
  return bytes.slice(4, 4 + len);
}

const API = {
  renderFrame, decodeFrameExact,
  encodeRSFrame, decodeRSFrame,
  splitIntoFrames, repairFrame, frameBodies, gifRepairCount,
  RatelessAssembler: Rateless.RatelessAssembler,
  buildPayload, parsePayload, withLengthPrefix, stripLengthPrefix,
  // exported for tests
  drawTile, drawFinder, finderOrigin,
};

if (typeof module !== 'undefined' && module.exports) module.exports = API;
else window.Cimbar = API;

})();
