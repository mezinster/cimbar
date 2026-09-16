'use strict';
const fs = require('fs');
const path = require('path');
const R = require('../tools/tile_rules.js');
const gen = require('../tools/gen_format_data.js');
const SPEC = require('../../spec/cimbar-v2.json');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }

console.log('\ntest_format.js');

test('grid constants are self-consistent', () => {
  const g = SPEC.grid;
  assertEq(g.pitchPx, g.cellPx + g.gapPx);
  assertEq(g.gridPx, g.gridCells * g.pitchPx);
  assertEq(g.framePx, g.gridPx + 2 * g.quietPx);
  assertEq(SPEC.gif.framePx, g.framePx);
});

test('finder constants are self-consistent', () => {
  const f = SPEC.finder, g = SPEC.grid;
  assertEq(f.outerPx, f.cells * g.pitchPx);
  assertEq(f.ringInsetPx, g.pitchPx);
  assertEq(f.coreInsetPx, 2 * g.pitchPx);
  assertEq(f.corePx, 3 * g.pitchPx);
  assertEq(f.dotPx, g.pitchPx);
  assertEq(f.dotInsetPx, 3 * g.pitchPx);
  assertEq(f.cornerCells, f.cells + 1);
  const n = g.gridCells;
  assertEq(f.centers.tl.join(','), '3.5,3.5');
  assertEq(f.centers.tr.join(','), `${n - 3.5},3.5`);
  assertEq(f.centers.bl.join(','), `3.5,${n - 3.5}`);
  assertEq(f.centers.br.join(','), `${n - 3.5},${n - 3.5}`);
  assertEq(f.dotOn.join(','), 'tr,bl,br');
});

test('palette has 4 bright colors', () => {
  assertEq(SPEC.palette.length, 4);
  for (const [r, g, b] of SPEC.palette) {
    const luma = 0.299 * r + 0.587 * g + 0.114 * b;
    assert(luma > 100, `luma ${luma} too dark`);
  }
});

test('tile set satisfies tile rules', () => {
  assertEq(SPEC.tiles.length, 16);
  const tiles = SPEC.tiles.map(R.hexToTile);
  const errs = R.checkSet(tiles);
  assertEq(errs.length, 0, errs.join('; '));
});

test('capacity numbers match derivation', () => {
  const n = SPEC.grid.gridCells, c = SPEC.finder.cornerCells;
  const usable = n * n - 4 * c * c;
  assertEq(SPEC.capacity.usableCells, usable);
  const bits = SPEC.bits.symbolBits + SPEC.bits.colorBits;
  assertEq(SPEC.capacity.rawBytesPerFrame, Math.floor(usable * bits / 8));
  let raw = SPEC.capacity.rawBytesPerFrame, data = 0;
  while (raw > SPEC.rs.eccBytes) { const bt = Math.min(SPEC.rs.blockTotal, raw); data += bt - SPEC.rs.eccBytes; raw -= bt; }
  assertEq(SPEC.capacity.dataBytesPerFrame, data);
  assertEq(SPEC.capacity.fileBytesPerFrame, data - SPEC.header.lengthBytes);
});

test('format-data.js is up to date with the spec', () => {
  const expected = gen.render(fs.readFileSync(gen.specPath, 'utf8'));
  const actual = fs.readFileSync(gen.outPath, 'utf8');
  assertEq(actual, expected, 'run: node tools/gen_format_data.js');
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
