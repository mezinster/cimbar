/**
 * format.js — CimBar v2 format constants and pure helpers shared by encoder,
 * decoder and tests. Loads spec/cimbar-v2.json in Node; in the browser the
 * generated format-data.js must be included first (it sets window.CIMBAR_SPEC).
 */
'use strict';

const SPEC = (typeof module !== 'undefined' && module.exports)
  ? require('../spec/cimbar-v2.json')
  : window.CIMBAR_SPEC;

const HEADER_LEN = 8;
const FORMAT_VERSION = 2;
const BITS_PER_CELL = SPEC.bits.symbolBits + SPEC.bits.colorBits; // 6

function isReservedCell(col, row) {
  const n = SPEC.grid.gridCells, c = SPEC.finder.cornerCells;
  const horiz = col < c || col >= n - c;
  const vert = row < c || row >= n - c;
  return horiz && vert;
}

let _positions = null;
function usableCellPositions() {
  if (_positions) return _positions;
  const p = [];
  for (let row = 0; row < SPEC.grid.gridCells; row++) {
    for (let col = 0; col < SPEC.grid.gridCells; col++) {
      if (!isReservedCell(col, row)) p.push([col, row]);
    }
  }
  _positions = p;
  return p;
}

function usableCells() { return usableCellPositions().length; }

function cellOrigin(col, row) {
  return [SPEC.grid.quietPx + col * SPEC.grid.pitchPx, SPEC.grid.quietPx + row * SPEC.grid.pitchPx];
}

function rawBytesPerFrame() { return Math.floor(usableCells() * BITS_PER_CELL / 8); }

function rsBlockSizes() {
  const raw = rawBytesPerFrame();
  const sizes = [];
  let total = 0;
  while (total < raw) {
    const left = raw - total;
    if (left <= SPEC.rs.eccBytes) break;
    const bt = Math.min(SPEC.rs.blockTotal, left);
    sizes.push(bt);
    total += bt;
  }
  return sizes;
}

function dataBytesPerFrame() { return rsBlockSizes().reduce((s, b) => s + b - SPEC.rs.eccBytes, 0); }
function fileBytesPerFrame() { return dataBytesPerFrame() - HEADER_LEN; }

function hexToTile(hex) {
  const t = new Uint8Array(64);
  for (let i = 0; i < 16; i++) {
    const nib = parseInt(hex[i], 16);
    for (let b = 0; b < 4; b++) t[i * 4 + b] = (nib >> (3 - b)) & 1;
  }
  return t;
}

const _tiles = SPEC.tiles.map(hexToTile);
function tileBits(sym) { return _tiles[sym]; }

const FLAG_ENCRYPTED = 1, FLAG_REPAIR = 2, FLAG_COMPRESSED = 4, FLAG_RESERVED = 0xF8;

function encodeHeader(h) {
  const b = new Uint8Array(HEADER_LEN);
  b[0] = FORMAT_VERSION;
  b[1] = (h.encrypted ? FLAG_ENCRYPTED : 0) | (h.repair ? FLAG_REPAIR : 0) | (h.compressed ? FLAG_COMPRESSED : 0);
  b[2] = (h.fileId >> 8) & 0xFF; b[3] = h.fileId & 0xFF;
  b[4] = (h.seq >> 8) & 0xFF;    b[5] = h.seq & 0xFF;
  b[6] = (h.total >> 8) & 0xFF;  b[7] = h.total & 0xFF;
  return b;
}

function decodeHeader(bytes) {
  const h = { valid: false, reason: '', version: 0, encrypted: false, repair: false, compressed: false, fileId: 0, seq: 0, total: 0 };
  if (!bytes || bytes.length < HEADER_LEN) { h.reason = 'short'; return h; }
  h.version = bytes[0];
  const flags = bytes[1];
  h.encrypted = (flags & FLAG_ENCRYPTED) !== 0;
  h.repair = (flags & FLAG_REPAIR) !== 0;
  h.compressed = (flags & FLAG_COMPRESSED) !== 0;
  h.fileId = (bytes[2] << 8) | bytes[3];
  h.seq = (bytes[4] << 8) | bytes[5];
  h.total = (bytes[6] << 8) | bytes[7];
  if (h.version !== FORMAT_VERSION) { h.reason = 'version'; return h; }
  if ((flags & FLAG_RESERVED) !== 0) { h.reason = 'flags'; return h; }
  if (h.total < 1) { h.reason = 'total'; return h; }
  if (!h.repair && h.seq >= h.total) { h.reason = 'seq'; return h; }
  h.valid = true;
  return h;
}

/** Repair-row coefficients for (fileId, r): xorshift32 seeded from the header (spec §5.3). */
function codingCoefficients(fileId, r, n) {
  let s = ((((fileId & 0xFFFF) << 16) | (r & 0xFFFF)) ^ SPEC.coding.seedXor) >>> 0;
  if (s === 0) s = SPEC.coding.seedXor >>> 0;
  const next = () => { s ^= (s << 13) >>> 0; s >>>= 0; s ^= s >>> 17; s ^= (s << 5) >>> 0; s >>>= 0; return s; };
  for (let i = 0; i < SPEC.coding.warmup; i++) next();
  const out = new Uint8Array(n);
  for (let j = 0; j < n; j++) out[j] = next() & 0xFF;
  return out;
}

function packCells(raw) {
  const n = usableCells();
  const out = new Uint8Array(n);
  let bitPos = 0;
  for (let k = 0; k < n; k++) {
    let v = 0;
    for (let b = 0; b < BITS_PER_CELL; b++) {
      const byte = bitPos >> 3, bit = 7 - (bitPos & 7);
      const d = byte < raw.length ? (raw[byte] >> bit) & 1 : 0;
      v = (v << 1) | d;
      bitPos++;
    }
    out[k] = v;
  }
  return out;
}

function unpackCells(cells) {
  const raw = new Uint8Array(rawBytesPerFrame());
  let bitPos = 0;
  for (let k = 0; k < cells.length; k++) {
    for (let b = BITS_PER_CELL - 1; b >= 0; b--) {
      if ((cells[k] >> b) & 1) raw[bitPos >> 3] |= 1 << (7 - (bitPos & 7));
      bitPos++;
    }
  }
  return raw;
}

function cellValue(sym, color) { return ((sym & 0xF) << SPEC.bits.colorBits) | (color & 0x3); }
function cellSymbol(v) { return (v >> SPEC.bits.colorBits) & 0xF; }
function cellColor(v) { return v & 0x3; }

const API = {
  SPEC, HEADER_LEN, FORMAT_VERSION, BITS_PER_CELL,
  FLAG_ENCRYPTED, FLAG_REPAIR, FLAG_COMPRESSED,
  isReservedCell, usableCellPositions, usableCells, cellOrigin,
  rawBytesPerFrame, rsBlockSizes, dataBytesPerFrame, fileBytesPerFrame,
  hexToTile, tileBits,
  encodeHeader, decodeHeader, codingCoefficients,
  packCells, unpackCells, cellValue, cellSymbol, cellColor,
};

if (typeof module !== 'undefined' && module.exports) module.exports = API;
else window.CimbarFormat = API;
