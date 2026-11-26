'use strict';
const fs = require('fs');
const path = require('path');
const F = require('../photo-fit.js');
const Fmt = require('../format.js');

let passed = 0, failed = 0;
const pending = [];
function test(name, fn) {
  pending.push((async () => {
    try { await fn(); passed++; console.log(`  PASS  ${name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); }
  })());
}
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}

const linear = (s, q) => Math.floor(s * s * q / 1000);
const steep = (s, q) => Math.floor(s * s * q * q * q / 100000);

class FakeSession {
  constructor(width, height, size) { this.width = width; this.height = height; this.size = size; this.calls = []; this.closed = false; }
  async encode(maxSide, quality) { this.calls.push({ maxSide, quality }); return new Uint8Array(this.size(maxSide, quality)); }
  close() { this.closed = true; }
}

console.log('\ntest_photo_fit.js');
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'test-data', 'photo-fit.json'), 'utf8'));

test('bytesPerFrame matches the format', () => eq(Fmt.fileBytesPerFrame(), fixture.bytesPerFrame, 'bytesPerFrame'));
for (const c of fixture.budget) {
  test(`fixture budget: ${c.frames} frames, name length ${c.name.length}`, () => eq(F.photoByteBudget(c.frames, c.name), c.budget, 'budget'));
}
for (const c of fixture.frames) {
  test(`fixture frames: ${c.dataBytes} B, encrypted ${c.encrypted}`, () => eq(F.framesForFile(c.name, c.dataBytes, c.encrypted), c.frames, 'frames'));
}
for (const c of fixture.fit) {
  test(`fixture fit: ${c.width}x${c.height} budget ${c.budget} (${c.model})`, async () => {
    const s = new FakeSession(c.width, c.height, c.model === 'steep' ? steep : linear);
    const r = await F.fitToBudget(s, c.budget);
    eq([r.maxSide, r.quality, r.fits], [c.maxSide, c.quality, c.fits], 'fit');
  });
}
for (const c of fixture.names) {
  test(`fixture name: "${c.original}"`, () => {
    // 'YYYY-MM-DDTHH:MM:SS' without a zone is local time, as in Dart's DateTime.parse.
    eq(F.optimisedFileName(c.original, new Date(c.now)), c.out, 'name');
  });
}

// ── ports of the NFC Archiver tests ──
test('candidateSides', () => {
  eq(F.candidateSides(4032), [4032, 3840, 2560, 1920, 1600, 1440, 1280, 1024, 800, 640, 480, 320], '4032');
  eq(F.candidateSides(640), [640, 480, 320], '640');
  eq(F.candidateSides(200), [200], '200');
  eq(F.candidateSides(1024).filter((s) => s === 1024).length, 1, 'no duplicate');
});
test('picks largest side reaching q50, then max quality', async () => {
  const budget = linear(1024, 50) + 100;
  const s = new FakeSession(3024, 4032, linear);
  const r = await F.fitToBudget(s, budget);
  eq(r.fits, true, 'fits'); eq(r.maxSide, 1024, 'side');
  let expected = 50;
  for (let q = 50; q <= 95; q++) if (linear(1024, q) <= budget) expected = q;
  eq(r.quality, expected, 'quality'); eq(r.bytes.length, linear(1024, expected), 'bytes');
  if (s.calls.length > F.candidateSides(4032).length + 7) throw new Error('too many encodes');
});
test('falls back to q30-49 when no side reaches q50', async () => {
  const budget = steep(480, 35) + 10;
  const r = await F.fitToBudget(new FakeSession(3000, 4000, steep), budget);
  eq(r.fits, true, 'fits'); eq(r.maxSide, 480, 'side');
  let expected = 30;
  for (let q = 30; q <= 49; q++) if (steep(480, q) <= budget) expected = q;
  eq(r.quality, expected, 'quality');
});
test('nothing fits', async () => {
  const r = await F.fitToBudget(new FakeSession(3000, 4000, linear), 10);
  eq([r.fits, r.maxSide, r.quality], [false, 320, 30], 'result');
});
test('budget <= 0 encodes at most once', async () => {
  for (const b of [0, -50]) {
    const s = new FakeSession(3000, 4000, linear);
    const r = await F.fitToBudget(s, b);
    eq(r.fits, false, 'fits');
    if (s.calls.length > 1) throw new Error('encoded more than once');
  }
});
test('small original is never upscaled', async () => {
  const s = new FakeSession(200, 100, () => 5000);
  const r = await F.fitToBudget(s, 10);
  eq(r.maxSide, 200, 'side');
  if (!s.calls.every((c) => c.maxSide === 200)) throw new Error('upscaled');
});
test('deterministic', async () => {
  const a = new FakeSession(3024, 4032, linear), b = new FakeSession(3024, 4032, linear);
  await F.fitToBudget(a, 200000); await F.fitToBudget(b, 200000);
  eq(a.calls, b.calls, 'call sequence');
});
test('encodeManual encodes once and judges fit', async () => {
  const s = new FakeSession(3000, 4000, linear);
  const r = await F.encodeManual(s, { maxSide: 800, quality: 70, budget: linear(800, 70) });
  eq(s.calls.length, 1, 'calls'); eq(r.fits, true, 'fits');
  const r2 = await F.encodeManual(s, { maxSide: 800, quality: 70, budget: linear(800, 70) - 1 });
  eq(r2.fits, false, 'fits tight');
});
test('constants and payload size', () => {
  eq(F.ENCRYPTION_OVERHEAD, 48, 'overhead'); eq(F.MAX_FRAMES, 4096, 'max frames');
  eq(Fmt.fileBytesPerFrame(), 2104, 'payload per frame');
});
test('budget plus container never exceeds the frames, and one more byte needs another', () => {
  for (const name of ['a.jpg', 'IMG_1234.jpg', 'ü'.repeat(200) + '.jpg']) {
    for (const frames of [1, 2, 5, 12]) {
      const b = F.photoByteBudget(frames, name);
      eq(F.framesForFile(name, b, true), frames, 'fits exactly');
      eq(F.framesForFile(name, b + 1, true), frames + 1, 'one more byte');
    }
  }
});
test('framedBytes', () => {
  eq(F.framedBytes(5, 100, false), 113, 'plain'); eq(F.framedBytes(5, 100, true), 161, 'encrypted');
});
test('optimisedFileName', () => {
  const now = new Date(2026, 10, 11, 9, 5, 3);
  eq(F.optimisedFileName('IMG_1234.HEIC', now), 'IMG_1234.jpg', 'heic');
  eq(F.optimisedFileName(undefined, now), 'photo-20261111-090503.jpg', 'undefined');
  eq(F.optimisedFileName('.hidden', now), '.hidden.jpg', 'leading dot');
});
test('isOptimisable', () => {
  const gif = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
  const heif = new Uint8Array([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);
  const sniff = (h) => h[4] === 0x66 && h[5] === 0x74;
  eq(F.isOptimisable('a.gif', 'image/gif'), false, 'gif');
  eq(F.isOptimisable('a.HEIC', ''), true, 'HEIC ext');
  eq(F.isOptimisable('x', 'application/octet-stream', heif, sniff), true, 'sniffed');
  eq(F.isOptimisable('x', 'application/octet-stream', heif), false, 'no sniff given');
  eq(F.isOptimisable('x.jpg', 'image/jpeg', gif), false, 'gif magic');
  eq(F.isOptimisable('a.svg', 'image/svg+xml'), false, 'svg');
  eq(F.isOptimisable('a.tif', 'image/tiff'), false, 'tiff');
  eq(F.isOptimisable('a.ico', 'image/vnd.microsoft.icon'), false, 'icon');
  eq(F.isOptimisable('a.bin', 'application/octet-stream'), false, 'other');
  eq(F.isOptimisable('p', 'image/avif'), true, 'other image type');
  eq(F.isOptimisable('p.JPG', ''), true, 'JPG ext');
});

Promise.all(pending).then(() => {
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
});
