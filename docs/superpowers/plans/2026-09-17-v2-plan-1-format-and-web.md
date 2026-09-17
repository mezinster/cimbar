# CimBar v2 — Plan 1: Shared Spec, Tiles, JS Encoder/Decoder, Goldens, Web UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the v2 format definition (`spec/cimbar-v2.json` + tile set), a v2 JS encoder and exact GIF decoder, golden GIFs with ground truth, and the web UI (present mode, no frame-size menu), with the web test suite green on v2 only.

**Architecture:** Format constants live in one JSON file loaded by `web-app/format.js` (Node: `require`; browser: generated `format-data.js`). `cimbar.js` becomes a thin v2 renderer/exact decoder over `format.js`. RS, crypto, GIF codecs are unchanged. A Node golden generator renders reference GIFs plus JSON sidecars that later Dart plans decode.

**Tech Stack:** Plain JavaScript (CommonJS in Node 14, `window.*` globals in the browser), no npm. Tests are plain Node scripts run by `web-app/tests/run_all.sh`.

**Spec:** `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` (sections 3, 4, 5, 7.1, 7.3, 9.1, 9.4 are implemented here).

## Global Constraints

- No build step, no npm install; Node 14 (`node --version` → v14.21.3): CommonJS only, no optional chaining in files that the browser also loads is fine (Chrome supports it), but **no top-level `await`**.
- Every browser-loaded file must also work under `require()` in Node (pattern at the bottom of every module: `if (typeof module !== 'undefined' && module.exports) module.exports = {...}; else window.X = {...};`).
- Grid: `gridCells=64, cellPx=8, gapPx=1, pitchPx=9, gridPx=576, quietPx=16, framePx=608`.
- Finder: 7×7 cells solid at pitch (63 px), ring inset 9 px, core 27 px inset 18 px, dot 9 px inset 27 px on `tr, bl, br` only. Corner blocks 8×8 cells reserved → 3840 usable cells.
- Palette: `[0,255,0], [0,255,255], [255,255,0], [255,85,255]`.
- Bits: 4 symbol bits (high) + 2 color bits (low) per cell, MSB-first bitstream, row-major over usable cells → 2880 raw bytes.
- RS(255,191), `eccBytes=64`, byte-stride interleave; 2880 raw → 11×255 + 75 → 2112 data bytes; header 8 → 2104 file bytes/frame.
- Header: `[ver=0x02][flags bit0=encrypted][fileId u16 BE][seq u16 BE][total u16 BE]`.
- Commit after every task with the attribution line: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Run tests from `web-app/`: `sh tests/run_all.sh`. Each test script exits non-zero on failure.

---

## File map

| Path | Responsibility |
|---|---|
| `spec/cimbar-v2.json` | All format constants and the 16 tiles (repo root) |
| `web-app/tools/tile_rules.js` | Tile hex/bit conversion and constraint checks (Node only) |
| `web-app/tools/gen_tiles.js` | Seeded tile-set search (Node only) |
| `web-app/tools/gen_format_data.js` | Writes `web-app/format-data.js` from the spec JSON |
| `web-app/tools/gen_goldens.js` | Writes `test-data/goldens/*.gif` + `*.json` |
| `web-app/format-data.js` | GENERATED: `window.CIMBAR_SPEC = {...}` |
| `web-app/format.js` | Spec accessors, cell geometry, header codec, bit packing |
| `web-app/cimbar.js` | v2 frame renderer, exact decoder, RS framing, frame split/assembly, payload helpers |
| `web-app/gif-encoder.js` | Palette from spec (only `buildPalette` changes) |
| `web-app/index.html` | Encode/decode flows on v2, present mode |
| `web-app/tests/test_tiles.js` | Tile rules + generator |
| `web-app/tests/test_format.js` | Spec consistency, header, packing, generated data freshness |
| `web-app/tests/test_frame.js` | Render → exact decode round-trip, finder pixels |
| `web-app/tests/test_goldens.js` | Decode every golden and compare to its sidecar |
| `web-app/tests/test_pipeline_node.js` | End-to-end file → GIF → file (rewritten for v2) |
| `web-app/tests/run_all.sh`, `tests/test_pipeline.py`, `tests/test_gif.py` | Runners updated |
| `test-data/goldens/` | Golden GIFs and sidecars (repo root, shared with Android) |

Test helper pattern used by every new test file (copy verbatim):

```js
let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
// ... tests ...
console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

---

### Task 1: Tile rules and generator

**Files:**
- Create: `web-app/tools/tile_rules.js`
- Create: `web-app/tools/gen_tiles.js`
- Test: `web-app/tests/test_tiles.js`

**Interfaces:**
- Produces: `tile_rules.js` exports `hexToTile(hex) → Uint8Array(64)`, `tileToHex(tile) → string(16)`, `popcount`, `hamming(a,b)`, `shift(t,dx,dy)`, `rot90`, `mirror`, `checkTile(t) → bool`, `checkPair(a,b) → bool`, `checkSet(tiles) → string[]` (empty = OK), `RULES`, `SHIFTS`.
- Produces: `gen_tiles.js` exports `generate(seed) → Uint8Array[16] | null`; CLI prints `{ "seed": n, "tiles": [16 hex] }`.

Design note: tiles are built from a 4×4 grid of 2×2-pixel blocks (7–9 lit blocks of 16), so the smallest feature is 2 source px. Random single-pixel scatter would satisfy the spec's Hamming constraints but blur to uniform gray on a camera; the block structure is the generator's choice, the spec constraints are still checked on the resulting 64-bit tiles.

- [ ] **Step 1: Write the failing test**

`web-app/tests/test_tiles.js`:

```js
'use strict';
const R = require('../tools/tile_rules.js');
const { generate } = require('../tools/gen_tiles.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }

console.log('\ntest_tiles.js');

test('hex <-> tile round trip, MSB is top-left', () => {
  const t = R.hexToTile('8000000000000001');
  assertEq(t[0], 1, 'top-left');
  assertEq(t[63], 1, 'bottom-right');
  assertEq(R.popcount(t), 2);
  assertEq(R.tileToHex(t), '8000000000000001');
});

test('hamming and shift', () => {
  const a = R.hexToTile('ff00000000000000'); // top row lit
  const b = R.hexToTile('00ff000000000000'); // second row lit
  assertEq(R.hamming(a, b), 16);
  assertEq(R.hamming(R.shift(a, 0, 1), b), 0, 'shift down by 1 equals row 2');
  assertEq(R.popcount(R.shift(a, 0, -1)), 0, 'shift up drops the row');
});

test('rot90 and mirror', () => {
  const a = R.hexToTile('ff00000000000000'); // top row
  const r = R.rot90(a);                        // right column
  assertEq(R.tileToHex(r), '0101010101010101');
  const m = R.mirror(R.hexToTile('8080808080808080')); // left column -> right column
  assertEq(R.tileToHex(m), '0101010101010101');
});

test('checkTile enforces fill 26..38', () => {
  assert(!R.checkTile(R.hexToTile('0000000000000000')), 'empty rejected');
  assert(!R.checkTile(R.hexToTile('ffffffffffffffff')), 'full rejected');
  assert(R.checkTile(R.hexToTile('ffffffff00000000')), '32 lit accepted');
});

test('checkPair rejects close, shifted-close and rotated tiles', () => {
  const a = R.hexToTile('ffffffff00000000');          // top half
  const b = R.hexToTile('ffffffff00000001');          // 1 bit away
  assert(!R.checkPair(a, b), 'hamming 1 rejected');
  const c = R.rot90(a);                                // rotation of a
  assert(!R.checkPair(a, c), 'rotation rejected');
  const d = R.hexToTile('00000000ffffffff');          // bottom half: hamming 64 but shift-by-1 differs by 48 -> ok
  assert(R.checkPair(a, d), 'far pair accepted');
});

test('checkSet returns [] for a valid pair and names violations', () => {
  const a = R.hexToTile('ffffffff00000000');
  const d = R.hexToTile('00000000ffffffff');
  assertEq(R.checkSet([a, d]).length, 0);
  const errs = R.checkSet([a, R.hexToTile('ffffffff00000001')]);
  assert(errs.length === 1 && /tiles 0,1/.test(errs[0]), 'violation named');
});

test('generate(seed) returns 16 tiles passing checkSet, deterministic', () => {
  const t1 = generate(1);
  assert(t1 && t1.length === 16, 'found 16 tiles');
  assertEq(R.checkSet(t1).length, 0, 'set valid');
  const t2 = generate(1);
  assertEq(t1.map(R.tileToHex).join(','), t2.map(R.tileToHex).join(','), 'deterministic');
});

test('generated tiles are made of uniform 2x2 blocks', () => {
  for (const t of generate(1)) {
    for (let by = 0; by < 4; by++) for (let bx = 0; bx < 4; bx++) {
      const v = t[(by * 2) * 8 + bx * 2];
      assertEq(t[(by * 2) * 8 + bx * 2 + 1], v, 'block uniform');
      assertEq(t[(by * 2 + 1) * 8 + bx * 2], v, 'block uniform');
      assertEq(t[(by * 2 + 1) * 8 + bx * 2 + 1], v, 'block uniform');
    }
  }
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web-app && node tests/test_tiles.js`
Expected: crash with `Cannot find module '../tools/tile_rules.js'`.

- [ ] **Step 3: Write tile_rules.js**

`web-app/tools/tile_rules.js`:

```js
'use strict';
/**
 * tile_rules.js — tile representation and the constraints from spec §3.4.
 * A tile is a Uint8Array(64) of 0/1, row-major, index = row*8 + col.
 * Hex form: 16 hex digits, MSB of the first digit = top-left pixel.
 */

const RULES = { minFill: 26, maxFill: 38, minHamming: 24, minShiftedHamming: 16 };
const SHIFTS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

function hexToTile(hex) {
  if (typeof hex !== 'string' || hex.length !== 16) throw new Error('tile hex must be 16 chars');
  const t = new Uint8Array(64);
  for (let i = 0; i < 16; i++) {
    const nib = parseInt(hex[i], 16);
    if (Number.isNaN(nib)) throw new Error('bad hex digit in tile');
    for (let b = 0; b < 4; b++) t[i * 4 + b] = (nib >> (3 - b)) & 1;
  }
  return t;
}

function tileToHex(t) {
  let s = '';
  for (let i = 0; i < 16; i++) {
    let nib = 0;
    for (let b = 0; b < 4; b++) nib = (nib << 1) | t[i * 4 + b];
    s += nib.toString(16);
  }
  return s;
}

function popcount(t) { let n = 0; for (let i = 0; i < 64; i++) n += t[i]; return n; }
function hamming(a, b) { let n = 0; for (let i = 0; i < 64; i++) n += a[i] ^ b[i]; return n; }

function shift(t, dx, dy) {
  const o = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const sx = x - dx, sy = y - dy;
    if (sx >= 0 && sx < 8 && sy >= 0 && sy < 8) o[y * 8 + x] = t[sy * 8 + sx];
  }
  return o;
}

function rot90(t) {
  const o = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) o[x * 8 + (7 - y)] = t[y * 8 + x];
  return o;
}

function mirror(t) {
  const o = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) o[y * 8 + (7 - x)] = t[y * 8 + x];
  return o;
}

function variants(t) {
  const r1 = rot90(t), r2 = rot90(r1), r3 = rot90(r2);
  return [r1, r2, r3, mirror(t), mirror(r1), mirror(r2), mirror(r3)];
}

function checkTile(t) {
  const f = popcount(t);
  return f >= RULES.minFill && f <= RULES.maxFill;
}

function checkPair(a, b) {
  if (hamming(a, b) < RULES.minHamming) return false;
  for (const [dx, dy] of SHIFTS) {
    if (hamming(shift(a, dx, dy), b) < RULES.minShiftedHamming) return false;
    if (hamming(shift(b, dx, dy), a) < RULES.minShiftedHamming) return false;
  }
  for (const v of variants(a)) if (hamming(v, b) === 0) return false;
  return true;
}

function checkSet(tiles) {
  const errors = [];
  tiles.forEach((t, i) => {
    if (!checkTile(t)) errors.push(`tile ${i}: fill ${popcount(t)} outside ${RULES.minFill}-${RULES.maxFill}`);
  });
  for (let i = 0; i < tiles.length; i++) {
    for (let j = i + 1; j < tiles.length; j++) {
      if (!checkPair(tiles[i], tiles[j])) {
        errors.push(`tiles ${i},${j}: pair rule violated (hamming ${hamming(tiles[i], tiles[j])})`);
      }
    }
  }
  return errors;
}

module.exports = { RULES, SHIFTS, hexToTile, tileToHex, popcount, hamming, shift, rot90, mirror, variants, checkTile, checkPair, checkSet };
```

- [ ] **Step 4: Write gen_tiles.js**

`web-app/tools/gen_tiles.js`:

```js
'use strict';
/**
 * gen_tiles.js — seeded search for a 16-tile set satisfying tile_rules.
 * Tiles are built from a 4x4 grid of 2x2-pixel blocks (7..9 lit blocks),
 * so the smallest feature is 2 px — survives camera blur far better than
 * single-pixel scatter while still meeting the spec's Hamming constraints.
 *
 * Usage: node tools/gen_tiles.js [startSeed]
 * Prints {"seed": n, "tiles": [16 hex strings]} for the first seed that works.
 */
const { checkTile, checkPair, tileToHex } = require('./tile_rules.js');

function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomTile(rnd) {
  const blocks = new Uint8Array(16);
  const target = 7 + Math.floor(rnd() * 3); // 7, 8 or 9 blocks -> 28, 32 or 36 px
  const idx = [];
  for (let i = 0; i < 16; i++) idx.push(i);
  for (let i = 15; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const tmp = idx[i]; idx[i] = idx[j]; idx[j] = tmp;
  }
  for (let k = 0; k < target; k++) blocks[idx[k]] = 1;
  const t = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) t[y * 8 + x] = blocks[(y >> 1) * 4 + (x >> 1)];
  return t;
}

function generate(seed, count = 16, maxTries = 200000) {
  const rnd = mulberry32(seed);
  const tiles = [];
  for (let tries = 0; tries < maxTries && tiles.length < count; tries++) {
    const c = randomTile(rnd);
    if (!checkTile(c)) continue;
    if (tiles.every(t => checkPair(t, c))) tiles.push(c);
  }
  return tiles.length === count ? tiles : null;
}

if (require.main === module) {
  const start = parseInt(process.argv[2] || '1', 10);
  for (let s = start; s < start + 1000; s++) {
    const tiles = generate(s);
    if (tiles) {
      console.log(JSON.stringify({ seed: s, tiles: tiles.map(tileToHex) }, null, 2));
      process.exit(0);
    }
  }
  console.error('no tile set found in 1000 seeds');
  process.exit(1);
}

module.exports = { generate, mulberry32, randomTile };
```

- [ ] **Step 5: Run tests**

Run: `cd web-app && node tests/test_tiles.js`
Expected: `Results: 8 passed, 0 failed`. If `generate(1)` returns null (search exhausted), raise `maxTries` to 1000000 in the default parameter and re-run; the seed the CLI prints is what Task 2 uses.

- [ ] **Step 6: Commit**

```bash
git add web-app/tools/tile_rules.js web-app/tools/gen_tiles.js web-app/tests/test_tiles.js
git commit -m "Add v2 tile rules and seeded tile-set generator

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Spec JSON and generated browser data

**Files:**
- Create: `spec/cimbar-v2.json`
- Create: `web-app/tools/gen_format_data.js`
- Create: `web-app/format-data.js` (generated, committed)
- Test: `web-app/tests/test_format.js` (part 1; extended in Task 3)

**Interfaces:**
- Produces: `spec/cimbar-v2.json` with the exact key layout below. Every later task and every Dart plan reads it.

- [ ] **Step 1: Generate the tile set**

Run: `cd web-app && node tools/gen_tiles.js 1`
Copy the 16 hex strings from the output into the `tiles` array in the next step, and the seed into `tilesSeed`.

- [ ] **Step 2: Write the spec file**

`spec/cimbar-v2.json` (replace `TILE_0`…`TILE_15` with the generated strings and `SEED` with the seed):

```json
{
  "version": 2,
  "grid": { "gridCells": 64, "cellPx": 8, "gapPx": 1, "pitchPx": 9, "gridPx": 576, "quietPx": 16, "framePx": 608 },
  "finder": {
    "cells": 7, "cornerCells": 8,
    "outerPx": 63, "ringInsetPx": 9, "corePx": 27, "coreInsetPx": 18, "dotPx": 9, "dotInsetPx": 27,
    "centers": { "tl": [3.5, 3.5], "tr": [60.5, 3.5], "bl": [3.5, 60.5], "br": [60.5, 60.5] },
    "dotOn": ["tr", "bl", "br"]
  },
  "palette": [[0, 255, 0], [0, 255, 255], [255, 255, 0], [255, 85, 255]],
  "tilesSeed": SEED,
  "tiles": ["TILE_0", "TILE_1", "TILE_2", "TILE_3", "TILE_4", "TILE_5", "TILE_6", "TILE_7",
            "TILE_8", "TILE_9", "TILE_10", "TILE_11", "TILE_12", "TILE_13", "TILE_14", "TILE_15"],
  "bits": { "symbolBits": 4, "colorBits": 2 },
  "rs": { "blockTotal": 255, "eccBytes": 64 },
  "header": {
    "lengthBytes": 8, "version": 2,
    "fields": [
      { "name": "version", "offset": 0, "size": 1 },
      { "name": "flags", "offset": 1, "size": 1 },
      { "name": "fileId", "offset": 2, "size": 2 },
      { "name": "seq", "offset": 4, "size": 2 },
      { "name": "total", "offset": 6, "size": 2 }
    ]
  },
  "gif": { "framePx": 608, "delayOptionsMs": [100, 200, 400], "defaultDelayMs": 200 },
  "capacity": { "usableCells": 3840, "rawBytesPerFrame": 2880, "dataBytesPerFrame": 2112, "fileBytesPerFrame": 2104 }
}
```

- [ ] **Step 3: Write the generator for the browser copy**

`web-app/tools/gen_format_data.js`:

```js
'use strict';
/**
 * gen_format_data.js — writes web-app/format-data.js from spec/cimbar-v2.json
 * so the browser (which cannot require() JSON) sees the same constants.
 * Usage: node tools/gen_format_data.js
 */
const fs = require('fs');
const path = require('path');

const specPath = path.join(__dirname, '..', '..', 'spec', 'cimbar-v2.json');
const outPath = path.join(__dirname, '..', 'format-data.js');

function render(specText) {
  const spec = JSON.parse(specText); // validates
  return '/* GENERATED by web-app/tools/gen_format_data.js from spec/cimbar-v2.json — do not edit */\n' +
    "'use strict';\n" +
    'window.CIMBAR_SPEC = ' + JSON.stringify(spec) + ';\n';
}

if (require.main === module) {
  fs.writeFileSync(outPath, render(fs.readFileSync(specPath, 'utf8')));
  console.log('wrote ' + outPath);
}

module.exports = { render, specPath, outPath };
```

- [ ] **Step 4: Generate and write the first part of test_format.js**

Run: `cd web-app && node tools/gen_format_data.js`

`web-app/tests/test_format.js`:

```js
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
```

- [ ] **Step 5: Run tests**

Run: `cd web-app && node tests/test_format.js`
Expected: `Results: 6 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add spec/cimbar-v2.json web-app/tools/gen_format_data.js web-app/format-data.js web-app/tests/test_format.js
git commit -m "Add cimbar-v2 spec JSON and generated browser format data

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: format.js — geometry, header codec, bit packing

**Files:**
- Create: `web-app/format.js`
- Modify: `web-app/tests/test_format.js` (append tests)

**Interfaces:**
- Produces (module `CimbarFormat`, also `window.CimbarFormat`):
  - `SPEC` (the spec object), `HEADER_LEN = 8`, `FORMAT_VERSION = 2`, `BITS_PER_CELL = 6`
  - `isReservedCell(col, row) → bool`
  - `usableCellPositions() → Array<[col,row]>` (cached, row-major, length 3840)
  - `usableCells() → 3840`
  - `cellOrigin(col, row) → [xPx, yPx]`
  - `rawBytesPerFrame() → 2880`, `rsBlockSizes() → number[]`, `dataBytesPerFrame() → 2112`, `fileBytesPerFrame() → 2104`
  - `hexToTile(hex) → Uint8Array(64)`, `tileBits(sym) → Uint8Array(64)` (cached)
  - `encodeHeader({encrypted, fileId, seq, total}) → Uint8Array(8)`
  - `decodeHeader(bytes) → {valid, reason, version, encrypted, fileId, seq, total}`
  - `packCells(raw: Uint8Array) → Uint8Array(3840)` of 6-bit values; `unpackCells(cells) → Uint8Array(2880)`
  - `cellValue(sym, color) → int`, `cellSymbol(v) → int`, `cellColor(v) → int`

- [ ] **Step 1: Append failing tests to test_format.js**

Insert before the final `console.log(\`Results…\`)` line:

```js
const F = require('../format.js');

test('format.js exposes the spec and derived capacities', () => {
  assertEq(F.SPEC.version, 2);
  assertEq(F.usableCells(), 3840);
  assertEq(F.rawBytesPerFrame(), 2880);
  assertEq(F.rsBlockSizes().join(','), '255,255,255,255,255,255,255,255,255,255,255,75');
  assertEq(F.dataBytesPerFrame(), 2112);
  assertEq(F.fileBytesPerFrame(), 2104);
});

test('reserved cells are exactly the four 8x8 corners', () => {
  assert(F.isReservedCell(0, 0) && F.isReservedCell(7, 7) && F.isReservedCell(56, 0) && F.isReservedCell(63, 63) && F.isReservedCell(0, 63));
  assert(!F.isReservedCell(8, 0) && !F.isReservedCell(7, 8) && !F.isReservedCell(55, 63) && !F.isReservedCell(32, 32));
  const pos = F.usableCellPositions();
  assertEq(pos.length, 3840);
  assertEq(pos[0].join(','), '8,0', 'first usable');
  assertEq(pos[pos.length - 1].join(','), '55,63', 'last usable');
});

test('cellOrigin uses quiet zone and pitch', () => {
  assertEq(F.cellOrigin(0, 0).join(','), '16,16');
  assertEq(F.cellOrigin(8, 0).join(','), '88,16');
  assertEq(F.cellOrigin(63, 63).join(','), '583,583');
});

test('tileBits matches spec hex', () => {
  const t = F.tileBits(3);
  assertEq(F.SPEC.tiles[3], R.tileToHex(t));
  let n = 0; for (let i = 0; i < 64; i++) n += t[i];
  assert(n >= 26 && n <= 38, 'fill in range');
});

test('header encode/decode round trip and validation', () => {
  const h = F.encodeHeader({ encrypted: true, fileId: 0xBEEF, seq: 3, total: 12 });
  assertEq(h.length, 8);
  assertEq(h[0], 2); assertEq(h[1], 1);
  assertEq(h[2], 0xBE); assertEq(h[3], 0xEF);
  assertEq(h[4], 0); assertEq(h[5], 3);
  assertEq(h[6], 0); assertEq(h[7], 12);
  const d = F.decodeHeader(h);
  assert(d.valid, 'valid');
  assertEq(d.fileId, 0xBEEF); assertEq(d.seq, 3); assertEq(d.total, 12); assertEq(d.encrypted, true);
  assertEq(F.decodeHeader(new Uint8Array([1, 0, 0, 0, 0, 0, 0, 1])).reason, 'version');
  assertEq(F.decodeHeader(new Uint8Array([2, 2, 0, 0, 0, 0, 0, 1])).reason, 'flags');
  assertEq(F.decodeHeader(new Uint8Array([2, 0, 0, 0, 0, 0, 0, 0])).reason, 'total');
  assertEq(F.decodeHeader(new Uint8Array([2, 0, 0, 0, 0, 5, 0, 5])).reason, 'seq');
  assertEq(F.decodeHeader(new Uint8Array([2, 0, 0])).reason, 'short');
});

test('packCells/unpackCells round trip 2880 bytes MSB-first', () => {
  const raw = new Uint8Array(2880);
  for (let i = 0; i < raw.length; i++) raw[i] = (i * 37 + 11) & 0xFF;
  const cells = F.packCells(raw);
  assertEq(cells.length, 3840);
  // first cell = top 6 bits of raw[0]
  assertEq(cells[0], raw[0] >> 2);
  // second cell = low 2 bits of raw[0] and top 4 bits of raw[1]
  assertEq(cells[1], ((raw[0] & 3) << 4) | (raw[1] >> 4));
  for (const v of cells) assert(v >= 0 && v < 64, '6-bit');
  const back = F.unpackCells(cells);
  assertEq(back.length, 2880);
  for (let i = 0; i < raw.length; i++) if (back[i] !== raw[i]) throw new Error(`byte ${i} differs`);
});

test('cellValue/cellSymbol/cellColor', () => {
  assertEq(F.cellValue(15, 3), 63);
  assertEq(F.cellValue(9, 2), (9 << 2) | 2);
  assertEq(F.cellSymbol(F.cellValue(9, 2)), 9);
  assertEq(F.cellColor(F.cellValue(9, 2)), 2);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd web-app && node tests/test_format.js`
Expected: crash `Cannot find module '../format.js'`.

- [ ] **Step 3: Write format.js**

`web-app/format.js`:

```js
/**
 * format.js — CimBar v2 format constants and pure helpers shared by encoder,
 * decoder and tests. Loads spec/cimbar-v2.json in Node; in the browser the
 * generated format-data.js must be included first (it sets window.CIMBAR_SPEC).
 */
'use strict';

const SPEC = (typeof module !== 'undefined' && module.exports)
  ? require('../spec/cimbar-v2.json')
  : window.CIMBAR_SPEC;

const HEADER_LEN = 8;
const FORMAT_VERSION = 2;
const BITS_PER_CELL = SPEC.bits.symbolBits + SPEC.bits.colorBits; // 6

function isReservedCell(col, row) {
  const n = SPEC.grid.gridCells, c = SPEC.finder.cornerCells;
  const horiz = col < c || col >= n - c;
  const vert = row < c || row >= n - c;
  return horiz && vert;
}

let _positions = null;
function usableCellPositions() {
  if (_positions) return _positions;
  const p = [];
  for (let row = 0; row < SPEC.grid.gridCells; row++) {
    for (let col = 0; col < SPEC.grid.gridCells; col++) {
      if (!isReservedCell(col, row)) p.push([col, row]);
    }
  }
  _positions = p;
  return p;
}

function usableCells() { return usableCellPositions().length; }

function cellOrigin(col, row) {
  return [SPEC.grid.quietPx + col * SPEC.grid.pitchPx, SPEC.grid.quietPx + row * SPEC.grid.pitchPx];
}

function rawBytesPerFrame() { return Math.floor(usableCells() * BITS_PER_CELL / 8); }

function rsBlockSizes() {
  const raw = rawBytesPerFrame();
  const sizes = [];
  let total = 0;
  while (total < raw) {
    const left = raw - total;
    if (left <= SPEC.rs.eccBytes) break;
    const bt = Math.min(SPEC.rs.blockTotal, left);
    sizes.push(bt);
    total += bt;
  }
  return sizes;
}

function dataBytesPerFrame() { return rsBlockSizes().reduce((s, b) => s + b - SPEC.rs.eccBytes, 0); }
function fileBytesPerFrame() { return dataBytesPerFrame() - HEADER_LEN; }

function hexToTile(hex) {
  const t = new Uint8Array(64);
  for (let i = 0; i < 16; i++) {
    const nib = parseInt(hex[i], 16);
    for (let b = 0; b < 4; b++) t[i * 4 + b] = (nib >> (3 - b)) & 1;
  }
  return t;
}

const _tiles = SPEC.tiles.map(hexToTile);
function tileBits(sym) { return _tiles[sym]; }

function encodeHeader(h) {
  const b = new Uint8Array(HEADER_LEN);
  b[0] = FORMAT_VERSION;
  b[1] = h.encrypted ? 1 : 0;
  b[2] = (h.fileId >> 8) & 0xFF; b[3] = h.fileId & 0xFF;
  b[4] = (h.seq >> 8) & 0xFF;    b[5] = h.seq & 0xFF;
  b[6] = (h.total >> 8) & 0xFF;  b[7] = h.total & 0xFF;
  return b;
}

function decodeHeader(bytes) {
  const h = { valid: false, reason: '', version: 0, encrypted: false, fileId: 0, seq: 0, total: 0 };
  if (!bytes || bytes.length < HEADER_LEN) { h.reason = 'short'; return h; }
  h.version = bytes[0];
  const flags = bytes[1];
  h.encrypted = (flags & 1) === 1;
  h.fileId = (bytes[2] << 8) | bytes[3];
  h.seq = (bytes[4] << 8) | bytes[5];
  h.total = (bytes[6] << 8) | bytes[7];
  if (h.version !== FORMAT_VERSION) { h.reason = 'version'; return h; }
  if ((flags & 0xFE) !== 0) { h.reason = 'flags'; return h; }
  if (h.total < 1) { h.reason = 'total'; return h; }
  if (h.seq >= h.total) { h.reason = 'seq'; return h; }
  h.valid = true;
  return h;
}

function packCells(raw) {
  const n = usableCells();
  const out = new Uint8Array(n);
  let bitPos = 0;
  for (let k = 0; k < n; k++) {
    let v = 0;
    for (let b = 0; b < BITS_PER_CELL; b++) {
      const byte = bitPos >> 3, bit = 7 - (bitPos & 7);
      const d = byte < raw.length ? (raw[byte] >> bit) & 1 : 0;
      v = (v << 1) | d;
      bitPos++;
    }
    out[k] = v;
  }
  return out;
}

function unpackCells(cells) {
  const raw = new Uint8Array(rawBytesPerFrame());
  let bitPos = 0;
  for (let k = 0; k < cells.length; k++) {
    for (let b = BITS_PER_CELL - 1; b >= 0; b--) {
      if ((cells[k] >> b) & 1) raw[bitPos >> 3] |= 1 << (7 - (bitPos & 7));
      bitPos++;
    }
  }
  return raw;
}

function cellValue(sym, color) { return ((sym & 0xF) << SPEC.bits.colorBits) | (color & 0x3); }
function cellSymbol(v) { return (v >> SPEC.bits.colorBits) & 0xF; }
function cellColor(v) { return v & 0x3; }

const API = {
  SPEC, HEADER_LEN, FORMAT_VERSION, BITS_PER_CELL,
  isReservedCell, usableCellPositions, usableCells, cellOrigin,
  rawBytesPerFrame, rsBlockSizes, dataBytesPerFrame, fileBytesPerFrame,
  hexToTile, tileBits,
  encodeHeader, decodeHeader,
  packCells, unpackCells, cellValue, cellSymbol, cellColor,
};

if (typeof module !== 'undefined' && module.exports) module.exports = API;
else window.CimbarFormat = API;
```

- [ ] **Step 4: Run tests**

Run: `cd web-app && node tests/test_format.js`
Expected: `Results: 13 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add web-app/format.js web-app/tests/test_format.js
git commit -m "Add format.js: v2 geometry, header codec and cell bit packing

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: cimbar.js v2 — renderer, exact decoder, RS framing, frame split/assembly

**Files:**
- Rewrite: `web-app/cimbar.js` (entire file replaced)
- Test: `web-app/tests/test_frame.js`
- Delete: `web-app/tests/test_symbols.js` (tests v1 `drawSymbol`)

**Interfaces:**
- Consumes: `CimbarFormat` (Task 3), `ReedSolomon` from `rs.js` (`new ReedSolomon(64)`, `encode(data) → data+ecc`, `decode(block) → data or throws`).
- Produces (module `Cimbar`, also `window.Cimbar`):
  - `renderFrame(ctx, raw: Uint8Array(2880))` draws a 608×608 frame
  - `decodeFrameExact(imageData) → { raw: Uint8Array(2880), cells: Uint8Array(3840), diag: { hammingMax, hammingMean, colorMarginMin } }`
  - `encodeRSFrame(data: Uint8Array(≤2112), rs) → Uint8Array(2880)`
  - `decodeRSFrame(raw, rs) → { data: Uint8Array(2112), blocksOk, blocksFailed }`
  - `splitIntoFrames(framedData, fileId, encrypted) → Uint8Array(2112)[]`
  - `class FrameAssembler { add(data2112) → {accepted, reason, header}; get total; get filled; isComplete(); framedData() → Uint8Array }`
  - `buildPayload(fileName, fileBytes) → Uint8Array`, `parsePayload(bytes) → {fileName, fileBytes}`
  - `withLengthPrefix(bytes) → Uint8Array`, `stripLengthPrefix(bytes) → Uint8Array` (throws on invalid)

- [ ] **Step 1: Write the failing test**

`web-app/tests/test_frame.js`:

```js
'use strict';
const { MockCanvas } = require('./mock_canvas.js');
const { ReedSolomon } = require('../rs.js');
const F = require('../format.js');
const C = require('../cimbar.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function assertBytes(a, b, msg) {
  assertEq(a.length, b.length, (msg || '') + ' length');
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) throw new Error(`${msg || ''} byte ${i}: ${a[i]} != ${b[i]}`);
}
function px(img, x, y) { const i = (y * img.width + x) * 4; return [img.data[i], img.data[i + 1], img.data[i + 2]]; }
function seqBytes(n, mul, add) { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = (i * mul + add) & 0xFF; return b; }

console.log('\ntest_frame.js');

const FRAME = F.SPEC.grid.framePx;

test('renderFrame paints finders per spec', () => {
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), new Uint8Array(2880));
  const img = cv.getImageData(0, 0, FRAME, FRAME);
  assertEq(px(img, 0, 0).join(','), '0,0,0', 'quiet zone black');
  assertEq(px(img, 16, 16).join(','), '255,255,255', 'TL outer ring white');
  assertEq(px(img, 16 + 9, 16 + 9).join(','), '0,0,0', 'TL black ring');
  assertEq(px(img, 16 + 18, 16 + 18).join(','), '255,255,255', 'TL core white');
  assertEq(px(img, 16 + 31, 16 + 31).join(','), '255,255,255', 'TL core center white (no dot)');
  assertEq(px(img, 529 + 31, 16 + 31).join(','), '0,0,0', 'TR core center black (dot)');
  assertEq(px(img, 16 + 31, 529 + 31).join(','), '0,0,0', 'BL core center black (dot)');
  assertEq(px(img, 529 + 31, 529 + 31).join(','), '0,0,0', 'BR core center black (dot)');
  assertEq(px(img, 529 + 18, 16 + 18).join(','), '255,255,255', 'TR core corner white');
  assertEq(px(img, 16 + 63, 16 + 63).join(','), '0,0,0', 'separator cell black');
  assertEq(px(img, 16 + 63, 16).join(','), '0,0,0', 'separator column right of TL finder black');
});

test('renderFrame paints cell (8,0) with symbol/color from raw bits', () => {
  const raw = new Uint8Array(2880);
  raw[0] = (F.cellValue(5, 2) << 2); // first cell = top 6 bits
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), raw);
  const img = cv.getImageData(0, 0, FRAME, FRAME);
  const [ox, oy] = F.cellOrigin(8, 0);
  const t = F.tileBits(5);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const expected = t[y * 8 + x] ? F.SPEC.palette[2].join(',') : '0,0,0';
    assertEq(px(img, ox + x, oy + y).join(','), expected, `pixel ${x},${y}`);
  }
  assertEq(px(img, ox + 8, oy).join(','), '0,0,0', 'gap after cell');
});

test('render -> decodeFrameExact round trip on random raw bytes', () => {
  const raw = seqBytes(2880, 131, 7);
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), raw);
  const r = C.decodeFrameExact(cv.getImageData(0, 0, FRAME, FRAME));
  assertBytes(r.raw, raw, 'raw');
  assertEq(r.diag.hammingMax, 0, 'exact hashes');
  assert(r.diag.colorMarginMin > 100, 'colors well separated');
});

test('encodeRSFrame/decodeRSFrame round trip and error correction', () => {
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const data = seqBytes(2112, 3, 1);
  const raw = C.encodeRSFrame(data, rs);
  assertEq(raw.length, 2880);
  const clean = C.decodeRSFrame(raw, rs);
  assertBytes(clean.data, data, 'clean');
  assertEq(clean.blocksOk, 12); assertEq(clean.blocksFailed, 0);
  // corrupt 30 bytes spread across the frame (interleaving spreads them over blocks)
  const bad = raw.slice();
  for (let i = 0; i < 30; i++) bad[i * 90] ^= 0xFF;
  const fixed = C.decodeRSFrame(bad, rs);
  assertBytes(fixed.data, data, 'corrected');
  assertEq(fixed.blocksFailed, 0);
});

test('decodeRSFrame reports failed blocks and zero-fills them', () => {
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const raw = C.encodeRSFrame(seqBytes(2112, 3, 1), rs);
  const bad = raw.slice();
  // Non-constant corruption: XOR by a constant could land on another valid RS codeword.
  for (let i = 0; i < 2880; i++) bad[i] ^= ((i * 37 + 11) & 0xFE) | 1;
  const r = C.decodeRSFrame(bad, rs);
  assertEq(r.blocksFailed, 12);
});

test('splitIntoFrames writes headers and pads the last frame', () => {
  const per = F.fileBytesPerFrame();
  const framed = seqBytes(per * 2 + 5, 1, 0);
  const frames = C.splitIntoFrames(framed, 0x1234, true);
  assertEq(frames.length, 3);
  frames.forEach((f, i) => {
    assertEq(f.length, 2112);
    const h = F.decodeHeader(f);
    assert(h.valid, 'valid header'); assertEq(h.seq, i); assertEq(h.total, 3); assertEq(h.fileId, 0x1234); assertEq(h.encrypted, true);
  });
  assertEq(frames[2][8 + 5], 0, 'zero padded');
  assertEq(frames[1][8], framed[per], 'second frame starts at byte per');
  assertEq(C.splitIntoFrames(new Uint8Array(0), 1, false).length, 1, 'empty input still yields one frame');
});

test('FrameAssembler accepts, dedups, rejects and completes', () => {
  const per = F.fileBytesPerFrame();
  const framed = seqBytes(per + 10, 5, 2);
  const frames = C.splitIntoFrames(framed, 7, false);
  const a = new C.FrameAssembler();
  assertEq(a.add(frames[1]).accepted, true);
  assertEq(a.total, 2); assertEq(a.filled, 1); assert(!a.isComplete());
  assertEq(a.add(frames[1]).reason, 'duplicate');
  const other = C.splitIntoFrames(framed, 8, false)[0];
  assertEq(a.add(other).reason, 'fileId');
  const badVer = frames[0].slice(); badVer[0] = 1;
  assertEq(a.add(badVer).reason, 'version');
  assertEq(a.add(frames[0]).accepted, true);
  assert(a.isComplete());
  const out = a.framedData();
  assertEq(out.length, per * 2);
  assertBytes(out.subarray(0, framed.length), framed, 'payload prefix');
});

test('payload helpers round trip', () => {
  const p = C.buildPayload('hello.txt', new Uint8Array([1, 2, 3]));
  const parsed = C.parsePayload(p);
  assertEq(parsed.fileName, 'hello.txt');
  assertBytes(parsed.fileBytes, new Uint8Array([1, 2, 3]));
  const withLen = C.withLengthPrefix(p);
  assertEq(withLen.length, p.length + 4);
  const padded = new Uint8Array(withLen.length + 50); padded.set(withLen);
  assertBytes(C.stripLengthPrefix(padded), p, 'strip');
  let threw = false;
  try { C.stripLengthPrefix(new Uint8Array([0, 0, 0, 99, 1])); } catch (e) { threw = true; }
  assert(threw, 'invalid length throws');
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

- [ ] **Step 2: Run to verify failure**

Run: `cd web-app && node tests/test_frame.js`
Expected: failures such as `C.renderFrame is not a function`.

- [ ] **Step 3: Replace cimbar.js**

`web-app/cimbar.js` (full file):

```js
/**
 * cimbar.js — CimBar v2 frame rendering, exact decoding, RS framing and
 * frame assembly. All constants come from format.js (spec/cimbar-v2.json).
 *
 * Frame layout: 64x64 cells, 8 px tiles with 1 px gaps, four 7x7-cell finders,
 * 6 bits per cell (4 symbol + 2 color), 2880 raw bytes per frame, RS(255,191).
 */
'use strict';

const Fmt = (typeof module !== 'undefined' && module.exports)
  ? require('./format.js')
  : window.CimbarFormat;
const SPEC = Fmt.SPEC;

// ── Rendering ────────────────────────────────────────────────────────────

function rgbStr(c) { return `rgb(${c[0]},${c[1]},${c[2]})`; }

function drawTile(ctx, sym, colorIdx, ox, oy) {
  const t = Fmt.tileBits(sym);
  ctx.fillStyle = rgbStr(SPEC.palette[colorIdx]);
  for (let y = 0; y < 8; y++) {
    let x = 0;
    while (x < 8) {
      if (t[y * 8 + x]) {
        let x2 = x;
        while (x2 < 8 && t[y * 8 + x2]) x2++;
        ctx.fillRect(ox + x, oy + y, x2 - x, 1);
        x = x2;
      } else {
        x++;
      }
    }
  }
}

function finderOrigin(corner) {
  const [cx, cy] = SPEC.finder.centers[corner];
  const half = SPEC.finder.outerPx / 2;
  return [
    Math.round(SPEC.grid.quietPx + cx * SPEC.grid.pitchPx - half),
    Math.round(SPEC.grid.quietPx + cy * SPEC.grid.pitchPx - half),
  ];
}

function drawFinder(ctx, corner) {
  const F = SPEC.finder;
  const [ox, oy] = finderOrigin(corner);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(ox, oy, F.outerPx, F.outerPx);
  ctx.fillStyle = '#000000';
  ctx.fillRect(ox + F.ringInsetPx, oy + F.ringInsetPx, F.outerPx - 2 * F.ringInsetPx, F.outerPx - 2 * F.ringInsetPx);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(ox + F.coreInsetPx, oy + F.coreInsetPx, F.corePx, F.corePx);
  if (F.dotOn.indexOf(corner) >= 0) {
    ctx.fillStyle = '#000000';
    ctx.fillRect(ox + F.dotInsetPx, oy + F.dotInsetPx, F.dotPx, F.dotPx);
  }
}

/** Draw one full 608x608 frame from 2880 raw (RS-encoded, interleaved) bytes. */
function renderFrame(ctx, raw) {
  const size = SPEC.grid.framePx;
  ctx.fillStyle = '#000000';
  ctx.fillRect(0, 0, size, size);
  const cells = Fmt.packCells(raw);
  const pos = Fmt.usableCellPositions();
  for (let k = 0; k < pos.length; k++) {
    const [ox, oy] = Fmt.cellOrigin(pos[k][0], pos[k][1]);
    drawTile(ctx, Fmt.cellSymbol(cells[k]), Fmt.cellColor(cells[k]), ox, oy);
  }
  for (const corner of ['tl', 'tr', 'bl', 'br']) drawFinder(ctx, corner);
}

// ── Exact decoding (GIF path: pixels are exactly where the encoder put them) ──

function lumaAt(d, i) { return 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]; }

/**
 * Decode a frame whose pixels are at exact spec positions (an ImageData of at
 * least framePx x framePx). Returns raw bytes, cell values and diagnostics.
 */
function decodeFrameExact(imageData) {
  const size = SPEC.grid.framePx;
  if (imageData.width < size || imageData.height < size) {
    throw new Error(`Frame must be at least ${size}x${size} px, got ${imageData.width}x${imageData.height}`);
  }
  const W = imageData.width, d = imageData.data;
  const pos = Fmt.usableCellPositions();
  const cells = new Uint8Array(pos.length);
  const lum = new Float32Array(64);
  const rgb = new Float32Array(192);
  let hammingMax = 0, hammingSum = 0, colorMarginMin = Infinity;

  for (let k = 0; k < pos.length; k++) {
    const [ox, oy] = Fmt.cellOrigin(pos[k][0], pos[k][1]);
    let mean = 0;
    for (let y = 0; y < 8; y++) {
      for (let x = 0; x < 8; x++) {
        const i = ((oy + y) * W + (ox + x)) * 4;
        const p = y * 8 + x;
        lum[p] = lumaAt(d, i);
        mean += lum[p];
        rgb[p * 3] = d[i]; rgb[p * 3 + 1] = d[i + 1]; rgb[p * 3 + 2] = d[i + 2];
      }
    }
    mean /= 64;

    let bestSym = 0, bestDist = 65;
    for (let s = 0; s < 16; s++) {
      const t = Fmt.tileBits(s);
      let dist = 0;
      for (let p = 0; p < 64; p++) dist += (lum[p] > mean ? 1 : 0) ^ t[p];
      if (dist < bestDist) { bestDist = dist; bestSym = s; }
    }
    hammingSum += bestDist;
    if (bestDist > hammingMax) hammingMax = bestDist;

    const t = Fmt.tileBits(bestSym);
    let r = 0, g = 0, b = 0, n = 0;
    for (let p = 0; p < 64; p++) {
      if (t[p]) { r += rgb[p * 3]; g += rgb[p * 3 + 1]; b += rgb[p * 3 + 2]; n++; }
    }
    r /= n; g /= n; b /= n;
    let bestC = 0, bestD = Infinity, secondD = Infinity;
    for (let c = 0; c < SPEC.palette.length; c++) {
      const pc = SPEC.palette[c];
      const dd = (r - pc[0]) * (r - pc[0]) + (g - pc[1]) * (g - pc[1]) + (b - pc[2]) * (b - pc[2]);
      if (dd < bestD) { secondD = bestD; bestD = dd; bestC = c; }
      else if (dd < secondD) { secondD = dd; }
    }
    const margin = Math.sqrt(secondD) - Math.sqrt(bestD);
    if (margin < colorMarginMin) colorMarginMin = margin;

    cells[k] = Fmt.cellValue(bestSym, bestC);
  }

  return {
    raw: Fmt.unpackCells(cells),
    cells,
    diag: { hammingMax, hammingMean: hammingSum / pos.length, colorMarginMin },
  };
}

// ── Reed-Solomon framing ─────────────────────────────────────────────────

function interleave(blocks, rawLen) {
  const out = new Uint8Array(rawLen);
  const N = blocks.length;
  let maxLen = 0;
  for (const b of blocks) if (b.length > maxLen) maxLen = b.length;
  let pos = 0;
  for (let j = 0; j < maxLen; j++) {
    for (let i = 0; i < N; i++) {
      if (j < blocks[i].length) out[pos++] = blocks[i][j];
    }
  }
  return out;
}

/** RS-encode up to dataBytesPerFrame() bytes into the frame's raw bytes. */
function encodeRSFrame(data, rs) {
  const sizes = Fmt.rsBlockSizes();
  const blocks = [];
  let off = 0;
  for (const bt of sizes) {
    const bd = bt - SPEC.rs.eccBytes;
    const chunk = new Uint8Array(bd);
    const take = Math.max(0, Math.min(bd, data.length - off));
    if (take > 0) chunk.set(data.subarray(off, off + take));
    off += take;
    blocks.push(rs.encode(chunk));
  }
  return interleave(blocks, Fmt.rawBytesPerFrame());
}

/** Inverse of encodeRSFrame. Failed blocks are zero-filled and counted. */
function decodeRSFrame(raw, rs) {
  const sizes = Fmt.rsBlockSizes();
  const N = sizes.length;
  const blocks = sizes.map(s => new Uint8Array(s));
  let maxLen = 0;
  for (const s of sizes) if (s > maxLen) maxLen = s;
  let pos = 0;
  for (let j = 0; j < maxLen; j++) {
    for (let i = 0; i < N; i++) {
      if (j < sizes[i]) { blocks[i][j] = pos < raw.length ? raw[pos] : 0; pos++; }
    }
  }
  const data = new Uint8Array(Fmt.dataBytesPerFrame());
  let off = 0, blocksOk = 0, blocksFailed = 0;
  for (let i = 0; i < N; i++) {
    const bd = sizes[i] - SPEC.rs.eccBytes;
    try {
      const dec = rs.decode(blocks[i]);
      data.set(dec.subarray(0, bd), off);
      blocksOk++;
    } catch (e) {
      blocksFailed++;
    }
    off += bd;
  }
  return { data, blocksOk, blocksFailed };
}

// ── Frame split and assembly ─────────────────────────────────────────────

/** Split framed data into per-frame data arrays (header + chunk, zero padded). */
function splitIntoFrames(framedData, fileId, encrypted) {
  const per = Fmt.fileBytesPerFrame();
  const total = Math.max(1, Math.ceil(framedData.length / per));
  if (total > 65535) throw new Error(`File too large: needs ${total} frames (max 65535)`);
  const frames = [];
  for (let seq = 0; seq < total; seq++) {
    const f = new Uint8Array(Fmt.dataBytesPerFrame());
    f.set(Fmt.encodeHeader({ encrypted, fileId, seq, total }), 0);
    const start = seq * per;
    const end = Math.min(framedData.length, start + per);
    if (end > start) f.set(framedData.subarray(start, end), Fmt.HEADER_LEN);
    frames.push(f);
  }
  return frames;
}

class FrameAssembler {
  constructor() { this.reset(); }

  reset() {
    this.fileId = null;
    this.total = 0;
    this.encrypted = false;
    this.slots = [];
    this.filled = 0;
  }

  /** data: Uint8Array(dataBytesPerFrame) after RS decode. */
  add(data) {
    const h = Fmt.decodeHeader(data);
    if (!h.valid) return { accepted: false, reason: h.reason, header: h };
    if (this.fileId !== null && h.fileId !== this.fileId) return { accepted: false, reason: 'fileId', header: h };
    if (this.fileId !== null && h.total !== this.total) return { accepted: false, reason: 'total', header: h };
    if (this.fileId === null) {
      this.fileId = h.fileId;
      this.total = h.total;
      this.encrypted = h.encrypted;
      this.slots = new Array(h.total).fill(null);
    }
    if (this.slots[h.seq]) return { accepted: false, reason: 'duplicate', header: h };
    this.slots[h.seq] = data.slice(Fmt.HEADER_LEN);
    this.filled++;
    return { accepted: true, reason: '', header: h };
  }

  isComplete() { return this.total > 0 && this.filled === this.total; }

  /** Concatenated frame bodies (still carries the u32 length prefix + zero padding). */
  framedData() {
    if (!this.isComplete()) throw new Error(`Incomplete: ${this.filled}/${this.total} frames`);
    const per = Fmt.fileBytesPerFrame();
    const out = new Uint8Array(per * this.total);
    for (let i = 0; i < this.total; i++) out.set(this.slots[i], i * per);
    return out;
  }
}

// ── File container helpers ───────────────────────────────────────────────

function buildPayload(fileName, fileBytes) {
  const nameBytes = new TextEncoder().encode(fileName);
  const out = new Uint8Array(4 + nameBytes.length + fileBytes.length);
  new DataView(out.buffer).setUint32(0, nameBytes.length, false);
  out.set(nameBytes, 4);
  out.set(fileBytes, 4 + nameBytes.length);
  return out;
}

function parsePayload(bytes) {
  if (bytes.length < 4) throw new Error('Header corrupt: payload too short');
  const nameLen = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, false);
  if (nameLen > 512 || 4 + nameLen > bytes.length) throw new Error('Header corrupt: filename length invalid');
  return {
    fileName: new TextDecoder().decode(bytes.subarray(4, 4 + nameLen)),
    fileBytes: bytes.slice(4 + nameLen),
  };
}

function withLengthPrefix(bytes) {
  const out = new Uint8Array(4 + bytes.length);
  new DataView(out.buffer).setUint32(0, bytes.length, false);
  out.set(bytes, 4);
  return out;
}

function stripLengthPrefix(bytes) {
  if (bytes.length < 4) throw new Error('Header corrupt: missing length prefix');
  const len = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, false);
  if (len < 1 || len > bytes.length - 4) throw new Error(`Header corrupt: payload length ${len} is invalid`);
  return bytes.slice(4, 4 + len);
}

const API = {
  renderFrame, decodeFrameExact,
  encodeRSFrame, decodeRSFrame,
  splitIntoFrames, FrameAssembler,
  buildPayload, parsePayload, withLengthPrefix, stripLengthPrefix,
  // exported for tests
  drawTile, drawFinder, finderOrigin,
};

if (typeof module !== 'undefined' && module.exports) module.exports = API;
else window.Cimbar = API;
```

- [ ] **Step 4: Run tests, delete the v1 symbol test**

Run: `cd web-app && node tests/test_frame.js`
Expected: `Results: 9 passed, 0 failed`.

Run: `git rm web-app/tests/test_symbols.js` (it imports v1 `drawSymbol`; `run_all.sh` is fixed in Task 8).

- [ ] **Step 5: Commit**

```bash
git add web-app/cimbar.js web-app/tests/test_frame.js
git commit -m "Replace cimbar.js with v2 renderer, exact decoder, RS framing and assembler

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: GIF palette from the spec

**Files:**
- Modify: `web-app/gif-encoder.js` (`buildPalette`, lines ~105–168, and the module header/exports)
- Modify: `web-app/tests/test_frame.js` (append one test)

**Interfaces:**
- Consumes: `CimbarFormat.SPEC.palette`.
- Produces: GIF global color table slots 0–3 = palette, 4 = black, 5 = white; unchanged `GifEncoder` API.

- [ ] **Step 1: Append failing test to test_frame.js**

Insert before the final `console.log(\`Results…\`)` line:

```js
test('GIF round trip keeps v2 pixels exact', () => {
  global.ImageData = global.ImageData || class ImageData {
    constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
  };
  global.Blob = global.Blob || class Blob {
    constructor(parts) {
      const flat = parts.map(p => p instanceof Uint8Array ? p : new Uint8Array(p));
      let total = 0; flat.forEach(a => total += a.length);
      this._data = new Uint8Array(total);
      let off = 0; flat.forEach(a => { this._data.set(a, off); off += a.length; });
    }
    get size() { return this._data.length; }
  };
  const { GifEncoder } = require('../gif-encoder.js');
  const { GifDecoder } = require('../gif-decoder.js');
  const raw = seqBytes(2880, 17, 3);
  const cv = new MockCanvas(FRAME, FRAME);
  C.renderFrame(cv.getContext('2d'), raw);
  const enc = new GifEncoder(FRAME, FRAME, 20);
  enc.addFrame(cv);
  const gif = enc.finish()._data;
  assertEq(gif[10] & 0x07, 7, 'global color table 256 entries');
  const pal = gif.subarray(13, 13 + 768);
  for (let c = 0; c < 4; c++) assertEq([pal[c * 3], pal[c * 3 + 1], pal[c * 3 + 2]].join(','), F.SPEC.palette[c].join(','), `palette slot ${c}`);
  assertEq([pal[12], pal[13], pal[14]].join(','), '0,0,0', 'slot 4 black');
  assertEq([pal[15], pal[16], pal[17]].join(','), '255,255,255', 'slot 5 white');
  const frames = new GifDecoder(gif).decode();
  assertEq(frames.length, 1);
  const r = C.decodeFrameExact(frames[0].imageData);
  assertBytes(r.raw, raw, 'after GIF');
  assertEq(r.diag.hammingMax, 0);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd web-app && node tests/test_frame.js`
Expected: the new test fails on `palette slot 0` (old palette starts with `0,200,200`).

- [ ] **Step 3: Replace buildPalette**

In `web-app/gif-encoder.js`, add after `'use strict';`:

```js
const GifFmt = (typeof module !== 'undefined' && module.exports)
  ? require('./format.js')
  : window.CimbarFormat;
```

Replace the whole `buildPalette` function with:

```js
/**
 * Build a 256-color palette (768 bytes).
 * Slots 0-3: the v2 palette, slot 4: black, slot 5: white,
 * then a grayscale ramp and a 6x6x6 cube so non-barcode pixels quantize sanely.
 */
function buildPalette() {
  const pal = new Uint8Array(256 * 3);
  let idx = 0;
  const fixed = GifFmt.SPEC.palette.concat([[0, 0, 0], [255, 255, 255]]);
  for (const [r, g, b] of fixed) {
    pal[idx * 3] = r; pal[idx * 3 + 1] = g; pal[idx * 3 + 2] = b;
    idx++;
  }
  for (let v = 0; v <= 255 && idx < 256; v += 8) {
    pal[idx * 3] = pal[idx * 3 + 1] = pal[idx * 3 + 2] = v;
    idx++;
  }
  for (let r = 0; r < 6 && idx < 256; r++) {
    for (let g = 0; g < 6 && idx < 256; g++) {
      for (let b = 0; b < 6 && idx < 256; b++) {
        pal[idx * 3] = r * 51; pal[idx * 3 + 1] = g * 51; pal[idx * 3 + 2] = b * 51;
        idx++;
      }
    }
  }
  return pal;
}
```

Update the file header comment's line "Uses LZW compression with a fixed global color table derived from CimBar colors." to "...derived from the v2 spec palette (format.js must be loaded first)."

- [ ] **Step 4: Run tests**

Run: `cd web-app && node tests/test_frame.js`
Expected: `Results: 10 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add web-app/gif-encoder.js web-app/tests/test_frame.js
git commit -m "Build GIF palette from the v2 spec palette

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Golden generator and golden tests

**Files:**
- Create: `web-app/tools/node_crypto.js` (Node AES-GCM matching crypto.js wire format, deterministic salt/iv for goldens)
- Create: `web-app/tools/gen_goldens.js`
- Create: `test-data/goldens/*.gif`, `*.json` (generated, committed)
- Test: `web-app/tests/test_goldens.js`

**Interfaces:**
- Produces sidecar JSON schema (consumed by the Dart plans):

```json
{
  "name": "lorem_12k",
  "fileName": "lorem_12k.bin",
  "fileBytesBase64": "...",
  "passphrase": null,
  "fileId": 4660,
  "total": 6,
  "delayMs": 200,
  "framedDataLength": 12345,
  "frames": [
    { "seq": 0, "header": { "version": 2, "encrypted": false, "fileId": 4660, "seq": 0, "total": 6 },
      "dataHex": "…2112 bytes…", "rawHex": "…2880 bytes…", "cells": [3840 ints 0..63] }
  ]
}
```
- Produces: `node_crypto.js` exports `encryptBytesNode(data, pass, salt16, iv12) → Uint8Array` and `decryptBytesNode(wire, pass) → Uint8Array`.

- [ ] **Step 1: Write the failing golden test**

`web-app/tests/test_goldens.js`:

```js
'use strict';
const fs = require('fs');
const path = require('path');
global.ImageData = global.ImageData || class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
const { GifDecoder } = require('../gif-decoder.js');
const { ReedSolomon } = require('../rs.js');
const F = require('../format.js');
const C = require('../cimbar.js');
const { decryptBytesNode } = require('../tools/node_crypto.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function hex(bytes) { let s = ''; for (const b of bytes) s += b.toString(16).padStart(2, '0'); return s; }

const dir = path.join(__dirname, '..', '..', 'test-data', 'goldens');
const names = fs.readdirSync(dir).filter(f => f.endsWith('.json')).map(f => f.replace(/\.json$/, '')).sort();

console.log('\ntest_goldens.js');
assert(names.length >= 5, `expected at least 5 goldens, found ${names.length}`);

for (const name of names) {
  test(`golden ${name}: frames, cells, headers and payload match sidecar`, () => {
    const side = JSON.parse(fs.readFileSync(path.join(dir, name + '.json'), 'utf8'));
    const gif = new Uint8Array(fs.readFileSync(path.join(dir, name + '.gif')));
    const frames = new GifDecoder(gif).decode();
    assertEq(frames.length, side.total, 'frame count');
    assertEq(frames[0].width, F.SPEC.grid.framePx, 'frame width');
    const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
    const asm = new C.FrameAssembler();
    for (let i = 0; i < frames.length; i++) {
      const r = C.decodeFrameExact(frames[i].imageData);
      assertEq(r.diag.hammingMax, 0, `frame ${i} exact hashes`);
      assertEq(hex(r.raw), side.frames[i].rawHex, `frame ${i} raw`);
      assertEq(Array.from(r.cells).join(','), side.frames[i].cells.join(','), `frame ${i} cells`);
      const d = C.decodeRSFrame(r.raw, rs);
      assertEq(d.blocksFailed, 0, `frame ${i} RS`);
      assertEq(hex(d.data), side.frames[i].dataHex, `frame ${i} data`);
      const h = F.decodeHeader(d.data);
      assertEq(JSON.stringify({ version: h.version, encrypted: h.encrypted, fileId: h.fileId, seq: h.seq, total: h.total }),
        JSON.stringify(side.frames[i].header), `frame ${i} header`);
      assert(asm.add(d.data).accepted, `frame ${i} accepted`);
    }
    assert(asm.isComplete(), 'complete');
    let payload = C.stripLengthPrefix(asm.framedData());
    if (side.passphrase !== null) {
      assert(payload[0] === 0xCB && payload[1] === 0x42, 'encrypted magic');
      payload = decryptBytesNode(payload, side.passphrase);
    }
    const parsed = C.parsePayload(payload);
    assertEq(parsed.fileName, side.fileName, 'file name');
    const expected = Buffer.from(side.fileBytesBase64, 'base64');
    assertEq(parsed.fileBytes.length, expected.length, 'file length');
    for (let i = 0; i < expected.length; i++) if (parsed.fileBytes[i] !== expected[i]) throw new Error(`file byte ${i} differs`);
  });
}

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

- [ ] **Step 2: Run to verify failure**

Run: `cd web-app && node tests/test_goldens.js`
Expected: crash `Cannot find module '../tools/node_crypto.js'`.

- [ ] **Step 3: Write node_crypto.js**

`web-app/tools/node_crypto.js`:

```js
'use strict';
/**
 * node_crypto.js — Node implementation of the crypto.js wire format so goldens
 * can be generated and verified without Web Crypto (Node 14 has none).
 * Wire: [CB 42 01 00][16 salt][12 iv][ciphertext][16 tag], PBKDF2-SHA256 150000 iters.
 */
const crypto = require('crypto');
const MAGIC = Buffer.from([0xCB, 0x42, 0x01, 0x00]);
const ITERATIONS = 150000;

function encryptBytesNode(data, passphrase, salt, iv) {
  if (salt.length !== 16 || iv.length !== 12) throw new Error('salt must be 16 bytes, iv 12 bytes');
  const key = crypto.pbkdf2Sync(passphrase, Buffer.from(salt), ITERATIONS, 32, 'sha256');
  const cipher = crypto.createCipheriv('aes-256-gcm', key, Buffer.from(iv));
  const ct = Buffer.concat([cipher.update(Buffer.from(data)), cipher.final()]);
  const tag = cipher.getAuthTag();
  return new Uint8Array(Buffer.concat([MAGIC, Buffer.from(salt), Buffer.from(iv), ct, tag]));
}

function decryptBytesNode(wire, passphrase) {
  const w = Buffer.from(wire);
  if (w[0] !== 0xCB || w[1] !== 0x42) throw new Error('Invalid file: missing CimBar magic header');
  if (w[2] !== 0x01) throw new Error(`Unsupported format version: ${w[2]}`);
  const salt = w.subarray(4, 20), iv = w.subarray(20, 32);
  const ct = w.subarray(32, w.length - 16), tag = w.subarray(w.length - 16);
  const key = crypto.pbkdf2Sync(passphrase, salt, ITERATIONS, 32, 'sha256');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return new Uint8Array(Buffer.concat([decipher.update(ct), decipher.final()]));
}

module.exports = { encryptBytesNode, decryptBytesNode, ITERATIONS };
```

- [ ] **Step 4: Write gen_goldens.js**

`web-app/tools/gen_goldens.js`:

```js
'use strict';
/**
 * gen_goldens.js — renders reference GIFs with the production encoder and
 * writes JSON sidecars with full ground truth (payload, per-frame header, raw
 * bytes, per-cell values). Output: test-data/goldens/<name>.{gif,json}.
 * Deterministic: fixed seeds, fixed fileIds, fixed salt/iv.
 * Usage: node tools/gen_goldens.js
 */
const fs = require('fs');
const path = require('path');
global.ImageData = global.ImageData || class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
global.Blob = global.Blob || class Blob {
  constructor(parts) {
    const flat = parts.map(p => p instanceof Uint8Array ? p : new Uint8Array(p));
    let total = 0; flat.forEach(a => total += a.length);
    this._data = new Uint8Array(total);
    let off = 0; flat.forEach(a => { this._data.set(a, off); off += a.length; });
  }
  get size() { return this._data.length; }
};
const { MockCanvas } = require('../tests/mock_canvas.js');
const { GifEncoder } = require('../gif-encoder.js');
const { ReedSolomon } = require('../rs.js');
const F = require('../format.js');
const C = require('../cimbar.js');
const { encryptBytesNode } = require('./node_crypto.js');
const { mulberry32 } = require('./gen_tiles.js');

const outDir = path.join(__dirname, '..', '..', 'test-data', 'goldens');
const PER = F.fileBytesPerFrame();
const DELAY_MS = F.SPEC.gif.defaultDelayMs;

function randomBytes(n, seed) {
  const rnd = mulberry32(seed);
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = Math.floor(rnd() * 256);
  return b;
}
function fixedBytes(n, start) { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = (start + i) & 0xFF; return b; }
function hex(bytes) { let s = ''; for (const b of bytes) s += b.toString(16).padStart(2, '0'); return s; }

// Payload sizes are chosen so that framedData (4 + 4 + nameLen + fileLen [+ 48 crypto overhead]) hits the edges.
const nameLen = (n) => Buffer.byteLength(n, 'utf8');
const CASES = [
  { name: 'hello', fileName: 'hello.txt', bytes: new Uint8Array(Buffer.from('Hello, CimBar v2!\n', 'utf8')), passphrase: null, fileId: 0x1001 },
  { name: 'lorem_12k', fileName: 'lorem_12k.bin', bytes: randomBytes(12000, 42), passphrase: null, fileId: 0x1002 },
  { name: 'lorem_12k_enc', fileName: 'lorem_12k.bin', bytes: randomBytes(12000, 42), passphrase: 'test123', fileId: 0x1003 },
  { name: 'edge_one_frame', fileName: 'e.bin', bytes: null, passphrase: null, fileId: 0x1004, framedLen: PER },
  { name: 'edge_two_frames', fileName: 'e.bin', bytes: null, passphrase: null, fileId: 0x1005, framedLen: PER + 1 },
];
for (const c of CASES) {
  if (c.framedLen) c.bytes = fixedBytes(c.framedLen - 4 - 4 - nameLen(c.fileName), 0x40);
}

function buildCase(c) {
  const payload = C.buildPayload(c.fileName, c.bytes);
  let framedPayload = payload;
  if (c.passphrase !== null) {
    framedPayload = encryptBytesNode(payload, c.passphrase, fixedBytes(16, 0xA0), fixedBytes(12, 0xB0));
  }
  const framedData = C.withLengthPrefix(framedPayload);
  if (c.framedLen && framedData.length !== c.framedLen) throw new Error(`${c.name}: framedData ${framedData.length} != ${c.framedLen}`);
  const frames = C.splitIntoFrames(framedData, c.fileId, c.passphrase !== null);
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const size = F.SPEC.grid.framePx;
  const enc = new GifEncoder(size, size, DELAY_MS / 10);
  const side = {
    name: c.name, fileName: c.fileName, fileBytesBase64: Buffer.from(c.bytes).toString('base64'),
    passphrase: c.passphrase, fileId: c.fileId, total: frames.length, delayMs: DELAY_MS,
    framedDataLength: framedData.length, frames: [],
  };
  frames.forEach((data, seq) => {
    const raw = C.encodeRSFrame(data, rs);
    const cv = new MockCanvas(size, size);
    C.renderFrame(cv.getContext('2d'), raw);
    enc.addFrame(cv);
    const h = F.decodeHeader(data);
    side.frames.push({
      seq,
      header: { version: h.version, encrypted: h.encrypted, fileId: h.fileId, seq: h.seq, total: h.total },
      dataHex: hex(data), rawHex: hex(raw), cells: Array.from(F.packCells(raw)),
    });
  });
  fs.writeFileSync(path.join(outDir, c.name + '.gif'), Buffer.from(enc.finish()._data));
  fs.writeFileSync(path.join(outDir, c.name + '.json'), JSON.stringify(side));
  console.log(`${c.name}: ${frames.length} frame(s), ${framedData.length} framed bytes`);
}

fs.mkdirSync(outDir, { recursive: true });
for (const c of CASES) buildCase(c);
```

- [ ] **Step 5: Generate goldens and run the test**

Run: `cd web-app && node tools/gen_goldens.js`
Expected output lines: `hello: 1 frame(s)…`, `lorem_12k: 6 frame(s)…`, `lorem_12k_enc: 6 frame(s)…`, `edge_one_frame: 1 frame(s), 2104 framed bytes`, `edge_two_frames: 2 frame(s), 2105 framed bytes`.

Run: `cd web-app && node tests/test_goldens.js`
Expected: `Results: 5 passed, 0 failed`.

Run `node tools/gen_goldens.js` a second time and `git status` must show no changes to `test-data/goldens/` (determinism).

- [ ] **Step 6: Commit**

```bash
git add web-app/tools/node_crypto.js web-app/tools/gen_goldens.js web-app/tests/test_goldens.js test-data/goldens/
git commit -m "Add golden GIF generator with ground-truth sidecars and golden tests

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Web UI on v2 with present mode

**Files:**
- Modify: `web-app/index.html`
  - CSS `.preview-frame img` (≈ lines 414–418)
  - Encode fields: frame size select (≈ 568–575), frame delay select (≈ 576–584)
  - Output section (≈ 604–613)
  - Script includes (≈ 740–744)
  - `startEncode` (≈ 820–930), `startDecode` (≈ 940–1030)
- Test: `web-app/tests/test_pipeline_node.js` (rewritten to mirror the page's flow)

**Interfaces:**
- Consumes: `Cimbar.*` and `CimbarFormat.*` from Tasks 3–4, `CimbarCrypto` (unchanged), `GifEncoder`/`GifDecoder` (unchanged).

- [ ] **Step 1: Rewrite test_pipeline_node.js for v2**

Replace the whole file with:

```js
'use strict';
/**
 * test_pipeline_node.js — end-to-end file -> frames -> GIF -> frames -> file,
 * mirroring index.html's startEncode/startDecode flow on v2.
 */
global.ImageData = class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
global.Blob = class Blob {
  constructor(parts) {
    const flat = parts.map(p => p instanceof Uint8Array ? p : new Uint8Array(p));
    let total = 0; flat.forEach(a => total += a.length);
    this._data = new Uint8Array(total);
    let off = 0; flat.forEach(a => { this._data.set(a, off); off += a.length; });
  }
  get size() { return this._data.length; }
};
const { MockCanvas } = require('./mock_canvas.js');
const { GifEncoder } = require('../gif-encoder.js');
const { GifDecoder } = require('../gif-decoder.js');
const { ReedSolomon } = require('../rs.js');
const F = require('../format.js');
const C = require('../cimbar.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }

function encodeToGif(fileName, fileBytes, fileId) {
  const framedData = C.withLengthPrefix(C.buildPayload(fileName, fileBytes));
  const frames = C.splitIntoFrames(framedData, fileId, false);
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const size = F.SPEC.grid.framePx;
  const gif = new GifEncoder(size, size, 20);
  for (const data of frames) {
    const cv = new MockCanvas(size, size);
    C.renderFrame(cv.getContext('2d'), C.encodeRSFrame(data, rs));
    gif.addFrame(cv);
  }
  return { gif: gif.finish()._data, frameCount: frames.length };
}

function decodeFromGif(gifBytes, order) {
  const frames = new GifDecoder(gifBytes).decode();
  const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
  const asm = new C.FrameAssembler();
  const idx = order || frames.map((_, i) => i);
  for (const i of idx) {
    const r = C.decodeFrameExact(frames[i].imageData);
    const d = C.decodeRSFrame(r.raw, rs);
    assertEq(d.blocksFailed, 0, `frame ${i} RS`);
    asm.add(d.data);
  }
  assert(asm.isComplete(), 'assembled');
  return C.parsePayload(C.stripLengthPrefix(asm.framedData()));
}

console.log('\ntest_pipeline_node.js');

test('multi-frame file round trip', () => {
  const bytes = new Uint8Array(5000); for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 7 + 13) & 0xFF;
  const { gif, frameCount } = encodeToGif('data.bin', bytes, 0x2001);
  assertEq(frameCount, 3);
  const out = decodeFromGif(gif);
  assertEq(out.fileName, 'data.bin');
  assertEq(out.fileBytes.length, 5000);
  for (let i = 0; i < 5000; i++) if (out.fileBytes[i] !== bytes[i]) throw new Error(`byte ${i}`);
});

test('frames decoded out of order still assemble', () => {
  const bytes = new Uint8Array(5000); for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 3 + 1) & 0xFF;
  const { gif } = encodeToGif('data.bin', bytes, 0x2002);
  const out = decodeFromGif(gif, [2, 0, 1]);
  assertEq(out.fileBytes.length, 5000);
});

test('tiny file is a single frame', () => {
  const { gif, frameCount } = encodeToGif('a.txt', new Uint8Array([65]), 0x2003);
  assertEq(frameCount, 1);
  const out = decodeFromGif(gif);
  assertEq(out.fileName, 'a.txt');
  assertEq(out.fileBytes[0], 65);
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

Run: `cd web-app && node tests/test_pipeline_node.js` → Expected: `Results: 3 passed, 0 failed` (this validates the flow the page will use before touching the page).

- [ ] **Step 2: Update script includes**

In `index.html`, replace the block

```html
<script src="rs.js"></script>
<script src="cimbar.js"></script>
```

with

```html
<script src="rs.js"></script>
<script src="format-data.js"></script>
<script src="format.js"></script>
<script src="cimbar.js"></script>
```

(`gif-encoder.js` must stay after `format.js`; it already is.)

- [ ] **Step 3: Encode form fields**

Remove the entire `<div class="field">` that contains `<select id="frameSize">`. Replace the frame delay select options with:

```html
<select id="frameDelay">
  <option value="10">100 ms (fast)</option>
  <option value="20" selected>200 ms</option>
  <option value="40">400 ms (slow)</option>
</select>
```

- [ ] **Step 4: Output section and CSS**

Replace the output section's stats and preview with:

```html
<div class="stats" id="statsEnc">
  <div class="stat"><div class="stat-val" id="sFrames">—</div><div class="stat-lbl">Frames</div></div>
  <div class="stat"><div class="stat-val" id="sBytes">—</div><div class="stat-lbl">Encoded bytes</div></div>
  <div class="stat"><div class="stat-val" id="sPerFrame">—</div><div class="stat-lbl">Bytes / frame</div></div>
</div>
<div class="preview-frame" style="margin-top:16px;">
  <img id="gifOut" alt="Encoded GIF">
</div>
<button class="btn btn-primary" onclick="downloadGif()">Download GIF</button>
<button class="btn" onclick="openPresent()">Present full screen</button>
```

Replace the `.preview-frame img` rule with:

```css
.preview-frame img {
  display: block;
  image-rendering: pixelated;
  width: min(100%, 608px);
  height: auto;
}
```

Add after it:

```css
#present {
  position: fixed; inset: 0; background: #000; z-index: 1000;
  display: none; align-items: center; justify-content: center; cursor: pointer;
}
#present.open { display: flex; }
#present img { image-rendering: pixelated; display: block; }
```

Add just before `<script src="rs.js">`:

```html
<div id="present" onclick="closePresent()" title="Click or press Esc to exit"><img id="presentImg" alt="CimBar"></div>
```

- [ ] **Step 5: Present-mode functions**

Add to the inline script, next to `downloadGif`:

```js
// ── Present mode (spec §5): integer scale unless that wastes >40% of the screen ──
function presentScale(viewportW, viewportH, framePx) {
  const shorter = Math.min(viewportW, viewportH);
  const integer = Math.max(1, Math.floor(shorter / framePx));
  const used = integer * framePx / shorter;
  if (used >= 0.6) return integer;
  return shorter / framePx; // fractional fill
}

function layoutPresent() {
  const img = document.getElementById('presentImg');
  if (!img.src) return;
  const framePx = CimbarFormat.SPEC.grid.framePx;
  const s = presentScale(window.innerWidth, window.innerHeight, framePx);
  img.style.width = (framePx * s) + 'px';
  img.style.height = (framePx * s) + 'px';
}

function openPresent() {
  if (!outputBlob) return;
  const img = document.getElementById('presentImg');
  img.src = document.getElementById('gifOut').src;
  document.getElementById('present').classList.add('open');
  layoutPresent();
  const el = document.documentElement;
  if (el.requestFullscreen) el.requestFullscreen().catch(() => {});
}

function closePresent() {
  document.getElementById('present').classList.remove('open');
  if (document.fullscreenElement && document.exitFullscreen) document.exitFullscreen().catch(() => {});
}

window.addEventListener('resize', layoutPresent);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closePresent(); });
```

- [ ] **Step 6: Replace startEncode**

Replace the body of `startEncode` from `// 1. Read file` through the end of the frame loop with:

```js
    // 1. Read file and build payload
    log('Reading file…', 'info', 'logEnc');
    setProgress(5, 'Reading file', 'progEncFill', 'progEncPct', 'progEncLabel');
    const raw = new Uint8Array(await encFile.arrayBuffer());
    const payload = Cimbar.buildPayload(encFile.name, raw);
    log(`File: ${encFile.name} (${fmtBytes(raw.length)})`, 'ok', 'logEnc');

    // 2. Encrypt (optional)
    let framedPayload;
    if (isEncrypted) {
      log('Encrypting with AES-256-GCM…', 'info', 'logEnc');
      setProgress(15, 'Encrypting', 'progEncFill', 'progEncPct', 'progEncLabel');
      framedPayload = await CimbarCrypto.encryptBytes(payload, pass);
      log(`Encrypted: ${fmtBytes(framedPayload.length)}`, 'ok', 'logEnc');
    } else {
      setProgress(15, 'Encoding', 'progEncFill', 'progEncPct', 'progEncLabel');
      framedPayload = payload;
      log(`Payload: ${fmtBytes(payload.length)} (no encryption)`, 'ok', 'logEnc');
    }
    const framedData = Cimbar.withLengthPrefix(framedPayload);

    // 3. Split into frames with headers
    const fileId = crypto.getRandomValues(new Uint16Array(1))[0];
    const frames = Cimbar.splitIntoFrames(framedData, fileId, isEncrypted);
    const perFrame = CimbarFormat.fileBytesPerFrame();
    log(`${frames.length} frame(s), ${perFrame} file bytes per frame, file id ${fileId.toString(16)}`, 'info', 'logEnc');
    document.getElementById('sFrames').textContent = frames.length;
    document.getElementById('sBytes').textContent = fmtBytes(framedPayload.length);
    document.getElementById('sPerFrame').textContent = perFrame;

    // 4. Render frames
    const size = CimbarFormat.SPEC.grid.framePx;
    const canvas = document.getElementById('workCanvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    const rs = new ReedSolomon(CimbarFormat.SPEC.rs.eccBytes);
    const gif = new GifEncoder(size, size, frameDelay);
    for (let f = 0; f < frames.length; f++) {
      setProgress(25 + (f / frames.length) * 65, `Encoding frame ${f + 1} / ${frames.length}`, 'progEncFill', 'progEncPct', 'progEncLabel');
      Cimbar.renderFrame(ctx, Cimbar.encodeRSFrame(frames[f], rs));
      gif.addFrame(canvas);
      if (f % 4 === 0) await sleep(0);
    }
```

Also delete the line `const frameSize = parseInt(document.getElementById('frameSize').value);` at the top of `startEncode`. Keep everything after the loop (GIF compile, preview, download) unchanged.

- [ ] **Step 7: Replace startDecode's frame loop and assembly**

Replace from `const frameSize = frames[0].width;` through `const payloadBytes = allBytes.slice(4, 4 + payloadLength);` with:

```js
    const rs = new ReedSolomon(CimbarFormat.SPEC.rs.eccBytes);
    const asm = new Cimbar.FrameAssembler();
    let rejected = 0;
    for (let f = 0; f < frames.length; f++) {
      setProgress(20 + (f / frames.length) * 55, `Decoding frame ${f + 1} / ${frames.length}`, 'progDecFill', 'progDecPct', 'progDecLabel');
      const cellsResult = Cimbar.decodeFrameExact(frames[f].imageData);
      const rsResult = Cimbar.decodeRSFrame(cellsResult.raw, rs);
      const added = asm.add(rsResult.data);
      if (!added.accepted) {
        rejected++;
        log(`Frame ${f + 1}: rejected (${added.reason}, RS failed blocks ${rsResult.blocksFailed})`, 'err', 'logDec');
      }
      if (f % 4 === 0) await sleep(0);
    }
    if (!asm.isComplete()) throw new Error(`Incomplete: ${asm.filled} of ${asm.total} frames decoded (${rejected} rejected)`);
    log(`Assembled ${asm.total} frame(s)`, 'ok', 'logDec');
    const payloadBytes = Cimbar.stripLengthPrefix(asm.framedData());
```

Replace the filename/header parsing block (from `// Parse header:` through `const fileData = decrypted.slice(4 + nameLen);`) with:

```js
    const { fileName: filename, fileBytes: fileData } = Cimbar.parsePayload(decrypted);
```

- [ ] **Step 8: Manual check in a browser**

Run: `cd web-app && python3 -m http.server 8080` and open `http://localhost:8080`.
1. Encode a small text file without passphrase → preview shows a black-background 608 px barcode with four finders; stats show `Bytes / frame` 2104.
2. Click "Present full screen" → black full-screen page, barcode scaled; Esc closes.
3. Download the GIF, switch to Decode, decode it → the original file downloads.
4. Repeat with a passphrase.
Stop the server.

- [ ] **Step 9: Commit**

```bash
git add web-app/index.html web-app/tests/test_pipeline_node.js
git commit -m "Move web UI to v2 encoding: single grid, frame headers, present mode

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Runners, Python checks, docs

**Files:**
- Modify: `web-app/tests/run_all.sh`
- Modify: `web-app/tests/test_pipeline.py`, `web-app/tests/test_gif.py`
- Modify: `CLAUDE.md` (web sections), `README.md` (format description)

- [ ] **Step 1: run_all.sh**

Replace the file with:

```sh
#!/bin/sh
# Run all automated CimBar web tests. Execute from web-app/:
#   sh tests/run_all.sh
set -e

echo "=== CimBar Web Test Suite (v2) ==="

echo ""; echo "--- Tile rules and generator ---"
node tests/test_tiles.js

echo ""; echo "--- Format spec, header, packing ---"
node tests/test_format.js

echo ""; echo "--- Frame render/decode, RS framing, assembler ---"
node tests/test_frame.js

echo ""; echo "--- Reed-Solomon ---"
node tests/test_rs.js

echo ""; echo "--- Goldens ---"
node tests/test_goldens.js

echo ""; echo "--- End-to-end pipeline ---"
node tests/test_pipeline_node.js

echo ""
echo "=== All tests passed ==="
```

Run: `cd web-app && sh tests/run_all.sh` → Expected: ends with `=== All tests passed ===`.

- [ ] **Step 2: Python orchestrator and GIF check**

In `tests/test_pipeline.py`, replace the `tests = [...]` list and the default size:

```python
    gif_size = sys.argv[2] if len(sys.argv) > 2 else '608'

    tests = [
        (['node', 'tests/test_tiles.js'],         'Tile rules and generator (Node.js)'),
        (['node', 'tests/test_format.js'],        'Format spec, header, packing (Node.js)'),
        (['node', 'tests/test_frame.js'],         'Frame render/decode, RS framing (Node.js)'),
        (['node', 'tests/test_rs.js'],            'Reed-Solomon (Node.js)'),
        (['node', 'tests/test_goldens.js'],       'Golden GIFs (Node.js)'),
        (['node', 'tests/test_pipeline_node.js'], 'End-to-end pipeline (Node.js)'),
    ]
```

In `tests/test_gif.py`: change both `expected_size=256` defaults (function signature and `__main__`) to `608`, update the docstring line to `expected_size defaults to 608.`, and replace the block from `# Palette must have ≥ 8 entries` through `print('  CimBar base palette entries ✓')` with:

```python
        # Palette slots 0-3 are the v2 spec palette, 4 black, 5 white
        import json, os
        spec_path = os.path.join(os.path.dirname(__file__), '..', '..', 'spec', 'cimbar-v2.json')
        with open(spec_path) as sf:
            spec = json.load(sf)
        img.seek(0)
        pal = img.getpalette()
        assert pal is not None, 'No palette'
        n_entries = len(pal) // 3
        assert n_entries >= 6, f'Palette too small: {n_entries} entries'
        print(f'  palette: {n_entries} entries ✓')
        EXPECTED = [tuple(c) for c in spec['palette']] + [(0, 0, 0), (255, 255, 255)]
        for i, (er, eg, eb) in enumerate(EXPECTED):
            r, g, b = pal[i*3], pal[i*3+1], pal[i*3+2]
            assert (r, g, b) == (er, eg, eb), (
                f'Palette slot {i}: got ({r},{g},{b}), expected ({er},{eg},{eb})'
            )
        print('  v2 palette entries ✓')
```

Run: `cd web-app && python3 tests/test_pipeline.py ../test-data/goldens/hello.gif 608` (skips the Pillow step with a message if Pillow is missing, as it does today). Expected: all Node scripts pass.

- [ ] **Step 3: Docs**

In `CLAUDE.md`:
- Replace the "Cell Encoding", "Center Metadata Block", "RS Block Interleaving" and "Key Constants" sections with a short "Format v2" section: point to `spec/cimbar-v2.json` and the design spec; state the 64×64 grid, 8 px tiles + 1 px gaps, 4 finders, 4 colors + 16 tiles = 6 bits/cell, 2880 raw / 2112 data / 2104 file bytes per frame, 8-byte header `[ver 02][flags][fileId][seq][total]`, and that v1 GIFs no longer decode.
- Update "Module responsibilities" for `format.js`, `format-data.js` (generated; run `node tools/gen_format_data.js`), `cimbar.js` (v2 API list from Task 4), tools (`gen_tiles.js`, `gen_format_data.js`, `gen_goldens.js`, `node_crypto.js`).
- Replace the web tests table with the six scripts and what each covers; note `test-data/goldens/` and that Android plans consume it.
- Leave the Android sections untouched (Plan 2 rewrites them); add one line at the top of the Android architecture section: "Android is still on v1 until Plan 2 lands; GIFs produced by the current web app will not decode on Android yet."

In `README.md`: replace the "Each cell in the grid carries 7 bits…" paragraph and the "What the symbols look like" section with a short v2 description (4 colors, 16 tile shapes, 6 bits per cell, black background, four finders, one 608 px frame size, per-frame sequence header) and a note that files encoded before v2 must be re-encoded.

- [ ] **Step 4: Full suite and commit**

Run: `cd web-app && sh tests/run_all.sh` → Expected: `=== All tests passed ===`.

```bash
git add web-app/tests/run_all.sh web-app/tests/test_pipeline.py web-app/tests/test_gif.py CLAUDE.md README.md
git commit -m "Update web test runners and docs for CimBar v2

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review notes

- Spec coverage for this plan's scope: §3.1–3.5 (Tasks 2–4), §4.1–4.4 (Task 4), §5 (Task 7), §7.1 (Tasks 2–3), §7.3 (Tasks 4–7), §9.1 (Task 6), §9.4 JS rows (Tasks 1–7). §6, §7.2, §8, §9.2–9.3 and Dart rows of §9.4 belong to Plans 2–4.
- The tile generator's 2×2-block structure is an implementation choice beyond the spec's stated constraints; the spec's constraints are still asserted on the output (Task 2 test "tile set satisfies tile rules").
- Names used across tasks: `CimbarFormat.{SPEC, HEADER_LEN, usableCellPositions, cellOrigin, tileBits, encodeHeader, decodeHeader, packCells, unpackCells, cellValue, cellSymbol, cellColor, rsBlockSizes, dataBytesPerFrame, fileBytesPerFrame, rawBytesPerFrame}` and `Cimbar.{renderFrame, decodeFrameExact, encodeRSFrame, decodeRSFrame, splitIntoFrames, FrameAssembler, buildPayload, parsePayload, withLengthPrefix, stripLengthPrefix}` are spelled identically in Tasks 3–7.
