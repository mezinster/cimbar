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
// Always install the shim: Node >= 18 has a native Blob without the `_data` view used below.
global.Blob = class Blob {
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
// Partly compressible: 40 000 chars of lorem text followed by 8 000 random bytes, so the
// deflated container is ~9 KB → N = 5 source frames, R = 2 repair frames (verify after generating).
const loremText = ('Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ').repeat(400).slice(0, 40000);
function codedBytes() { const t = new Uint8Array(Buffer.from(loremText, 'utf8')); const r = randomBytes(8000, 7); const out = new Uint8Array(t.length + r.length); out.set(t, 0); out.set(r, t.length); return out; }

const CASES = [
  { name: 'hello', fileName: 'hello.txt', bytes: new Uint8Array(Buffer.from('Hello, CimBar v2!\n', 'utf8')), passphrase: null, fileId: 0x1001, coded: false },
  { name: 'lorem_12k', fileName: 'lorem_12k.bin', bytes: randomBytes(12000, 42), passphrase: null, fileId: 0x1002, coded: false },
  { name: 'lorem_12k_enc', fileName: 'lorem_12k.bin', bytes: randomBytes(12000, 42), passphrase: 'test123', fileId: 0x1003, coded: false },
  { name: 'edge_one_frame', fileName: 'e.bin', bytes: null, passphrase: null, fileId: 0x1004, framedLen: PER, coded: false },
  { name: 'edge_two_frames', fileName: 'e.bin', bytes: null, passphrase: null, fileId: 0x1005, framedLen: PER + 1, coded: false },
  { name: 'lorem_coded', fileName: 'lorem.bin', bytes: codedBytes(), passphrase: null, fileId: 0x1006, coded: true },
  { name: 'lorem_coded_enc', fileName: 'lorem.bin', bytes: codedBytes(), passphrase: 'test123', fileId: 0x1007, coded: true },
];
for (const c of CASES) {
  if (c.framedLen) c.bytes = fixedBytes(c.framedLen - 4 - 4 - nameLen(c.fileName), 0x40);
}

// NOTE: the five pre-v2.1 cases (coded: false) must keep producing byte-identical .gif/.json
// output to what is already committed, so every v2.1 addition below (compression, repair
// frames, and the new sidecar fields that describe them) is strictly gated on `c.coded`.
function buildCase(c) {
  const payload = C.buildPayload(c.fileName, c.bytes);
  let container = payload;
  let compressed = false;
  if (c.coded) {
    const z = require('zlib');
    const d = new Uint8Array(z.deflateSync(Buffer.from(payload)));
    if (d.length <= Math.floor(payload.length * (1 - F.SPEC.compression.minSaving))) {
      container = d;
      compressed = true;
    }
  }
  let framedPayload = container;
  if (c.passphrase !== null) {
    framedPayload = encryptBytesNode(container, c.passphrase, fixedBytes(16, 0xA0), fixedBytes(12, 0xB0));
  }
  const framedData = C.withLengthPrefix(framedPayload);
  if (c.framedLen && framedData.length !== c.framedLen) throw new Error(`${c.name}: framedData ${framedData.length} != ${c.framedLen}`);
  const frames = c.coded
    ? C.splitIntoFrames(framedData, c.fileId, { encrypted: c.passphrase !== null, compressed })
    : C.splitIntoFrames(framedData, c.fileId, c.passphrase !== null);
  const R = c.coded ? C.gifRepairCount(frames.length) : 0;
  const all = frames.slice();
  if (R > 0) {
    const bodies = C.frameBodies(frames);
    for (let r = 0; r < R; r++) all.push(C.repairFrame(bodies, c.fileId, r, { encrypted: c.passphrase !== null, compressed }));
  }

  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const size = F.SPEC.grid.framePx;
  const enc = new GifEncoder(size, size, DELAY_MS / 10);
  const side = {
    name: c.name, fileName: c.fileName, fileBytesBase64: Buffer.from(c.bytes).toString('base64'),
    passphrase: c.passphrase, fileId: c.fileId, total: frames.length, delayMs: DELAY_MS,
    framedDataLength: framedData.length,
  };
  if (c.coded) {
    side.compressed = compressed;
    side.sourceFrames = frames.length;
    side.repairFrames = R;
    side.frameCount = all.length;
  }
  side.frames = [];
  all.forEach((data, idx) => {
    const raw = C.encodeRSFrame(data, rs);
    const cv = new MockCanvas(size, size);
    C.renderFrame(cv.getContext('2d'), raw);
    enc.addFrame(cv);
    const h = F.decodeHeader(data);
    if (c.coded) {
      side.frames.push({
        seq: h.seq,
        repair: h.repair,
        r: h.repair ? h.seq : null,
        header: { version: h.version, encrypted: h.encrypted, repair: h.repair, compressed: h.compressed, fileId: h.fileId, seq: h.seq, total: h.total },
        dataHex: hex(data), rawHex: hex(raw), cells: Array.from(F.packCells(raw)),
        coef12: h.repair ? Array.from(F.codingCoefficients(h.fileId, h.seq, h.total).subarray(0, 12)) : null,
      });
    } else {
      side.frames.push({
        seq: idx,
        header: { version: h.version, encrypted: h.encrypted, fileId: h.fileId, seq: h.seq, total: h.total },
        dataHex: hex(data), rawHex: hex(raw), cells: Array.from(F.packCells(raw)),
      });
    }
  });
  fs.writeFileSync(path.join(outDir, c.name + '.gif'), Buffer.from(enc.finish()._data));
  fs.writeFileSync(path.join(outDir, c.name + '.json'), JSON.stringify(side));
  console.log(`${c.name}: ${frames.length} source frame(s), ${R} repair frame(s), ${framedData.length} framed bytes, compressed=${compressed}`);
}

fs.mkdirSync(outDir, { recursive: true });
for (const c of CASES) buildCase(c);
