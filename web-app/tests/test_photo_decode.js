'use strict';
const fs = require('fs');
const path = require('path');
const Fmt = require('../format.js');
const Cimbar = require('../cimbar.js');
const { ReedSolomon } = require('../rs.js');
const { MockCanvas } = require('./mock_canvas.js');
const { PNG } = require('./png.js');
const { CimbarPhoto } = require('../photo-decoder.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }

console.log('\ntest_photo_decode.js');

const SCENES = path.join(__dirname, '..', '..', 'test-data', 'scenes');
const GOLDENS = path.join(__dirname, '..', '..', 'test-data', 'goldens');

// A real RS-encoded frame, not arbitrary cell values: the equivalence
// invariant is about pixels, but the photo chain also RS-decodes and reads
// the header, and arbitrary cells would (correctly) come back rsFailed.
function exactFrameImageData() {
  const rs = new ReedSolomon(Fmt.SPEC.rs.eccBytes);
  const data = new Uint8Array(Fmt.dataBytesPerFrame());
  data.set(Fmt.encodeHeader({ fileId: 0x1001, seq: 0, total: 1 }), 0);
  for (let i = Fmt.HEADER_LEN; i < data.length; i++) data[i] = (i * 11) % 251;
  const raw = Cimbar.encodeRSFrame(data, rs);
  const canvas = new MockCanvas(Fmt.SPEC.gif.framePx, Fmt.SPEC.gif.framePx);
  Cimbar.renderFrame(canvas.getContext('2d'), raw);
  return { imageData: canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height), cells: Fmt.packCells(raw) };
}

// THE equivalence invariant: the camera chain must be a no-op on a perfect frame.
test('on a pristine frame, decode() matches decodeFrameExact cell for cell', () => {
  const { imageData } = exactFrameImageData();
  const want = Cimbar.decodeFrameExact(imageData);
  const got = CimbarPhoto.decode(imageData);
  assertEq(got.status, 'ok', `status (${got.diag && got.diag.failReason})`);
  assertEq(got.cells.length, want.cells.length, 'cell count');
  let wrong = 0;
  for (let i = 0; i < want.cells.length; i++) if (got.cells[i] !== want.cells[i]) wrong++;
  assertEq(wrong, 0, 'cells differing from decodeFrameExact');
});

test('a pristine frame round-trips to the same raw bytes as the exact path', () => {
  const { imageData } = exactFrameImageData();
  const a = Fmt.unpackCells(Cimbar.decodeFrameExact(imageData).cells);
  const b = Fmt.unpackCells(CimbarPhoto.decode(imageData).cells);
  assertEq(Buffer.compare(Buffer.from(a), Buffer.from(b)), 0, 'packed bytes differ');
});

for (const name of ['plain_s13', 'rot37_s18', 'rot90_s18', 'rot271_s18', 'keystone_s16', 'blur_s20', 'dim_s15', 'noise_s15']) {
  test(`decodes the ${name} scene fixture to its recorded cells`, () => {
    const side = JSON.parse(fs.readFileSync(path.join(SCENES, `${name}.json`), 'utf8'));
    const r = CimbarPhoto.decode(PNG.decode(fs.readFileSync(path.join(SCENES, `${name}.png`))));
    assertEq(r.status, 'ok', `status (${JSON.stringify(r.diag)})`);
    let wrong = 0;
    for (let i = 0; i < side.cells.length; i++) if (r.cells[i] !== side.cells[i]) wrong++;
    assert(wrong / side.cells.length < 0.01, `${wrong} of ${side.cells.length} cells wrong (>1%)`);
    assertEq(r.blocksFailed, 0, 'RS blocks failed');
  });
}

test('a photo with no barcode reports notLocated, not an exception', () => {
  const d = { width: 800, height: 600, data: new Uint8ClampedArray(800 * 600 * 4).fill(120) };
  assertEq(CimbarPhoto.decode(d).status, 'notLocated');
});

test('a barcode far below the module floor reports tooSmall', () => {
  const { imageData } = exactFrameImageData();
  // Nearest-neighbour shrink to ~1/4, well under CapturePolicy.minModulePx = 6.
  const s = 4, w = Math.floor(imageData.width / s), h = Math.floor(imageData.height / s);
  const data = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const si = ((y * s) * imageData.width + x * s) * 4, di = (y * w + x) * 4;
    data[di] = imageData.data[si]; data[di+1] = imageData.data[si+1];
    data[di+2] = imageData.data[si+2]; data[di+3] = 255;
  }
  const st = CimbarPhoto.decode({ width: w, height: h, data }).status;
  assert(st === 'tooSmall' || st === 'notLocated', `expected tooSmall/notLocated, got ${st}`);
});

test('performance: the 1920x1080 scene decodes well inside the CI ceiling', () => {
  const img = PNG.decode(fs.readFileSync(path.join(SCENES, 'plain_s13.png')));
  CimbarPhoto.decode(img);                       // warm up
  const t0 = process.hrtime.bigint();
  const r = CimbarPhoto.decode(img);
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  console.log(`        totalMs=${ms.toFixed(1)} locateMs=${r.diag.locateMs} sampleMs=${r.diag.sampleMs} driftMs=${r.diag.driftMs} rsMs=${r.diag.rsMs}`);
  assert(ms < 1500, `decode took ${ms.toFixed(0)} ms, over the 1500 ms ceiling`);
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
