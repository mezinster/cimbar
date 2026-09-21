# Web App Photo Decode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the web app decode a CimBar barcode from a photograph, accumulating frames across several photos, by porting the Android camera decode layer to JavaScript.

**Architecture:** Nine new `web-app/*.js` modules mirroring `app/lib/core/decode/` one-to-one, each an IIFE with the repo's dual browser/Node export. They feed the *existing* `RatelessAssembler` and the existing decode tail, so nothing below the assembler changes. Decoding runs on the main thread; live camera scanning is out of scope.

**Tech Stack:** Vanilla ES2017 JavaScript, no build step, no dependencies. Tests are plain Node scripts run by `sh tests/run_all.sh`. One Dart test-only tool generates shared fixtures.

**Spec:** `docs/superpowers/specs/2026-09-21-web-photo-decode-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **This is a port, not a redesign.** The Dart file named in each task is the source of truth. Copy tuned constants verbatim; never re-derive or "improve" them. A JS file that decodes differently from Android on the same photo breaks the shared fixtures that make this maintainable.
- **Tuned constants, exact values:** locator `maxDevNorm` 0.35, side/module ratio gate 36–75, `tlMargin` 40, module floor 3 px (on the 2×-downscaled plane); `DriftSolver` `wideThreshold` 20, `clampPx` 6, 3 hill-climb iterations; `WhitePoint.minChannel` 30; grid-size gate 64 ± 10; `CapturePolicy.minModulePx` 6 (the user-facing "too small" threshold).
- **Use `Math.floor`, never `| 0`, for pixel quantisation.** `| 0` truncates toward zero and differs from `floor` for negative coordinates, which occur at image edges. Dart already hit the mirror-image bug: `.round()` is banker's rounding there and corrupted every warped cell until it became `.floor()`.
- **One global scope.** Page scripts are classic `<script>` tags, so two files declaring the same top-level `const` is a browser `SyntaxError` that no Node test catches. Every new file is an IIFE using the pattern in Task 1 Step 3.
- **`packCells` and `unpackCells` read backwards.** `packCells(raw)` takes bytes and returns *cells*; `unpackCells(cells)` takes cells and returns *bytes*. `renderFrame(ctx, raw)` likewise takes **bytes** — render a known cell array with `renderFrame(ctx, Fmt.unpackCells(cells))`. Inverting this yields a frame that renders and decodes without error but carries the wrong data.
- **Constants come from `format.js`.** The 16 tiles, 4 palette colours, and finder cell centres `(3.5,3.5) (60.5,3.5) (3.5,60.5) (60.5,60.5)` are never re-declared.
- **Working resolution:** downscale inputs to a long edge of 1920 before locating, by drawing into a ≤1920 canvas — not by reading full-resolution pixels and shrinking after.
- **Five languages.** Every user-visible string needs a key in en, ru, uk, tr, ka or `test_i18n.js` fails.
- **No change to `rateless.js`.** The wrong-file guard lives in the caller so GIF, photo and Android keep identical assembler semantics.
- **No change to the Android app's runtime or decode behaviour.** Task 3 adds a Dart tool under `app/tool/`, which ships in neither APK.

## File Structure

Create in `web-app/` (load order matters; all after `format.js`):

| File | Responsibility |
|---|---|
| `rgb-buffer.js` | RGBA→RGB buffer, bilinear RGB read |
| `luma-plane.js` | luma plane, bilinear, `downscale2`, `mean3x3` |
| `homography.js` | DLT solve, `HomographyGridModel`, `ExactGridModel` |
| `finder-locator.js` | find the four finder centres in a luma plane |
| `white-point.js` | per-channel white point from the finder cores |
| `cell-sampler.js` | read a cell's 8×8 tile (RGB or luma) through a grid model |
| `cell-classifier.js` | average-hash symbol + nearest palette colour |
| `drift-solver.js` | per-cell sub-pixel drift field |
| `photo-decoder.js` | the chain, entry point `CimbarPhoto.decode(imageData)` |

Create tests in `web-app/tests/`: `test_photo_geometry.js` (Task 1–2), `test_finder_locator.js` (Task 4), `test_cell_decode.js` (Task 5), `test_drift.js` (Task 6), `test_photo_decode.js` (Task 7).

Create `app/tool/gen_scene_fixtures.dart` and the generated `test-data/scenes/*.png` + `*.json` (Task 3).

Modify: `web-app/index.html`, `web-app/i18n.js`, `web-app/tests/run_all.sh`, `web-app/tests/test_browser_load.js`, `.github/workflows/deploy-webapp.yml`, `CLAUDE.md`.

---

### Task 1: RgbBuffer and LumaPlane

**Files:**
- Create: `web-app/rgb-buffer.js`, `web-app/luma-plane.js`
- Test: `web-app/tests/test_photo_geometry.js`

**Interfaces:**
- Consumes: nothing.
- Produces: `RgbBuffer.fromImageData(imageData) → RgbBuffer` with `.width .height .rgb .originX .originY`, `.r(x,y) .g(x,y) .b(x,y) → int`, `.bilinear(x, y, out, outOff)` writing 3 floats. `LumaPlane.fromRgb(rgb) → LumaPlane` with `.width .height .luma .originX .originY`, `.at(x,y) → int`, `.bilinear(x,y) → number`, `.downscale2() → LumaPlane`, `.mean3x3(x,y) → number`, `.crop(x0,y0,w,h) → LumaPlane`.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_photo_geometry.js`:

```js
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

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_photo_geometry.js`
Expected: FAIL — `Cannot find module '../rgb-buffer.js'`

- [ ] **Step 3: Write the modules**

Port `app/lib/core/decode/rgb_buffer.dart` and `luma_plane.dart`, **omitting** `RgbBuffer.fromYuv420`, `LumaPlane.fromYPlane` and `fromImage` (no YUV in a browser; `fromImageData` replaces them).

Mapping: `Uint8List`→`Uint8Array`, `Float32List`→`Float32Array`, `~/`→`Math.floor(a/b)`, `>>`→`>>`, `.floor()`→`Math.floor()`.

Every file created by this plan uses exactly this shape:

```js
/**
 * rgb-buffer.js — flat 8-bit RGB buffer with bilinear sampling.
 * Port of app/lib/core/decode/rgb_buffer.dart. Loads after format.js.
 * IIFE; exposes window.CimbarRgbBuffer / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;

class RgbBuffer {
  constructor(width, height, rgb, originX = 0, originY = 0) {
    if (rgb.length !== width * height * 3) throw new Error(`rgb length ${rgb.length} != ${width}*${height}*3`);
    this.width = width; this.height = height; this.rgb = rgb;
    this.originX = originX; this.originY = originY;
  }

  static fromImageData(d) {
    const out = new Uint8Array(d.width * d.height * 3);
    const src = d.data;
    for (let i = 0, j = 0, k = 0; i < d.width * d.height; i++, j += 4, k += 3) {
      out[k] = src[j]; out[k + 1] = src[j + 1]; out[k + 2] = src[j + 2];
    }
    return new RgbBuffer(d.width, d.height, out);
  }
  // ... r/g/b/bilinear ported from rgb_buffer.dart
}

const API = { RgbBuffer };
if (isNode) module.exports = API; else window.CimbarRgbBuffer = API;
})();
```

`luma-plane.js` follows the same shape exposing `window.CimbarLumaPlane`, with `fromRgb` implementing `(77*r + 150*g + 29*b) >> 8` and `bilinear` implementing the half-pixel offset `fx = x - originX - 0.5` with `Math.floor` and per-axis clamping, exactly as `luma_plane.dart:84`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web-app && node tests/test_photo_geometry.js`
Expected: PASS, 8 passed 0 failed

- [ ] **Step 5: Commit**

```bash
git add web-app/rgb-buffer.js web-app/luma-plane.js web-app/tests/test_photo_geometry.js
git commit -m "feat(web): port RgbBuffer and LumaPlane from the Android decoder"
```

---

### Task 2: Homography and grid models

**Files:**
- Create: `web-app/homography.js`
- Modify: `web-app/tests/test_photo_geometry.js` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `Homography.solve(from, to) → Homography|null` where `from`/`to` are arrays of 4 `[x,y]` pairs; `h.map(x, y) → [x,y]`. `HomographyGridModel.fromFinders({tl,tr,bl,br}) → GridModel|null`; `ExactGridModel` with the same interface. Every grid model exposes `toSource(cx, cy) → [x,y]` mapping cell coordinates to source pixels. `HomographyGridModel.finderCells` is `[[3.5,3.5],[60.5,3.5],[3.5,60.5],[60.5,60.5]]`.

- [ ] **Step 1: Write the failing test**

Append to `web-app/tests/test_photo_geometry.js`, before the results line:

```js
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_photo_geometry.js`
Expected: FAIL — `Cannot find module '../homography.js'`

- [ ] **Step 3: Write the module**

Port `app/lib/core/decode/homography.dart` (DLT `solve`, the `_solve8` Gaussian elimination, `HomographyGridModel`) and `grid_model.dart` (`ExactGridModel`) into one `homography.js` using the Task 1 Step 3 shape, exposing `window.CimbarHomography`.

`ExactGridModel.toSource(cx, cy)` is the GIF-exact mapping already implicit in `cimbar.js`'s `decodeFrameExact`: `quietPx + cx * pitchPx` in each axis, with `pitchPx`/`quietPx` read from `CimbarFormat.SPEC.grid` — do not hardcode 9 and 16.

`_solve8` returns `null` on a singular matrix; keep that, it is how `solve` reports a degenerate quad.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web-app && node tests/test_photo_geometry.js`
Expected: PASS, 13 passed 0 failed

- [ ] **Step 5: Commit**

```bash
git add web-app/homography.js web-app/tests/test_photo_geometry.js
git commit -m "feat(web): port Homography, HomographyGridModel and ExactGridModel"
```

---

### Task 3: Shared scene fixtures

**Files:**
- Create: `app/tool/gen_scene_fixtures.dart`
- Create: `test-data/scenes/*.png`, `test-data/scenes/*.json`, `test-data/scenes/README.md`

**Interfaces:**
- Consumes: `app/test/test_utils/synthetic_scene.dart` (`SceneSpec`, `renderScene`, `loadGoldenFrame`).
- Produces: for each fixture `<name>`, a PNG and a JSON sidecar `{name, golden, frameIndex, spec:{...}, width, height, finderCenters:{tl:[x,y],tr:[x,y],bl:[x,y],br:[x,y]}, homography:[9 doubles], cells:[3840 ints]}` where `cells[i]` is the 6-bit value of the i-th usable cell. Both suites read these.

- [ ] **Step 1: Write the failing test**

The test here is the Dart suite asserting the generator's own output is self-consistent. Create `app/test/tool/scene_fixtures_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:image/image.dart' as img;

void main() {
  final dir = Directory('../test-data/scenes');

  test('scene fixtures exist and every PNG has a sidecar', () {
    expect(dir.existsSync(), isTrue, reason: 'run: dart run tool/gen_scene_fixtures.dart');
    final pngs = dir.listSync().where((f) => f.path.endsWith('.png')).toList();
    expect(pngs.length, greaterThanOrEqualTo(8));
    for (final p in pngs) {
      expect(File(p.path.replaceAll('.png', '.json')).existsSync(), isTrue, reason: p.path);
    }
  });

  test('each fixture decodes to its recorded cells through its recorded geometry', () {
    for (final f in dir.listSync().where((f) => f.path.endsWith('.json'))) {
      final side = jsonDecode(File(f.path).readAsStringSync()) as Map<String, dynamic>;
      final image = img.decodeImage(File(f.path.replaceAll('.json', '.png')).readAsBytesSync())!;
      final c = side['finderCenters'] as Map<String, dynamic>;
      (double, double) pt(String k) => ((c[k][0] as num).toDouble(), (c[k][1] as num).toDouble());
      final grid = HomographyGridModel.fromFinders(tl: pt('tl'), tr: pt('tr'), bl: pt('bl'), br: pt('br'));
      expect(grid, isNotNull, reason: side['name'] as String);
      final res = FrameDecoder().decodeWithGrid(RgbBuffer.fromImage(image), grid!);
      final want = (side['cells'] as List).cast<int>();
      expect(res.cells!.length, want.length, reason: side['name'] as String);
      var wrong = 0;
      for (var i = 0; i < want.length; i++) if (res.cells![i] != want[i]) wrong++;
      expect(wrong, 0, reason: '${side['name']}: $wrong cells differ from ground truth');
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && sh tests/run_all.sh --verbose 2>&1 | grep -i scene_fixtures`
Expected: FAIL — `../test-data/scenes` does not exist

- [ ] **Step 3: Write the generator**

Create `app/tool/gen_scene_fixtures.dart`. It reuses the existing harness rather than re-rendering anything by hand:

```dart
// Renders the degradation matrix used by camera_path_test.dart to PNG +
// ground-truth JSON, so the JS port can be tested against the same pixels.
// Test-only: ships in neither APK. Usage: dart run tool/gen_scene_fixtures.dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import '../test/test_utils/synthetic_scene.dart';

// SceneSpec has NO named constructor -- it is default-constructed and mutated
// with cascade syntax, exactly as camera_path_test.dart does it.
// centerX/centerY default to 0, which would put the barcode at the canvas
// corner, so every case sets them. Canvas size is per case because a 608 px
// frame at scale 1.8 rotated 37 degrees spans ~1533 px and does not fit a
// 1080 px tall canvas; only the unrotated case is true 1080p (and it is the
// one the JS performance guard uses).
class Case {
  final int w, h;
  final SceneSpec spec;
  const Case(this.w, this.h, this.spec);
}

final cases = <String, Case>{
  'plain_s13':    Case(1920, 1080, SceneSpec()..scale = 1.3..centerX = 960..centerY = 540),
  'rot37_s18':    Case(1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = 37..centerX = 850..centerY = 850),
  'rot90_s18':    Case(1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = 90..centerX = 850..centerY = 850),
  'rot271_s18':   Case(1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = 271..centerX = 850..centerY = 850),
  'keystone_s16': Case(1600, 1600, SceneSpec()..scale = 1.6..keystone = 0.12..rotationDeg = 8..centerX = 800..centerY = 800),
  'blur_s20':     Case(1600, 1600, SceneSpec()..scale = 2.0..blurSigma = 2..centerX = 800..centerY = 800),
  'dim_s15':      Case(1500, 1500, SceneSpec()..scale = 1.5..brightness = 0.7..centerX = 750..centerY = 750),
  'noise_s15':    Case(1500, 1500, SceneSpec()..scale = 1.5..noiseSigma = 8..seed = 7..centerX = 750..centerY = 750),
};

void main() {
  final out = Directory('../test-data/scenes')..createSync(recursive: true);
  for (final e in cases.entries) {
    final frame = loadGoldenFrame('hello', 0);
    final scene = renderScene(frame, e.value.w, e.value.h, e.value.spec);
    File('${out.path}/${e.key}.png').writeAsBytesSync(img.encodePng(scene.image));
    File('${out.path}/${e.key}.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'name': e.key,
      'golden': 'hello',
      'frameIndex': 0,
      'width': e.value.w,
      'height': e.value.h,
      'finderCenters': {
        'tl': [scene.finderCenters[0].$1, scene.finderCenters[0].$2],
        'tr': [scene.finderCenters[1].$1, scene.finderCenters[1].$2],
        'bl': [scene.finderCenters[2].$1, scene.finderCenters[2].$2],
        'br': [scene.finderCenters[3].$1, scene.finderCenters[3].$2],
      },
      'homography': scene.frameToScene.h.toList(),
      'cells': goldenCells('hello', 0),
    }));
    stdout.writeln('wrote ${e.key}.png + .json');
  }
}
```

`goldenCells(name, index)` is a two-line helper reading
`jsonDecode(File('../test-data/goldens/$name.json'))['frames'][index]['cells']`
(verified present: `hello.json` frame 0 carries a flat 3840-entry `cells`
list, written by `web-app/tools/gen_goldens.js`). The ground truth is the
source frame's known cells, never a decode of the degraded scene.

Add `test-data/scenes/README.md` stating the files are generated, the command that regenerates them, and that both test suites consume them.

- [ ] **Step 4: Generate and verify**

Run:
```bash
cd app && dart run tool/gen_scene_fixtures.dart && sh tests/run_all.sh
```
Expected: 8 PNG+JSON pairs written; the Dart suite passes including both new tests.

- [ ] **Step 5: Commit**

```bash
git add app/tool/gen_scene_fixtures.dart app/test/tool/scene_fixtures_test.dart test-data/scenes/
git commit -m "test: shared camera-path scene fixtures for the Dart and JS suites"
```

---

### Task 4: FinderLocator

**Files:**
- Create: `web-app/finder-locator.js`
- Test: `web-app/tests/test_finder_locator.js`

**Interfaces:**
- Consumes: `LumaPlane` (Task 1).
- Produces: `FinderLocator.locate(lumaPlane) → {ok, tl, tr, bl, br, candidates, clusters, devNorm, tlLuma, secondLuma, failReason, module}` where each corner is `[x,y]` in full-resolution source pixels and `failReason` is one of `'candidates'|'clusters'|'parallelogram'|'ratio'|null`.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_finder_locator.js`:

```js
'use strict';
const fs = require('fs');
const path = require('path');
const { PNG } = require('./png.js');                 // see Step 3 note
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_finder_locator.js`
Expected: FAIL — `Cannot find module './png.js'`

- [ ] **Step 3: Write the PNG reader and the locator**

The suite has no dependencies, so add a minimal `web-app/tests/png.js` exposing `PNG.decode(buffer) → {width, height, data}` for 8-bit RGB/RGBA non-interlaced PNGs: parse `IHDR`, concatenate `IDAT`, `zlib.inflateSync`, then undo the five per-row filters (None/Sub/Up/Average/Paeth). This is a test helper, not a page script, so it needs no IIFE and is not staged for deploy.

Then port `app/lib/core/decode/finder_locator.dart` (405 lines) to `web-app/finder-locator.js` using the Task 1 Step 3 shape, exposing `window.CimbarFinderLocator`. Stages, in order, all present in the Dart source: `downscale2` → local-mean binarise → strict 1:1:3:1:1 row scan → dotted 7-run pattern anchored at the hit row (25% tolerance) → cluster → refine centres by alternating row/column extent, 3 iterations → select four by parallelogram closure (`maxDevNorm` 0.35) → side/module ratio gate 36–75 → classify TL by core brightness in the **full-resolution** plane (`tlMargin` 40) → orient TR/BL by cross product → correct the module estimate by cos(rotation).

Two traps:
- Sample the finder cores via `full.mean3x3`, not the downscaled plane. After 2× downscale the ~8 px core cell is ~4 px, too coarse to tell a dotted from a solid centre.
- Keep the fallback to coordinate extremes when the brightness gap is below `tlMargin`; it is what keeps older barcodes decodable.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web-app && node tests/test_finder_locator.js`
Expected: PASS, 10 passed 0 failed

- [ ] **Step 5: Commit**

```bash
git add web-app/finder-locator.js web-app/tests/test_finder_locator.js web-app/tests/png.js
git commit -m "feat(web): port FinderLocator, tested against the shared scene fixtures"
```

---

### Task 5: WhitePoint, CellSampler, CellClassifier

**Files:**
- Create: `web-app/white-point.js`, `web-app/cell-sampler.js`, `web-app/cell-classifier.js`
- Test: `web-app/tests/test_cell_decode.js`

**Interfaces:**
- Consumes: `RgbBuffer`, `LumaPlane` (Task 1); `ExactGridModel` (Task 2).
- Produces: `WhitePoint.fromFinders(rgbBuffer, grid) → [r,g,b]|null`. `new CellSampler(rgbBuffer, grid, lumaPlane|null)` with `.sample(col, row, patch, dx=0, dy=0)` filling `patch.luma` (64 floats) and `patch.rgb` (192 floats), and `.sampleLuma(col, row, out64, dx=0, dy=0)`. `new CellClassifier()` with `.classify(patch, whitePoint|null) → {symbol, hamming, color, colorMargin}` and `.bestSymbol(luma64) → [symbol, hamming]`. `newPatch() → {luma: Float32Array(64), rgb: Float32Array(192)}`.

These three ship together because `CellClassifier` is untestable without `CellSampler`, and `WhitePoint` is one function consumed by the classifier.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_cell_decode.js`:

```js
'use strict';
const Fmt = require('../format.js');
const Cimbar = require('../cimbar.js');
const MockCanvas = require('./mock_canvas.js');
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_cell_decode.js`
Expected: FAIL — `Cannot find module '../white-point.js'`

- [ ] **Step 3: Write the modules**

Port `white_point.dart`, `cell_sampler.dart` and `cell_classifier.dart` using the Task 1 Step 3 shape, exposing `window.CimbarWhitePoint`, `window.CimbarCellSampler`, `window.CimbarCellClassifier`.

Three things that must be ported exactly rather than reimplemented:

1. **`CellSampler` interpolates the 64 sample positions from the cell's 4 corners** (`_cellCorners` + `_samplePositions`), costing 4 grid evaluations per cell rather than 64. This is an approximation Dart justifies because the projective error over a 9 px cell is below bilinear resolution. A "more correct" exact version decodes differently from Android — port the approximation. The tile extent is `cellPx / pitchPx` (8/9), read from `CimbarFormat.SPEC.grid`.
2. **`CellClassifier` normalises chroma by brightness** before nearest-palette matching, which is why the 45%-brightness test passes. It divides by the white point when one is given.
3. **`WhitePoint.fromFinders`** takes the per-channel 90th percentile over the eight core cells around each finder core — five samples per cell through the grid model, **excluding the centre dot cell** — and returns `null` when any channel is below `minChannel` 30.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web-app && node tests/test_cell_decode.js`
Expected: PASS, 8 passed 0 failed

- [ ] **Step 5: Commit**

```bash
git add web-app/white-point.js web-app/cell-sampler.js web-app/cell-classifier.js web-app/tests/test_cell_decode.js
git commit -m "feat(web): port WhitePoint, CellSampler and CellClassifier"
```

---

### Task 6: DriftSolver

**Files:**
- Create: `web-app/drift-solver.js`
- Test: `web-app/tests/test_drift.js`

**Interfaces:**
- Consumes: `CellSampler`, `CellClassifier` (Task 5).
- Produces: `new DriftSolver(sampler, classifier, {wideThreshold = 20, clampPx = 6})` with `.solve() → {dx: Int8Array(4096), dy: Int8Array(4096), widened: int, meanAbs: number, maxAbs: number}`, indexed by `row * 64 + col`.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_drift.js`:

```js
'use strict';
const Fmt = require('../format.js');
const Cimbar = require('../cimbar.js');
const MockCanvas = require('./mock_canvas.js');
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_drift.js`
Expected: FAIL — `Cannot find module '../drift-solver.js'`

- [ ] **Step 3: Write the module**

Port `drift_solver.dart` using the Task 1 Step 3 shape, exposing `window.CimbarDriftSolver`.

Structure, all from the Dart source: BFS flood-fill from the eight seed cells `(8,0) (0,8) (55,0) (63,8) (0,55) (8,63) (63,55) (55,63)`, each cell starting from its decided neighbour's drift; hill-climb over `_near` (the 3×3 offsets) for at most **3** iterations, breaking early when no offset improves; widen to the `_ring2` ±2 ring when the best hamming exceeds `wideThreshold` 20, and always for seed cells (no decided neighbour); clamp to ±`clampPx` 6.

Sampling is **luma-only** and matching is **symbol-only** (`bestSymbol`) — this is the hot loop and must not do RGB reads or colour matching.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web-app && node tests/test_drift.js`
Expected: PASS, 4 passed 0 failed

- [ ] **Step 5: Commit**

```bash
git add web-app/drift-solver.js web-app/tests/test_drift.js
git commit -m "feat(web): port DriftSolver"
```

---

### Task 7: photo-decoder.js and the equivalence invariant

**Files:**
- Create: `web-app/photo-decoder.js`
- Test: `web-app/tests/test_photo_decode.js`

**Interfaces:**
- Consumes: every module from Tasks 1–6, plus existing `CimbarFormat.unpackCells` and `Cimbar.decodeRSFrame`.
- Produces: `CimbarPhoto.decode(imageData) → {status, cells, raw, data, blocksFailed, header, diag}` where `status` is one of `'ok'|'notLocated'|'tooSmall'|'unsupportedGrid'|'rsFailed'|'badHeader'`, `data` is the `Uint8Array` to hand to `RatelessAssembler.add`, and `diag` carries `{candidates, clusters, devNorm, module, gridEstimate, whitePoint, driftMean, driftMax, widened, rsBlocks, rsOk, rsFail, hammingMean, hammingMax, locateMs, sampleMs, driftMs, rsMs, totalMs}`.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_photo_decode.js`:

```js
'use strict';
const fs = require('fs');
const path = require('path');
const Fmt = require('../format.js');
const Cimbar = require('../cimbar.js');
const MockCanvas = require('./mock_canvas.js');
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

function exactFrameImageData() {
  const n = Fmt.usableCellPositions().length;
  const cells = new Uint8Array(n);
  for (let i = 0; i < n; i++) cells[i] = (i * 11) % 64;
  const canvas = new MockCanvas(Fmt.SPEC.gif.framePx, Fmt.SPEC.gif.framePx);
  Cimbar.renderFrame(canvas.getContext('2d'), Fmt.unpackCells(cells));
  return { imageData: canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height), cells };
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_photo_decode.js`
Expected: FAIL — `Cannot find module '../photo-decoder.js'`

- [ ] **Step 3: Write the module**

Port the camera path of `frame_decoder.dart` (`decode` and `decodeWithGrid`) into `web-app/photo-decoder.js`, Task 1 Step 3 shape, exposing `window.CimbarPhoto`. Stage order, timing each stage into `diag`:

```
RgbBuffer.fromImageData → LumaPlane.fromRgb
  → FinderLocator.locate           → not ok            → status 'notLocated'
  → module < 6                                          → status 'tooSmall'
  → HomographyGridModel.fromFinders → null             → status 'notLocated'
  → grid estimate outside 64 ± 10                       → status 'unsupportedGrid'
  → WhitePoint.fromFinders (null is tolerated)
  → new DriftSolver(...).solve()
  → CellSampler + CellClassifier over usableCellPositions() → cells
  → CimbarFormat.unpackCells(cells) → Cimbar.decodeRSFrame → blocksFailed > 0 → status 'rsFailed'
  → CimbarFormat.decodeHeader(data) → !valid              → status 'badHeader'
  → status 'ok'
```

The grid estimate is derived from the located side length over the module estimate, as `frame_decoder.dart` does; reuse its expression rather than inventing one.

Every failing status still returns a populated `diag` — the whole point is that the page can tell the user *why*.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web-app && node tests/test_photo_decode.js`
Expected: PASS, 12 passed 0 failed, with the timing line printed

- [ ] **Step 5: Commit**

```bash
git add web-app/photo-decoder.js web-app/tests/test_photo_decode.js
git commit -m "feat(web): CimbarPhoto.decode — the photo decode chain"
```

---

### Task 8: Page integration

**Files:**
- Modify: `web-app/index.html` (tab label, file input, `onFileSelect`, new `addPhoto`/`resetPhotoSession`, script tags)
- Modify: `web-app/i18n.js` (all five language tables)

**Interfaces:**
- Consumes: `CimbarPhoto.decode` (Task 7); existing `Cimbar.RatelessAssembler`, `CimbarFormat.decodeHeader`, and the existing decode tail.
- Produces: no new module API; `photoSession` is page-local state.

- [ ] **Step 1: Write the failing test**

`test_i18n.js` already fails when a `data-i18n` key used in `index.html` is missing from any language, so it *is* the test for this task. Add the new keys to the English table only, and to the markup, so the test fails for the other four languages first.

Run: `cd web-app && node tests/test_i18n.js`
Expected after adding English-only keys: FAIL, naming the missing ru/uk/tr/ka keys.

New keys (English text; the five statuses from spec §7.1, the seven assembler reasons plus the header reasons from §7.2, and the UI):

```js
tabDecode: 'Decode',
takePhoto: 'Take a photo',
choosePhotoOrGif: 'Choose a GIF or a photo of a barcode',
photoAccepted: 'Frame {seq} accepted — {rank} of {total}',
photoDuplicate: 'You already have this frame',
photoDependent: 'No new information in this photo',
photoKeepGoing: '{rank} of {total} frames — photograph the next one',
photoWrongFile: 'This photo is from a different file. Discard {n} frames of progress and start over?',
photoStartOver: 'Start over',
errNotLocated: 'No barcode found in this photo',
errTooSmall: 'Barcode too small in frame — move closer',
errUnsupportedGrid: "This doesn't look like a CimBar v2 barcode",
errRsFailed: 'Blurry or angled — try again, straighter',
errBadHeader: 'Frame damaged',
rejRs: 'Too damaged to read',
rejShort: 'Frame truncated',
rejTotal: 'Frame belongs to a file of a different length',
rejFlags: 'Frame flags do not match the file in progress',
rejUncoded: 'Repair frame rejected: file too large for coding',
rejVersion: 'Not a CimBar v2 barcode',
rejSeq: 'Frame number out of range for this file',
```

`decodeHeader` reports `short`, `version`, `flags`, `total` and `seq`; the
first four share keys with the assembler reasons above, so only `rejVersion`
and `rejSeq` are additional.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_i18n.js`
Expected: FAIL — missing keys in ru, uk, tr, ka

- [ ] **Step 3: Implement**

Translate all new keys into ru, uk, tr, ka. Then in `index.html`:

Add the nine scripts in dependency order, after `format.js` and before `i18n.js`:

```html
<script src="rgb-buffer.js"></script>
<script src="luma-plane.js"></script>
<script src="homography.js"></script>
<script src="finder-locator.js"></script>
<script src="white-point.js"></script>
<script src="cell-sampler.js"></script>
<script src="cell-classifier.js"></script>
<script src="drift-solver.js"></script>
<script src="photo-decoder.js"></script>
```

Widen the input and add the camera button:

```html
<input type="file" id="fileDec" accept="image/gif,image/*" onchange="onFileSelect(this,'dec')">
<input type="file" id="photoDec" accept="image/*" capture="environment" style="display:none"
       onchange="onFileSelect(this,'dec')">
<button type="button" data-i18n="takePhoto" onclick="document.getElementById('photoDec').click()">Take a photo</button>
```

Add the session and the photo path:

```js
let photoSession = null;   // { asm, photos, accepted }

function resetPhotoSession() {
  photoSession = null;
  document.getElementById('progDec').style.display = 'none';
}

function isGifBytes(u8) {   // magic bytes, not file.type — galleries mislabel GIFs
  return u8.length >= 4 && u8[0] === 0x47 && u8[1] === 0x49 && u8[2] === 0x46 && u8[3] === 0x38;
}

async function toImageData(file) {
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
  const long = Math.max(bitmap.width, bitmap.height);
  const k = long > 1920 ? 1920 / long : 1;          // downscale during draw, never after
  const w = Math.round(bitmap.width * k), h = Math.round(bitmap.height * k);
  const canvas = document.createElement('canvas');
  canvas.width = w; canvas.height = h;
  canvas.getContext('2d').drawImage(bitmap, 0, 0, w, h);
  bitmap.close();
  return canvas.getContext('2d').getImageData(0, 0, w, h);
}

async function addPhoto(file) {
  const r = CimbarPhoto.decode(await toImageData(file));
  if (r.status !== 'ok') {
    const key = { notLocated: 'errNotLocated', tooSmall: 'errTooSmall',
                  unsupportedGrid: 'errUnsupportedGrid', rsFailed: 'errRsFailed',
                  badHeader: 'errBadHeader' }[r.status];
    log(t(key), 'err', 'logDec');
    return;
  }

  if (!photoSession) photoSession = { asm: new Cimbar.RatelessAssembler(), photos: 0, accepted: 0 };

  // Wrong-file guard: rateless.js resets the collection on a foreign fileId,
  // which would silently discard this session. Check before add().
  const h = CimbarFormat.decodeHeader(r.data);
  if (h.valid && photoSession.asm.fileId !== null && h.fileId !== photoSession.asm.fileId) {
    if (!confirm(t('photoWrongFile', { n: photoSession.asm.rank }))) return;
    photoSession = { asm: new Cimbar.RatelessAssembler(), photos: 0, accepted: 0 };
  }

  photoSession.photos++;
  const res = photoSession.asm.add(r.data, r.blocksFailed);
  if (res.accepted) {
    photoSession.accepted++;
    log(t('photoAccepted', { seq: res.header.seq, rank: photoSession.asm.rank, total: photoSession.asm.total }), 'ok', 'logDec');
  } else {
    const key = { duplicate: 'photoDuplicate', dependent: 'photoDependent', rs: 'rejRs',
                  short: 'rejShort', total: 'rejTotal', flags: 'rejFlags', uncoded: 'rejUncoded' }[res.reason];
    log(t(key) || res.reason, res.reason === 'duplicate' || res.reason === 'dependent' ? 'info' : 'err', 'logDec');
  }

  const asm = photoSession.asm;
  document.getElementById('progDec').style.display = 'block';
  setProgress(Math.round(100 * asm.rank / asm.total), t('photoKeepGoing', { rank: asm.rank, total: asm.total }),
              'progDecFill', 'progDecPct', 'progDecLabel');
  if (asm.rank === asm.total) await finishDecode(asm);
}
```

Refactor the tail of the existing `startDecode` — from `asm.framedData()` through the result card — into `finishDecode(asm)`, and call it from both paths. Do not duplicate it.

In `onFileSelect`, read the first 4 bytes and branch: a GIF calls `resetPhotoSession()` then takes today's path; anything else calls `addPhoto(file)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd web-app && node tests/test_i18n.js && node tests/test_browser_load.js`
Expected: `test_i18n.js` PASS; `test_browser_load.js` still fails until Task 9 (it asserts a script count) — that is expected here and fixed next.

- [ ] **Step 5: Commit**

```bash
git add web-app/index.html web-app/i18n.js
git commit -m "feat(web): decode a barcode from photos, accumulating frames across shots"
```

---

### Task 9: Deploy staging, browser load, docs

**Files:**
- Modify: `web-app/tests/test_browser_load.js`, `web-app/tests/run_all.sh`
- Modify: `.github/workflows/deploy-webapp.yml`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new; this task makes the feature deployable and the suite complete.

- [ ] **Step 1: Write the failing test**

Update `web-app/tests/test_browser_load.js`: raise the expected script count from ten to nineteen, add the nine files in their load order, and assert their globals:

```js
const EXPECTED_GLOBALS = [
  'ReedSolomon', 'CIMBAR_SPEC', 'CimbarFormat', 'CimbarRateless', 'Cimbar',
  'CimbarCrypto', 'CimbarCompress', 'GifEncoder', 'GifDecoder', 'CimbarI18n',
  'CimbarRgbBuffer', 'CimbarLumaPlane', 'CimbarHomography', 'CimbarFinderLocator',
  'CimbarWhitePoint', 'CimbarCellSampler', 'CimbarCellClassifier',
  'CimbarDriftSolver', 'CimbarPhoto',
];
```

Keep its existing order assertions and add: `format.js` before all nine; `rgb-buffer.js` and `luma-plane.js` before `cell-sampler.js`; `cell-sampler.js` and `cell-classifier.js` before `drift-solver.js`; all eight before `photo-decoder.js`; `i18n.js` last.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web-app && node tests/test_browser_load.js`
Expected: FAIL — script count mismatch and/or missing globals

- [ ] **Step 3: Implement**

1. Add the nine filenames to the staging list in `.github/workflows/deploy-webapp.yml`. `*.js` already has a Content-Type row, so the per-type table is unchanged — but confirm the verify step still passes, since it refuses any `<script src>` that is not staged.
2. Add the four new test scripts to `web-app/tests/run_all.sh`:

```sh
echo ""; echo "--- Photo decode: geometry ---"
node tests/test_photo_geometry.js

echo ""; echo "--- Photo decode: finder locator ---"
node tests/test_finder_locator.js

echo ""; echo "--- Photo decode: cells and drift ---"
node tests/test_cell_decode.js
node tests/test_drift.js

echo ""; echo "--- Photo decode: end to end ---"
node tests/test_photo_decode.js
```

3. Update `CLAUDE.md`: add the nine modules to the web module list, the five test files to the web test table, and a "Known Subtleties (Web)" entry recording that `Math.floor` (not `| 0`) is required for pixel quantisation and that `CellSampler`'s corner interpolation is an approximation deliberately shared with Dart.

- [ ] **Step 4: Run the full suites to verify they pass**

Run:
```bash
cd web-app && sh tests/run_all.sh
cd ../app && sh tests/run_all.sh
```
Expected: both suites fully green.

- [ ] **Step 5: Commit**

```bash
git add web-app/tests/test_browser_load.js web-app/tests/run_all.sh .github/workflows/deploy-webapp.yml CLAUDE.md
git commit -m "chore(web): stage photo decode scripts for deploy; docs and suite wiring"
```
