'use strict';
/**
 * gen_goldens.js — renders reference GIFs with the production encoder and
 * writes JSON sidecars with full ground truth (payload, per-frame header, raw
 * bytes, per-cell values). Output: test-data/goldens/<name>.{gif,json}.
 * Deterministic: fixed seeds, fixed fileIds, fixed salt/iv.
 * Usage: node tools/gen_goldens.js
 */
const fs = require('fs');
const path = require('path');
global.ImageData = global.ImageData || class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
global.Blob = global.Blob || class Blob {
  constructor(parts) {
    const flat = parts.map(p => p instanceof Uint8Array ? p : new Uint8Array(p));
    let total = 0; flat.forEach(a => total += a.length);
    this._data = new Uint8Array(total);
    let off = 0; flat.forEach(a => { this._data.set(a, off); off += a.length; });
  }
  get size() { return this._data.length; }
};
const { MockCanvas } = require('../tests/mock_canvas.js');
const { GifEncoder } = require('../gif-encoder.js');
const { ReedSolomon } = require('../rs.js');
const F = require('../format.js');
const C = require('../cimbar.js');
const { encryptBytesNode } = require('./node_crypto.js');
const { mulberry32 } = require('./gen_tiles.js');

const outDir = path.join(__dirname, '..', '..', 'test-data', 'goldens');
const PER = F.fileBytesPerFrame();
const DELAY_MS = F.SPEC.gif.defaultDelayMs;

function randomBytes(n, seed) {
  const rnd = mulberry32(seed);
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = Math.floor(rnd() * 256);
  return b;
}
function fixedBytes(n, start) { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = (start + i) & 0xFF; return b; }
function hex(bytes) { let s = ''; for (const b of bytes) s += b.toString(16).padStart(2, '0'); return s; }

// Payload sizes are chosen so that framedData (4 + 4 + nameLen + fileLen [+ 48 crypto overhead]) hits the edges.
const nameLen = (n) => Buffer.byteLength(n, 'utf8');
const CASES = [
  { name: 'hello', fileName: 'hello.txt', bytes: new Uint8Array(Buffer.from('Hello, CimBar v2!\n', 'utf8')), passphrase: null, fileId: 0x1001 },
  { name: 'lorem_12k', fileName: 'lorem_12k.bin', bytes: randomBytes(12000, 42), passphrase: null, fileId: 0x1002 },
  { name: 'lorem_12k_enc', fileName: 'lorem_12k.bin', bytes: randomBytes(12000, 42), passphrase: 'test123', fileId: 0x1003 },
  { name: 'edge_one_frame', fileName: 'e.bin', bytes: null, passphrase: null, fileId: 0x1004, framedLen: PER },
  { name: 'edge_two_frames', fileName: 'e.bin', bytes: null, passphrase: null, fileId: 0x1005, framedLen: PER + 1 },
];
for (const c of CASES) {
  if (c.framedLen) c.bytes = fixedBytes(c.framedLen - 4 - 4 - nameLen(c.fileName), 0x40);
}

function buildCase(c) {
  const payload = C.buildPayload(c.fileName, c.bytes);
  let framedPayload = payload;
  if (c.passphrase !== null) {
    framedPayload = encryptBytesNode(payload, c.passphrase, fixedBytes(16, 0xA0), fixedBytes(12, 0xB0));
  }
  const framedData = C.withLengthPrefix(framedPayload);
  if (c.framedLen && framedData.length !== c.framedLen) throw new Error(`${c.name}: framedData ${framedData.length} != ${c.framedLen}`);
  const frames = C.splitIntoFrames(framedData, c.fileId, c.passphrase !== null);
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const size = F.SPEC.grid.framePx;
  const enc = new GifEncoder(size, size, DELAY_MS / 10);
  const side = {
    name: c.name, fileName: c.fileName, fileBytesBase64: Buffer.from(c.bytes).toString('base64'),
    passphrase: c.passphrase, fileId: c.fileId, total: frames.length, delayMs: DELAY_MS,
    framedDataLength: framedData.length, frames: [],
  };
  frames.forEach((data, seq) => {
    const raw = C.encodeRSFrame(data, rs);
    const cv = new MockCanvas(size, size);
    C.renderFrame(cv.getContext('2d'), raw);
    enc.addFrame(cv);
    const h = F.decodeHeader(data);
    side.frames.push({
      seq,
      header: { version: h.version, encrypted: h.encrypted, fileId: h.fileId, seq: h.seq, total: h.total },
      dataHex: hex(data), rawHex: hex(raw), cells: Array.from(F.packCells(raw)),
    });
  });
  fs.writeFileSync(path.join(outDir, c.name + '.gif'), Buffer.from(enc.finish()._data));
  fs.writeFileSync(path.join(outDir, c.name + '.json'), JSON.stringify(side));
  console.log(`${c.name}: ${frames.length} frame(s), ${framedData.length} framed bytes`);
}

fs.mkdirSync(outDir, { recursive: true });
for (const c of CASES) buildCase(c);
