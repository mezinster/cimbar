'use strict';
const R = require('../tools/tile_rules.js');
const { generate } = require('../tools/gen_tiles.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }

console.log('\ntest_tiles.js');

test('hex <-> tile round trip, MSB is top-left', () => {
  const t = R.hexToTile('8000000000000001');
  assertEq(t[0], 1, 'top-left');
  assertEq(t[63], 1, 'bottom-right');
  assertEq(R.popcount(t), 2);
  assertEq(R.tileToHex(t), '8000000000000001');
});

test('hamming and shift', () => {
  const a = R.hexToTile('ff00000000000000'); // top row lit
  const b = R.hexToTile('00ff000000000000'); // second row lit
  assertEq(R.hamming(a, b), 16);
  assertEq(R.hamming(R.shift(a, 0, 1), b), 0, 'shift down by 1 equals row 2');
  assertEq(R.popcount(R.shift(a, 0, -1)), 0, 'shift up drops the row');
});

test('rot90 and mirror', () => {
  const a = R.hexToTile('ff00000000000000'); // top row
  const r = R.rot90(a);                        // right column
  assertEq(R.tileToHex(r), '0101010101010101');
  const m = R.mirror(R.hexToTile('8080808080808080')); // left column -> right column
  assertEq(R.tileToHex(m), '0101010101010101');
});

test('checkTile enforces fill 26..38', () => {
  assert(!R.checkTile(R.hexToTile('0000000000000000')), 'empty rejected');
  assert(!R.checkTile(R.hexToTile('ffffffffffffffff')), 'full rejected');
  assert(R.checkTile(R.hexToTile('ffffffff00000000')), '32 lit accepted');
});

test('checkPair rejects close, shifted-close and rotated tiles', () => {
  const a = R.hexToTile('ffffffff00000000');          // top half
  const b = R.hexToTile('ffffffff00000001');          // 1 bit away
  assert(!R.checkPair(a, b), 'hamming 1 rejected');
  const c = R.rot90(a);                                // rotation of a
  assert(!R.checkPair(a, c), 'rotation rejected');
  const d = R.hexToTile('00000000ffffffff');          // bottom half: hamming 64 but shift-by-1 differs by 48 -> ok
  assert(R.checkPair(a, d), 'far pair accepted');
});

test('checkSet returns [] for a valid pair and names violations', () => {
  const a = R.hexToTile('ffffffff00000000');
  const d = R.hexToTile('00000000ffffffff');
  assertEq(R.checkSet([a, d]).length, 0);
  const errs = R.checkSet([a, R.hexToTile('ffffffff00000001')]);
  assert(errs.length === 1 && /tiles 0,1/.test(errs[0]), 'violation named');
});

test('generate(seed) returns 16 tiles passing checkSet, deterministic', () => {
  const t1 = generate(1);
  assert(t1 && t1.length === 16, 'found 16 tiles');
  assertEq(R.checkSet(t1).length, 0, 'set valid');
  const t2 = generate(1);
  assertEq(t1.map(R.tileToHex).join(','), t2.map(R.tileToHex).join(','), 'deterministic');
});

test('generated tiles are made of uniform 2x2 blocks', () => {
  for (const t of generate(1)) {
    for (let by = 0; by < 4; by++) for (let bx = 0; bx < 4; bx++) {
      const v = t[(by * 2) * 8 + bx * 2];
      assertEq(t[(by * 2) * 8 + bx * 2 + 1], v, 'block uniform');
      assertEq(t[(by * 2 + 1) * 8 + bx * 2], v, 'block uniform');
      assertEq(t[(by * 2 + 1) * 8 + bx * 2 + 1], v, 'block uniform');
    }
  }
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
