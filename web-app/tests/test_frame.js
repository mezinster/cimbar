'use strict';
const { MockCanvas } = require('./mock_canvas.js');
const { ReedSolomon } = require('../rs.js');
const F = require('../format.js');
const C = require('../cimbar.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function assertBytes(a, b, msg) {
  assertEq(a.length, b.length, (msg || '') + ' length');
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) throw new Error(`${msg || ''} byte ${i}: ${a[i]} != ${b[i]}`);
}
function px(img, x, y) { const i = (y * img.width + x) * 4; return [img.data[i], img.data[i + 1], img.data[i + 2]]; }
function seqBytes(n, mul, add) { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = (i * mul + add) & 0xFF; return b; }

console.log('\ntest_frame.js');

const FRAME = F.SPEC.grid.framePx;

test('renderFrame paints finders per spec', () => {
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), new Uint8Array(2880));
  const img = cv.getImageData(0, 0, FRAME, FRAME);
  assertEq(px(img, 0, 0).join(','), '0,0,0', 'quiet zone black');
  assertEq(px(img, 16, 16).join(','), '255,255,255', 'TL outer ring white');
  assertEq(px(img, 16 + 9, 16 + 9).join(','), '0,0,0', 'TL black ring');
  assertEq(px(img, 16 + 18, 16 + 18).join(','), '255,255,255', 'TL core white');
  assertEq(px(img, 16 + 31, 16 + 31).join(','), '255,255,255', 'TL core center white (no dot)');
  assertEq(px(img, 529 + 31, 16 + 31).join(','), '0,0,0', 'TR core center black (dot)');
  assertEq(px(img, 16 + 31, 529 + 31).join(','), '0,0,0', 'BL core center black (dot)');
  assertEq(px(img, 529 + 31, 529 + 31).join(','), '0,0,0', 'BR core center black (dot)');
  assertEq(px(img, 529 + 18, 16 + 18).join(','), '255,255,255', 'TR core corner white');
  assertEq(px(img, 16 + 63, 16 + 63).join(','), '0,0,0', 'separator cell black');
  assertEq(px(img, 16 + 63, 16).join(','), '0,0,0', 'separator column right of TL finder black');
});

test('renderFrame paints cell (8,0) with symbol/color from raw bits', () => {
  const raw = new Uint8Array(2880);
  raw[0] = (F.cellValue(5, 2) << 2); // first cell = top 6 bits
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), raw);
  const img = cv.getImageData(0, 0, FRAME, FRAME);
  const [ox, oy] = F.cellOrigin(8, 0);
  const t = F.tileBits(5);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const expected = t[y * 8 + x] ? F.SPEC.palette[2].join(',') : '0,0,0';
    assertEq(px(img, ox + x, oy + y).join(','), expected, `pixel ${x},${y}`);
  }
  assertEq(px(img, ox + 8, oy).join(','), '0,0,0', 'gap after cell');
});

test('render -> decodeFrameExact round trip on random raw bytes', () => {
  const raw = seqBytes(2880, 131, 7);
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), raw);
  const r = C.decodeFrameExact(cv.getImageData(0, 0, FRAME, FRAME));
  assertBytes(r.raw, raw, 'raw');
  assertEq(r.diag.hammingMax, 0, 'exact hashes');
  assert(r.diag.colorMarginMin > 100, 'colors well separated');
});

test('encodeRSFrame/decodeRSFrame round trip and error correction', () => {
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const data = seqBytes(2112, 3, 1);
  const raw = C.encodeRSFrame(data, rs);
  assertEq(raw.length, 2880);
  const clean = C.decodeRSFrame(raw, rs);
  assertBytes(clean.data, data, 'clean');
  assertEq(clean.blocksOk, 12); assertEq(clean.blocksFailed, 0);
  // corrupt 30 bytes spread across the frame (interleaving spreads them over blocks)
  const bad = raw.slice();
  for (let i = 0; i < 30; i++) bad[i * 90] ^= 0xFF;
  const fixed = C.decodeRSFrame(bad, rs);
  assertBytes(fixed.data, data, 'corrected');
  assertEq(fixed.blocksFailed, 0);
});

test('decodeRSFrame reports failed blocks and zero-fills them', () => {
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const raw = C.encodeRSFrame(seqBytes(2112, 3, 1), rs);
  const bad = raw.slice();
  // Non-constant corruption: XOR by a constant could land on another valid RS codeword.
  for (let i = 0; i < 2880; i++) bad[i] ^= ((i * 37 + 11) & 0xFE) | 1;
  const r = C.decodeRSFrame(bad, rs);
  assertEq(r.blocksFailed, 12);
});

test('splitIntoFrames writes headers and pads the last frame', () => {
  const per = F.fileBytesPerFrame();
  const framed = seqBytes(per * 2 + 5, 1, 0);
  const frames = C.splitIntoFrames(framed, 0x1234, true);
  assertEq(frames.length, 3);
  frames.forEach((f, i) => {
    assertEq(f.length, 2112);
    const h = F.decodeHeader(f);
    assert(h.valid, 'valid header'); assertEq(h.seq, i); assertEq(h.total, 3); assertEq(h.fileId, 0x1234); assertEq(h.encrypted, true);
  });
  assertEq(frames[2][8 + 5], 0, 'zero padded');
  assertEq(frames[1][8], framed[per], 'second frame starts at byte per');
  assertEq(C.splitIntoFrames(new Uint8Array(0), 1, false).length, 1, 'empty input still yields one frame');
});

test('FrameAssembler accepts, dedups, rejects and completes', () => {
  const per = F.fileBytesPerFrame();
  const framed = seqBytes(per + 10, 5, 2);
  const frames = C.splitIntoFrames(framed, 7, false);
  const a = new C.FrameAssembler();
  assertEq(a.add(frames[1]).accepted, true);
  assertEq(a.total, 2); assertEq(a.filled, 1); assert(!a.isComplete());
  assertEq(a.add(frames[1]).reason, 'duplicate');
  const other = C.splitIntoFrames(seqBytes(20, 9, 3), 8, false)[0];
  assertEq(a.add(other).accepted, true, 'fileId change resets and accepts');
  assertEq(a.total, 1); assertEq(a.fileId, 8); assertEq(a.filled, 1);
  const badVer = frames[0].slice(); badVer[0] = 1;
  assertEq(a.add(badVer).reason, 'version');
  assertEq(a.add(frames[1]).accepted, true, 'fileId change back resets again');
  assertEq(a.total, 2); assertEq(a.fileId, 7); assertEq(a.filled, 1);
  assertEq(a.add(frames[0], 1).reason, 'rs');
  assertEq(a.add(frames[0]).accepted, true);
  assert(a.isComplete());
  const out = a.framedData();
  assertEq(out.length, per * 2);
  assertBytes(out.subarray(0, framed.length), framed, 'payload prefix');
});

test('payload helpers round trip', () => {
  const p = C.buildPayload('hello.txt', new Uint8Array([1, 2, 3]));
  const parsed = C.parsePayload(p);
  assertEq(parsed.fileName, 'hello.txt');
  assertBytes(parsed.fileBytes, new Uint8Array([1, 2, 3]));
  const withLen = C.withLengthPrefix(p);
  assertEq(withLen.length, p.length + 4);
  const padded = new Uint8Array(withLen.length + 50); padded.set(withLen);
  assertBytes(C.stripLengthPrefix(padded), p, 'strip');
  let threw = false;
  try { C.stripLengthPrefix(new Uint8Array([0, 0, 0, 99, 1])); } catch (e) { threw = true; }
  assert(threw, 'invalid length throws');
});

test('GIF round trip keeps v2 pixels exact', () => {
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
  const { GifEncoder } = require('../gif-encoder.js');
  const { GifDecoder } = require('../gif-decoder.js');
  const raw = seqBytes(2880, 17, 3);
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), raw);
  const enc = new GifEncoder(FRAME, FRAME, 20);
  enc.addFrame(cv);
  const gif = enc.finish()._data;
  assertEq(gif[10] & 0x07, 7, 'global color table 256 entries');
  const pal = gif.subarray(13, 13 + 768);
  for (let c = 0; c < 4; c++) assertEq([pal[c * 3], pal[c * 3 + 1], pal[c * 3 + 2]].join(','), F.SPEC.palette[c].join(','), `palette slot ${c}`);
  assertEq([pal[12], pal[13], pal[14]].join(','), '0,0,0', 'slot 4 black');
  assertEq([pal[15], pal[16], pal[17]].join(','), '255,255,255', 'slot 5 white');
  const frames = new GifDecoder(gif).decode();
  assertEq(frames.length, 1);
  const r = C.decodeFrameExact(frames[0].imageData);
  assertBytes(r.raw, raw, 'after GIF');
  assertEq(r.diag.hammingMax, 0);
});

test('decodeFrameExact rejects non-exact dimensions', () => {
  const cv = new MockCanvas(FRAME + 8, FRAME + 8);
  let threw = false;
  try { C.decodeFrameExact(cv.getImageData(0, 0, FRAME + 8, FRAME + 8)); }
  catch (e) { threw = true; assert(/v1 GIFs must be re-encoded/.test(e.message), 'error names v1 re-encode'); }
  assert(threw, 'oversized frame throws');
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
