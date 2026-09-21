# Web App Live Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the web app decode a CimBar barcode shown on another screen by scanning it continuously with the phone's camera, feeding the same accumulating session as photos.

**Architecture:** A `LiveScan` controller (`live-scan.js`) opens the camera, grabs one frame at a time, and posts its pixels to a stateless Web Worker (`scan-worker.js`) that runs the existing, unmodified `CimbarPhoto.decode`. Replies drive a port of Android's `CapturePolicy` (`capture-policy.js`) for hints and focus/exposure locking. `ok` frames go to a new page function `addFrame`, split out of `addPhoto`, so photos and live scan share one `photoSession`.

**Tech Stack:** Vanilla ES2017 JavaScript, classic `<script>` tags, no build step, no dependencies. Tests are plain Node scripts run by `sh tests/run_all.sh` from `web-app/`. The optional end-to-end tool uses Playwright's Chromium.

**Spec:** `docs/superpowers/specs/2026-09-21-web-live-scan-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **No decode-module edits.** `photo-decoder.js`, `rgb-buffer.js`, `luma-plane.js`, `homography.js`, `finder-locator.js`, `white-point.js`, `cell-sampler.js`, `cell-classifier.js`, `drift-solver.js`, `rs.js`, `format.js`, `rateless.js`, `cimbar.js` are not modified. If a task seems to need it, stop and report — it is a design change (spec §12.5).
- **One global scope.** Page scripts are classic `<script>` tags sharing one global lexical scope. Every new page script (`capture-policy.js`, `live-scan.js`) is an IIFE with the repo's dual export: `const isNode = typeof module !== 'undefined' && module.exports;` … `if (isNode) module.exports = API; else window.CimbarX = API;`. `scan-worker.js` is a worker script, not a page script, and is never listed in a `<script src>`.
- **ES2017 only.** No `??`, no `?.`, no class fields, no optional catch binding (`catch {}`) — match the surrounding code.
- **Capture policy constants, verbatim from `app/lib/core/services/capture_policy.dart`:** `minModulePx` 6, `maxModulePx` 40, `motionPx` 10, `unlockAfterMs` 2000.
- **Live-scan constants (spec):** worker reply timeout 10 000 ms; 3 consecutive worker failures stop the scan; "point at the barcode" hint after 1000 ms without a located frame; overlay fades 500 ms after the last located frame; debug panel keeps at most 50 lines; camera request `{ audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } } }`.
- **Located** means `corners` non-null **and** `status` ∈ {`ok`, `rsFailed`, `badHeader`, `unsupportedGrid`, `tooSmall`}.
- **Only `status === 'ok'` frames reach the session.**
- **Five languages.** Every user-visible string has a key in en, ru, uk, tr, ka (`test_i18n.js`). Dynamic strings in the page use literal `t('key')` calls (the test greps for them). The debug panel is English-only and untranslated.
- **`test_page_logic.js`'s existing tests must pass unchanged** after the `addFrame` refactor — they are the behavioural contract of the photo session.
- **Run tests from `web-app/`:** `cd web-app && node tests/<file>.js`; the whole suite is `sh tests/run_all.sh`.
- **Commits** end with the line `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. Work happens on a feature branch, never on `master`.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `web-app/capture-policy.js` | create | `CapturePolicy` (hint + lock action from a decode outcome), `isLocated` |
| `web-app/scan-worker.js` | create | worker: `importScripts` the decode chain, answer `{id,width,height,buffer}` with a decode result |
| `web-app/live-scan.js` | create | `LiveScan` controller, `coverTransform`, `drawOverlay`, lock helpers |
| `web-app/index.html` | modify | script tags; `addFrame` split from `addPhoto`; scanner markup, CSS and page glue |
| `web-app/i18n.js` | modify | 16 new keys × 5 languages; `howDecodingHtml` sentence |
| `.github/workflows/deploy-webapp.yml` | modify | stage the three new files |
| `web-app/tests/test_capture_policy.js` | create | port of `capture_policy_test.dart` |
| `web-app/tests/test_scan_worker.js` | create | worker in a `vm` context vs `CimbarPhoto.decode` on the scene fixtures |
| `web-app/tests/test_live_scan.js` | create | `LiveScan` against fake camera/worker/timers |
| `web-app/tests/test_page_logic.js` | modify | `addFrame` kinds; live-scan session integration |
| `web-app/tests/test_browser_load.js` | modify | 21 scripts, order, globals; wrong-file invariant now in `addFrame` |
| `web-app/tests/test_web_icons.js` | modify | worker + `importScripts` files are staged |
| `web-app/tests/run_all.sh` | modify | three new test files |
| `web-app/tools/e2e_live_scan.js` | create | local Playwright fake-camera end-to-end (not CI) |
| `CLAUDE.md` | modify | modules, pipeline paragraph, tests, counts |

---

### Task 1: Capture policy

**Files:**
- Create: `web-app/capture-policy.js`
- Test: `web-app/tests/test_capture_policy.js`
- Modify: `web-app/tests/run_all.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `window.CimbarCapturePolicy = { CapturePolicy, isLocated, LOCATED_STATUSES }` (Node: `module.exports`, same shape).
  - `new CapturePolicy(opts?)` — `opts` may override `minModulePx`, `maxModulePx`, `motionPx`, `unlockAfterMs`.
  - `policy.update(outcome, nowMs) → { hint, lockAction }` where `outcome` is `{ status, corners: number[8] | null, module: number }`, `hint ∈ 'none'|'moveCloser'|'moveBack'|'holdStill'|'adjustAngle'`, `lockAction ∈ 'none'|'lock'|'unlock'`.
  - `policy.locked` (boolean getter), `policy.reset()`.
  - `isLocated(outcome) → boolean`.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_capture_policy.js`:

```js
// Port of app/test/core/services/capture_policy_test.dart, case for case,
// plus the web-only 'tooSmall' status (photo-decoder.js's module floor).
'use strict';
const path = require('path');
const { CapturePolicy, isLocated } = require(path.join(__dirname, '..', 'capture-policy.js'));

let passed = 0, failed = 0;
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

// Mirrors the Dart helper: corners absent only for notLocated.
function outcome(status, opts) {
  const o = Object.assign({ module: 12, ox: 0 }, opts);
  return {
    status,
    corners: status === 'notLocated' ? null
      : [100 + o.ox, 100, 700 + o.ox, 100, 100 + o.ox, 700, 700 + o.ox, 700],
    module: o.module,
  };
}

test('locks after the first located frame, unlocks 2 s after losing it', () => {
  const p = new CapturePolicy();
  assertEq(p.update(outcome('notLocated'), 0).lockAction, 'none', 'not located yet');
  assertEq(p.update(outcome('rsFailed'), 100).lockAction, 'lock', 'first located frame locks');
  assertEq(p.locked, true, 'locked');
  assertEq(p.update(outcome('ok'), 300).lockAction, 'none', 'already locked');
  assertEq(p.update(outcome('notLocated'), 1000).lockAction, 'none', 'lost for 700 ms');
  assertEq(p.update(outcome('notLocated'), 2400).lockAction, 'unlock', 'lost for 2300 ms');
  assertEq(p.locked, false, 'unlocked');
});

test('hints from module size, motion and rsFailed', () => {
  const p = new CapturePolicy();
  assertEq(p.update(outcome('ok', { module: 4 }), 0).hint, 'moveCloser', 'module 4');
  assertEq(p.update(outcome('ok', { module: 50 }), 100).hint, 'moveBack', 'module 50');
  assertEq(p.update(outcome('ok', { module: 12 }), 200).hint, 'none', 'module 12, same corners');
  assertEq(p.update(outcome('ok', { module: 12, ox: 25 }), 300).hint, 'holdStill', 'moved 25 px');
  assertEq(p.update(outcome('rsFailed', { module: 12, ox: 25 }), 400).hint, 'adjustAngle', 'rsFailed, still');
  assertEq(p.update(outcome('notLocated'), 500).hint, 'none', 'not located');
});

test('reset clears lock and stale corner history', () => {
  const p = new CapturePolicy();
  assertEq(p.update(outcome('ok'), 0).lockAction, 'lock', 'lock');
  assertEq(p.locked, true, 'locked');
  p.reset();
  assertEq(p.locked, false, 'reset unlocks');
  const r = p.update(outcome('ok', { ox: 25 }), 100);
  assertEq(r.lockAction, 'lock', 'locks again after reset');
  assertEq(r.hint, 'none', 'no motion hint against pre-reset corners');
});

test('tooSmall with corners is located and asks to move closer (web-only status)', () => {
  const p = new CapturePolicy();
  const r = p.update(outcome('tooSmall', { module: 4 }), 0);
  assertEq(r.lockAction, 'lock', 'tooSmall with corners locks');
  assertEq(r.hint, 'moveCloser', 'tooSmall -> moveCloser via the module rule');
});

test('tooSmall without corners (locator-level floor) is not located', () => {
  const p = new CapturePolicy();
  const o = { status: 'tooSmall', corners: null, module: 0 };
  assertEq(isLocated(o), false, 'isLocated');
  const r = p.update(o, 0);
  assertEq(r.lockAction, 'none', 'no lock');
  assertEq(r.hint, 'none', 'no hint');
});

test('isLocated needs both corners and a located status', () => {
  assertEq(isLocated(outcome('ok')), true, 'ok');
  assertEq(isLocated(outcome('badHeader')), true, 'badHeader');
  assertEq(isLocated(outcome('unsupportedGrid')), true, 'unsupportedGrid');
  assertEq(isLocated(outcome('notLocated')), false, 'notLocated');
  assertEq(isLocated({ status: 'error', corners: [0, 0, 0, 0, 0, 0, 0, 0], module: 1 }), false, 'error status');
});

(async () => {
  console.log('\ntest_capture_policy.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web-app && node tests/test_capture_policy.js`
Expected: FAIL — `Cannot find module '.../capture-policy.js'`.

- [ ] **Step 3: Write the implementation**

Create `web-app/capture-policy.js`:

```js
/**
 * capture-policy.js — camera acquisition policy for live scan (spec §8).
 *
 * Transliteration of app/lib/core/services/capture_policy.dart: lock focus
 * and exposure once a barcode is located, unlock after unlockAfterMs without
 * one, and derive a user hint from the finder module size, corner motion and
 * the decode status. Constants are Android's, verbatim.
 *
 * One web-only addition: 'tooSmall' counts as located. It is the photo
 * decoder's module floor, which runs after the locator filled corners and
 * module, so a small barcode yields moveCloser through the module rule.
 *
 * Pure logic, no DOM. IIFE; exposes window.CimbarCapturePolicy / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;

const LOCATED_STATUSES = ['ok', 'rsFailed', 'badHeader', 'unsupportedGrid', 'tooSmall'];

function isLocated(o) {
  return !!(o && o.corners) && LOCATED_STATUSES.indexOf(o.status) >= 0;
}

function motion(a, b) {
  let worst = 0;
  for (let i = 0; i < 8; i += 2) {
    const dx = a[i] - b[i], dy = a[i + 1] - b[i + 1];
    const d = dx * dx + dy * dy;
    if (d > worst) worst = d;
  }
  return worst === 0 ? 0 : Math.sqrt(worst);
}

class CapturePolicy {
  constructor(opts) {
    const p = opts || {};
    this.minModulePx = p.minModulePx !== undefined ? p.minModulePx : 6;
    this.maxModulePx = p.maxModulePx !== undefined ? p.maxModulePx : 40;
    this.motionPx = p.motionPx !== undefined ? p.motionPx : 10;
    this.unlockAfterMs = p.unlockAfterMs !== undefined ? p.unlockAfterMs : 2000;
    this.reset();
  }

  get locked() { return this._locked; }

  reset() {
    this._locked = false;
    this._lastLocatedMs = null;
    this._lastCorners = null;
  }

  update(o, nowMs) {
    let lockAction = 'none';
    let hint = 'none';
    if (isLocated(o)) {
      this._lastLocatedMs = nowMs;
      if (!this._locked) {
        this._locked = true;
        lockAction = 'lock';
      }
      if (o.module < this.minModulePx) {
        hint = 'moveCloser';
      } else if (o.module > this.maxModulePx) {
        hint = 'moveBack';
      } else if (this._lastCorners !== null && motion(this._lastCorners, o.corners) > this.motionPx) {
        hint = 'holdStill';
      } else if (o.status === 'rsFailed') {
        hint = 'adjustAngle';
      }
      this._lastCorners = o.corners;
    } else {
      this._lastCorners = null;
      if (this._locked && this._lastLocatedMs !== null && nowMs - this._lastLocatedMs >= this.unlockAfterMs) {
        this._locked = false;
        lockAction = 'unlock';
      }
    }
    return { hint, lockAction };
  }
}

const API = { CapturePolicy, isLocated, LOCATED_STATUSES };
if (isNode) module.exports = API; else window.CimbarCapturePolicy = API;
})();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd web-app && node tests/test_capture_policy.js`
Expected: `Results: 6 passed, 0 failed`.

- [ ] **Step 5: Add to the suite**

In `web-app/tests/run_all.sh`, after the `test_photo_decode.js` block and before `--- Deploy healthcheck ---`, add:

```sh
echo ""; echo "--- Capture policy (live scan hints and focus lock) ---"
node tests/test_capture_policy.js
```

- [ ] **Step 6: Commit**

```bash
git add web-app/capture-policy.js web-app/tests/test_capture_policy.js web-app/tests/run_all.sh
git commit -m "feat(web): port CapturePolicy for live scan

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Scan worker

**Files:**
- Create: `web-app/scan-worker.js`
- Test: `web-app/tests/test_scan_worker.js`
- Modify: `web-app/tests/run_all.sh`

**Interfaces:**
- Consumes: the page scripts `rs.js`, `format-data.js`, `format.js`, `rateless.js`, `cimbar.js`, the eight photo modules and `photo-decoder.js` (via `importScripts`); `self.CimbarPhoto.decode(imageDataLike)`.
- Produces: the worker message protocol, used by Task 3:
  - request `{ id: number, width: number, height: number, buffer: ArrayBuffer }` (RGBA, `width*height*4` bytes);
  - reply `{ id, status, data: Uint8Array|null, blocksFailed, corners: number[8]|null, module: number, diag: object }`, or `{ id, status: 'error', message: string }` if decode threw.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_scan_worker.js`:

```js
// scan-worker.js run the way a browser runs a worker: one global scope
// (`self`), no `window` until the worker's own shim, no module/require, and
// importScripts loading the real page files from disk into that scope.
// The worker must add nothing to and lose nothing from CimbarPhoto.decode:
// for every scene fixture its reply equals a direct decode of the same pixels.
'use strict';
const vm = require('vm');
const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');
const PNG = require('./png.js');

const root = path.join(__dirname, '..');
const scenes = path.join(root, '..', 'test-data', 'scenes');
const { CimbarPhoto } = require(path.join(root, 'photo-decoder.js'));

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

function loadWorker() {
  const posted = [];
  const imported = [];
  const sandbox = { console, performance };
  sandbox.self = sandbox;
  sandbox.postMessage = (m) => posted.push(m);
  const ctx = vm.createContext(sandbox);
  sandbox.importScripts = (...files) => {
    for (const f of files) {
      imported.push(f);
      vm.runInContext(fs.readFileSync(path.join(root, f), 'utf8'), ctx, { filename: f });
    }
  };
  vm.runInContext(fs.readFileSync(path.join(root, 'scan-worker.js'), 'utf8'), ctx, { filename: 'scan-worker.js' });
  return { ctx, posted, imported };
}

function post(w, msg) {
  w.ctx.onmessage({ data: msg });
  assertEq(w.posted.length > 0, true, 'the worker must reply synchronously to each message');
  return w.posted.pop();
}

test('loads the decode chain in index.html order and installs onmessage', () => {
  const w = loadWorker();
  assertEq(typeof w.ctx.onmessage, 'function', 'self.onmessage');
  assertEq(typeof w.ctx.CimbarPhoto.decode, 'function', 'CimbarPhoto reachable after importScripts');
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const pageOrder = [...html.matchAll(/<script src="([^"]+)"><\/script>/g)].map((m) => m[1]);
  let last = -1;
  for (const f of w.imported) {
    const i = pageOrder.indexOf(f);
    assert(i >= 0, `${f} is imported by the worker but is not a page script`);
    assert(i > last, `${f} is imported out of index.html order`);
    last = i;
  }
  assert(w.imported.includes('photo-decoder.js'), 'photo-decoder.js imported');
});

for (const name of fs.readdirSync(scenes).filter((f) => f.endsWith('.png')).sort()) {
  test(`reply equals a direct CimbarPhoto.decode — ${name}`, () => {
    const img = PNG.decode(fs.readFileSync(path.join(scenes, name)));
    const direct = CimbarPhoto.decode(img);
    const w = loadWorker();
    const buffer = new Uint8ClampedArray(img.data).buffer;       // a copy, as getImageData would give
    const r = post(w, { id: 7, width: img.width, height: img.height, buffer });
    assertEq(r.id, 7, 'id echoed');
    assertEq(r.status, direct.status, 'status');
    assertEq(r.blocksFailed, direct.blocksFailed, 'blocksFailed');
    assertEq(JSON.stringify(r.corners), JSON.stringify(direct.diag.corners), 'corners');
    assertEq(r.module, direct.diag.module, 'module');
    if (direct.data) {
      assert(r.data, 'data present');
      assertEq(Buffer.from(r.data).equals(Buffer.from(direct.data)), true, 'data bytes');
    } else {
      assertEq(r.data, null, 'data null');
    }
    assertEq(r.cells, undefined, 'cells are not sent back');
    assertEq(r.raw, undefined, 'raw is not sent back');
  });
}

test('a blank frame replies notLocated rather than throwing', () => {
  const w = loadWorker();
  const width = 200, height = 200;
  const px = new Uint8ClampedArray(width * height * 4).fill(128);
  const r = post(w, { id: 1, width, height, buffer: px.buffer });
  assertEq(r.status, 'notLocated', 'status');
  assertEq(r.corners, null, 'no corners');
});

test('an exception inside decode becomes status "error" with the message', () => {
  const w = loadWorker();
  w.ctx.CimbarPhoto.decode = () => { throw new Error('boom'); };
  const r = post(w, { id: 3, width: 1, height: 1, buffer: new ArrayBuffer(4) });
  assertEq(r.id, 3, 'id echoed');
  assertEq(r.status, 'error', 'status');
  assertEq(r.message, 'boom', 'message');
});

(async () => {
  console.log('\ntest_scan_worker.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web-app && node tests/test_scan_worker.js`
Expected: FAIL — `ENOENT ... scan-worker.js` on every test.

- [ ] **Step 3: Write the implementation**

Create `web-app/scan-worker.js`:

```js
/**
 * scan-worker.js — the live-scan decode worker (spec §5).
 *
 * Stateless: one message in, one reply out. Request
 *   { id, width, height, buffer }   RGBA ArrayBuffer, transferred
 * reply
 *   { id, status, data, blocksFailed, corners, module, diag }
 * or, if decode threw,
 *   { id, status: 'error', message }.
 * cells and raw are not sent back: the page never uses them.
 *
 * The decode modules are classic scripts that read their dependencies from
 * window.* when `module` is undefined; a worker has no window, so alias it
 * before importScripts. importScripts runs them in one shared global scope,
 * the same situation tests/test_browser_load.js simulates for the page, so
 * none of them changes. Keep the list in index.html's order.
 */
'use strict';
self.window = self;
importScripts(
  'rs.js', 'format-data.js', 'format.js', 'rateless.js', 'cimbar.js',
  'rgb-buffer.js', 'luma-plane.js', 'homography.js', 'finder-locator.js',
  'white-point.js', 'cell-sampler.js', 'cell-classifier.js', 'drift-solver.js',
  'photo-decoder.js'
);

self.onmessage = function (e) {
  const m = e.data;
  let reply;
  try {
    const r = self.CimbarPhoto.decode({ width: m.width, height: m.height, data: new Uint8ClampedArray(m.buffer) });
    reply = {
      id: m.id, status: r.status, data: r.data, blocksFailed: r.blocksFailed,
      corners: r.diag.corners, module: r.diag.module, diag: r.diag,
    };
  } catch (err) {
    reply = { id: m.id, status: 'error', message: String((err && err.message) || err) };
  }
  self.postMessage(reply);
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd web-app && node tests/test_scan_worker.js`
Expected: `Results: 11 passed, 0 failed` (1 load test + 8 fixtures + 2). If the blank-frame test reports a status other than `notLocated`, print `r.diag.failReason` and report it rather than loosening the assertion — the spec requires `notLocated`.

- [ ] **Step 5: Add to the suite**

In `web-app/tests/run_all.sh`, directly after the capture-policy block from Task 1:

```sh
echo ""; echo "--- Scan worker (decode chain inside a Web Worker) ---"
node tests/test_scan_worker.js
```

- [ ] **Step 6: Commit**

```bash
git add web-app/scan-worker.js web-app/tests/test_scan_worker.js web-app/tests/run_all.sh
git commit -m "feat(web): live-scan decode worker

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: LiveScan controller

**Files:**
- Create: `web-app/live-scan.js`
- Test: `web-app/tests/test_live_scan.js`
- Modify: `web-app/tests/run_all.sh`

**Interfaces:**
- Consumes: `CimbarCapturePolicy.CapturePolicy`, `CimbarCapturePolicy.isLocated` (Task 1); the worker protocol (Task 2).
- Produces: `window.CimbarLiveScan = { LiveScan, coverTransform, drawOverlay, lockSupport, lockConstraints, unlockConstraints, CAMERA_CONSTRAINTS, CAMERA_ERRORS }`.
  - `new LiveScan(opts)` — `opts`:
    - `video` (HTMLVideoElement-like: `srcObject`, `play()`, `videoWidth`, `videoHeight`), `overlay` (canvas or `null`), `mediaDevices`;
    - callbacks: `onFrame(result) → {kind, complete, rank, total} | Promise<same>` (called only for `status === 'ok'`), `onStatus({ hint })` with `hint ∈ null|'point'|'moveCloser'|'moveBack'|'holdStill'|'adjustAngle'`, `onDebug(line: string)`, `onError(code)` with `code ∈ 'camDenied'|'camNone'|'camBusy'|'camFailed'|'scanDecoderFailed'`, `onPaused()`, `onStopped({ reason, frames, accepted })` with `reason ∈ 'closed'|'complete'|'error'|'decoderFailed'|string`;
    - optional: `debug` (bool), `doc`/`win` (event targets for `visibilitychange`/`pagehide`), `createWorker` (default `() => new Worker('scan-worker.js')`), `nextFrame(video, cb) → cancel`, `grabFrame(video) → ImageData|null`, `now`, `setTimeout`, `clearTimeout`, `timeoutMs` (10000), `maxFailures` (3), `pointAfterMs` (1000), `fadeMs` (500).
  - `scan.start() → Promise<boolean>`, `scan.stop(reason)`, `scan.pause()`, `scan.resume() → Promise<boolean>`, `scan.state ∈ 'idle'|'starting'|'scanning'|'paused'|'stopped'`.
  - `coverTransform(srcW, srcH, boxW, boxH) → { scale, dx, dy }`.

- [ ] **Step 1: Write the failing test**

Create `web-app/tests/test_live_scan.js`:

```js
// LiveScan against fake camera, track, worker, frame clock and timers.
// Nothing here touches a real DOM: the controller takes every browser
// surface as an option precisely so these rules can be pinned in Node.
'use strict';
const path = require('path');
const { LiveScan, coverTransform, drawOverlay } = require(path.join(__dirname, '..', 'live-scan.js'));

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
function assertJson(a, b, msg) { assertEq(JSON.stringify(a), JSON.stringify(b), msg); }
function near(a, b, msg) { if (Math.abs(a - b) > 1e-6) throw new Error(`${msg}: got ${a}, want ${b}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
const flush = () => new Promise((r) => setImmediate(r));

function eventTarget(extra) {
  const listeners = {};
  return Object.assign({
    addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
    removeEventListener(type, fn) { listeners[type] = (listeners[type] || []).filter((f) => f !== fn); },
    fire(type) { (listeners[type] || []).slice().forEach((fn) => fn({ type })); },
    count(type) { return (listeners[type] || []).length; },
  }, extra);
}

function diag() { return { totalMs: 5, locateMs: 1, sampleMs: 2, driftMs: 1, rsMs: 1 }; }
function located(status, opts) {
  const o = Object.assign({ ox: 0, module: 12 }, opts);
  return { status: status || 'ok', corners: [100 + o.ox, 100, 700 + o.ox, 100, 100 + o.ox, 700, 700 + o.ox, 700],
           module: o.module, blocksFailed: 0, data: new Uint8Array(8), diag: diag() };
}
function notLocated() { return { status: 'notLocated', corners: null, module: 0, blocksFailed: 0, data: null, diag: diag() }; }

function rig(opts) {
  const o = opts || {};
  const log = { posts: [], transfers: [], applied: [], errors: [], debug: [], stopped: [], paused: 0, statuses: [], workers: [], frames: [], gum: 0 };
  const track = {
    stopped: false,
    stop() { this.stopped = true; },
    getCapabilities: () => o.caps || {},
    getSettings: () => o.settings || {},
    applyConstraints: async (c) => { log.applied.push(c); if (o.rejectLock) throw new Error('not allowed'); },
  };
  const stream = { getVideoTracks: () => [track], getTracks: () => [track] };
  const mediaDevices = {
    getUserMedia: async (c) => {
      log.gum++; log.constraints = c;
      if (o.gumError) { const e = new Error('x'); e.name = o.gumError; throw e; }
      track.stopped = false;
      return stream;
    },
  };
  let pending = null;
  const nextFrame = (video, cb) => { pending = cb; return () => { pending = null; }; };
  const fireFrame = () => { const cb = pending; pending = null; if (cb) cb(); return !!cb; };
  const timers = [];
  const setT = (fn, ms) => { const t = { fn, ms, cleared: false, fired: false }; timers.push(t); return t; };
  const clearT = (t) => { if (t) t.cleared = true; };
  const fireTimeouts = () => timers.filter((t) => !t.cleared && !t.fired).forEach((t) => { t.fired = true; t.fn(); });
  class FakeWorker {
    constructor() { this.posted = []; this.terminated = false; log.workers.push(this); }
    postMessage(m, transfer) { this.posted.push(m); log.posts.push(m); log.transfers.push(transfer); }
    terminate() { this.terminated = true; }
  }
  let clock = 0;
  const doc = eventTarget({ visibilityState: 'visible' });
  const win = eventTarget();
  const video = { videoWidth: 1280, videoHeight: 720, srcObject: null, play: async () => {} };
  const scan = new LiveScan({
    video, overlay: null, mediaDevices, doc, win, debug: true,
    createWorker: () => new FakeWorker(), nextFrame,
    grabFrame: () => ({ width: 2, height: 2, data: new Uint8ClampedArray(16) }),
    now: () => clock, setTimeout: setT, clearTimeout: clearT,
    onFrame: o.onFrame || (async (r) => { log.frames.push(r); return { kind: 'accepted', complete: false, rank: 1, total: 5 }; }),
    onStatus: (s) => log.statuses.push(s), onDebug: (l) => log.debug.push(l), onError: (c) => log.errors.push(c),
    onPaused: () => { log.paused++; }, onStopped: (i) => log.stopped.push(i),
  });
  const worker = () => log.workers[log.workers.length - 1];
  const reply = async (msg, w) => {
    const target = w || worker();
    const last = target.posted[target.posted.length - 1];
    target.onmessage({ data: Object.assign({ id: last.id }, msg) });
    await flush();
  };
  return { scan, track, video, log, fireFrame, fireTimeouts, reply, worker, doc, win, setClock: (v) => { clock = v; } };
}

test('start requests the rear camera at ideal 1080p, no audio, and reports resolution and lock support', async () => {
  const r = rig();
  assertEq(await r.scan.start(), true, 'start resolves true');
  assertJson(r.log.constraints, { audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } } }, 'constraints');
  assertEq(r.video.srcObject !== null, true, 'stream attached to the video');
  assertEq(r.scan.state, 'scanning', 'state');
  assert(r.log.debug[0].includes('1280x720') && r.log.debug[0].includes('lock=unsupported'), `debug header: ${r.log.debug[0]}`);
});

test('one frame in flight: no second post until the worker replies', async () => {
  const r = rig();
  await r.scan.start();
  assertEq(r.fireFrame(), true, 'a frame callback is registered after start');
  assertEq(r.log.posts.length, 1, 'first frame posted');
  assertEq(r.fireFrame(), false, 'no frame callback while a decode is in flight');
  assertEq(r.log.posts.length, 1, 'still one post');
  await r.reply(notLocated());
  assertEq(r.fireFrame(), true, 'the next frame is requested after the reply');
  assertEq(r.log.posts.length, 2, 'second post');
});

test('the pixel buffer is transferred, not copied', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame();
  const m = r.log.posts[0];
  assertEq(m.width, 2, 'width'); assertEq(m.height, 2, 'height');
  assert(r.log.transfers[0] && r.log.transfers[0][0] === m.buffer, 'transfer list holds the buffer');
});

test('lock pins the current focus distance and exposure time; unlock restores continuous', async () => {
  const r = rig({
    caps: { focusMode: ['manual', 'single-shot', 'continuous'], exposureMode: ['continuous', 'manual'] },
    settings: { focusDistance: 0.3, exposureTime: 20 },
  });
  await r.scan.start();
  assert(r.log.debug[0].includes('lock=focus+exposure'), r.log.debug[0]);
  r.fireFrame(); await r.reply(located());
  assertJson(r.log.applied[0], { advanced: [{ focusMode: 'manual', focusDistance: 0.3 }, { exposureMode: 'manual', exposureTime: 20 }] }, 'lock');
  r.setClock(2500);
  r.fireFrame(); await r.reply(notLocated());
  assertJson(r.log.applied[1], { advanced: [{ focusMode: 'continuous' }, { exposureMode: 'continuous' }] }, 'unlock');
});

test('focus-only support locks focus only; a setting that is not a number is left out', async () => {
  const r = rig({ caps: { focusMode: ['manual', 'continuous'] }, settings: { focusDistance: 0.5, exposureTime: 20 } });
  await r.scan.start();
  assert(r.log.debug[0].includes('lock=focus '), r.log.debug[0]);
  r.fireFrame(); await r.reply(located());
  assertJson(r.log.applied[0], { advanced: [{ focusMode: 'manual', focusDistance: 0.5 }] }, 'focus only');

  const r2 = rig({ caps: { focusMode: ['manual', 'continuous'] }, settings: {} });
  await r2.scan.start();
  r2.fireFrame(); await r2.reply(located());
  assertJson(r2.log.applied[0], { advanced: [{ focusMode: 'manual' }] }, 'no focusDistance setting -> mode only');
});

test('no lock support means no applyConstraints calls at all', async () => {
  const r = rig({ caps: { focusMode: ['continuous'] } });
  await r.scan.start();
  r.fireFrame(); await r.reply(located());
  r.setClock(3000);
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.applied.length, 0, 'applyConstraints never called');
});

test('a rejected applyConstraints disables locking and scanning continues', async () => {
  const r = rig({ caps: { focusMode: ['manual', 'continuous'] }, settings: { focusDistance: 1 }, rejectLock: true });
  await r.scan.start();
  r.fireFrame(); await r.reply(located());
  assertEq(r.log.applied.length, 1, 'lock attempted once');
  assert(r.log.debug.some((l) => l.includes('lock failed')), 'the failure is in the debug log');
  r.setClock(3000);
  r.fireFrame(); await r.reply(notLocated());
  r.setClock(3100);
  r.fireFrame(); await r.reply(located());
  assertEq(r.log.applied.length, 1, 'no further lock/unlock attempts');
  assertEq(r.fireFrame(), true, 'still scanning');
});

test('only ok frames reach onFrame', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply(located('rsFailed'));
  r.fireFrame(); await r.reply(located('badHeader'));
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.frames.length, 0, 'no non-ok frame reaches the session');
  r.fireFrame(); await r.reply(located('ok'));
  assertEq(r.log.frames.length, 1, 'ok frame delivered');
});

test('hints: policy hints pass through; "point" only after 1 s without a located frame', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply(located('ok', { module: 4 }));
  assertEq(r.log.statuses[r.log.statuses.length - 1].hint, 'moveCloser', 'module 4');
  r.setClock(500);
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.statuses[r.log.statuses.length - 1].hint, null, 'lost for 500 ms: no hint yet');
  r.setClock(1200);
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.statuses[r.log.statuses.length - 1].hint, 'point', 'lost for 1200 ms');
});

test('worker failures respawn; three in a row stop the scan; a success resets the count', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply({ status: 'error', message: 'boom' });
  assertEq(r.log.workers.length, 2, 'error reply -> respawn');
  assertEq(r.log.workers[0].terminated, true, 'old worker terminated');
  r.fireFrame(); r.worker().onerror({ preventDefault() {} }); await flush();
  assertEq(r.log.workers.length, 3, 'error event -> respawn');
  r.fireFrame(); await r.reply(notLocated());                 // success resets the count
  r.fireFrame(); r.fireTimeouts(); await flush();
  assertEq(r.log.workers.length, 4, 'timeout -> respawn');
  r.fireFrame(); await r.reply({ status: 'error', message: 'x' });
  assertEq(r.scan.state, 'scanning', 'two in a row since the success: still scanning');
  r.fireFrame(); await r.reply({ status: 'error', message: 'y' });
  assertEq(r.scan.state, 'stopped', 'third in a row stops');
  assertJson(r.log.errors, ['scanDecoderFailed'], 'error reported');
  assertEq(r.log.stopped[0].reason, 'decoderFailed', 'stop reason');
  assertEq(r.track.stopped, true, 'camera released');
});

test('a late reply from a timed-out request is ignored', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame();
  const old = r.worker();
  const oldId = old.posted[0].id;
  r.fireTimeouts(); await flush();
  old.onmessage({ data: Object.assign(located('ok'), { id: oldId }) });
  await flush();
  assertEq(r.log.frames.length, 0, 'the stale reply did not reach onFrame');
});

test('camera errors map to translated codes and stop', async () => {
  for (const [name, code] of [['NotAllowedError', 'camDenied'], ['SecurityError', 'camDenied'], ['NotFoundError', 'camNone'],
                              ['OverconstrainedError', 'camNone'], ['NotReadableError', 'camBusy'], ['AbortError', 'camBusy'], ['TypeError', 'camFailed']]) {
    const r = rig({ gumError: name });
    assertEq(await r.scan.start(), false, `${name}: start resolves false`);
    assertJson(r.log.errors, [code], name);
    assertEq(r.log.stopped[0].reason, 'error', `${name}: stop reason`);
  }
});

test('stop releases the camera and the worker and reports counts', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply(located('ok'));
  r.scan.stop('closed');
  assertEq(r.track.stopped, true, 'track stopped');
  assertEq(r.worker().terminated, true, 'worker terminated');
  assertJson(r.log.stopped, [{ reason: 'closed', frames: 1, accepted: 1 }], 'onStopped');
  assertEq(r.doc.count('visibilitychange'), 0, 'visibility listener removed');
  assertEq(r.win.count('pagehide'), 0, 'pagehide listener removed');
  r.scan.stop('closed');
  assertEq(r.log.stopped.length, 1, 'stop is idempotent');
});

test('hidden tab and pagehide pause (camera released); resume reopens the camera', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame();                                   // a decode in flight while hidden
  r.doc.visibilityState = 'hidden';
  r.doc.fire('visibilitychange');
  assertEq(r.scan.state, 'paused', 'paused');
  assertEq(r.track.stopped, true, 'camera released');
  assertEq(r.log.paused, 1, 'onPaused');
  assertEq(await r.scan.resume(), true, 'resume');
  assertEq(r.log.gum, 2, 'camera reopened');
  assertEq(r.scan.state, 'scanning', 'scanning again');
  assertEq(r.fireFrame(), true, 'frames flow again');

  r.win.fire('pagehide');
  assertEq(r.scan.state, 'paused', 'pagehide pauses');
});

test('a completing frame stops the scan with reason "complete"', async () => {
  const r = rig({ onFrame: async () => ({ kind: 'accepted', complete: true, rank: 5, total: 5 }) });
  await r.scan.start();
  r.fireFrame(); await r.reply(located('ok'));
  assertEq(r.scan.state, 'stopped', 'stopped');
  assertJson(r.log.stopped, [{ reason: 'complete', frames: 1, accepted: 1 }], 'onStopped');
});

test('stop during the permission prompt releases the late stream', async () => {
  const r = rig();
  const p = r.scan.start();
  r.scan.stop('closed');
  assertEq(await p, false, 'start resolves false');
  assertEq(r.track.stopped, true, 'the stream granted after close is released');
});

test('coverTransform scales to fill and centres the overflow', () => {
  let t = coverTransform(1280, 720, 640, 360);
  near(t.scale, 0.5, 'same aspect scale'); near(t.dx, 0, 'dx'); near(t.dy, 0, 'dy');
  t = coverTransform(1280, 720, 400, 800);                       // portrait phone, landscape video
  near(t.scale, 800 / 720, 'tall box scale'); near(t.dx, (400 - 1280 * 800 / 720) / 2, 'dx'); near(t.dy, 0, 'dy');
  t = coverTransform(640, 480, 1000, 500);                       // wide box
  near(t.scale, 1000 / 640, 'wide box scale'); near(t.dx, 0, 'dx'); near(t.dy, (500 - 480 * 1000 / 640) / 2, 'dy');
});

test('drawOverlay maps corners through the cover transform in tl-tr-br-bl order', () => {
  const ops = [];
  const g = {
    clearRect: (...a) => ops.push(['clear', ...a]), beginPath: () => ops.push(['begin']),
    moveTo: (x, y) => ops.push(['move', x, y]), lineTo: (x, y) => ops.push(['line', x, y]),
    closePath: () => ops.push(['close']), stroke: () => ops.push(['stroke']),
  };
  const canvas = { clientWidth: 640, clientHeight: 360, width: 0, height: 0, getContext: () => g };
  drawOverlay(canvas, 1280, 720, [0, 0, 1280, 0, 0, 720, 1280, 720], '#0f0');
  assertEq(canvas.width, 640, 'canvas sized to its box');
  assertJson(ops.filter((o) => o[0] === 'move' || o[0] === 'line'),
    [['move', 0, 0], ['line', 640, 0], ['line', 640, 360], ['line', 0, 360]], 'path');
  ops.length = 0;
  drawOverlay(canvas, 1280, 720, null, null);
  assertJson(ops, [['clear', 0, 0, 640, 360]], 'no corners -> cleared only');
});

(async () => {
  console.log('\ntest_live_scan.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web-app && node tests/test_live_scan.js`
Expected: FAIL — `Cannot find module '.../live-scan.js'`.

- [ ] **Step 3: Write the implementation**

Create `web-app/live-scan.js`:

```js
/**
 * live-scan.js — the live camera scanner (spec §6, §7, §9.3).
 *
 * LiveScan opens the camera, takes one frame at a time (a new frame is
 * requested only after the worker replied — Android's wantsFrame
 * back-pressure), posts its RGBA pixels to scan-worker.js, runs each reply
 * through CapturePolicy, applies focus/exposure lock where the browser
 * supports it, draws the finder overlay, and hands `ok` frames to the page
 * via onFrame. It knows nothing about sessions or i18n: the page owns the
 * assembler and turns hint/error codes into translated text.
 *
 * Every browser surface (camera, worker, frame clock, timers, document) is an
 * option with a real default, so tests/test_live_scan.js can drive it in Node.
 *
 * Loads after capture-policy.js. IIFE; exposes window.CimbarLiveScan /
 * module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const { CapturePolicy, isLocated } = isNode ? require('./capture-policy.js') : window.CimbarCapturePolicy;

const CAMERA_CONSTRAINTS = {
  audio: false,
  video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } },
};

const CAMERA_ERRORS = {
  NotAllowedError: 'camDenied', SecurityError: 'camDenied',
  NotFoundError: 'camNone', OverconstrainedError: 'camNone',
  NotReadableError: 'camBusy', AbortError: 'camBusy',
};

const COLOR_ACCEPTED = '#2ecc71';
const COLOR_LOCATED = '#f39c12';

/** object-fit: cover — scale to fill the box, centre the overflow. */
function coverTransform(srcW, srcH, boxW, boxH) {
  const scale = Math.max(boxW / srcW, boxH / srcH);
  return { scale, dx: (boxW - srcW * scale) / 2, dy: (boxH - srcH * scale) / 2 };
}

/** Clears the overlay; draws the finder quadrilateral when corners and color are given. */
function drawOverlay(canvas, srcW, srcH, corners, color) {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (canvas.width !== w) canvas.width = w;
  if (canvas.height !== h) canvas.height = h;
  const g = canvas.getContext('2d');
  g.clearRect(0, 0, w, h);
  if (!corners || !color) return;
  const t = coverTransform(srcW, srcH, w, h);
  // corners = [tlx, tly, trx, try, blx, bly, brx, bry]; draw tl, tr, br, bl.
  const order = [0, 2, 6, 4];
  g.strokeStyle = color;
  g.lineWidth = 4;
  g.beginPath();
  for (let k = 0; k < order.length; k++) {
    const x = corners[order[k]] * t.scale + t.dx, y = corners[order[k] + 1] * t.scale + t.dy;
    if (k === 0) g.moveTo(x, y); else g.lineTo(x, y);
  }
  g.closePath();
  g.stroke();
}

function supports(list) {
  return Array.isArray(list) && list.indexOf('manual') >= 0 && list.indexOf('continuous') >= 0;
}

/** Which of focus/exposure can be locked, from track.getCapabilities(). */
function lockSupport(caps) {
  const c = caps || {};
  return { focus: supports(c.focusMode), exposure: supports(c.exposureMode) };
}

function lockLabel(s) {
  if (s.focus && s.exposure) return 'focus+exposure';
  if (s.focus) return 'focus';
  if (s.exposure) return 'exposure';
  return 'unsupported';
}

/** advanced[] entries pinning the current values (one entry per concern, satisfied independently). */
function lockConstraints(support, settings) {
  const s = settings || {};
  const out = [];
  if (support.focus) {
    const f = { focusMode: 'manual' };
    if (typeof s.focusDistance === 'number') f.focusDistance = s.focusDistance;
    out.push(f);
  }
  if (support.exposure) {
    const e = { exposureMode: 'manual' };
    if (typeof s.exposureTime === 'number') e.exposureTime = s.exposureTime;
    out.push(e);
  }
  return out;
}

function unlockConstraints(support) {
  const out = [];
  if (support.focus) out.push({ focusMode: 'continuous' });
  if (support.exposure) out.push({ exposureMode: 'continuous' });
  return out;
}

/** One callback per new camera frame: requestVideoFrameCallback, else rAF polling currentTime. */
function defaultNextFrame(video, cb) {
  if (typeof video.requestVideoFrameCallback === 'function') {
    const h = video.requestVideoFrameCallback(() => cb());
    return () => video.cancelVideoFrameCallback(h);
  }
  const last = video.currentTime;
  let h;
  const tick = () => { if (video.currentTime !== last) cb(); else h = requestAnimationFrame(tick); };
  h = requestAnimationFrame(tick);
  return () => cancelAnimationFrame(h);
}

function makeGrabber() {
  let canvas = null, g = null;
  return function grabFrame(video) {
    const w = video.videoWidth, h = video.videoHeight;
    if (!w || !h) return null;                              // metadata not ready yet
    if (!canvas) {
      canvas = document.createElement('canvas');
      g = canvas.getContext('2d', { willReadFrequently: true });
    }
    if (canvas.width !== w) canvas.width = w;
    if (canvas.height !== h) canvas.height = h;
    g.drawImage(video, 0, 0, w, h);
    return g.getImageData(0, 0, w, h);
  };
}

function stopStream(stream) {
  if (stream) stream.getTracks().forEach((t) => t.stop());
}

const noop = () => {};

class LiveScan {
  constructor(opts) {
    this.o = Object.assign({
      overlay: null, debug: false, doc: null, win: null,
      createWorker: () => new Worker('scan-worker.js'),
      nextFrame: defaultNextFrame,
      grabFrame: null,
      now: () => performance.now(),
      setTimeout: (fn, ms) => setTimeout(fn, ms),
      clearTimeout: (t) => clearTimeout(t),
      timeoutMs: 10000, maxFailures: 3, pointAfterMs: 1000, fadeMs: 500,
      onFrame: () => null, onStatus: noop, onDebug: noop, onError: noop, onPaused: noop, onStopped: noop,
    }, opts);
    if (!this.o.grabFrame) this.o.grabFrame = makeGrabber();
    this.policy = new CapturePolicy();
    this.state = 'idle';
    this.stream = null; this.track = null; this.worker = null;
    this.support = { focus: false, exposure: false };
    this.lockEnabled = false;
    this.busy = false; this.inflight = null; this.seq = 0; this.timer = null; this.cancelFrame = null;
    this.failures = 0; this.frames = 0; this.accepted = 0;
    this.lastLocatedMs = 0; this.quadMs = -Infinity;
    this._onVisibility = () => { if (this.o.doc && this.o.doc.visibilityState === 'hidden') this.pause(); };
    this._onPageHide = () => this.pause();
    this._listening = false;
  }

  async start() {
    if (this.state !== 'idle' && this.state !== 'paused') return false;
    this.state = 'starting';
    this._listen(true);
    let stream;
    try {
      stream = await this.o.mediaDevices.getUserMedia(CAMERA_CONSTRAINTS);
    } catch (e) {
      if (this.state === 'starting') {
        this.o.onError(CAMERA_ERRORS[e && e.name] || 'camFailed');
        this.stop('error');
      }
      return false;
    }
    if (this.state !== 'starting') { stopStream(stream); return false; }   // closed during the prompt
    this.stream = stream;
    this.track = stream.getVideoTracks()[0];
    const caps = this.track && typeof this.track.getCapabilities === 'function' ? this.track.getCapabilities() : {};
    this.support = lockSupport(caps);
    this.lockEnabled = this.support.focus || this.support.exposure;
    try {
      this.o.video.srcObject = stream;
      await this.o.video.play();
    } catch (e) {
      this.o.onError('camFailed');
      this.stop('error');
      return false;
    }
    if (this.state !== 'starting') return false;
    if (!this.worker) this._spawn();
    this.policy.reset();
    this.lastLocatedMs = this.o.now();
    this.state = 'scanning';
    this._debug(`${this.o.video.videoWidth}x${this.o.video.videoHeight} lock=${lockLabel(this.support)} worker=ok`);
    this._schedule();
    return true;
  }

  resume() { return this.state === 'paused' ? this.start() : Promise.resolve(false); }

  pause() {
    if (this.state !== 'scanning') return;
    this.state = 'paused';
    this._cancelPending();
    stopStream(this.stream);
    this.stream = null; this.track = null;
    this.o.video.srcObject = null;
    this.o.onPaused();
  }

  stop(reason) {
    if (this.state === 'stopped') return;
    this.state = 'stopped';
    this._cancelPending();
    this._listen(false);
    if (this.worker) { this.worker.terminate(); this.worker = null; }
    stopStream(this.stream);
    this.stream = null; this.track = null;
    this.o.video.srcObject = null;
    this.o.onStopped({ reason, frames: this.frames, accepted: this.accepted });
  }

  _listen(on) {
    if (on === this._listening) return;
    this._listening = on;
    const verb = on ? 'addEventListener' : 'removeEventListener';
    if (this.o.doc) this.o.doc[verb]('visibilitychange', this._onVisibility);
    if (this.o.win) this.o.win[verb]('pagehide', this._onPageHide);
  }

  _cancelPending() {
    if (this.cancelFrame) { this.cancelFrame(); this.cancelFrame = null; }
    if (this.timer) { this.o.clearTimeout(this.timer); this.timer = null; }
    this.inflight = null;
    this.busy = false;
  }

  _spawn() {
    const w = this.o.createWorker();
    w.onmessage = (e) => this._onReply(w, e.data);
    w.onerror = (e) => {
      if (e && typeof e.preventDefault === 'function') e.preventDefault();
      if (w === this.worker) this._fail('worker error');
    };
    this.worker = w;
  }

  _schedule() {
    if (this.state !== 'scanning' || this.busy || this.cancelFrame) return;
    this.cancelFrame = this.o.nextFrame(this.o.video, () => { this.cancelFrame = null; this._onVideoFrame(); });
  }

  _onVideoFrame() {
    if (this.state !== 'scanning' || this.busy) return;
    const img = this.o.grabFrame(this.o.video);
    if (!img) { this._schedule(); return; }
    const id = ++this.seq;
    this.inflight = id;
    this.busy = true;
    this.frames++;
    const buffer = img.data.buffer;
    this.worker.postMessage({ id, width: img.width, height: img.height, buffer }, [buffer]);
    this.timer = this.o.setTimeout(() => { if (this.inflight === id) this._fail('timeout'); }, this.o.timeoutMs);
  }

  _fail(reason) {
    if (this.timer) { this.o.clearTimeout(this.timer); this.timer = null; }
    this.inflight = null;
    this.busy = false;
    this.failures++;
    this._debug(`worker failure ${this.failures}: ${reason}`);
    if (this.worker) { this.worker.terminate(); this.worker = null; }
    if (this.failures >= this.o.maxFailures) {
      this.o.onError('scanDecoderFailed');
      this.stop('decoderFailed');
      return;
    }
    if (this.state === 'scanning') { this._spawn(); this._schedule(); }
  }

  async _onReply(w, msg) {
    if (w !== this.worker || !msg || msg.id !== this.inflight) return;   // stale or foreign reply
    this.o.clearTimeout(this.timer);
    this.timer = null;
    this.inflight = null;
    if (msg.status === 'error') { this._fail('error: ' + msg.message); return; }
    this.failures = 0;

    const now = this.o.now();
    const decision = this.policy.update(msg, now);
    await this._applyLock(decision.lockAction);

    let res = null;
    if (msg.status === 'ok') {
      res = await this.o.onFrame(msg);
      if (res && res.kind === 'accepted') this.accepted++;
    }
    if (this.state !== 'scanning') return;              // closed or paused while we awaited

    const loc = isLocated(msg);
    if (loc) this.lastLocatedMs = now;
    let hint = decision.hint === 'none' ? null : decision.hint;
    if (!loc && now - this.lastLocatedMs > this.o.pointAfterMs) hint = 'point';
    this.o.onStatus({ hint });
    this._overlay(msg, res, loc, now);
    if (this.o.debug) this._debug(debugLine(this.seq, msg, res));

    this.busy = false;
    if (res && res.complete) { this.stop('complete'); return; }
    this._schedule();
  }

  async _applyLock(action) {
    if (!this.lockEnabled || action === 'none' || !this.track) return;
    const advanced = action === 'lock'
      ? lockConstraints(this.support, this.track.getSettings ? this.track.getSettings() : {})
      : unlockConstraints(this.support);
    if (!advanced.length) return;
    try {
      await this.track.applyConstraints({ advanced });
    } catch (e) {
      this.lockEnabled = false;
      this._debug(`lock failed (${action}): ${e && e.message}; locking disabled`);
    }
  }

  _overlay(msg, res, loc, now) {
    if (!this.o.overlay) return;
    const vw = this.o.video.videoWidth, vh = this.o.video.videoHeight;
    if (loc) {
      this.quadMs = now;
      const color = res && res.kind === 'accepted' ? COLOR_ACCEPTED : COLOR_LOCATED;
      drawOverlay(this.o.overlay, vw, vh, msg.corners, color);
    } else if (now - this.quadMs >= this.o.fadeMs) {
      drawOverlay(this.o.overlay, vw, vh, null, null);
    }
  }

  _debug(line) { this.o.onDebug(line); }
}

function debugLine(n, msg, res) {
  const d = msg.diag || {};
  let s = `#${n} ${msg.status} ${d.totalMs}ms loc=${d.locateMs} smp=${d.sampleMs} drf=${d.driftMs} rs=${d.rsMs} mod=${(msg.module || 0).toFixed(1)}`;
  if (res) s += ` ${res.kind} r=${res.rank}/${res.total}`;
  return s;
}

const API = { LiveScan, coverTransform, drawOverlay, lockSupport, lockConstraints, unlockConstraints, CAMERA_CONSTRAINTS, CAMERA_ERRORS };
if (isNode) module.exports = API; else window.CimbarLiveScan = API;
})();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd web-app && node tests/test_live_scan.js`
Expected: `Results: 18 passed, 0 failed`.

If the "hidden tab" test fails because a reply for the frame in flight at pause time arrives later: `pause()` clears `inflight`, so `_onReply` ignores it by id — confirm that path rather than changing the test.

- [ ] **Step 5: Add to the suite**

In `web-app/tests/run_all.sh`, directly after the scan-worker block:

```sh
echo ""; echo "--- Live scan controller (camera loop, lock, worker lifecycle) ---"
node tests/test_live_scan.js
```

- [ ] **Step 6: Commit**

```bash
git add web-app/live-scan.js web-app/tests/test_live_scan.js web-app/tests/run_all.sh
git commit -m "feat(web): LiveScan controller — frame loop, focus lock, worker lifecycle

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Page load order and deploy staging

**Files:**
- Modify: `web-app/index.html` (the `<script src>` list, currently ending `<script src="photo-decoder.js"></script>` / `<script src="i18n.js"></script>`)
- Modify: `.github/workflows/deploy-webapp.yml` (the `for f in … ; do` staging loop)
- Test: `web-app/tests/test_browser_load.js`, `web-app/tests/test_web_icons.js`

**Interfaces:**
- Consumes: `capture-policy.js`, `live-scan.js`, `scan-worker.js` (Tasks 1–3).
- Produces: `window.CimbarCapturePolicy` and `window.CimbarLiveScan` available to the inline page script (Task 6).

- [ ] **Step 1: Update the failing tests**

In `web-app/tests/test_browser_load.js`:

1. Rename the first test to `'index.html lists the twenty-one local scripts in dependency order'` and change its count line to:

```js
  assert(scripts.length === 21, `expected 21 local scripts, found ${scripts.length}: ${scripts.join(', ')}`);
```

2. In that same test, before the final `assert(scripts[scripts.length - 1] === 'i18n.js', …)`, add:

```js
  // live scan (spec §4): capture-policy.js before live-scan.js (which reads
  // CimbarCapturePolicy at load), both after the photo chain and before i18n.js.
  assert(scripts.indexOf('photo-decoder.js') < scripts.indexOf('capture-policy.js'), 'photo-decoder.js must precede capture-policy.js');
  assert(scripts.indexOf('capture-policy.js') < scripts.indexOf('live-scan.js'), 'capture-policy.js must precede live-scan.js');
  assert(scripts.indexOf('live-scan.js') < scripts.indexOf('i18n.js'), 'live-scan.js must precede i18n.js');
  assert(!scripts.includes('scan-worker.js'), 'scan-worker.js is a worker script and must not be a page <script>');
```

3. In `'the globals the inline page script uses are all defined'`, add `'CimbarCapturePolicy', 'CimbarLiveScan'` to the globals array just before `'CimbarI18n'`, and after the `CimbarPhoto.decode` assertion add:

```js
  assert(typeof w.CimbarLiveScan.LiveScan === 'function', 'CimbarLiveScan.LiveScan missing');
  assert(typeof w.CimbarCapturePolicy.CapturePolicy === 'function', 'CimbarCapturePolicy.CapturePolicy missing');
```

In `web-app/tests/test_web_icons.js`, add this test after `'the deploy workflow stages every local file the page links to'`:

```js
test('the deploy workflow stages the live-scan worker and every script it imports', () => {
  // The workflow's verify step checks <script src> and <link href> only; a
  // worker is created from JS (new Worker('…')) and pulls its own files with
  // importScripts, so a missing one would 404 only once someone scans.
  const staged = stagedFiles();
  const sources = ['live-scan.js', 'index.html'].map((f) => fs.readFileSync(path.join(root, f), 'utf8')).join('\n');
  const workers = [...sources.matchAll(/new Worker\('([^']+)'\)/g)].map((m) => m[1]);
  assert(workers.includes('scan-worker.js'), `expected new Worker('scan-worker.js'), found ${workers.join(', ') || 'none'}`);
  for (const w of workers) {
    assert(staged.includes(w), `deploy-webapp.yml does not stage the worker ${w}`);
    const src = fs.readFileSync(path.join(root, w), 'utf8');
    const call = src.match(/importScripts\(([\s\S]*?)\);/);
    assert(call, `${w} has no importScripts(...) call`);
    const files = [...call[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
    assert(files.length >= 10, `${w} imports only ${files.length} files`);
    for (const f of files) {
      assert(fs.existsSync(path.join(root, f)), `${w} imports ${f}, which does not exist`);
      assert(staged.includes(f), `deploy-webapp.yml does not stage ${f}, which ${w} imports`);
    }
  }
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd web-app && node tests/test_browser_load.js; node tests/test_web_icons.js`
Expected: `test_browser_load.js` FAIL `expected 21 local scripts, found 19`; `test_web_icons.js` FAIL `deploy-webapp.yml does not stage the worker scan-worker.js`.

- [ ] **Step 3: Add the script tags**

In `web-app/index.html`, replace

```html
<script src="photo-decoder.js"></script>
<script src="i18n.js"></script>
```

with

```html
<script src="photo-decoder.js"></script>
<script src="capture-policy.js"></script>
<script src="live-scan.js"></script>
<script src="i18n.js"></script>
```

- [ ] **Step 4: Stage the files for deploy**

In `.github/workflows/deploy-webapp.yml`, in the `for f in … ; do` line of the "Stage the deployable files" step, replace `photo-decoder.js i18n.js` with `photo-decoder.js capture-policy.js live-scan.js scan-worker.js i18n.js`. All three are `*.js`, which the upload/rollback Content-Type tables already cover; change nothing else.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd web-app && node tests/test_browser_load.js && node tests/test_web_icons.js && node tests/test_page_logic.js`
Expected: all PASS (`test_page_logic.js` is unaffected — it runs only the inline script).

- [ ] **Step 6: Commit**

```bash
git add web-app/index.html .github/workflows/deploy-webapp.yml web-app/tests/test_browser_load.js web-app/tests/test_web_icons.js
git commit -m "chore(web): load and stage the live-scan scripts and worker

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `addFrame` — one session, two sources

**Files:**
- Modify: `web-app/index.html` — `addPhoto` (the `// ── PHOTO DECODE` section near the end of the inline script)
- Test: `web-app/tests/test_page_logic.js`, `web-app/tests/test_browser_load.js`

**Interfaces:**
- Consumes: `photoSession`, `completePhotoSession`, `setProgress`, `CimbarFormat.decodeHeader`, `Cimbar.RatelessAssembler`.
- Produces (page-level functions, used by Task 6):
  - `addFrame(r) → { kind, reason, header, fileId, rank, total, complete }` — `r` is a decode result with `status === 'ok'`, `data`, `blocksFailed`. `kind ∈ 'accepted'|'duplicate'|'dependent'|'rejected'|'kept'|'done'|'busy'`. `fileId` is the frame header's fileId (set for `kept`). `complete` is `asm.isComplete()` after the add. Synchronous. Does not log, does not start completion.
  - `photoSessionGate() → 'done'|'busy'|null`.
  - `newPhotoSession() → { asm, photos, accepted, done, finishing }`.

- [ ] **Step 1: Write the failing tests**

In `web-app/tests/test_page_logic.js`:

1. Add `'addFrame'` to `REQUIRED_GLOBALS`:

```js
const REQUIRED_GLOBALS = ['addPhoto', 'addFrame', 'handleDecFile', 'startDecode', 'resetPhotoSession', 'finishDecode', 'isGifBytes'];
```

2. Append these tests before the final runner block:

```js
test('addFrame reports what happened without logging or completing — kinds', async () => {
  const { ctx, elements, calls } = freshPage();
  const f0 = makeFrame({ fileId: 4, seq: 0, total: 3 });
  let r = ctx.addFrame(okResult(f0));
  assertEq(r.kind, 'accepted', 'first frame accepted');
  assertEq(r.rank, 1, 'rank'); assertEq(r.total, 3, 'total'); assertEq(r.complete, false, 'not complete');
  r = ctx.addFrame(okResult(f0));
  assertEq(r.kind, 'duplicate', 'same frame again');
  r = ctx.addFrame(okResult(makeFrame({ fileId: 4, seq: 1, total: 3, compressed: true })));   // new seq, so not a duplicate
  assertEq(r.kind, 'rejected', 'flags mismatch is a plain rejection');
  assertEq(elements['logDec'].innerHTML, '', 'addFrame never logs');
  assertEq(elements['progDec'].style.display, 'block', 'progress shown');
  assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'start-over shown');

  calls.confirmResult = false;
  r = ctx.addFrame(okResult(makeFrame({ fileId: 9, seq: 0, total: 2 })));
  assertEq(r.kind, 'kept', 'foreign file, user keeps the session');
  assertEq(r.fileId, 9, 'foreign fileId reported');
  assertEq(r.rank, 1, 'session untouched');
});

test('addFrame returns complete: true and leaves completion to the caller', async () => {
  const { ctx, calls } = freshPage();
  const r = ctx.addFrame(okResult(makeCompletingFrame({ fileId: 2, seq: 0, total: 1 })));
  assertEq(r.kind, 'accepted', 'accepted');
  assertEq(r.complete, true, 'complete');
  await new Promise((res) => setTimeout(res, 0));
  assertEq(calls.anchorClicks, 0, 'addFrame itself must not start finishDecode');
  assertEq(calls.parsePayload, 0, 'no completion attempted');
});

test('addFrame on a finished session returns "done"', async () => {
  const { ctx } = freshPage();
  const data = makeCompletingFrame({ fileId: 7, seq: 0, total: 1 });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});                                  // completes and downloads
  assertEq(ctx.addFrame(okResult(data)).kind, 'done', 'done');
});
```

3. In `web-app/tests/test_browser_load.js`, the test `'addPhoto compares a decoded fileId against the assembler before add() (wrong-file guard)'` extracts `addPhoto`'s body. Retarget it to `addFrame`: rename the test to `'addFrame compares a decoded fileId against the assembler before add() (wrong-file guard)'`, change `extractFunctionBody(html, 'addPhoto')` to `extractFunctionBody(html, 'addFrame')`, and replace every `addPhoto` in that test's assertion messages with `addFrame`. The three regexes (`CimbarFormat\.decodeHeader\(`, the `.fileId !== null && … .fileId !== … .fileId` guard, `\.asm\.add\(`) stay as they are.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd web-app && node tests/test_page_logic.js; node tests/test_browser_load.js`
Expected: `test_page_logic.js` fails every test with `expected the inline page script to define a top-level function 'addFrame'`; `test_browser_load.js` FAIL `addFrame() not found in index.html`.

- [ ] **Step 3: Split `addPhoto`**

In `web-app/index.html`, replace the whole `async function addPhoto(file) { … }` (from its leading comment `// A finished session ignores further photos…` through its closing brace, just above `// ── Utilities`) with:

```js
function newPhotoSession() {
  return { asm: new Cimbar.RatelessAssembler(), photos: 0, accepted: 0, done: false, finishing: false };
}

// Why a frame cannot be added right now: 'done' — the session completed and
// ignores further frames until "Start over" (otherwise every later frame,
// almost certainly a duplicate, would re-fire decrypt/inflate/download);
// 'busy' — a completion attempt (PBKDF2 + decrypt) is still running and its
// outcome decides whether the session is done.
function photoSessionGate() {
  if (photoSession && photoSession.done) return 'done';
  if (photoSession && photoSession.finishing) return 'busy';
  return null;
}

// Adds one decoded `ok` frame to the photo session — shared by photos
// (addPhoto) and live scan. Reports what happened; the caller decides what to
// tell the user and runs completePhotoSession() when `complete` is true (a
// live scan closes the scanner first so the passphrase field is visible).
function addFrame(r) {
  const gate = photoSessionGate();
  if (gate) return { kind: gate };
  if (!photoSession) photoSession = newPhotoSession();

  // Wrong-file guard: rateless.js's add() silently resets the whole
  // collection when a frame carries a different fileId (harmless for a GIF —
  // one file, one fileId — but destructive across a photo session). Decode
  // the header ourselves and ask before that reset would happen.
  const h = CimbarFormat.decodeHeader(r.data);
  if (h.valid && photoSession.asm.fileId !== null && h.fileId !== photoSession.asm.fileId) {
    if (!confirm(t('photoWrongFile', { n: photoSession.asm.rank }))) {
      return { kind: 'kept', fileId: h.fileId, rank: photoSession.asm.rank, total: photoSession.asm.total, complete: false };
    }
    photoSession = newPhotoSession();
  }

  document.getElementById('progDec').style.display = 'block';
  document.getElementById('photoStartOverBtn').style.display = 'inline-flex';

  photoSession.photos++;
  const res = photoSession.asm.add(r.data, r.blocksFailed);
  if (res.accepted) photoSession.accepted++;
  const asm = photoSession.asm;
  setProgress(Math.round(100 * asm.rank / asm.total), t('photoKeepGoing', { rank: asm.rank, total: asm.total }),
              'progDecFill', 'progDecPct', 'progDecLabel');
  const kind = res.accepted ? 'accepted'
    : (res.reason === 'duplicate' || res.reason === 'dependent') ? res.reason
    : 'rejected';
  return { kind, reason: res.reason, header: res.header, fileId: h.valid ? h.fileId : null,
           rank: asm.rank, total: asm.total, complete: asm.isComplete() };
}

async function addPhoto(file) {
  const gate = photoSessionGate();
  if (gate === 'done') { log(t('photoAlreadyDone'), 'info', 'logDec'); return; }
  if (gate === 'busy') return;   // transient, so no log line

  document.getElementById('progDec').style.display = 'block';
  log(t('decoding'), 'info', 'logDec');
  await sleep(0); // let the browser paint the log line before the synchronous decode below blocks it

  let r;
  try {
    r = CimbarPhoto.decode(await toImageData(file));
  } catch (err) {
    logDecodeError(err);
    return;
  }
  if (r.status !== 'ok') {
    const key = { notLocated: 'errNotLocated', tooSmall: 'errTooSmall',
                  unsupportedGrid: 'errUnsupportedGrid', rsFailed: 'errRsFailed',
                  badHeader: 'errBadHeader' }[r.status];
    log(t(key), 'err', 'logDec');
    return;
  }

  const res = addFrame(r);
  if (res.kind === 'kept') { log(t('photoWrongFileKept'), 'info', 'logDec'); return; }
  if (res.kind === 'done' || res.kind === 'busy') return;
  if (res.kind === 'accepted') {
    log(t('photoAccepted', { seq: res.header.seq, rank: res.rank, total: res.total }), 'ok', 'logDec');
  } else {
    // duplicate/dependent are the normal result of re-photographing a
    // looping animation — not errors.
    const key = { duplicate: 'photoDuplicate', dependent: 'photoDependent', rs: 'rejRs',
                  short: 'rejShort', total: 'rejTotal', flags: 'rejFlags', uncoded: 'rejUncoded',
                  version: 'rejVersion', seq: 'rejSeq' }[res.reason];
    const isInfo = res.kind === 'duplicate' || res.kind === 'dependent';
    log(key ? t(key) : res.reason, isInfo ? 'info' : 'err', 'logDec');
  }
  if (res.complete) await completePhotoSession();
}
```

Also replace the two remaining inline session constructions elsewhere in the script, if any, with `newPhotoSession()` (search for `new Cimbar.RatelessAssembler(), photos: 0` — after this step it must appear only inside `newPhotoSession`).

Note: `complete` is `asm.isComplete()`, not "this frame completed it". That keeps today's behaviour: a frame arriving while a completed-but-failed session waits for its passphrase re-triggers the completion attempt (the existing test `'a completion that failed can be retried…'` relies on the second photo being processed).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd web-app && node tests/test_page_logic.js && node tests/test_browser_load.js && node tests/test_i18n.js`
Expected: all PASS — including every pre-existing `test_page_logic.js` test, unchanged.

- [ ] **Step 5: Commit**

```bash
git add web-app/index.html web-app/tests/test_page_logic.js web-app/tests/test_browser_load.js
git commit -m "refactor(web): split addFrame out of addPhoto for a second frame source

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Scanner view, page glue and i18n

**Files:**
- Modify: `web-app/index.html` — `<meta name="viewport">`, the CSS block, the Decode tab's buttons, markup next to `#present`, the inline script
- Modify: `web-app/i18n.js` — five language tables
- Test: `web-app/tests/test_page_logic.js`

**Interfaces:**
- Consumes: `CimbarLiveScan.LiveScan` (Task 3), `addFrame`/`photoSessionGate`/`completePhotoSession`/`resetPhotoSession` (Task 5).
- Produces (page-level): `openScanner()`, `closeScanner()`, `resumeScanner()`, `onScanFrame(s, r)`, `onScanStopped(s, info)`.

- [ ] **Step 1: Write the failing tests**

In `web-app/tests/test_page_logic.js`, inside `freshPage()`:

1. Add to `calls`: `liveScans: []`.
2. Add `documentStub.body = makeEl('body');` right after `documentStub` is defined.
3. Add these properties to `sandbox`:

```js
    navigator: { mediaDevices: { getUserMedia: async () => ({}) } },
    location: { search: '' },
    history: { state: null, pushState(s) { this.state = s; calls.pushes = (calls.pushes || 0) + 1; }, back() { this.state = null; calls.backs = (calls.backs || 0) + 1; } },
    Worker: class { constructor(u) { this.url = u; } },
    CimbarLiveScan: {
      LiveScan: class {
        constructor(o) { this.o = o; this.state = 'idle'; calls.liveScans.push(this); }
        async start() { this.state = 'scanning'; return true; }
        stop(reason) { if (this.state === 'stopped') return; this.state = 'stopped'; this.o.onStopped({ reason, frames: 0, accepted: 0 }); }
        async resume() { this.state = 'scanning'; return true; }
      },
    },
```

4. Add `'openScanner', 'closeScanner'` to `REQUIRED_GLOBALS`.

Then append these tests:

```js
const tick = () => new Promise((r) => setTimeout(r, 0));

test('live-scan frames and photos build ONE session', async () => {
  const { ctx, calls } = freshPage();
  const payload = Core.withLengthPrefix(Core.buildPayload('x.bin', new Uint8Array([1, 2, 3])));
  const f0 = makeFrameWithPayload(payload, { fileId: 6, seq: 0, total: 2 });
  const f1 = makeFrame({ fileId: 6, seq: 1, total: 2 });

  await ctx.openScanner();
  const scan = calls.liveScans[0];
  assert(scan, 'openScanner constructs a LiveScan');
  const r = await scan.o.onFrame(okResult(f0));
  assertEq(r.kind, 'accepted', 'live frame accepted');
  ctx.closeScanner();
  await tick();

  ctx.CimbarPhoto.decode = () => okResult(f1);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});                                   // the photo completes the SAME session
  assertEq(calls.anchorClicks, 1, 'the photo completed the file started by the live scan');
});

test('a wrong-file live frame prompts once; after "keep" that file is ignored silently', async () => {
  const { ctx, calls } = freshPage();
  await ctx.openScanner();
  const scan = calls.liveScans[0];
  await scan.o.onFrame(okResult(makeFrame({ fileId: 1, seq: 0, total: 3 })));
  calls.confirmResult = false;
  const foreign = okResult(makeFrame({ fileId: 2, seq: 0, total: 4 }));
  assertEq((await scan.o.onFrame(foreign)).kind, 'kept', 'first foreign frame: kept');
  assertEq(calls.confirmPrompts.length, 1, 'prompted once');
  assertEq((await scan.o.onFrame(okResult(makeFrame({ fileId: 2, seq: 1, total: 4 })))).kind, 'kept', 'second foreign frame: kept');
  assertEq(calls.confirmPrompts.length, 1, 'not prompted again for the same foreign file');
});

test('completion during a scan closes the scanner, then completes the session (encrypted retry intact)', async () => {
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 8, seq: 0, total: 1, encrypted: true });
  await ctx.openScanner();
  const scan = calls.liveScans[0];
  const r = await scan.o.onFrame(okResult(data));
  assertEq(r.complete, true, 'complete');
  scan.stop('complete');                                     // what LiveScan does on complete
  await tick();
  assert(!elements['scanner'].classList.contains('open'), 'scanner view closed');
  assert(calls.alerts.includes('encryptedNeedPass'), 'completion ran after the close (and failed: no passphrase)');

  elements['passDec'].value = 'pw';
  await ctx.startDecode();                                   // the existing recovery route
  assertEq(calls.decrypt, 1, 'retry decrypts from the intact assembler');
  assertEq(calls.anchorClicks, 1, 'file delivered');
});

test('opening the scanner clears a staged GIF; closing logs a summary and pops the history entry', async () => {
  const { ctx, elements, calls } = freshPage();
  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  await ctx.handleDecFile({ name: 'a.gif', size: 8, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }) });
  assert(elements['pillDec'].classList.contains('show'), 'setup: GIF staged');
  await ctx.openScanner();
  assert(!elements['pillDec'].classList.contains('show'), 'GIF pill cleared');
  assert(elements['scanner'].classList.contains('open'), 'scanner open');
  assertEq(calls.pushes, 1, 'history entry pushed');
  ctx.closeScanner();
  await tick();
  assertEq(calls.backs, 1, 'history entry consumed on close');
  assert(elements['logDec'].innerHTML.includes('scanSummary'), 'summary logged');
  await ctx.startDecode();
  assertEq(calls.alerts[calls.alerts.length - 1], 'selectGifFirst', 'decFile itself was cleared');
});

test('a camera error closes the scanner and explains in the Decode log', async () => {
  const { ctx, elements, calls } = freshPage();
  await ctx.openScanner();
  const scan = calls.liveScans[0];
  scan.o.onError('camDenied');
  scan.stop('error');
  await tick();
  assert(!elements['scanner'].classList.contains('open'), 'closed');
  assert(elements['logDec'].innerHTML.includes('camDenied'), 'error explained');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd web-app && node tests/test_page_logic.js`
Expected: every test FAILs with `expected the inline page script to define a top-level function 'openScanner'`.

- [ ] **Step 3: Markup, CSS and viewport**

In `web-app/index.html`:

1. Replace `<meta name="viewport" content="width=device-width, initial-scale=1.0">` with `<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">`.

2. Directly after the `#presentStatus { … }` CSS rule, add:

```css
/* Live scan (spec §9.3): full-viewport camera view over the page. */
body.scan-lock { overflow: hidden; }
#scanner { position: fixed; inset: 0; background: #000; z-index: 1001; display: none; }
#scanner.open { display: block; }
#scanVideo, #scanOverlay { position: absolute; inset: 0; width: 100%; height: 100%; }
#scanVideo { object-fit: cover; }
.scan-top, .scan-bottom { position: absolute; left: 0; right: 0; padding: 12px 16px; color: #fff; background: rgba(0,0,0,.45); }
.scan-top { top: 0; padding-top: calc(12px + env(safe-area-inset-top)); display: flex; justify-content: space-between; align-items: center; }
.scan-bottom { bottom: 0; padding-bottom: calc(12px + env(safe-area-inset-bottom)); text-align: center; }
.scan-close { background: none; border: 0; color: #fff; font-size: 24px; line-height: 1; cursor: pointer; padding: 4px 8px; }
#scanCount { font: 600 15px/1 var(--mono, monospace); }
#scanTrack { display: none; margin-bottom: 8px; }
#scanHint { min-height: 1.4em; font-size: 16px; }
#scanResumeBtn { display: none; margin-top: 8px; }
#scanDebug { display: none; max-height: 30vh; overflow: auto; margin: 8px 0 0; text-align: left; font: 11px/1.35 var(--mono, monospace); color: #9f9; white-space: pre-wrap; }
```

3. In the Decode tab, directly after the `Take a photo` button line, add:

```html
        <button type="button" class="btn btn-outline" id="scanBtn" style="margin-top:12px;display:none;" data-i18n="scanCamera" onclick="openScanner()">Scan with camera</button>
```

4. Directly after the `<div id="present" …>…</div>` line, add:

```html
<div id="scanner" role="dialog" aria-modal="true">
  <video id="scanVideo" playsinline muted autoplay></video>
  <canvas id="scanOverlay"></canvas>
  <div class="scan-top">
    <button type="button" class="scan-close" id="scanCloseBtn" title="Close" aria-label="Close" data-i18n-title="scanClose" onclick="closeScanner()">✕</button>
    <span id="scanCount"></span>
  </div>
  <div class="scan-bottom">
    <div class="progress-track" id="scanTrack"><div class="progress-fill" id="scanFill"></div></div>
    <div id="scanHint"></div>
    <button type="button" class="btn btn-primary" id="scanResumeBtn" data-i18n="scanResume" onclick="resumeScanner()">Resume</button>
    <pre id="scanDebug"></pre>
  </div>
</div>
```

- [ ] **Step 4: Page glue**

In the inline script of `web-app/index.html`:

1. Replace `document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closePresent(); });` with:

```js
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (scanner) closeScanner(); else closePresent();
});
```

2. Directly above `// ── Utilities`, add:

```js
// ── LIVE SCAN (camera → worker → the same photo session) ─────
let scanner = null;   // { scan, ignoreFileId, debugLines } while the scanner view is open
const SCAN_DEBUG = /[?&]debug=1(&|$)/.test(location.search);

if (navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function') {
  document.getElementById('scanBtn').style.display = '';
}

function scanHintText(hint) {
  switch (hint) {
    case 'point': return t('hintPoint');
    case 'moveCloser': return t('hintCloser');
    case 'moveBack': return t('hintBack');
    case 'holdStill': return t('hintStill');
    case 'adjustAngle': return t('hintAngle');
    default: return '';
  }
}

function scanErrorText(code) {
  switch (code) {
    case 'camDenied': return t('camDenied');
    case 'camNone': return t('camNone');
    case 'camBusy': return t('camBusy');
    case 'scanDecoderFailed': return t('scanDecoderFailed');
    default: return t('camFailed');
  }
}

function showScanProgress() {
  const asm = photoSession && photoSession.asm;
  const count = document.getElementById('scanCount');
  const track = document.getElementById('scanTrack');
  if (!asm || !asm.total) { count.textContent = ''; track.style.display = 'none'; return; }
  count.textContent = `${asm.rank} / ${asm.total}`;
  track.style.display = 'block';
  document.getElementById('scanFill').style.width = Math.round(100 * asm.rank / asm.total) + '%';
}

async function openScanner() {
  if (scanner) return;
  const gate = photoSessionGate();
  if (gate === 'busy') return;
  if (gate === 'done') resetPhotoSession();                  // the finished file was delivered; a new scan starts fresh
  if (photoSession && photoSession.asm.isComplete()) {       // complete but unfinished (e.g. passphrase missing)
    await completePhotoSession();
    return;
  }
  decFile = null;                                             // a GIF and a session are mutually exclusive
  document.getElementById('pillDec').classList.remove('show');

  const s = { scan: null, ignoreFileId: null, debugLines: [] };
  scanner = s;
  document.getElementById('scanner').classList.add('open');
  document.body.classList.add('scan-lock');
  document.getElementById('scanHint').textContent = t('scanStarting');
  document.getElementById('scanResumeBtn').style.display = 'none';
  document.getElementById('scanDebug').style.display = SCAN_DEBUG ? 'block' : 'none';
  document.getElementById('scanDebug').textContent = '';
  showScanProgress();
  history.pushState({ cimbarScanner: true }, '');
  document.getElementById('progDec').style.display = 'block';
  log(t('scanStarting'), 'info', 'logDec');

  s.scan = new CimbarLiveScan.LiveScan({
    video: document.getElementById('scanVideo'),
    overlay: document.getElementById('scanOverlay'),
    mediaDevices: navigator.mediaDevices,
    doc: document, win: window, debug: SCAN_DEBUG,
    onFrame: (r) => onScanFrame(s, r),
    onStatus: (st) => {
      if (scanner !== s) return;
      document.getElementById('scanHint').textContent = scanHintText(st.hint);
      showScanProgress();
    },
    onDebug: (line) => {
      if (scanner !== s || !SCAN_DEBUG) return;
      s.debugLines.push(line);
      if (s.debugLines.length > 50) s.debugLines.splice(1, 1);   // keep the header line
      const pre = document.getElementById('scanDebug');
      pre.textContent = s.debugLines.join('\n');
      pre.scrollTop = pre.scrollHeight;
    },
    onError: (code) => log(scanErrorText(code), 'err', 'logDec'),
    onPaused: () => {
      if (scanner !== s) return;
      document.getElementById('scanHint').textContent = t('scanPaused');
      document.getElementById('scanResumeBtn').style.display = '';
    },
    onStopped: (info) => onScanStopped(s, info),
  });
  await s.scan.start();
}

// A live frame goes through the same addFrame as a photo. After the user
// chose to keep their session over a different file, that file's frames are
// ignored silently for the rest of this scan — otherwise pointing at the
// other screen would re-prompt several times a second.
function onScanFrame(s, r) {
  const h = CimbarFormat.decodeHeader(r.data);
  if (h.valid && s.ignoreFileId !== null && h.fileId === s.ignoreFileId) {
    return { kind: 'kept', fileId: h.fileId, complete: false };
  }
  const res = addFrame(r);
  if (res.kind === 'kept') s.ignoreFileId = res.fileId;
  return res;
}

async function onScanStopped(s, info) {
  if (scanner !== s) return;
  scanner = null;
  document.getElementById('scanner').classList.remove('open');
  document.body.classList.remove('scan-lock');
  if (history.state && history.state.cimbarScanner) history.back();
  log(t('scanSummary', { frames: info.frames, accepted: info.accepted }), 'info', 'logDec');
  if (info.reason === 'complete') await completePhotoSession();
}

function closeScanner() { if (scanner) scanner.scan.stop('closed'); }

function resumeScanner() {
  if (!scanner) return;
  document.getElementById('scanResumeBtn').style.display = 'none';
  document.getElementById('scanHint').textContent = t('scanStarting');
  scanner.scan.resume();
}

// The browser Back gesture closes the scanner instead of leaving the page;
// by the time popstate fires our history entry is already gone, so
// onScanStopped sees history.state without cimbarScanner and does not go back again.
window.addEventListener('popstate', () => { if (scanner) scanner.scan.stop('back'); });
```

- [ ] **Step 5: i18n strings**

In `web-app/i18n.js`, add these keys to each language table (next to `takePhoto` is a good place). English:

```js
    scanCamera: 'Scan with camera',
    scanClose: 'Close',
    scanStarting: 'Starting camera…',
    scanPaused: 'Scanning paused',
    scanResume: 'Resume',
    hintPoint: 'Point at the barcode',
    hintCloser: 'Move closer',
    hintBack: 'Move back',
    hintStill: 'Hold still',
    hintAngle: 'Tilt to face the screen',
    camDenied: 'Camera permission denied — use “Take a photo” instead',
    camNone: 'No camera found — use “Take a photo” instead',
    camBusy: 'The camera is in use by another app',
    camFailed: 'Couldn’t start the camera — use “Take a photo” instead',
    scanDecoderFailed: 'The decoder stopped working — close the scanner and try again',
    scanSummary: 'Scanned {frames} frames, {accepted} accepted',
```

Russian (`ru`):

```js
    scanCamera: 'Сканировать камерой',
    scanClose: 'Закрыть',
    scanStarting: 'Запуск камеры…',
    scanPaused: 'Сканирование приостановлено',
    scanResume: 'Продолжить',
    hintPoint: 'Наведите камеру на штрихкод',
    hintCloser: 'Поднесите ближе',
    hintBack: 'Отодвиньте дальше',
    hintStill: 'Держите неподвижно',
    hintAngle: 'Держите камеру прямо напротив экрана',
    camDenied: 'Нет доступа к камере — используйте «Сделать фото»',
    camNone: 'Камера не найдена — используйте «Сделать фото»',
    camBusy: 'Камера занята другим приложением',
    camFailed: 'Не удалось запустить камеру — используйте «Сделать фото»',
    scanDecoderFailed: 'Декодер перестал работать — закройте сканер и попробуйте снова',
    scanSummary: 'Отсканировано кадров: {frames}, принято: {accepted}',
```

Ukrainian (`uk`):

```js
    scanCamera: 'Сканувати камерою',
    scanClose: 'Закрити',
    scanStarting: 'Запуск камери…',
    scanPaused: 'Сканування призупинено',
    scanResume: 'Продовжити',
    hintPoint: 'Наведіть камеру на штрихкод',
    hintCloser: 'Піднесіть ближче',
    hintBack: 'Відсуньте далі',
    hintStill: 'Тримайте нерухомо',
    hintAngle: 'Тримайте камеру прямо навпроти екрана',
    camDenied: 'Немає доступу до камери — скористайтеся «Зробити фото»',
    camNone: 'Камеру не знайдено — скористайтеся «Зробити фото»',
    camBusy: 'Камера зайнята іншою програмою',
    camFailed: 'Не вдалося запустити камеру — скористайтеся «Зробити фото»',
    scanDecoderFailed: 'Декодер перестав працювати — закрийте сканер і спробуйте знову',
    scanSummary: 'Відскановано кадрів: {frames}, прийнято: {accepted}',
```

Turkish (`tr`):

```js
    scanCamera: 'Kamerayla tara',
    scanClose: 'Kapat',
    scanStarting: 'Kamera başlatılıyor…',
    scanPaused: 'Tarama duraklatıldı',
    scanResume: 'Devam et',
    hintPoint: 'Kamerayı barkoda doğrultun',
    hintCloser: 'Yaklaştırın',
    hintBack: 'Uzaklaştırın',
    hintStill: 'Sabit tutun',
    hintAngle: 'Kamerayı ekrana düz tutun',
    camDenied: 'Kamera izni reddedildi — bunun yerine “Fotoğraf çek”i kullanın',
    camNone: 'Kamera bulunamadı — bunun yerine “Fotoğraf çek”i kullanın',
    camBusy: 'Kamera başka bir uygulama tarafından kullanılıyor',
    camFailed: 'Kamera başlatılamadı — bunun yerine “Fotoğraf çek”i kullanın',
    scanDecoderFailed: 'Çözücü çalışmayı durdurdu — taramayı kapatıp yeniden deneyin',
    scanSummary: '{frames} kare tarandı, {accepted} kare kabul edildi',
```

Georgian (`ka`):

```js
    scanCamera: 'კამერით სკანირება',
    scanClose: 'დახურვა',
    scanStarting: 'კამერა ირთვება…',
    scanPaused: 'სკანირება შეჩერებულია',
    scanResume: 'გაგრძელება',
    hintPoint: 'მიმართეთ კამერა შტრიხკოდს',
    hintCloser: 'მიიტანეთ უფრო ახლოს',
    hintBack: 'გასწიეთ უფრო შორს',
    hintStill: 'დაიჭირეთ უძრავად',
    hintAngle: 'დაიჭირეთ კამერა ეკრანის პირდაპირ',
    camDenied: 'კამერაზე წვდომა უარყოფილია — გამოიყენეთ „ფოტოს გადაღება“',
    camNone: 'კამერა ვერ მოიძებნა — გამოიყენეთ „ფოტოს გადაღება“',
    camBusy: 'კამერას სხვა აპი იყენებს',
    camFailed: 'კამერის ჩართვა ვერ მოხერხდა — გამოიყენეთ „ფოტოს გადაღება“',
    scanDecoderFailed: 'დეკოდერმა მუშაობა შეწყვიტა — დახურეთ სკანერი და სცადეთ ხელახლა',
    scanSummary: 'დასკანერდა {frames} კადრი, მიღებულია {accepted}',
```

Then extend `howDecodingHtml` in every table, and the English fallback text of the `data-i18n-html="howDecodingHtml"` callout in `index.html`, by inserting one sentence directly after the sentence about photographing a looping animation (the one ending "…until every frame is in." / its translation) and before the sentence about pixels:

- en: ` Scanning with the camera does the same continuously, several frames a second.`
- ru: ` Сканирование камерой делает то же самое непрерывно, по нескольку кадров в секунду.`
- uk: ` Сканування камерою робить те саме безперервно, по кілька кадрів на секунду.`
- tr: ` Kamerayla tarama aynısını kesintisiz, saniyede birkaç kare olarak yapar.`
- ka: ` კამერით სკანირება იგივეს აკეთებს უწყვეტად, წამში რამდენიმე კადრს.`

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd web-app && node tests/test_page_logic.js && node tests/test_i18n.js && node tests/test_browser_load.js`
Expected: all PASS. `test_i18n.js` checks every `t('…')` literal in `index.html` exists and every language has every key with matching `{frames}`/`{accepted}` placeholders.

- [ ] **Step 7: Manual smoke check in a desktop browser**

Run: `cd web-app && python3 -m http.server 8080`, open `http://localhost:8080/?debug=1`, go to the Decode tab, press "Scan with camera". Expected: permission prompt; the full-screen view with video, ✕ and "Starting camera…" then hints; the debug panel shows a header line (`<w>x<h> lock=… worker=ok`) and one line per frame. Press Escape: the view closes and the Decode log shows "Scanned N frames, M accepted". If no webcam is available, expect the view to close with "No camera found — use “Take a photo” instead" in the log. Report what you saw; do not skip this step silently.

- [ ] **Step 8: Commit**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/test_page_logic.js
git commit -m "feat(web): live camera scanner view feeding the photo session

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Local end-to-end with Chromium's fake camera

**Files:**
- Create: `web-app/tools/e2e_live_scan.js`

**Interfaces:**
- Consumes: the whole page (Tasks 1–6), `test-data/goldens/<name>.gif` + `.json`, `web-app/gif-decoder.js`.
- Produces: a local command; not part of CI or `run_all.sh`.

- [ ] **Step 1: Write the tool**

Create `web-app/tools/e2e_live_scan.js`:

```js
#!/usr/bin/env node
/**
 * e2e_live_scan.js — local end-to-end check of live scan (spec §11.2). Not in CI.
 *
 * Renders a golden GIF's frames (source + repair) into a looping 1280x720
 * .y4m, starts Chromium with that file as a fake camera, serves web-app/,
 * presses "Scan with camera" and asserts the download equals the golden's
 * payload. Proves the plumbing (getUserMedia -> frame callback -> worker ->
 * addFrame -> completion), not camera optics: the frames are pixel-perfect.
 *
 * Usage, from web-app/ (Playwright + Chromium resolvable via NODE_PATH):
 *   NODE_PATH=~/banana_split/node_modules node tools/e2e_live_scan.js [golden]
 * golden defaults to lorem_coded; lorem_coded_enc exercises the passphrase.
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

global.ImageData = global.ImageData || class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
const { GifDecoder } = require('../gif-decoder.js');

const root = path.join(__dirname, '..');
const goldens = path.join(root, '..', 'test-data', 'goldens');
const name = process.argv[2] || 'lorem_coded';
const W = 1280, H = 720, FPS = 30, HOLD = 6;           // each barcode frame shown for 200 ms

function clamp(v) { return v < 0 ? 0 : v > 255 ? 255 : Math.round(v); }

/** One RGBA barcode frame centred on black, as planar I420 (BT.601 full range, C420jpeg). */
function toI420(rgba, fw, fh) {
  const Y = Buffer.alloc(W * H), U = Buffer.alloc((W / 2) * (H / 2)), V = Buffer.alloc((W / 2) * (H / 2));
  const ox = (W - fw) >> 1, oy = (H - fh) >> 1;
  const px = (x, y) => {
    const fx = x - ox, fy = y - oy;
    if (fx < 0 || fy < 0 || fx >= fw || fy >= fh) return [0, 0, 0];
    const i = (fy * fw + fx) * 4;
    return [rgba[i], rgba[i + 1], rgba[i + 2]];
  };
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const [r, g, b] = px(x, y);
      Y[y * W + x] = clamp(0.299 * r + 0.587 * g + 0.114 * b);
    }
  }
  for (let y = 0; y < H; y += 2) {
    for (let x = 0; x < W; x += 2) {
      let r = 0, g = 0, b = 0;
      for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { const p = px(x + dx, y + dy); r += p[0]; g += p[1]; b += p[2]; }
      r /= 4; g /= 4; b /= 4;
      const i = (y / 2) * (W / 2) + x / 2;
      U[i] = clamp(128 - 0.168736 * r - 0.331264 * g + 0.5 * b);
      V[i] = clamp(128 + 0.5 * r - 0.418688 * g - 0.081312 * b);
    }
  }
  return Buffer.concat([Y, U, V]);
}

function writeY4m(file, frames) {
  const fd = fs.openSync(file, 'w');
  fs.writeSync(fd, `YUV4MPEG2 W${W} H${H} F${FPS}:1 Ip A1:1 C420jpeg\n`);
  for (const f of frames) {
    const yuv = toI420(f.imageData.data, f.width, f.height);
    for (let k = 0; k < HOLD; k++) { fs.writeSync(fd, 'FRAME\n'); fs.writeSync(fd, yuv); }
  }
  fs.closeSync(fd);
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.png': 'image/png',
                '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' };

function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
      const file = path.join(root, rel);
      if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

(async () => {
  let playwright;
  try { playwright = require('playwright'); } catch (e) {
    console.error('Playwright not found. Run with NODE_PATH=<a node_modules containing playwright> (Chromium installed).');
    process.exit(2);
  }
  const golden = JSON.parse(fs.readFileSync(path.join(goldens, `${name}.json`), 'utf8'));
  const frames = new GifDecoder(new Uint8Array(fs.readFileSync(path.join(goldens, `${name}.gif`)))).decode();
  const y4m = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'cimbar-e2e-')), `${name}.y4m`);
  writeY4m(y4m, frames);
  console.log(`${name}: ${frames.length} frames -> ${y4m}`);

  const server = await serve();
  const url = `http://127.0.0.1:${server.address().port}/index.html?debug=1`;
  const browser = await playwright.chromium.launch({
    args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${y4m}`],
  });
  let ok = false;
  try {
    const context = await browser.newContext({ acceptDownloads: true, permissions: ['camera'] });
    const page = await context.newPage();
    page.on('pageerror', (e) => console.log('[pageerror]', e.message));
    await page.goto(url);
    await page.click('button[onclick*="\'decode\'"]');
    if (golden.passphrase) await page.fill('#passDec', golden.passphrase);
    const download = page.waitForEvent('download', { timeout: 120000 });
    await page.click('#scanBtn');
    const d = await download;
    const got = fs.readFileSync(await d.path());
    const want = Buffer.from(golden.fileBytesBase64, 'base64');
    ok = got.equals(want) && d.suggestedFilename() === golden.fileName;
    console.log(`download ${d.suggestedFilename()} ${got.length} bytes: ${ok ? 'MATCHES' : 'DIFFERS FROM'} the golden`);
    if (!ok) console.log(await page.textContent('#logDec'));
  } catch (e) {
    console.log(`FAILED: ${e.message}`);
  } finally {
    await browser.close();
    server.close();
  }
  process.exit(ok ? 0 : 1);
})();
```

- [ ] **Step 2: Run it**

Run: `cd web-app && NODE_PATH=~/banana_split/node_modules node tools/e2e_live_scan.js`
Expected: `download lorem.bin … MATCHES the golden`, exit 0.

Then: `cd web-app && NODE_PATH=~/banana_split/node_modules node tools/e2e_live_scan.js lorem_coded_enc`
Expected: MATCHES (the passphrase is typed before scanning).

If it times out, rerun after adding `page.on('console', (m) => console.log('[page]', m.text()))` and print `await page.textContent('#scanDebug')` before closing; the per-frame debug lines show whether frames are located (`notLocated` everywhere suggests the y4m colour conversion; `rsFailed` suggests chroma subsampling damage). Report the finding; do not change decode modules (Global Constraints).

- [ ] **Step 3: Commit**

```bash
git add web-app/tools/e2e_live_scan.js
git commit -m "test(web): local fake-camera end-to-end for live scan

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Documentation and full verification

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-09-21-web-live-scan-design.md` (status line only)

**Interfaces:**
- Consumes: everything above.
- Produces: documentation.

- [ ] **Step 1: Update `CLAUDE.md`**

Make these edits:

1. After the "Photo decode pipeline" section's second paragraph (ending "…while a repeat download is still impossible."), add:

```markdown
**Live scan** (Decode tab, "Scan with camera") is a second source of frames for the same `photoSession`: `live-scan.js`'s `LiveScan` opens the rear camera (`getUserMedia`, ideal 1920×1080), grabs one video frame at a time (a new frame only after the previous reply), transfers its RGBA pixels to `scan-worker.js` — a stateless Web Worker that `importScripts` the decode chain and runs the unmodified `CimbarPhoto.decode` — and feeds each `ok` reply to the page's `addFrame`, the function `addPhoto` also calls, so photos and live frames build one assembler with one wrong-file guard. `capture-policy.js` (port of Android's `CapturePolicy`) turns each reply into a hint and a focus/exposure lock action; locking is applied only where `track.getCapabilities()` lists `manual` and `continuous` (Chrome on Android) and is otherwise ignored — Safari, Firefox and every iOS browser scan with continuous autofocus. When `addFrame` reports `complete`, the scanner closes first and then runs `completePhotoSession()`, so the passphrase field and the Decode-button retry are visible. `?debug=1` shows a per-frame timing panel. Design: `docs/superpowers/specs/2026-09-21-web-live-scan-design.md`.
```

2. In the module list, after the `photo-decoder.js` bullet, add:

```markdown
- `capture-policy.js` — live-scan acquisition policy: `CapturePolicy.update(outcome, nowMs) → {hint, lockAction}` (lock on the first located frame, unlock 2 s after losing it; hints from module size 6–40 px, corner motion > 10 px, `rsFailed`) and `isLocated`; port of Android's `CapturePolicy`, plus the web-only `tooSmall` status counting as located. Pure logic. Exposes `window.CimbarCapturePolicy`
- `live-scan.js` — `LiveScan` controller: camera open/close/pause, one-frame-in-flight loop, worker spawn/respawn (10 s timeout, stop after 3 consecutive failures), focus/exposure lock via `applyConstraints` pinning the current `focusDistance`/`exposureTime`, finder overlay (`coverTransform`, `drawOverlay`), debug lines. Every browser surface is an option, so it is testable in Node. Loads after `capture-policy.js`. Exposes `window.CimbarLiveScan`
- `scan-worker.js` — the live-scan Web Worker: sets `self.window = self`, `importScripts` the decode chain in page order, answers `{id, width, height, buffer}` with `{id, status, data, blocksFailed, corners, module, diag}` (or `status: 'error'`). **Not** a page `<script>`; staged for deploy explicitly
- `tools/e2e_live_scan.js` — local (not CI) end-to-end: renders a golden into a `.y4m`, runs Playwright Chromium with it as a fake camera, asserts the scanned download equals the golden payload. Usage: `NODE_PATH=~/banana_split/node_modules node tools/e2e_live_scan.js [golden]`
```

3. In "Web App Tests": change the `run_all.sh` comment's list to include `+ capture policy + scan worker + live scan`; add `node tests/test_capture_policy.js`, `node tests/test_scan_worker.js`, `node tests/test_live_scan.js` to the command list; change "runs six of the eighteen Node tests" and "`sh tests/run_all.sh` runs all" / "is what runs all eighteen" to twenty-one; add to the `test_pipeline.py` row's exclusion list `test_capture_policy.js`, `test_scan_worker.js`, `test_live_scan.js`.

4. Add table rows:

```markdown
| `tests/test_capture_policy.js` | `capture-policy.js`: case-for-case port of `capture_policy_test.dart` (lock/unlock timing, module/motion/`rsFailed` hints, reset), plus `tooSmall` with corners → `moveCloser` and without corners → not located. |
| `tests/test_scan_worker.js` | `scan-worker.js` run in a `vm` context with a real `importScripts` (one shared scope, no `window` until the shim): imports follow `index.html` order; for every `test-data/scenes/` fixture the reply equals a direct `CimbarPhoto.decode` (status, blocksFailed, corners, module, data bytes); a blank frame replies `notLocated`; a throwing decode replies `status: 'error'`. |
| `tests/test_live_scan.js` | `live-scan.js` against fake camera/track/worker/frame clock/timers: camera constraints, one frame in flight, buffer transferred, lock pins current settings only where `manual`+`continuous` are supported and unlock restores `continuous`, rejected lock disables locking without stopping, only `ok` frames reach `onFrame`, hint timing, worker respawn on error/error-event/timeout and stop after three in a row, stale replies ignored, camera error codes, stop/pause/resume lifecycle, `coverTransform`, `drawOverlay`. |
```

5. Update the `test_browser_load.js` row: "nineteen page scripts" → "twenty-one page scripts"; add `CimbarCapturePolicy`, `CimbarLiveScan` to its globals list; add "`capture-policy.js` before `live-scan.js`, both before `i18n.js`; `scan-worker.js` is not a page script"; change "assert `addPhoto` decodes a frame's header…" to "`addFrame`". Update the `test_page_logic.js` row to mention `addFrame` kinds and the live-scan session integration (shared session with photos, wrong-file prompt once then ignored, completion closes the scanner before `completePhotoSession`, a staged GIF cleared when scanning starts, camera error closes the view). Update the `test_web_icons.js` row: "every `new Worker('…')` target and every file it `importScripts` is staged".

6. In "Known Subtleties (Web)", change "`tests/test_browser_load.js` enforces it for all nineteen scripts" to "twenty-one", and add:

```markdown
- **A Web Worker has no `window`.** Every decode module picks `window.X` when `module` is undefined, so `scan-worker.js` sets `self.window = self` before `importScripts`; the imported files then run in one shared scope exactly like the page. The worker is created from JS, so the deploy workflow's `<script src>` check cannot see it — `test_web_icons.js` checks the worker and its `importScripts` list are staged instead.
```

- [ ] **Step 2: Mark the spec implemented**

In `docs/superpowers/specs/2026-09-21-web-live-scan-design.md`, change `Status: Designed; not implemented` to `Status: Implemented (plan: docs/superpowers/plans/2026-09-21-web-live-scan.md)`.

- [ ] **Step 3: Full suite**

Run: `cd web-app && sh tests/run_all.sh`
Expected: ends with `=== All tests passed ===`.

Run: `cd web-app && python3 tests/test_pipeline.py`
Expected: passes (it runs six Node tests, unchanged).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-09-21-web-live-scan-design.md
git commit -m "docs: live scan modules, tests and pipeline

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## After the plan

Not tasks for the implementer — for the human, before release (spec §11.3): run the manual device checklist (Android Chrome, iPhone Safari, iPhone Chrome, Firefox for Android, a desktop webcam) against a deploy, with `?debug=1`, and record resolution, lock state, per-stage timings and accepted fps. `locateMs` dominating on phones is the trigger for the deferred ROI work.
