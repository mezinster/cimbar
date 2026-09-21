'use strict';
const Fmt = require('../format.js');
const Cimbar = require('../cimbar.js');
const { MockCanvas } = require('./mock_canvas.js');
const { RgbBuffer } = require('../rgb-buffer.js');
const { LumaPlane } = require('../luma-plane.js');
const { ExactGridModel } = require('../homography.js');
const { WhitePoint } = require('../white-point.js');
const { CellSampler, newPatch } = require('../cell-sampler.js');
const { CellClassifier } = require('../cell-classifier.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function assertNear(a, b, eps, msg) { if (Math.abs(a - b) > eps) throw new Error(`${msg || 'assertNear'}: expected ${b}±${eps}, got ${a}`); }

console.log('\ntest_cell_decode.js');

// Render one frame of known cells with the production encoder, then read it back.
function renderKnownFrame(cells) {
  const canvas = new MockCanvas(Fmt.SPEC.gif.framePx, Fmt.SPEC.gif.framePx);
  Cimbar.renderFrame(canvas.getContext('2d'), Fmt.unpackCells(cells));
  const d = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
  return RgbBuffer.fromImageData(d);
}
function everyCombination() {
  const n = Fmt.usableCellPositions().length;
  const cells = new Uint8Array(n);
  for (let i = 0; i < n; i++) cells[i] = i % 64;   // all 16 symbols x 4 colours
  return cells;
}

test('white point of an exact frame is pure white', () => {
  const rgb = renderKnownFrame(everyCombination());
  const wp = WhitePoint.fromFinders(rgb, new ExactGridModel());
  assert(wp !== null, 'returned null on a clean frame');
  for (const c of wp) assertNear(c, 255, 8, 'channel');
});

test('white point returns null when the image is too dark', () => {
  const rgb = renderKnownFrame(everyCombination());
  for (let i = 0; i < rgb.rgb.length; i++) rgb.rgb[i] = Math.floor(rgb.rgb[i] * 0.05);
  assertEq(WhitePoint.fromFinders(rgb, new ExactGridModel()), null);
});

test('a colour cast shows up in the white point', () => {
  const rgb = renderKnownFrame(everyCombination());
  for (let i = 0; i < rgb.rgb.length; i += 3) rgb.rgb[i + 2] = Math.floor(rgb.rgb[i + 2] * 0.6);
  const wp = WhitePoint.fromFinders(rgb, new ExactGridModel());
  assert(wp !== null);
  assert(wp[2] < wp[0] * 0.8, `blue ${wp[2]} should be well below red ${wp[0]}`);
});

test('all 64 symbol/colour combinations classify exactly on an exact frame', () => {
  const cells = everyCombination();
  const rgb = renderKnownFrame(cells);
  const grid = new ExactGridModel();
  const sampler = new CellSampler(rgb, grid);
  const classifier = new CellClassifier();
  const patch = newPatch();
  const pos = Fmt.usableCellPositions();
  let wrongSym = 0, wrongCol = 0;
  for (let i = 0; i < pos.length; i++) {
    sampler.sample(pos[i][0], pos[i][1], patch);
    const c = classifier.classify(patch, null);
    if (c.symbol !== Fmt.cellSymbol(cells[i])) wrongSym++;
    if (c.color !== Fmt.cellColor(cells[i])) wrongCol++;
  }
  assertEq(wrongSym, 0, 'symbol mismatches');
  assertEq(wrongCol, 0, 'colour mismatches');
});

test('hamming is 0 on an exact frame', () => {
  const cells = everyCombination();
  const sampler = new CellSampler(renderKnownFrame(cells), new ExactGridModel());
  const classifier = new CellClassifier();
  const patch = newPatch();
  const pos = Fmt.usableCellPositions();
  let maxH = 0;
  for (let i = 0; i < pos.length; i++) {
    sampler.sample(pos[i][0], pos[i][1], patch);
    maxH = Math.max(maxH, classifier.classify(patch, null).hamming);
  }
  assertEq(maxH, 0, 'max hamming over an exact frame');
});

test('dimmed cells still classify (brightness-normalised chroma)', () => {
  const cells = everyCombination();
  const rgb = renderKnownFrame(cells);
  for (let i = 0; i < rgb.rgb.length; i++) rgb.rgb[i] = Math.floor(rgb.rgb[i] * 0.45);
  const sampler = new CellSampler(rgb, new ExactGridModel());
  const classifier = new CellClassifier();
  const patch = newPatch();
  const pos = Fmt.usableCellPositions();
  let wrong = 0;
  for (let i = 0; i < pos.length; i++) {
    sampler.sample(pos[i][0], pos[i][1], patch);
    if (classifier.classify(patch, null).color !== Fmt.cellColor(cells[i])) wrong++;
  }
  assertEq(wrong, 0, 'colour mismatches at 45% brightness');
});

test('sampleLuma agrees with the luma of the RGB sample', () => {
  const rgb = renderKnownFrame(everyCombination());
  const luma = LumaPlane.fromRgb(rgb);
  const grid = new ExactGridModel();
  const patch = newPatch();
  new CellSampler(rgb, grid).sample(10, 10, patch);
  const out = new Float32Array(64);
  new CellSampler(rgb, grid, luma).sampleLuma(10, 10, out);
  for (let i = 0; i < 64; i++) assertNear(out[i], patch.luma[i], 1.5, `sample ${i}`);
});

test('bestSymbol is exact on a clean tile', () => {
  const rgb = renderKnownFrame(everyCombination());
  const sampler = new CellSampler(rgb, new ExactGridModel(), LumaPlane.fromRgb(rgb));
  const classifier = new CellClassifier();
  const out = new Float32Array(64);
  const pos = Fmt.usableCellPositions();
  sampler.sampleLuma(pos[5][0], pos[5][1], out);
  const [, h] = classifier.bestSymbol(out);
  assertEq(h, 0, 'hamming on a clean tile');
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
