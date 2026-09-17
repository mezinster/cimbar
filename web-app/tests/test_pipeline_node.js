'use strict';
/**
 * test_pipeline_node.js — end-to-end file -> frames -> GIF -> frames -> file,
 * mirroring index.html's startEncode/startDecode flow on v2.
 */
global.ImageData = class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
global.Blob = class Blob {
  constructor(parts) {
    const flat = parts.map(p => p instanceof Uint8Array ? p : new Uint8Array(p));
    let total = 0; flat.forEach(a => total += a.length);
    this._data = new Uint8Array(total);
    let off = 0; flat.forEach(a => { this._data.set(a, off); off += a.length; });
  }
  get size() { return this._data.length; }
};
const { MockCanvas } = require('./mock_canvas.js');
const { GifEncoder } = require('../gif-encoder.js');
const { GifDecoder } = require('../gif-decoder.js');
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

function encodeToGif(fileName, fileBytes, fileId) {
  const framedData = C.withLengthPrefix(C.buildPayload(fileName, fileBytes));
  const frames = C.splitIntoFrames(framedData, fileId, false);
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const size = F.SPEC.grid.framePx;
  const gif = new GifEncoder(size, size, 20);
  for (const data of frames) {
    const cv = new MockCanvas(size, size);
    C.renderFrame(cv.getContext('2d'), C.encodeRSFrame(data, rs));
    gif.addFrame(cv);
  }
  return { gif: gif.finish()._data, frameCount: frames.length };
}

function decodeFromGif(gifBytes, order) {
  const frames = new GifDecoder(gifBytes).decode();
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const asm = new C.FrameAssembler();
  const idx = order || frames.map((_, i) => i);
  for (const i of idx) {
    const r = C.decodeFrameExact(frames[i].imageData);
    const d = C.decodeRSFrame(r.raw, rs);
    assertEq(d.blocksFailed, 0, `frame ${i} RS`);
    asm.add(d.data, d.blocksFailed);
  }
  assert(asm.isComplete(), 'assembled');
  return C.parsePayload(C.stripLengthPrefix(asm.framedData()));
}

console.log('\ntest_pipeline_node.js');

test('multi-frame file round trip', () => {
  const bytes = new Uint8Array(5000); for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 7 + 13) & 0xFF;
  const { gif, frameCount } = encodeToGif('data.bin', bytes, 0x2001);
  assertEq(frameCount, 3);
  const out = decodeFromGif(gif);
  assertEq(out.fileName, 'data.bin');
  assertEq(out.fileBytes.length, 5000);
  for (let i = 0; i < 5000; i++) if (out.fileBytes[i] !== bytes[i]) throw new Error(`byte ${i}`);
});

test('frames decoded out of order still assemble', () => {
  const bytes = new Uint8Array(5000); for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 3 + 1) & 0xFF;
  const { gif } = encodeToGif('data.bin', bytes, 0x2002);
  const out = decodeFromGif(gif, [2, 0, 1]);
  assertEq(out.fileBytes.length, 5000);
});

test('tiny file is a single frame', () => {
  const { gif, frameCount } = encodeToGif('a.txt', new Uint8Array([65]), 0x2003);
  assertEq(frameCount, 1);
  const out = decodeFromGif(gif);
  assertEq(out.fileName, 'a.txt');
  assertEq(out.fileBytes[0], 65);
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
