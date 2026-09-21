'use strict';
const { RgbBuffer } = require('../rgb-buffer.js');
const { LumaPlane } = require('../luma-plane.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function assertNear(a, b, eps, msg) { if (Math.abs(a - b) > eps) throw new Error(`${msg || 'assertNear'}: expected ${b}±${eps}, got ${a}`); }

console.log('\ntest_photo_geometry.js');

function imageData(w, h, px) {  // px: [r,g,b] per pixel, row-major
  const data = new Uint8ClampedArray(w * h * 4);
  px.forEach(([r, g, b], i) => { data[i*4] = r; data[i*4+1] = g; data[i*4+2] = b; data[i*4+3] = 255; });
  return { width: w, height: h, data };
}

test('fromImageData copies RGB and drops alpha', () => {
  const b = RgbBuffer.fromImageData(imageData(2, 1, [[10,20,30],[40,50,60]]));
  assertEq(b.width, 2); assertEq(b.height, 1);
  assertEq(b.r(0,0), 10); assertEq(b.g(0,0), 20); assertEq(b.b(0,0), 30);
  assertEq(b.r(1,0), 40); assertEq(b.g(1,0), 50); assertEq(b.b(1,0), 60);
  assertEq(b.rgb.length, 6, 'no alpha retained');
});

test('RgbBuffer.bilinear is exact at pixel centres', () => {
  const b = RgbBuffer.fromImageData(imageData(2, 1, [[0,0,0],[200,100,50]]));
  const out = new Float32Array(3);
  b.bilinear(1.5, 0.5, out, 0);
  assertNear(out[0], 200, 1e-6); assertNear(out[1], 100, 1e-6); assertNear(out[2], 50, 1e-6);
});

test('RgbBuffer.bilinear blends halfway between two pixels', () => {
  const b = RgbBuffer.fromImageData(imageData(2, 1, [[0,0,0],[200,100,50]]));
  const out = new Float32Array(3);
  b.bilinear(1.0, 0.5, out, 0);
  assertNear(out[0], 100, 1e-6); assertNear(out[1], 50, 1e-6); assertNear(out[2], 25, 1e-6);
});

test('LumaPlane.fromRgb uses BT.601 integer weights 77/150/29', () => {
  const b = RgbBuffer.fromImageData(imageData(4, 1, [[255,0,0],[0,255,0],[0,0,255],[255,255,255]]));
  const l = LumaPlane.fromRgb(b);
  assertEq(l.at(0,0), 76,  'red');    // (77*255)>>8
  assertEq(l.at(1,0), 149, 'green');  // (150*255)>>8
  assertEq(l.at(2,0), 28,  'blue');   // (29*255)>>8
  assertEq(l.at(3,0), 255, 'white');  // (256*255)>>8
});

test('downscale2 averages 2x2 blocks', () => {
  const b = RgbBuffer.fromImageData(imageData(2, 2, [[0,0,0],[255,255,255],[255,255,255],[0,0,0]]));
  const d = LumaPlane.fromRgb(b).downscale2();
  assertEq(d.width, 1); assertEq(d.height, 1);
  assertEq(d.at(0,0), 127, '(0+255+255+0)>>2');
});

test('downscale2 floors odd sizes, dropping the trailing row/column', () => {
  const b = RgbBuffer.fromImageData(imageData(3, 3, Array(9).fill([255,255,255])));
  const d = LumaPlane.fromRgb(b).downscale2();
  assertEq(d.width, 1); assertEq(d.height, 1);
});

test('LumaPlane.bilinear clamps outside the plane instead of throwing', () => {
  const b = RgbBuffer.fromImageData(imageData(2, 2, Array(4).fill([100,100,100])));
  const l = LumaPlane.fromRgb(b);
  assertNear(l.bilinear(-5, -5), l.at(0,0), 1e-6, 'top-left clamp');
  assertNear(l.bilinear(99, 99), l.at(1,1), 1e-6, 'bottom-right clamp');
});

test('crop keeps an origin so reads stay in absolute coordinates', () => {
  const px = []; for (let i = 0; i < 16; i++) px.push([i*16, i*16, i*16]);
  const l = LumaPlane.fromRgb(RgbBuffer.fromImageData(imageData(4, 4, px)));
  const c = l.crop(1, 1, 2, 2);
  assertEq(c.originX, 1); assertEq(c.originY, 1);
  assertNear(c.bilinear(1.5, 1.5), l.bilinear(1.5, 1.5), 1e-6, 'absolute read matches');
});

const { Homography, HomographyGridModel, ExactGridModel } = require('../homography.js');

const unit = [[0,0],[1,0],[0,1],[1,1]];

test('identity homography maps points to themselves', () => {
  const h = Homography.solve(unit, unit);
  assert(h !== null, 'solve returned null');
  for (const [x, y] of [[0,0],[0.5,0.5],[1,1],[2,-3]]) {
    const [mx, my] = h.map(x, y);
    assertNear(mx, x, 1e-9); assertNear(my, y, 1e-9);
  }
});

test('scale-and-translate homography maps corners exactly', () => {
  const to = [[10,20],[30,20],[10,60],[30,60]];   // x*20+10, y*40+20
  const h = Homography.solve(unit, to);
  assert(h !== null);
  const [mx, my] = h.map(0.5, 0.5);
  assertNear(mx, 20, 1e-9); assertNear(my, 40, 1e-9);
});

test('a rotated, keystoned quad maps its four corners exactly', () => {
  const to = [[100,50],[300,90],[70,250],[330,300]];
  const h = Homography.solve(unit, to);
  assert(h !== null);
  unit.forEach(([x, y], i) => {
    const [mx, my] = h.map(x, y);
    assertNear(mx, to[i][0], 1e-6, `corner ${i} x`);
    assertNear(my, to[i][1], 1e-6, `corner ${i} y`);
  });
});

test('solve returns null for a degenerate (collinear) quad', () => {
  assertEq(Homography.solve(unit, [[0,0],[1,1],[2,2],[3,3]]), null);
});

test('fromFinders on an exact frame reproduces ExactGridModel', () => {
  const ex = new ExactGridModel();
  const c = HomographyGridModel.finderCells.map(([cx, cy]) => ex.toSource(cx, cy));
  const g = HomographyGridModel.fromFinders({ tl: c[0], tr: c[1], bl: c[2], br: c[3] });
  assert(g !== null, 'fromFinders returned null');
  for (const [cx, cy] of [[0,0],[31.5,31.5],[63,63],[8,0],[55,63]]) {
    const [gx, gy] = g.toSource(cx, cy), [exx, exy] = ex.toSource(cx, cy);
    assertNear(gx, exx, 1e-6, `cell ${cx},${cy} x`);
    assertNear(gy, exy, 1e-6, `cell ${cx},${cy} y`);
  }
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
