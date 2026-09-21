'use strict';
const fs = require('fs');
const path = require('path');
const { PNG } = require('./png.js');
const { RgbBuffer } = require('../rgb-buffer.js');
const { LumaPlane } = require('../luma-plane.js');
const { FinderLocator } = require('../finder-locator.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }

console.log('\ntest_finder_locator.js');

const SCENES = path.join(__dirname, '..', '..', 'test-data', 'scenes');
function loadScene(name) {
  const side = JSON.parse(fs.readFileSync(path.join(SCENES, `${name}.json`), 'utf8'));
  const img = PNG.decode(fs.readFileSync(path.join(SCENES, `${name}.png`)));
  return { side, luma: LumaPlane.fromRgb(RgbBuffer.fromImageData(img)) };
}
function dist(a, b) { return Math.hypot(a[0] - b[0], a[1] - b[1]); }

// Each scene's barcode is the 608 px golden frame scaled by `scale`; the v2
// grid has a 9 px cell pitch, so the true module is 9 * scale. The scales come
// from app/tool/gen_scene_fixtures.dart's `cases` table.
const FIXTURES = [
  ['plain_s13', 1.3],
  ['rot37_s18', 1.8],
  ['rot90_s18', 1.8],
  ['rot271_s18', 1.8],
  ['keystone_s16', 1.6],
  ['blur_s20', 2.0],
  ['dim_s15', 1.5],
  ['noise_s15', 1.5],
];

// The `locate` sidecar block is what the DART FinderLocator found in these
// same pixels (recorded by app/tool/gen_scene_fixtures.dart). Asserting it
// here is the Dart<->JS parity contract: landing within 2 px of the analytic
// ground truth only proves this locator is good, not that it is the same
// locator. Observed delta on every field of every fixture is exactly 0 — the
// two runtimes agree bit-for-bit, including `module`, which goes through
// atan2 and cos — so 1e-9 is a real assertion and not a fudge factor.
const PARITY_EPS = 1e-9;

for (const [name, scale] of FIXTURES) {
  test(`locates all four finders in ${name} within 2 px of ground truth`, () => {
    const { side, luma } = loadScene(name);
    const r = FinderLocator.locate(luma);
    assert(r.ok, `locate failed: ${r.failReason}`);
    for (const k of ['tl', 'tr', 'bl', 'br']) {
      const d = dist(r[k], side.finderCenters[k]);
      assert(d <= 2.0, `${k} off by ${d.toFixed(2)} px`);
    }
    // Guards the Euclidean-modulo fold in the cos(rotation) correction: with
    // a plain JS `%` the centres above are unaffected but the module of any
    // scene whose TL->TR points "upward" (rot271_s18) collapses to ~0.29.
    const want = 9 * scale;
    assert(Math.abs(r.module - want) <= 1,
      `module ${r.module.toFixed(3)} is not within 1 of 9 * ${scale} = ${want}`);
  });

  test(`reproduces the recorded Dart locate output for ${name}`, () => {
    const { side, luma } = loadScene(name);
    assert(side.locate, 'sidecar has no `locate` block — rerun: cd app && dart run tool/gen_scene_fixtures.dart');
    const want = side.locate;
    const r = FinderLocator.locate(luma);
    assert(r.ok, `locate failed: ${r.failReason}`);
    // Integer stage counters must match exactly: a single differing pixel or
    // a changed run/threshold rule moves these long before it moves a centre.
    assert(r.candidates === want.candidates, `candidates ${r.candidates} != Dart's ${want.candidates}`);
    assert(r.clusters === want.clusters, `clusters ${r.clusters} != Dart's ${want.clusters}`);
    for (const k of ['module', 'devNorm', 'tlLuma', 'secondLuma']) {
      const d = Math.abs(r[k] - want[k]);
      assert(d <= PARITY_EPS, `${k} ${r[k]} differs from Dart's ${want[k]} by ${d.toExponential(3)}`);
    }
    for (const k of ['tl', 'tr', 'bl', 'br']) {
      for (const [i, axis] of [[0, 'x'], [1, 'y']]) {
        const d = Math.abs(r[k][i] - want.corners[k][i]);
        assert(d <= PARITY_EPS, `${k}.${axis} ${r[k][i]} differs from Dart's ${want.corners[k][i]} by ${d.toExponential(3)}`);
      }
    }
  });
}

test('returns absolute coordinates when the plane carries an origin', () => {
  // Every fixture has origin (0, 0), so a dropped `+ full.originX/originY`
  // passes all of the above. Locating inside a crop is also what the camera
  // path does with an ROI, so this is not a hypothetical.
  const { side, luma } = loadScene('plain_s13');
  const cropped = luma.crop(500, 100, 1000, 900);
  assert(cropped.originX === 500 && cropped.originY === 100, 'crop did not carry an origin');
  const r = FinderLocator.locate(cropped);
  assert(r.ok, `locate failed on the crop: ${r.failReason}`);
  for (const k of ['tl', 'tr', 'bl', 'br']) {
    const d = dist(r[k], side.finderCenters[k]);
    assert(d <= 2.0, `${k} off by ${d.toFixed(2)} px — crop-local instead of absolute?`);
  }
});

test('reports notLocated on a blank image instead of throwing', () => {
  const blank = { width: 640, height: 480, data: new Uint8ClampedArray(640 * 480 * 4).fill(255) };
  const r = FinderLocator.locate(LumaPlane.fromRgb(RgbBuffer.fromImageData(blank)));
  assert(!r.ok);
  assert(typeof r.failReason === 'string' && r.failReason.length > 0, 'failReason must say why');
});

test('module estimate is plausible for a scale-1.3 scene', () => {
  const { luma } = loadScene('plain_s13');
  const r = FinderLocator.locate(luma);
  assert(r.ok);
  assert(r.module > 6 && r.module < 40, `module ${r.module} outside the CapturePolicy 6..40 band`);
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
