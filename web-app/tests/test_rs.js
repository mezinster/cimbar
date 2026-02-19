'use strict';
/**
 * test_rs.js — Reed-Solomon encode/decode tests.
 *
 * Run: node tests/test_rs.js
 */

const { ReedSolomon } = require('../rs.js');

const rs = new ReedSolomon(32); // ECC_BYTES = 32, correction capacity = 16

let passed = 0, failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  PASS: ${name}`);
    passed++;
  } catch (e) {
    console.error(`  FAIL: ${name} — ${e.message}`);
    failed++;
  }
}

function assertArrayEqual(a, b, msg) {
  if (a.length !== b.length)
    throw new Error(`${msg}: length ${a.length} != ${b.length}`);
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i])
      throw new Error(`${msg}: mismatch at index ${i}: 0x${a[i].toString(16)} != 0x${b[i].toString(16)}`);
  }
}

// Deterministic pseudo-random byte sequence
function seqData(n, seed) {
  const d = new Uint8Array(n);
  let s = seed;
  for (let i = 0; i < n; i++) { s = (s * 1664525 + 1013904223) >>> 0; d[i] = s & 0xFF; }
  return d;
}

// ── Test 1: encode + decode with no errors ────────────────────────────────────
test('encode/decode, no errors', () => {
  const data    = seqData(100, 42);
  const encoded = rs.encode(data);
  if (encoded.length !== 132)
    throw new Error(`encoded length ${encoded.length} != 132`);
  const decoded = rs.decode(encoded);
  assertArrayEqual(decoded, data, 'no-error round-trip');
});

// ── Test 2: correct exactly 16 errors ─────────────────────────────────────────
test('correct 16 random errors', () => {
  const data     = seqData(100, 99);
  const encoded  = rs.encode(data);
  const received = new Uint8Array(encoded);

  // Inject 16 errors at fixed, spread-out positions
  for (let k = 0; k < 16; k++) {
    received[k * 8] ^= 0xA5;
  }

  const decoded = rs.decode(received);
  assertArrayEqual(decoded, data, '16-error correction');
});

// ── Test 3: 17+ errors → must be uncorrectable (throws OR wrong decode) ───────
// RS(255,223) guarantees ≤16 errors correctable; 17 errors exceeds the bound.
test('17+ errors detected as uncorrectable', () => {
  const data     = seqData(100, 7);
  const encoded  = rs.encode(data);
  const received = new Uint8Array(encoded);

  // Inject 20 errors to reliably exceed correction capacity
  for (let k = 0; k < 20; k++) {
    received[k * 6] ^= 0xFF;
  }

  let threw = false;
  let wrongDecode = false;
  try {
    const decoded = rs.decode(received);
    // Decoder returned something — check it's NOT the original data
    wrongDecode = !decoded.every((v, i) => v === data[i]);
  } catch {
    threw = true;
  }

  if (!threw && !wrongDecode) {
    throw new Error('20 injected errors were silently "corrected" to the original data — impossible for this RS configuration');
  }
});

// ── Test 4: Omega (error evaluator) correctness via multi-error correction ─────
// This test specifically exercises the Forney algorithm; if the Omega
// polynomial slice was wrong (.slice(0,t) instead of .slice(-t)), the
// error magnitudes would be garbage and the assertion below would fail.
test('Forney / Omega correctness with 8 errors at known positions', () => {
  const data     = seqData(50, 13);
  const encoded  = rs.encode(data);
  const received = new Uint8Array(encoded);

  // Inject 8 errors at specific byte positions with known magnitudes
  const errorPositions = [0, 7, 14, 21, 28, 35, 42, 49];
  for (const pos of errorPositions) received[pos] ^= 0xC3;

  const decoded = rs.decode(received);
  assertArrayEqual(decoded, data, 'Omega-based Forney correction');
});

console.log(`\nRS tests: ${passed} pass, ${failed} fail`);
process.exit(failed === 0 ? 0 : 1);
