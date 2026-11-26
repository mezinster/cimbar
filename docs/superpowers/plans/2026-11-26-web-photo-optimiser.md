# Web Photo Optimiser + HEIC Everywhere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The CimBar web app gets Choose photo, an Optimise photo screen that fits a photo into N frames by the app's rules, and HEIC/HEIF decoding in every browser.

**Architecture:** Five new classic page scripts in `web-app/` (IIFE-wrapped, one `window.Cimbar*` export each, `module.exports` when `module` exists — the pattern of `cimbar.js`), transliterated from NFC Archiver's TypeScript (`~/nfcarchiver/webapp/src/photo/*.ts`, `app/ui/canvas-jpeg.ts`, `app/ui/photo-optimiser.ts`, tests in `~/nfcarchiver/webapp/test/`). HEIC falls back to a vendored, unmodified libheif-js 1.23.5 WebAssembly build run in a short-lived worker. DOM glue lives in `index.html`'s inline script like every other screen.

**Tech Stack:** Plain browser JS (no build step, no npm), Canvas 2D / `createImageBitmap`, Web Workers, WebAssembly; Node test scripts (`node tests/test_*.js`, own tiny `test()` helper as in `tests/test_text_message.js`); Dart `flutter test` for the shared-fixture side.

**Spec:** `docs/superpowers/specs/2026-11-26-web-photo-optimiser-design.md` (approved 2026-11-26). Read it before your task; it is the authority where this plan is silent.

## Global Constraints

- No build step, no npm, no `package.json` in `web-app/`; it must still run from `python3 -m http.server`.
- Every page script shares ONE global scope: wrap each new file in an IIFE; no top-level `const`/`let`/`class` outside it (`tests/test_browser_load.js` enforces).
- Exports: `photo-fit.js` → `CimbarPhotoFit`; `jpeg-metadata.js` → `CimbarJpegMeta`; `image-decode.js` → `CimbarImageDecode`; `canvas-jpeg.js` → `CimbarCanvasJpeg`; `photo-optimiser.js` → `CimbarPhotoOptimiser`. `heic-worker.js` is a Worker, never a page script.
- Frame budget: 2104 file bytes per frame (`CimbarFormat.fileBytesPerFrame()`); framed = 4 + 4 + UTF-8 name bytes + data + 48 when encrypted; the optimiser always reserves the 48.
- Presets `[320, 480, 640, 800, 1024, 1280, 1440, 1600, 1920, 2560, 3840]` + Original; never upscale; pick largest side reaching q ≥ 50, else largest fitting at q ≥ 30, else smallest result unfit.
- Starting N = frames of the 640 px / q70 encode; stepper range 1 … min(frames of the original as picked, 4096); 250 ms re-fit debounce.
- Output name: stem + `.jpg`; no name or bare-UUID stem → `photo-yyyyMMdd-HHmmss.jpg` (local time).
- Canvas cap 16,000,000 px; at most 2 live scaled canvases; HEIF primary image cap 64,000,000 px; decoded bitmap downscaled to ≤ 16,000,000 px.
- libheif files byte-for-byte unmodified; no third-party network request, no CDN; libheif loads only when native decode failed on a HEIF file.
- HEIF sniff: `ftyp` major brand ∈ {heic, heix, heim, heis, hevc, hevx, mif1, msf1} and no compatible brand `avif`/`avis`.
- GIF (magic bytes `GIF8`) and SVG are never optimised.
- New UI strings in all seven languages (en, ru, uk, tr, ka, pl, be); reuse the app's ARB wording (`app/lib/l10n/app_<lang>.arb`, keys `photo*`) where it exists; plurals via the `[[param|form…]]` syntax in `i18n.js`.
- Never touch the camera decode chain (`photo-decoder.js` and its eight modules), `test-data/goldens/` or `test-data/scenes/`.
- Web tests: `cd web-app && sh tests/run_all.sh`. App tests: `cd app && sh tests/run_all.sh` (never bare `flutter test`).

## Review Focus

1. **A photo whose original is smaller than one frame or already tiny** (e.g. a 3 KB PNG icon): cap is 1, the stepper must not go to 0, and the result is likely `largerThanOriginal` — Skip must remain the obvious choice, no crash. → Task 5 test `tiny original: cap 1, stepper clamps, largerThanOriginal`.
2. **The user picks a second photo while the optimiser is still fitting the first.** The old controller must be disposed and its late results must not overwrite the new screen. → Task 7 test `second pick while fitting disposes the first optimiser`.
3. **HEIC labelled `application/octet-stream` with a `.HEIC` or no extension** (Android galleries do this): must still reach the optimiser and decode. → Task 3 test `octet-stream HEIF still sniffed` and Task 7 test `octet-stream .heic via Choose a file opens the optimiser`.
4. **libheif fails to load or the worker errors** (offline cache miss, blocked wasm, CSP): the user gets "This photo can't be read" with Skip, never a stuck spinner. → Task 3 test `worker error rejects with PhotoDecodeError` and `compile failure rejects with PhotoDecodeError`.
5. **A passphrase typed after Continue** must not raise the frame count above what the optimiser showed. → Task 7 test `frame estimate on pill counts encryption; encoding the optimised file with a passphrase needs ≤ shown frames`.

---

### Task 1: `photo-fit.js` — fit, budget, names, shared Dart↔JS fixture

**Files:**
- Create: `web-app/photo-fit.js`, `web-app/tests/test_photo_fit.js`, `test-data/photo-fit.json`, `app/test/features/photo/photo_fit_fixture_test.dart`
- Modify: `web-app/tests/run_all.sh` (add the test after the text-message test)

**Interfaces:**
- Consumes: `CimbarFormat.fileBytesPerFrame()` (2104) — in Node `require('./format.js')`, in the browser `window.CimbarFormat`.
- Produces (`window.CimbarPhotoFit` / `module.exports`):
  - `PHOTO_PRESETS: number[]`
  - `candidateSides(longest: number): number[]`
  - `fitToBudget(session, budget: number): Promise<{maxSide, quality, bytes: Uint8Array, fits: boolean}>` — session is `{width, height, encode(maxSide, quality): Promise<Uint8Array>, close()}`
  - `encodeManual(session, {maxSide, quality, budget}): Promise<same shape>`
  - `ENCRYPTION_OVERHEAD = 48`, `MAX_FRAMES = 4096`
  - `framedBytes(nameBytes: number, dataBytes: number, encrypted: boolean): number`
  - `framesForFile(name: string, dataBytes: number, encrypted: boolean): number`
  - `photoByteBudget(frames: number, name: string): number`
  - `optimisedFileName(original: string|undefined, now: Date): string`
  - `isOptimisable(name: string, type: string, head?: Uint8Array, sniff?: (head) => boolean): boolean` — false for GIF (type `image/gif`, extension `.gif`, or `head` starting `GIF8`) and for `image/svg+xml`, `image/tiff`, `image/x-icon`, `image/vnd.microsoft.icon`; otherwise true for any other `image/*` type, the extensions `jpg jpeg png webp heic heif` (case-insensitive), or when `sniff(head)` is true. The page passes `CimbarImageDecode.sniffHeif` as `sniff` (Task 3); `photo-fit.js` keeps no copy of the HEIF rule.

- [ ] **Step 1: Write `test-data/photo-fit.json` and the failing JS test.** Fixture shape:
  ```json
  { "bytesPerFrame": 2104,
    "model": "bytes = floor(s*s*q/1000), s = min(maxSide, max(width,height))",
    "budget": [ {"frames": 1, "name": "IMG_1234.jpg", "budget": <from Dart>}, ... ],
    "frames": [ {"name": "a.jpg", "dataBytes": 0, "encrypted": false, "frames": 1}, ... ],
    "fit": [ {"width": 3024, "height": 4032, "budget": 200000, "maxSide": ..., "quality": ..., "fits": true}, ... ],
    "names": [ {"original": "IMG_1234.HEIC", "now": "2026-11-26T10:20:30", "out": "IMG_1234.jpg"},
               {"original": "", ...,"out": "photo-20261126-102030.jpg"},
               {"original": "0F8FAD5B-D9CB-469F-A165-70867728950E.png", ..., "out": "photo-20261126-102030.jpg"} ] }
  ```
  At least 6 budget, 8 frames (incl. 2104/2105-byte boundaries, encrypted and not, a multi-byte UTF-8 name, a name long enough to make the budget ≤ 0), 6 fit (the five cases of the Dart `photo_fit_test.dart` incl. the q30 fallback with model `floor(s*s*q*q*q/100000)` marked `"model": "steep"`, a tiny image, budget ≤ 0) and 4 name cases. Fill expected values by running the Dart implementation (Step 3 makes the Dart test authoritative; adjust the JSON until the Dart test passes, then never hand-edit values to suit JS).
  `test_photo_fit.js` asserts every fixture case against `photo-fit.js` with a fake session implementing the model, plus ports of `~/nfcarchiver/webapp/test/photo-fit.test.ts` and `photo-budget.test.ts` (tags → frames, payloadSize → 2104), plus `isOptimisable` cases: `('a.gif','image/gif')` false, `('a.HEIC','')` true, `('x','application/octet-stream', heifHead, sniff)` true, `('x.jpg','image/jpeg', gifHead)` false, `('a.svg','image/svg+xml')` false.
- [ ] **Step 2: Run** `cd web-app && node tests/test_photo_fit.js` → FAIL (module missing).
- [ ] **Step 3: Write `photo_fit_fixture_test.dart`** reading `../test-data/photo-fit.json` (path helper as in `app/test/core/format/text_message_test.dart`), asserting `budget`/`frames` against `lib/core/encode/frame_budget.dart` and `fit`/`names` against `photo_fit.dart` + `optimised_file_name.dart` using `test/support/fake_jpeg_session.dart`. Run `cd app && flutter test test/features/photo/photo_fit_fixture_test.dart` → PASS once the JSON values are right.
- [ ] **Step 4: Implement `web-app/photo-fit.js`** by transliterating `fit.ts`/`budget.ts` (fit search unchanged; budget per Global Constraints; UUID rule = stem matches `/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i`).
- [ ] **Step 5: Run** `node tests/test_photo_fit.js` → all PASS; add it to `run_all.sh`; `sh tests/run_all.sh` green.
- [ ] **Step 6: Commit** `feat(web): photo fit and frame budget, shared fixture with the app`.

### Task 2: `jpeg-metadata.js`

**Files:** Create `web-app/jpeg-metadata.js`, `web-app/tests/test_jpeg_metadata.js`; modify `run_all.sh`.

**Interfaces:** Produces `CimbarJpegMeta.stripJpegMetadata(jpeg: Uint8Array): Uint8Array` (throws on non-JPEG/malformed).

- [ ] **Step 1: Port** `~/nfcarchiver/webapp/test/jpeg-metadata.test.ts` to `test_jpeg_metadata.js` (APP1–APP15 and COM dropped, APP0 kept, DQT/SOF/SOS/entropy untouched, bytes after first EOI dropped, FF fill bytes, non-JPEG and truncated input throw).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** by transliterating `src/photo/jpeg-metadata.ts`.
- [ ] **Step 4: Run** → PASS; add to `run_all.sh`.
- [ ] **Step 5: Commit** `feat(web): strip JPEG metadata`.

### Task 3: Vendored libheif, `heic-worker.js`, `image-decode.js`

**Files:**
- Create: `web-app/vendor/libheif/{libheif.js,libheif.wasm,LICENSE,DAV1D-LICENSE,README.md}`, `web-app/heic-worker.js`, `web-app/image-decode.js`, `web-app/tests/test_image_decode.js`, `test-data/photos/rotated.heic`, `test-data/photos/README.md`
- Modify: `run_all.sh`

**Interfaces:**
- Produces (`window.CimbarImageDecode`):
  - `sniffHeif(head: Uint8Array): boolean` (reads the `ftyp` box: size, `ftyp`, major brand, minor version, compatible brands)
  - `class PhotoDecodeError extends Error`, `class ImageTooLargeError extends Error`
  - `MAX_HEIF_PIXELS = 64_000_000`, `MAX_BITMAP_PIXELS = 16_000_000`
  - `decodeImage(blob: Blob): Promise<ImageBitmap>` — native `createImageBitmap(blob, {imageOrientation: 'from-image'})` first; on failure, if `sniffHeif(first 64 bytes)` → worker path; else `PhotoDecodeError`.
  - `_impl` seam for tests: `{ createImageBitmap, createWorker(url), compileWasm(url) }`, replaceable.
- Worker protocol: main → `{module: WebAssembly.Module, buffer: ArrayBuffer}` (buffer transferred); worker → `{ok: true, width, height, rgba: ArrayBuffer}` (transferred) or `{ok: false, code: 'decode_failed' | 'too_large'}`. Main thread: compiles `vendor/libheif/libheif.wasm` once (`WebAssembly.compileStreaming(fetch(url))`, memoised promise), creates a fresh `new Worker('heic-worker.js')` per decode and `terminate()`s it after the reply/error; worker `error` event or compile failure → `PhotoDecodeError`; `too_large` → `ImageTooLargeError`. RGBA → `ImageData` → `createImageBitmap(imageData, {resizeWidth, resizeHeight, resizeQuality: 'high'})` scaled so w×h ≤ 16 MP (only when larger).
- `heic-worker.js`: `self.window = self; importScripts('vendor/libheif/libheif.js')`; instantiate with `libheif({ instantiateWasm(imports, done) { WebAssembly.instantiate(module, imports).then(i => done(i)); return {}; }, locateFile: (p) => 'vendor/libheif/' + p })`; `new lib.HeifDecoder().decode(new Uint8Array(buffer))`, take image 0, check `get_width() * get_height() ≤ 64e6` before `display(...)`, reply. Check the exact libheif-js API in Node first (`node -e` with `require('./vendor/libheif/libheif.js')({wasmBinary})`).

- [ ] **Step 1: Vendor.** `npm pack libheif-js@1.23.5` in the scratchpad (not in the repo), copy `package/libheif-wasm/libheif.js`, `package/libheif-wasm/libheif.wasm`, `package/libheif-wasm/LICENSE` into `web-app/vendor/libheif/` unmodified; add `DAV1D-LICENSE` (dav1d's BSD-2-Clause text from its upstream `COPYING`, VideoLAN copyright line); write `README.md` with version 1.23.5, `https://github.com/catdad-experiments/libheif-js` and upstream libheif/libde265/dav1d URLs, LGPL-3.0/BSD-2-Clause, "unmodified; replace both files to upgrade", and `sha256sum` of each vendored file.
- [ ] **Step 2: Make the fixture.** In a scratchpad venv, `pip install pillow-heif`; write a 64×32 image (left half red `#ff0000`, right half blue `#0000ff`) as HEIC with EXIF orientation 6 so the file stores an `irot` transform (verify: decoded by libheif in Node it comes out **32×64** with red on top). No other metadata. Commit as `test-data/photos/rotated.heic` (≤ 50 KB) with a `README.md` giving the exact script. If the tools can't produce an `irot`, stop and report BLOCKED with what you tried.
- [ ] **Step 3: Write failing `test_image_decode.js`:** `sniffHeif` true for `heic`/`mif1` major brands, true for octet-stream bytes of `rotated.heic`, false for major `avif`, false for `mif1` with compatible `avif`, false for JPEG/PNG/GIF heads, short (< 12 bytes) and garbage input; vendored SHA-256s equal `vendor/libheif/README.md`; **real decode in Node** of `rotated.heic` through `vendor/libheif/libheif.js` (`wasmBinary`) → 32×64, pixel (16, 8) red, pixel (16, 56) blue; `decodeImage` with stubbed `_impl`: native success returns it without touching the worker; native failure + non-HEIF → `PhotoDecodeError`; `worker error rejects with PhotoDecodeError`; `compile failure rejects with PhotoDecodeError`; `too_large` reply → `ImageTooLargeError`; worker is terminated after success and after failure; compile called once across two decodes; `octet-stream HEIF still sniffed` (a `Blob` with type `application/octet-stream` takes the worker path); a 9000×8000 RGBA reply is resized to ≤ 16 MP. Source check: `heic-worker.js` contains `locateFile` returning `'vendor/libheif/' + …` and `importScripts('vendor/libheif/libheif.js')`.
- [ ] **Step 4: Run** → FAIL.
- [ ] **Step 5: Implement** `image-decode.js` and `heic-worker.js` per Interfaces.
- [ ] **Step 6: Run** → PASS; add to `run_all.sh`.
- [ ] **Step 7: Commit** `feat(web): HEIC decoding in every browser via vendored libheif`.

### Task 4: `canvas-jpeg.js`

**Files:** Create `web-app/canvas-jpeg.js`, `web-app/tests/test_canvas_jpeg.js`; modify `run_all.sh`.

**Interfaces:**
- Consumes: `CimbarImageDecode.decodeImage`, `PhotoDecodeError`, `ImageTooLargeError`; `CimbarJpegMeta.stripJpegMetadata`.
- Produces (`window.CimbarCanvasJpeg`): `MAX_CANVAS_PIXELS = 16_000_000`, `MAX_LIVE_CANVASES = 2`, `class SideTooLargeError extends Error`, `class BoundedCache(limit, release)` (`get/set/reserve/clear/size`), `scaledSize(w, h, maxSide) → {w, h}`, `class CanvasJpegSession` with `static open(blob): Promise<CanvasJpegSession>` (uses `decodeImage`, so HEIC works; rethrows `PhotoDecodeError`/`ImageTooLargeError`), `width`, `height`, `encode(maxSide, quality): Promise<Uint8Array>` (metadata stripped), `close()`.

- [ ] **Step 1: Failing tests:** port NFC Archiver's tests for `BoundedCache` and `scaledSize` (search `~/nfcarchiver/webapp/test/` for them); `CanvasJpegSession` with `mock_canvas.js`-style fakes injected through a `_impl` seam (`makeCanvas`, `toJpeg`): never more than 2 live canvases across a descending walk of 12 sides; a side above 16 MP throws `SideTooLargeError` without allocating; a null 2D context → `SideTooLargeError`; `encode` output passes through `stripJpegMetadata`; white fill before `drawImage`; `open` maps a decode failure to `PhotoDecodeError`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** by transliterating `app/ui/canvas-jpeg.ts`, replacing `createImageBitmap` with `CimbarImageDecode.decodeImage`.
- [ ] **Step 4: Run** → PASS; add to `run_all.sh`.
- [ ] **Step 5: Commit** `feat(web): canvas JPEG encoder session`.

### Task 5: `photo-optimiser.js` — DOM-free controller

**Files:** Create `web-app/photo-optimiser.js`, `web-app/tests/test_photo_optimiser.js`; modify `run_all.sh`.

**Interfaces:**
- Consumes: Task 1 (`fitToBudget`, `encodeManual`, `framesForFile`, `photoByteBudget`, `optimisedFileName`, `MAX_FRAMES`); `SideTooLargeError` (Task 4), `PhotoDecodeError`/`ImageTooLargeError` (Task 3).
- Produces (`window.CimbarPhotoOptimiser`):
  - `REFIT_DEBOUNCE_MS = 250`, `HOLD_INITIAL_DELAY_MS = 400`, `holdIntervalAfter(ms)`, `holdMultiplierAfter(ms)`, `class HoldRepeater(clock, {onStep, onHoldStart?, onHoldEnd?})` with `press(step)`, `release()`, `cancel()`
  - `previewDimensions(w, h, maxSide) → {width, height}`
  - `class PhotoOptimiser(io, photo)`; `io = {openSession(blob): Promise<session>, clock: {setTimeout, clearTimeout}, onChange(state), warn?(msg)}`; `photo = {source: Blob, fileName, originalSize, now?: Date}`; property `outputName`.
  - State passed to `onChange`: `{frames, cap, mode: 'auto'|'manual', manualSide, manualQuality, result: {maxSide, quality, bytes, fits}|null, needed, width, height, busy, error: 'none'|'decodeFailed'|'tooLarge'|'memory', largerThanOriginal, continueWithFrames: number|null, asIsFrames: number|null}` — `cap = min(framesForFile(fileName, originalSize, true), 4096)`; `needed` = smallest N whose `photoByteBudget(N, outputName)` ≥ result bytes; `continueWithFrames = needed` when the result doesn't fit and `needed ≤ 4096`, else null; `asIsFrames = framesForFile(outputName, result.bytes.length, true)` when the result doesn't fit, else null; `error: 'tooLarge'` for `ImageTooLargeError` at open, `'memory'` when every side throws `SideTooLargeError`.
  - Methods: `setFrames(n)` (clamped to 1…cap, debounced refit), `step(delta)`, `beginHold()`, `endHold()`, `setManual({side?, quality?})`, `backToAuto()`, `continueAsShown(): {kind: 'optimised', name, bytes, frames} | null` (null while busy or without result), `continueAtNeeded(): Promise<same | null>` (sets frames = `needed`, refits, returns the new result's choice), `skip(): {kind: 'original'}`, `dispose()` (closes the session; later callbacks are ignored).

- [ ] **Step 1: Failing tests:** port `~/nfcarchiver/webapp/test/photo-optimiser.test.ts` with its fake session/clock (`test/fake-jpeg-session.ts`), translating tags → frames and payloadSize → 2104 (drop tag-type/payload-size switching and `archiveGate`); plus: starting frames = frames of the 640/q70 encode; `tiny original: cap 1, stepper clamps, largerThanOriginal`; `continueWithFrames` null when needed > 4096 while `asIsFrames` is set; `continueAtNeeded` returns a fitting result at `needed` frames; a count set while opening is kept; `continueAsShown` null while busy; open with `ImageTooLargeError` → `error: 'tooLarge'`; with `PhotoDecodeError` → `'decodeFailed'`; `dispose()` mid-fit → no `onChange` after it.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** by transliterating `app/ui/photo-optimiser.ts` with the changes above.
- [ ] **Step 4: Run** → PASS; add to `run_all.sh`.
- [ ] **Step 5: Commit** `feat(web): photo optimiser controller`.

### Task 6: Wire scripts into the page and the deploy

**Files:**
- Modify: `web-app/index.html` (`<script src>` tags only), `web-app/tests/test_browser_load.js`, `.github/workflows/deploy-webapp.yml`, `web-app/tests/test_web_icons.js`

**Interfaces:** Consumes the five page scripts and `heic-worker.js` (Tasks 1–5). Produces the load order later tasks rely on.

- [ ] **Step 1: Failing tests.** `test_browser_load.js`: 21 → 26 page scripts; `photo-fit.js` and `jpeg-metadata.js` after `cimbar.js`; `image-decode.js` after `jpeg-metadata.js`; `canvas-jpeg.js` after `image-decode.js`; `photo-optimiser.js` after `canvas-jpeg.js` and `photo-fit.js`; all before `i18n.js`; the five globals exist; `heic-worker.js` and anything under `vendor/` are not page scripts. `test_web_icons.js`: `heic-worker.js` and its `importScripts` target `vendor/libheif/libheif.js` are staged; `vendor/libheif/libheif.wasm`, `LICENSE`, `DAV1D-LICENSE` are staged at their paths; the upload and rollback type tables have `*.wasm` → `application/wasm` and a type for the licence files; the verify step's allow-list accepts them.
- [ ] **Step 2: Run** both → FAIL.
- [ ] **Step 3: Implement:** add the five `<script src>` tags in that order; in `deploy-webapp.yml` stage the new files, teach the staging loop to keep subdirectories (`mkdir -p "$(dirname "_site/$f")"`-style), add `*.wasm application/wasm` and `vendor/libheif/*LICENSE text/plain; charset=utf-8` (or stage as `.txt`) to both type tables and the verify allow-list. Keep the S3 sync per-type structure; check sync patterns match files in subdirectories.
- [ ] **Step 4: Run** `sh tests/run_all.sh` → green; `python3 -m http.server` in `web-app/` and load `/` in a browser-less smoke (`node tests/test_browser_load.js`) — PASS.
- [ ] **Step 5: Commit** `build(web): load photo scripts; deploy the HEIC worker and libheif`.

### Task 7: Optimise photo screen, Choose photo, HEIC on Receive, strings

**Files:**
- Modify: `web-app/index.html` (markup, CSS, inline script), `web-app/i18n.js`, `web-app/tests/page_harness.js`, `web-app/tests/test_page_logic.js`, `web-app/tests/test_router.js`, `web-app/tests/test_markup.js` (if a guard needs the new screen)

**Interfaces:**
- Consumes: everything above. `CimbarCanvasJpeg.CanvasJpegSession.open` is the optimiser's `io.openSession`; `CimbarImageDecode.decodeImage` replaces `createImageBitmap(file, …)` in the Receive photo path (`index.html` ~line 1591).
- Produces (inline-script globals, added to `REQUIRED_GLOBALS` in `page_harness.js`): `openPhotoOptimiser(file)`, `closePhotoOptimiser()`, `photoSkip()`, `photoContinue()`, `photoContinueAtNeeded()`, `stageEncFile(file)`; `resolveRoute` learns `'/send/photo'` with state flag `hasPendingPhoto`.

- [ ] **Step 1: Failing tests** (`test_page_logic.js` / `test_router.js`, stubbing `CanvasJpegSession.open` with a fake session):
  - router: `#/send/photo` with `hasPendingPhoto: false` → `/send`; with true → stays.
  - Choose photo with a JPEG → route `#/send/photo`, optimiser opened with that file.
  - Choose photo with GIF bytes → staged as a plain file, no optimiser.
  - Choose a file / drop: `photo.png` opens the optimiser; `doc.pdf` and `anim.gif` stage directly; `octet-stream .heic via Choose a file opens the optimiser`; a photo over 128 MB stages directly.
  - Continue stages `IMG_1234.jpg` (optimised bytes) and returns to `#/send` in File mode; Skip stages the original `File`; "Continue with M frames" calls `continueAtNeeded` then stages; "Continue with this image (K frames)" stages the unfit result; Back leaves the previously staged file untouched.
  - `second pick while fitting disposes the first optimiser` (the first fake session's late result never reaches the screen).
  - Pill shows `"<size> · ≈ <n> frames"` using `framesForFile(name, size, true)`; `frame estimate on pill counts encryption; encoding the optimised file with a passphrase needs ≤ shown frames` (run `encodeToGif`'s framing path or `Cimbar.splitIntoFrames` on the staged bytes with a passphrase and compare counts).
  - `updateTextInfo` uses `CimbarPhotoFit.framesForFile` (same numbers as before for typed text).
  - `addPhoto` calls `CimbarImageDecode.decodeImage`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement the screen** `<section class="screen" data-route="/send/photo" hidden>` per the spec's mock-up: topbar back to `#/send`; preview `<img>` (object URL of the result, revoked on change) + working badge; label `photoResultLabel`; Frames to send stepper (−/+ buttons driven by `HoldRepeater`, `<input type="number" inputmode="numeric">`), transfer-time line using the Send screen's `#frameDelay` value; Manual preset chips (+ Original) and quality range 1–100; Back to auto; note/error line (`photoDoesNotFit`, `photoDecodeError`, `photoMemoryError`, too-large); action bar Skip + Continue, and when unfit `photoContinueWith` (if `continueWithFrames`) + `photoContinueAsIs`. Disable Continue while `busy`. Use existing design tokens/classes; follow `test_markup.js` guards (one screen per route, `--accent-fg` for text, icons from the sprite).
- [ ] **Step 4: Implement the routing:** add `'/send/photo'` to `ROUTES` and the guard; Choose photo button + `<input type="file" accept="image/*" id="photoEnc">` under Choose a file; `onFileSelect`/drop for `'enc'` read the first 64 bytes and call `isOptimisable(name, type, head, CimbarImageDecode.sniffHeif)`; > 128 MB (`CimbarFormat.SPEC.compression.maxInflatedBytes`) stages directly; `stageEncFile(file)` sets `encFile`, shows the pill with the frame estimate, calls `updateTextInfo`, sets File mode.
- [ ] **Step 5: Strings:** add every new key in all seven languages in `i18n.js`, taking the wording from `app/lib/l10n/app_<lang>.arb` (`photoOptimiseTitle`, `photoFramesToSend`, `photoTransferTime`, `photoManual`, `photoBackToAuto`, `photoQuality`, `photoOriginal`, `photoSkip`, `photoContinue`, `photoContinueWith`, `photoContinueAsIs`, `photoDoesNotFit`, `photoDecodeError`, `photoMemoryError`, `photoResultLabel`, `photoFewerFrames`, `photoMoreFrames`), converting ICU plurals to `[[param|forms]]` per `PLURAL_ORDER`; new web-only keys (`choosePhoto`, the pill estimate, too-large-to-optimise, the How it works libheif credit) written fresh in all seven. Add the libheif credit (name, LGPL-3.0, link to `vendor/libheif/README.md`'s upstream URL) to How it works → under the hood.
- [ ] **Step 6: Run** `sh tests/run_all.sh` → green (incl. `test_i18n.js`, `test_markup.js`).
- [ ] **Step 7: Manual smoke:** `cd web-app && python3 -m http.server 8080`; in Chromium (Playwright from `~/banana_split/node_modules` is fine) pick `test-data/photos/rotated.heic` and a JPEG via Choose photo, Continue, Create code; confirm no console errors and the frame count on Ready ≤ the optimiser's. Note the result in the report.
- [ ] **Step 8: Commit** `feat(web): Choose photo, Optimise photo screen, HEIC on Receive`.

### Task 8: Docs

**Files:** Modify `CLAUDE.md` (root), `README.md`, `README.ru.md`.

- [ ] **Step 1:** Root `CLAUDE.md`: "Running the Application" stays no-build but mention the vendored decoder; add the five modules, `heic-worker.js` and `vendor/libheif/` to the module list (with the upgrade rule: replace both files unmodified, update SHA-256s in its README, run `test_image_decode.js`); add a **Photo send pipeline** line beside the decode pipelines; add the six new tests to the test table and `run_all.sh` list; page-script count 21 → 26 everywhere it appears; Known Subtleties: libheif in a worker resolves the wasm relative to the worker URL (hence `locateFile`), and the worker is terminated per decode because WebAssembly memory never shrinks.
- [ ] **Step 2:** `README.md` / `README.ru.md` web-app sections: Choose photo + optimiser + HEIC everywhere; third-party credit for libheif-js/libheif/libde265 (LGPL-3.0) and dav1d (BSD-2-Clause). No CHANGELOG edit (the release PR writes it; the version tests require the newest heading to be a version).
- [ ] **Step 3: Run** `cd web-app && sh tests/run_all.sh` and `cd app && sh tests/run_all.sh` → green.
- [ ] **Step 4: Commit** `docs: web photo optimiser and vendored libheif`.
