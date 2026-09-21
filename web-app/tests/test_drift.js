'use strict';
const fs = require('fs');
const path = require('path');
const Fmt = require('../format.js');
const Cimbar = require('../cimbar.js');
const { MockCanvas } = require('./mock_canvas.js');
const { RgbBuffer } = require('../rgb-buffer.js');
const { LumaPlane } = require('../luma-plane.js');
const { ExactGridModel } = require('../homography.js');
const { CellSampler, newPatch } = require('../cell-sampler.js');
const { CellClassifier } = require('../cell-classifier.js');
const { DriftSolver } = require('../drift-solver.js');
global.ImageData = global.ImageData || class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
const { GifDecoder } = require('../gif-decoder.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function assertNear(a, b, tol, msg) { if (Math.abs(a - b) > tol) throw new Error(`${msg || 'assertNear'}: expected ${b} +/- ${tol}, got ${a}`); }

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

// The exact frame app/test/core/decode/drift_solver_test.dart uses
// (loadGoldenFrame('lorem_12k', 1)): needed only for the Dart-parity
// assertions below, which check specific numeric values rather than a
// property, so they need the same pixel content Dart checks them against.
function goldenFrame() {
  const dir = path.join(__dirname, '..', '..', 'test-data', 'goldens');
  const gif = new Uint8Array(fs.readFileSync(path.join(dir, 'lorem_12k.gif')));
  const frames = new GifDecoder(gif).decode();
  return RgbBuffer.fromImageData(frames[1].imageData);
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

  // Mirrors app/test/core/decode/drift_solver_test.dart:42-45 — keep these
  // three assertions in lockstep with that file if either changes.
  //
  // Checked against the SAME frame Dart's test uses (loadGoldenFrame
  // ('lorem_12k', 1)), not the synthetic frameBuffer() above: the hill-climb's
  // discrete tie-breaking is pixel-content-dependent, and on frameBuffer()'s
  // content the center cell lands at dx=-2.011 (just outside +-0.01) even in
  // Dart itself — verified by running app/lib/core/decode/drift_solver.dart
  // against frameBuffer()'s exact bytes via a throwaway probe script, which
  // reproduced -2.01100754737854 / 0.9929145574569702 / 1.5521714523654533,
  // bit-for-bit matching this module's output on the same input. So a miss
  // there reflects fixture content, not a port divergence; checking here
  // against Dart's own fixture is the fair apples-to-apples comparison.
  const gf = solveOn(new OffsetGrid(2, -1), goldenFrame());
  assertNear(gf.meanAbs, 1.5, 0.3, 'meanAbs');
  const k = 32 * 64 + 32;
  assertNear(gf.dx[k], -2, 0.01, 'center cell dx');
  assertNear(gf.dy[k], 1, 0.01, 'center cell dy');
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
