'use strict';
/**
 * test_pipeline_node.js — End-to-end encode→GIF→decode round-trip test.
 *
 * Simulates the index.html encode/decode pipeline entirely in Node.js:
 *   1. Build a fake "encrypted" payload
 *   2. Prepend 4-byte length prefix (the fix for the AES-GCM padding bug)
 *   3. RS-encode into frames, draw to mock canvas, GIF-encode
 *   4. GIF-decode, RS-decode frames, extract payload via length prefix
 *   5. Assert decoded payload matches original
 *
 * Run: node tests/test_pipeline_node.js
 */

const { TextEncoder } = require('util');
global.TextEncoder = TextEncoder;

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

const nodeCrypto      = require('crypto');
const { MockCanvas }  = require('./mock_canvas.js');
const { GifEncoder }  = require('../gif-encoder.js');
const { GifDecoder }  = require('../gif-decoder.js');
const { ReedSolomon } = require('../rs.js');
const Cimbar          = require('../cimbar.js');

function concat(...arrays) {
  const len = arrays.reduce((s, a) => s + a.length, 0);
  const out = new Uint8Array(len);
  let off = 0;
  for (const a of arrays) { out.set(a, off); off += a.length; }
  return out;
}

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  PASS  ${name}`);
    passed++;
  } catch (e) {
    console.log(`  FAIL  ${name}: ${e.message}`);
    failed++;
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg || 'assertion failed');
}

// ── Tests ──────────────────────────────────────────────────────────────────

console.log('\ntest_pipeline_node.js');
console.log('─'.repeat(60));

const FRAME_SIZE = 256;
const rs  = new ReedSolomon(Cimbar.ECC_BYTES);
const dpf = Cimbar.dataBytesPerFrame(FRAME_SIZE);
const rpf = Cimbar.rawBytesPerFrame(FRAME_SIZE);

// ── Test 1: length prefix survives round-trip ──────────────────────────────
test('length prefix round-trip (small payload, non-dpf-aligned)', () => {
  // Simulate an "encrypted" payload that is NOT a multiple of dpf
  // 37345 bytes → dpf=752 → 49 full frames + 497 extra → last frame padded with 255 zeros
  const fakeEncLen = 37345;
  const fakeEnc = new Uint8Array(fakeEncLen);
  for (let i = 0; i < fakeEncLen; i++) fakeEnc[i] = (i * 7 + 13) & 0xFF; // deterministic pattern

  // Encoder side: prepend length prefix
  const lengthPrefix = new Uint8Array(4);
  new DataView(lengthPrefix.buffer).setUint32(0, fakeEnc.length, false);
  const framedData = concat(lengthPrefix, fakeEnc);

  const numFrames = Math.ceil(framedData.length / dpf);

  // Encode into GIF
  const canvas = new MockCanvas(FRAME_SIZE, FRAME_SIZE);
  const ctx    = canvas.getContext('2d');
  const gif    = new GifEncoder(FRAME_SIZE, FRAME_SIZE, 10);

  for (let f = 0; f < numFrames; f++) {
    const chunk   = framedData.slice(f * dpf, (f + 1) * dpf);
    const rsFrame = Cimbar.encodeRSFrame(chunk, FRAME_SIZE, rs);
    Cimbar.encodeFrame(canvas, ctx, rsFrame, 0, rpf);
    gif.addFrame(canvas);
  }

  const blob     = gif.finish();
  const gifBytes = blob._data;

  // Decode GIF
  const frames = new GifDecoder(gifBytes).decode();
  assert(frames.length === numFrames, `frame count: got ${frames.length}, want ${numFrames}`);

  const allData = [];
  for (const frame of frames) {
    const rawBytes  = Cimbar.decodeFramePixels(frame.imageData, FRAME_SIZE);
    const dataBytes = Cimbar.decodeRSFrame(rawBytes, FRAME_SIZE, rs);
    for (let i = 0; i < dataBytes.length; i++) allData.push(dataBytes[i]);
  }

  const allBytes = new Uint8Array(allData);

  // Decoder side: read length prefix
  const payloadLength = new DataView(allBytes.buffer, allBytes.byteOffset, 4).getUint32(0, false);
  assert(payloadLength === fakeEncLen,
    `payloadLength: got ${payloadLength}, want ${fakeEncLen}`);
  assert(payloadLength >= 32 && payloadLength <= allBytes.length - 4,
    `payloadLength ${payloadLength} out of bounds`);

  const recovered = allBytes.slice(4, 4 + payloadLength);
  assert(recovered.length === fakeEncLen,
    `recovered.length: got ${recovered.length}, want ${fakeEncLen}`);

  // Byte-by-byte check
  let mismatches = 0;
  for (let i = 0; i < fakeEncLen; i++) {
    if (recovered[i] !== fakeEnc[i]) mismatches++;
  }
  assert(mismatches === 0, `${mismatches} byte mismatches in recovered payload`);
});

// ── Test 2: exact dpf alignment still works ───────────────────────────────
test('length prefix round-trip (exact dpf-aligned payload)', () => {
  // Payload exactly fills 3 frames → no zero padding
  const fakeEncLen = 3 * dpf - 4; // framedData = 3 * dpf exactly
  const fakeEnc = new Uint8Array(fakeEncLen);
  for (let i = 0; i < fakeEncLen; i++) fakeEnc[i] = (i * 3 + 77) & 0xFF;

  const lengthPrefix = new Uint8Array(4);
  new DataView(lengthPrefix.buffer).setUint32(0, fakeEnc.length, false);
  const framedData = concat(lengthPrefix, fakeEnc);
  assert(framedData.length === 3 * dpf, `framedData.length not aligned: ${framedData.length}`);

  const numFrames = Math.ceil(framedData.length / dpf); // = 3
  const canvas = new MockCanvas(FRAME_SIZE, FRAME_SIZE);
  const ctx    = canvas.getContext('2d');
  const gif    = new GifEncoder(FRAME_SIZE, FRAME_SIZE, 10);

  for (let f = 0; f < numFrames; f++) {
    const chunk   = framedData.slice(f * dpf, (f + 1) * dpf);
    const rsFrame = Cimbar.encodeRSFrame(chunk, FRAME_SIZE, rs);
    Cimbar.encodeFrame(canvas, ctx, rsFrame, 0, rpf);
    gif.addFrame(canvas);
  }

  const frames = new GifDecoder(gif.finish()._data).decode();
  const allData = [];
  for (const frame of frames) {
    const rawBytes  = Cimbar.decodeFramePixels(frame.imageData, FRAME_SIZE);
    const dataBytes = Cimbar.decodeRSFrame(rawBytes, FRAME_SIZE, rs);
    for (let i = 0; i < dataBytes.length; i++) allData.push(dataBytes[i]);
  }

  const allBytes = new Uint8Array(allData);
  const payloadLength = new DataView(allBytes.buffer, allBytes.byteOffset, 4).getUint32(0, false);
  assert(payloadLength === fakeEncLen, `payloadLength: got ${payloadLength}, want ${fakeEncLen}`);

  const recovered = allBytes.slice(4, 4 + payloadLength);
  let mismatches = 0;
  for (let i = 0; i < fakeEncLen; i++) {
    if (recovered[i] !== fakeEnc[i]) mismatches++;
  }
  assert(mismatches === 0, `${mismatches} byte mismatches`);
});

// ── Test 3: single-frame tiny payload ─────────────────────────────────────
test('length prefix round-trip (tiny payload, single frame)', () => {
  const fakeEncLen = 100; // well under dpf=752
  const fakeEnc = new Uint8Array(fakeEncLen);
  nodeCrypto.randomFillSync(fakeEnc);

  const lengthPrefix = new Uint8Array(4);
  new DataView(lengthPrefix.buffer).setUint32(0, fakeEnc.length, false);
  const framedData = concat(lengthPrefix, fakeEnc);

  const numFrames = 1;
  const canvas = new MockCanvas(FRAME_SIZE, FRAME_SIZE);
  const ctx    = canvas.getContext('2d');
  const gif    = new GifEncoder(FRAME_SIZE, FRAME_SIZE, 10);

  const chunk   = framedData.slice(0, dpf);
  const rsFrame = Cimbar.encodeRSFrame(chunk, FRAME_SIZE, rs);
  Cimbar.encodeFrame(canvas, ctx, rsFrame, 0, rpf);
  gif.addFrame(canvas);

  const frames = new GifDecoder(gif.finish()._data).decode();
  const allData = [];
  for (const frame of frames) {
    const rawBytes  = Cimbar.decodeFramePixels(frame.imageData, FRAME_SIZE);
    const dataBytes = Cimbar.decodeRSFrame(rawBytes, FRAME_SIZE, rs);
    for (let i = 0; i < dataBytes.length; i++) allData.push(dataBytes[i]);
  }

  const allBytes = new Uint8Array(allData);
  const payloadLength = new DataView(allBytes.buffer, allBytes.byteOffset, 4).getUint32(0, false);
  assert(payloadLength === fakeEncLen, `payloadLength: got ${payloadLength}, want ${fakeEncLen}`);

  const recovered = allBytes.slice(4, 4 + payloadLength);
  let mismatches = 0;
  for (let i = 0; i < fakeEncLen; i++) {
    if (recovered[i] !== fakeEnc[i]) mismatches++;
  }
  assert(mismatches === 0, `${mismatches} byte mismatches`);
});

// ── Summary ────────────────────────────────────────────────────────────────
console.log('─'.repeat(60));
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
