'use strict';
const Fmt = require('../format.js');
const Cimbar = require('../cimbar.js');
const { MockCanvas } = require('./mock_canvas.js');
const { RgbBuffer } = require('../rgb-buffer.js');
const { LumaPlane } = require('../luma-plane.js');
const { ExactGridModel } = require('../homography.js');
const { CellSampler, newPatch } = require('../cell-sampler.js');
const { CellClassifier } = require('../cell-classifier.js');
const { DriftSolver } = require('../drift-solver.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }

console.log('\ntest_drift.js');

function frameBuffer() {
  const n = Fmt.usableCellPositions().length;
  const cells = new Uint8Array(n);
  for (let i = 0; i < n; i++) cells[i] = (i * 7) % 64;
  const canvas = new MockCanvas(Fmt.SPEC.gif.framePx, Fmt.SPEC.gif.framePx);
  Cimbar.renderFrame(canvas.getContext('2d'), Fmt.unpackCells(cells));
  const d = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
  return { rgb: RgbBuffer.fromImageData(d), cells };
}

// A grid model deliberately offset from the truth by a known number of pixels.
class OffsetGrid {
  constructor(ox, oy) { this.ox = ox; this.oy = oy; this.base = new ExactGridModel(); }
  toSource(cx, cy) { const [x, y] = this.base.toSource(cx, cy); return [x + this.ox, y + this.oy]; }
}

function solveOn(grid, rgb) {
  const luma = LumaPlane.fromRgb(rgb);
  const sampler = new CellSampler(rgb, grid, luma);
  return new DriftSolver(sampler, new CellClassifier()).solve();
}

test('an exact grid produces zero drift', () => {
  const { rgb } = frameBuffer();
  const f = solveOn(new ExactGridModel(), rgb);
  assertEq(f.maxAbs, 0, 'maxAbs on a perfectly aligned frame');
  assertEq(f.widened, 0, 'no cell should need the widened ring');
});

test('a grid offset by (2,-1) px is corrected back', () => {
  const { rgb } = frameBuffer();
  const f = solveOn(new OffsetGrid(2, -1), rgb);
  let matched = 0;
  for (let i = 0; i < 4096; i++) if (f.dx[i] === -2 && f.dy[i] === 1) matched++;
  assert(matched > 3000, `only ${matched} of 3840 cells recovered the offset`);
});

test('drift stays inside the clamp', () => {
  const { rgb } = frameBuffer();
  const f = solveOn(new OffsetGrid(3, 3), rgb);
  for (let i = 0; i < 4096; i++) {
    assert(Math.abs(f.dx[i]) <= 6 && Math.abs(f.dy[i]) <= 6, `cell ${i} drift outside ±6`);
  }
});

test('drift correction lowers mean hamming on an offset grid', () => {
  const { rgb } = frameBuffer();
  const grid = new OffsetGrid(2, -1);
  const luma = LumaPlane.fromRgb(rgb);
  const sampler = new CellSampler(rgb, grid, luma);
  const classifier = new CellClassifier();
  const patch = newPatch();
  const pos = Fmt.usableCellPositions();

  let before = 0;
  for (const [c, r] of pos) { sampler.sample(c, r, patch); before += classifier.classify(patch, null).hamming; }

  const f = new DriftSolver(sampler, classifier).solve();
  let after = 0;
  for (const [c, r] of pos) {
    sampler.sample(c, r, patch, f.dx[r * 64 + c], f.dy[r * 64 + c]);
    after += classifier.classify(patch, null).hamming;
  }
  assert(after < before / 2, `mean hamming ${after / pos.length} not much better than ${before / pos.length}`);
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
