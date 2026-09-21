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

// Builds a CellPatch directly from a symbol's tile bits and a solid color,
// scaled uniformly (port of app/test/core/decode/cell_classifier_test.dart's
// patchFor) — no rendering/sampling round trip needed to exercise classify().
function patchFor(sym, color, scale = 1.0) {
  const p = newPatch();
  const t = Fmt.tileBits(sym);
  for (let i = 0; i < 64; i++) {
    const lit = t[i] === 1;
    const r = lit ? color[0] * scale : 0.0;
    const g = lit ? color[1] * scale : 0.0;
    const b = lit ? color[2] * scale : 0.0;
    p.rgb[i * 3] = r;
    p.rgb[i * 3 + 1] = g;
    p.rgb[i * 3 + 2] = b;
    p.luma[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }
  return p;
}

// A frame-sized RgbBuffer with a single symbol's tile painted (cyan) at cell
// (8,0), everything else black — port of the frame luma_plane_test.dart
// builds to exercise sampleLuma's no-luma-plane RGB fallback.
function singleTileFrame(sym) {
  const framePx = Fmt.SPEC.gif.framePx;
  const rgb = new Uint8Array(framePx * framePx * 3);
  const t = Fmt.tileBits(sym);
  const [ox, oy] = Fmt.cellOrigin(8, 0);
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      if (t[y * 8 + x] === 1) {
        const idx = ((oy + y) * framePx + (ox + x)) * 3;
        rgb[idx] = 0; rgb[idx + 1] = 255; rgb[idx + 2] = 255;
      }
    }
  }
  return new RgbBuffer(framePx, framePx, rgb);
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

test('white point rescales channels before chroma', () => {
  // A strong blue deficit (blue x0.3) turns cyan (0,255,255) into (0,255,77),
  // whose chroma is closer to green than to cyan without white balance.
  const classifier = new CellClassifier();
  const p = patchFor(7, [0, 255, 77]);
  const withoutWB = classifier.classify(p, null);
  assertEq(withoutWB.color, 0, 'without WB the cast reads as green');
  const withWB = classifier.classify(p, [255, 255, 77]);
  assertEq(withWB.color, 1, 'with WB it reads as cyan');
  assertEq(withWB.symbol, 7, 'symbol unaffected by white point');
});

test('sampleLuma without a luma plane matches the luma-plane-backed path', () => {
  const rgb = singleTileFrame(11);
  const luma = LumaPlane.fromRgb(rgb);
  const grid = new ExactGridModel();
  const viaLuma = new CellSampler(rgb, grid, luma);
  const viaRgb = new CellSampler(rgb, grid); // no luma plane: exercises the RGB fallback branch
  const a = new Float32Array(64), b = new Float32Array(64);
  viaLuma.sampleLuma(8, 0, a);
  viaRgb.sampleLuma(8, 0, b);
  const t = Fmt.tileBits(11);
  for (let p = 0; p < 64; p++) {
    assertEq(a[p] > 100, t[p] === 1, `luma path pixel ${p}`);
    assert(Math.abs(a[p] - b[p]) < 2, `paths agree within rounding at ${p}`);
  }
  const classifier = new CellClassifier();
  const [sym, ham] = classifier.bestSymbol(a);
  assertEq(sym, 11, 'symbol from luma path');
  assertEq(ham, 0, 'hamming from luma path');
  // shifting by one pixel must raise the distance (drift search relies on this)
  viaLuma.sampleLuma(8, 0, a, 1, 0);
  const [, ham2] = classifier.bestSymbol(a);
  assert(ham2 > 0, `shifted hamming ${ham2}`);
});

test('colorMargin is brightness-invariant (scale-invariance, not just color-preservation)', () => {
  const cells = everyCombination();
  const rgbFull = renderKnownFrame(cells);
  const rgbDim = renderKnownFrame(cells);
  for (let i = 0; i < rgbDim.rgb.length; i++) rgbDim.rgb[i] = Math.floor(rgbDim.rgb[i] * 0.45);
  const grid = new ExactGridModel();
  const samplerFull = new CellSampler(rgbFull, grid);
  const samplerDim = new CellSampler(rgbDim, grid);
  const classifier = new CellClassifier();
  const patchFull = newPatch(), patchDim = newPatch();
  const pos = Fmt.usableCellPositions();
  for (let i = 0; i < pos.length; i++) {
    samplerFull.sample(pos[i][0], pos[i][1], patchFull);
    samplerDim.sample(pos[i][0], pos[i][1], patchDim);
    const cFull = classifier.classify(patchFull, null);
    const cDim = classifier.classify(patchDim, null);
    assert(cFull.colorMargin > 0.3, `cell ${i}: full-brightness colorMargin ${cFull.colorMargin} should exceed 0.3`);
    const ratio = cDim.colorMargin / cFull.colorMargin;
    assert(Math.abs(ratio - 1) <= 0.2,
      `cell ${i}: colorMargin ratio ${ratio} (full=${cFull.colorMargin}, dim=${cDim.colorMargin}) not within 20% of 1`);
  }
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
