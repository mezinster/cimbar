'use strict';
const Z = require('../compress.js');
let passed = 0, failed = 0; const tests = [];
function test(n, f) { tests.push({ n, f }); }
function assert(c, m) { if (!c) throw new Error(m); }
function assertEq(a, b, m) { if (a !== b) throw new Error(`${m}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }

test('text deflates well and round-trips', async () => {
  const text = new TextEncoder().encode('lorem ipsum dolor sit amet, '.repeat(500));
  const r = await Z.maybeDeflate(text);
  assert(r.compressed, 'should compress');
  assert(r.bytes.length < text.length * 0.2, `ratio ${r.bytes.length / text.length}`);
  assertEq(r.bytes[0], 0x78, 'zlib header byte');
  const back = await Z.inflateBytes(r.bytes);
  assertEq(back.length, text.length, 'length');
  for (let i = 0; i < text.length; i++) if (back[i] !== text[i]) throw new Error(`byte ${i}`);
});

test('random bytes are left alone (below the 5 % saving)', async () => {
  const rnd = new Uint8Array(4096); let s = 1; for (let i = 0; i < rnd.length; i++) { s = (s * 1103515245 + 12345) >>> 0; rnd[i] = s >>> 24; }
  const r = await Z.maybeDeflate(rnd);
  assertEq(r.compressed, false, 'not compressed');
  assert(r.bytes === rnd, 'same buffer returned');
  const empty = await Z.maybeDeflate(new Uint8Array(0));
  assertEq(empty.compressed, false, 'empty stays raw');
});

test('inflate rejects garbage', async () => {
  let threw = false;
  try { await Z.inflateBytes(new Uint8Array([1, 2, 3, 4])); } catch (e) { threw = true; }
  assert(threw, 'must throw');
});

test('a browser without CompressionStream still encodes (payload left raw)', async () => {
  const text = new TextEncoder().encode('lorem ipsum dolor sit amet, '.repeat(500));
  const saved = Z._impl.hasCompression;
  Z._impl.hasCompression = () => false;
  try {
    const r = await Z.maybeDeflate(text);
    assertEq(r.compressed, false, 'not compressed without CompressionStream');
    assert(r.bytes === text, 'same buffer returned');
  } finally { Z._impl.hasCompression = saved; }
});

test('a browser without DecompressionStream reports an unsupported error', async () => {
  const deflated = await Z.deflateBytes(new TextEncoder().encode('x'.repeat(4096)));
  const saved = Z._impl.hasDecompression;
  Z._impl.hasDecompression = () => false;
  let err = null;
  try { await Z.inflateBytes(deflated); } catch (e) { err = e; } finally { Z._impl.hasDecompression = saved; }
  assert(err !== null, 'must throw');
  assertEq(err.unsupported, true, 'marked unsupported');
  assert(!err.tooLarge, 'not a size error');
});

test('inflate refuses output past the cap (zip-bomb guard)', async () => {
  const zeros = new Uint8Array(2 * 1024 * 1024);
  const deflated = await Z.deflateBytes(zeros);
  assert(deflated.length < 16 * 1024, `expected a tiny stream, got ${deflated.length}`);
  let err = null;
  try { await Z.inflateBytes(deflated, 64 * 1024); } catch (e) { err = e; }
  assert(err !== null, 'must throw past the cap');
  assertEq(err.tooLarge, true, 'marked tooLarge');
  const back = await Z.inflateBytes(deflated, 4 * 1024 * 1024);
  assertEq(back.length, zeros.length, 'inflates fine under the cap');
  assertEq(Z.MAX_INFLATED, 134217728, 'default cap is the spec 128 MB');
});

(async () => {
  console.log('\ntest_compress.js');
  for (const t of tests) { try { await t.f(); passed++; console.log(`  PASS  ${t.n}`); } catch (e) { failed++; console.log(`  FAIL  ${t.n}: ${e.message}`); } }
  console.log(`Results: ${passed} passed, ${failed} failed`); process.exit(failed ? 1 : 0);
})();
