'use strict';
const F = require('../format.js');
const R = require('../rateless.js');
const C = require('../cimbar.js');
let passed = 0, failed = 0; const tests = [];
function test(n, f) { tests.push({ n, f }); }
function assert(c, m) { if (!c) throw new Error(m); }
function assertEq(a, b, m) { if (a !== b) throw new Error(`${m}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
function hex(b) { let s = ''; for (const x of b) s += x.toString(16).padStart(2, '0'); return s; }
function seqBytes(n, seed) { const b = new Uint8Array(n); let s = seed >>> 0; for (let i = 0; i < n; i++) { s = (s * 1664525 + 1013904223) >>> 0; b[i] = s >>> 24; } return b; }
const PER = F.fileBytesPerFrame();

function sources(n, seed) { return Array.from({ length: n }, (_, i) => seqBytes(PER, seed + i)); }
function frameSet(n, seed, fileId, repairCount, opts = {}) {
  const framed = new Uint8Array(n * PER); const bodies = sources(n, seed);
  bodies.forEach((b, i) => framed.set(b, i * PER));
  const src = C.splitIntoFrames(framed, fileId, opts);
  const rep = Array.from({ length: repairCount }, (_, r) => C.repairFrame(bodies, fileId, r, opts));
  return { bodies, src, rep };
}
function mulberry(seed) { return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function shuffled(arr, seed) { const a = arr.slice(); const rnd = mulberry(seed); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }

test('combineBodies is XOR for unit and 1-coefficients, matches GF math', () => {
  const b = [seqBytes(8, 1), seqBytes(8, 2)];
  const e0 = R.combineBodies(b, new Uint8Array([1, 0]));
  assertEq(hex(e0), hex(b[0]), 'unit row');
  const x = R.combineBodies(b, new Uint8Array([1, 1]));
  for (let i = 0; i < 8; i++) assertEq(x[i], b[0][i] ^ b[1][i], `xor ${i}`);
  const { ReedSolomon } = require('../rs.js');
  const y = R.combineBodies(b, new Uint8Array([3, 7]));
  for (let i = 0; i < 8; i++) assertEq(y[i], ReedSolomon.gfMul(3, b[0][i]) ^ ReedSolomon.gfMul(7, b[1][i]), `gf ${i}`);
});

test('repairFrame header carries repair flag, r and total; body is the combination', () => {
  const { bodies, rep } = frameSet(3, 10, 0x1234, 2, { compressed: true });
  const h = F.decodeHeader(rep[1]);
  assert(h.valid && h.repair && h.compressed && !h.encrypted, 'flags');
  assertEq(h.seq, 1, 'r'); assertEq(h.total, 3, 'total');
  const expect = R.combineBodies(bodies, F.codingCoefficients(0x1234, 1, 3));
  assertEq(hex(rep[1].subarray(F.HEADER_LEN)), hex(expect), 'body');
  assertEq(C.gifRepairCount(1), 0); assertEq(C.gifRepairCount(2), 1); assertEq(C.gifRepairCount(345), 87);
});

for (const n of [1, 2, 7, 64, 345]) {
  test(`N=${n}: any N independent rows decode (source-only, repair-only, mixed, shuffled)`, () => {
    const { bodies, src, rep } = frameSet(n, 100 + n, 0x2000 + n, n === 1 ? 0 : 2 * n);
    const check = (rows, label) => {
      const a = new R.RatelessAssembler();
      for (const d of rows) { const r = a.add(d, 0); assert(r.accepted || r.reason === 'dependent', `${label}: ${r.reason}`); }
      assert(a.isComplete(), `${label}: rank ${a.rank}/${a.total}`);
      const out = a.framedData();
      for (let i = 0; i < n; i++) assertEq(hex(out.subarray(i * PER, (i + 1) * PER)), hex(bodies[i]), `${label} body ${i}`);
    };
    check(src, 'source only');
    if (n > 1) {
      check(rep.slice(0, n + 2), 'repair only');
      const mixed = shuffled(src.slice(0, Math.floor(n / 2)).concat(rep.slice(0, n - Math.floor(n / 2) + 2)), n);
      check(mixed, 'mixed shuffled');
    }
  });
}

// Guard against a future linear generator (e.g. a plain xorshift/LFSR):
// exactly N consecutive repair ids r = 0..N-1 must already be full rank, with
// no slack repair rows to fall back on.
for (const n of [7, 64, 345]) {
  test(`N=${n}: exactly N repair rows r=0..N-1 (no slack) reach full rank`, () => {
    const { bodies, fileId } = (() => {
      const seed = 200 + n, fid = 0x5000 + n;
      const bodies = sources(n, seed);
      return { bodies, fileId: fid };
    })();
    const rep = Array.from({ length: n }, (_, r) => C.repairFrame(bodies, fileId, r, {}));
    const a = new R.RatelessAssembler();
    for (const d of rep) { const r = a.add(d, 0); assert(r.accepted, `N=${n}: r=${r.header && r.header.seq} rejected: ${r.reason}`); }
    assert(a.isComplete(), `N=${n}: rank ${a.rank}/${a.total} from exactly N repair rows`);
    const out = a.framedData();
    for (let i = 0; i < n; i++) assertEq(hex(out.subarray(i * PER, (i + 1) * PER)), hex(bodies[i]), `body ${i}`);
  });
}

test('duplicates and dependent rows leave rank unchanged; counters and flags mismatch', () => {
  const { src, rep } = frameSet(4, 7, 0x3000, 4, { compressed: true });
  const a = new R.RatelessAssembler();
  assert(a.add(src[0]).accepted); assertEq(a.rank, 1);
  assertEq(a.add(src[0]).reason, 'duplicate'); assertEq(a.rank, 1);
  assert(a.add(rep[0]).accepted); assertEq(a.rank, 2);
  assertEq(a.add(rep[0]).reason, 'duplicate');
  // test dependence by re-adding src rows that are already pivots via a second, full-rank assembler:
  const b = new R.RatelessAssembler();
  for (const d of src) assert(b.add(d).accepted);
  assertEq(b.rank, 4); assert(b.isComplete());
  const r = b.add(rep[3]); assertEq(r.reason, 'dependent', 'full-rank assembler treats any new row as dependent'); assertEq(b.rank, 4);
  assertEq(b.counts.source, 4); assertEq(b.counts.repair, 0, 'the dependent repair row must not be counted'); assertEq(b.counts.dependent, 1);
  // flags mismatch: a frame claiming uncompressed for the same file is rejected
  const mismatch = new Uint8Array(src[1]); mismatch.set(F.encodeHeader({ fileId: 0x3000, seq: 1, total: 4 }), 0);
  assertEq(a.add(mismatch).reason, 'flags', 'bit 2 must match the first accepted frame');
  assertEq(a.add(src[1], 1).reason, 'rs');
});

test('systematic fast path: in-order source frames never need arithmetic', () => {
  const { src } = frameSet(50, 3, 0x4000, 0);
  const a = new R.RatelessAssembler();
  for (const d of src) assert(a.add(d).accepted);
  assert(a.isComplete()); assertEq(a.counts.repair, 0);
});

test('memory bound: an all-source, in-order file never materialises a dense coefficient array', () => {
  const n = 200;
  const { src, bodies } = frameSet(n, 11, 0x6000, 0);
  const a = new R.RatelessAssembler();
  for (const d of src) assert(a.add(d).accepted);
  assert(a.isComplete());
  assertEq(a.denseRows(), 0, 'an all-source, in-order file must never materialise a dense coefficient array');
  const out = a.framedData();
  for (let i = 0; i < n; i++) assertEq(hex(out.subarray(i * PER, (i + 1) * PER)), hex(bodies[i]), `body ${i}`);

  const b = new R.RatelessAssembler();
  assert(b.add(C.repairFrame(bodies, 0x6000, 0, {})).accepted);
  assertEq(b.denseRows(), 1, 'a repair row is always materialised (it needs real coefficients)');
});

test('memory bound: total beyond maxFrames accepts source frames only (uncoded mode)', () => {
  const maxFrames = F.SPEC.coding.maxFrames;
  const n = maxFrames + 1;
  const fileId = 0x7000;

  const srcFrame = new Uint8Array(F.dataBytesPerFrame());
  srcFrame.set(F.encodeHeader({ fileId, seq: 0, total: n }), 0);
  srcFrame.set(seqBytes(PER, 42), F.HEADER_LEN);

  const repFrame = new Uint8Array(F.dataBytesPerFrame());
  repFrame.set(F.encodeHeader({ repair: true, fileId, seq: 0, total: n }), 0);
  repFrame.set(seqBytes(PER, 43), F.HEADER_LEN);

  const a = new R.RatelessAssembler();
  const rSrc = a.add(srcFrame);
  assert(rSrc.accepted, 'source frame accepted even when total exceeds maxFrames');
  assertEq(a.total, n);
  const rRep = a.add(repFrame);
  assertEq(rRep.reason, 'uncoded', 'repair frame rejected when total exceeds maxFrames');
  assertEq(a.denseRows(), 0, 'uncoded-mode acceptance never materialises a dense array');
});

test('a short frame buffer is rejected before header decode', () => {
  const { src } = frameSet(3, 77, 0x7100, 0);
  const a = new R.RatelessAssembler();
  const truncated = src[0].slice(0, F.dataBytesPerFrame() - 1);
  const r = a.add(truncated);
  assertEq(r.accepted, false, 'rejected');
  assertEq(r.reason, 'short', 'reason');
  assertEq(r.header, null, 'header not decoded');
  assertEq(a.total, 0, 'assembler state untouched');
  assert(a.add(src[0]).accepted, 'a full frame is still accepted afterwards');
});

test('repairFrame stays under 50 ms for a 345-frame file', () => {
  const n = 345, fileId = 0x7200;
  const bodies = sources(n, 991);
  const times = [];
  for (let i = 0; i < 5; i++) {
    const t0 = process.hrtime.bigint();
    const f = C.repairFrame(bodies, fileId, i, {});
    const t1 = process.hrtime.bigint();
    assertEq(f.length, F.dataBytesPerFrame(), 'repair frame size');
    times.push(Number(t1 - t0) / 1e6);
  }
  times.sort((a, b) => a - b);
  const median = times[2];
  console.log(`        repairFrame N=${n}: median ${median.toFixed(1)} ms over 5 runs (${times.map(x => x.toFixed(1)).join(', ')})`);
  assert(median < 50, `median ${median.toFixed(1)} ms exceeds the 50 ms budget`);
});

(async () => {
  console.log('\ntest_rateless.js');
  for (const t of tests) { try { await t.f(); passed++; console.log(`  PASS  ${t.n}`); } catch (e) { failed++; console.log(`  FAIL  ${t.n}: ${e.message}`); } }
  console.log(`Results: ${passed} passed, ${failed} failed`); process.exit(failed ? 1 : 0);
})();
