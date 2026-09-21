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

for (const name of ['plain_s13', 'rot37_s18', 'rot90_s18', 'rot271_s18', 'keystone_s16', 'blur_s20', 'dim_s15', 'noise_s15']) {
  test(`locates all four finders in ${name} within 2 px of ground truth`, () => {
    const { side, luma } = loadScene(name);
    const r = FinderLocator.locate(luma);
    assert(r.ok, `locate failed: ${r.failReason}`);
    for (const k of ['tl', 'tr', 'bl', 'br']) {
      const d = dist(r[k], side.finderCenters[k]);
      assert(d <= 2.0, `${k} off by ${d.toFixed(2)} px`);
    }
  });
}

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
