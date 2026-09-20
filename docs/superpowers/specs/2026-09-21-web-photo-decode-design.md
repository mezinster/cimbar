# Web app — decoding a CimBar barcode from a photo

Status: Designed; not implemented
Date: 2026-09-21
Builds on: `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` (v2 geometry),
`docs/superpowers/specs/2026-09-18-cimbar-v2.1-rateless-and-compression-design.md` (coding layer)
Ports from: `app/lib/core/decode/` (the Android camera decode layer, released in v0.11.0)

## 1. Problem

The web app decodes only animated GIFs. Its single frame decoder,
`decodeFrameExact` (`web-app/cimbar.js:90`), assumes a pixel-exact 608×608
frame: cells sit at known grid positions, colours are the exact palette, and
there is no perspective, no illumination cast and no sub-pixel drift. The file
input reflects this — `accept="image/gif,.gif"`.

So a user who is *shown* a CimBar barcode — on someone else's screen, in a
photo a colleague sent, on a printout — cannot decode it in the browser at
all, even though the Android app has done exactly that since v0.11.0.

This design ports the Android photo decode path to the web app. Live camera
scanning is explicitly out of scope (§9).

## 2. Scope

In scope:

- Decoding one CimBar v2/v2.1 frame from an arbitrary photograph: perspective,
  rotation, uneven illumination, blur and noise.
- **Accumulating frames across several photos** into one `RatelessAssembler`
  session, so a multi-frame file can be recovered by photographing a looping
  animation repeatedly. This exceeds the Android photo path, which rejects any
  frame whose header says `total > 1` and directs the user to Live Scan.
- Both input affordances: choosing an image file, and `capture="environment"`
  to open the device's native camera.

Out of scope:

- Live camera scanning (`getUserMedia`), the `CapturePolicy` lock/hint loop,
  and the AR overlay. See §9 for why this is a separate phase.
- Any change to the encoder, the format, or the GIF decode path.
- Any change to the Android app's runtime or decode behaviour. §8.2 does add
  one Dart **test-only** tool, which renders shared fixtures and ships in
  neither APK.

## 3. Why this is a port, not a design

`app/lib/core/decode/` is 2001 lines of Dart with, by deliberate constraint,
no Flutter imports — it is arithmetic over typed arrays. Of that, ~1320 lines
are the camera chain ported here (§5); the rest is either already in JS
(`rateless_assembler.dart` → `rateless.js`), test-only (`golden_sidecar`,
`decode_report`, `diagnostics`) or unnecessary in a browser (`yuv_frame`).
Porting is
transliteration (`Float64List`→`Float64Array`, `Uint8List`→`Uint8Array`), not
redesign. The repository already maintains three such bit-compatible pairs:
`format.js`↔`cimbar_spec.dart`, `rateless.js`↔`rateless.dart`,
`rs.js`↔`reed_solomon.dart`.

The browser also *removes* a layer. Canvas `getImageData` returns RGBA
directly, so `yuv_frame.dart` (88 lines), `RgbBuffer.fromYuv420`, plane
strides and video-range expansion have no JS counterpart.

**Every tuned constant is copied, never re-derived.** `maxDevNorm` 0.35, the
side/module ratio gate 36–75, `tlMargin` 40, the 3 px downscaled module floor,
`wideThreshold` 20 and the ±6 px drift clamp were each tuned against real
captures. A JS file that "improves" one of them decodes differently from the
Android app on the same photo, and the shared fixtures (§8) stop being a
contract.

## 4. Data flow

The existing `startDecode` (`web-app/index.html:1062`) already has the right
shape: build a `RatelessAssembler`, feed it frames, finish at
`rank === total`. Photo decode changes only where frames come from.

```
GIF  (today):  gif bytes → GifDecoder → N × decodeFrameExact ─┐
                                                               ├→ RatelessAssembler
Photo (new):   File → ImageBitmap → RGBA → CimbarPhoto.decode ─┘        │
                                                                        ▼
                     strip length prefix → detect+decrypt → inflate? → parsePayload → File
```

Everything below the assembler is untouched and already tested.

The new chain, mirroring `FrameDecoder.decode`:

```
ImageBitmap → canvas → getImageData (RGBA)
  → RgbBuffer                bilinear RGB
  → LumaPlane.fromRgb        BT.601 77/150/29; downscale2; mean3x3
  → FinderLocator            1:1:3:1:1 row scan, cluster, refine → 4 corners
  → HomographyGridModel      DLT from the four finder centres
  → grid-size gate           64 ± 10, else unsupportedGrid
  → WhitePoint.fromFinders   per-channel 90th percentile over the finder cores
  → DriftSolver              BFS ±1 px, widened to ±2 when hamming > 20
  → CellSampler ×3840        corner-interpolated 8×8 tiles
  → CellClassifier           average-hash symbol + nearest palette colour
  → packCells → decodeRSFrame            (existing: format.js / cimbar.js)
  → RatelessAssembler.add                (existing: rateless.js)
```

### 4.1 Working resolution

Per-cell cost is fixed (3840 cells × 64 samples) regardless of image size, but
the locator scales with pixel count: a 12 MP phone photo is roughly six times a
1080p frame. Inputs are therefore downscaled to a **long edge of 1920** before
locating.

The counter-constraint is the px/cell floor. `frame_decoder_scaled_test.dart`
shows a 608 px frame at 0.5× (4.75 px/cell) does not decode, while 2× and 3×
upscales do. A barcode filling ~60% of a 1920 px frame gives ~18 px/cell, with
ample margin; when it does not, §7 reports it rather than failing obscurely.

### 4.2 Orientation

EXIF rotation does not affect decoding. `FinderLocator` identifies TL by core
brightness (TL has no inner white dot; TR/BL/BR do) and orients TR/BL by cross
product, so it is rotation-invariant — `finder_locator_test.dart` covers 37°,
90°, 180° and 271°. `createImageBitmap` is still called with
`imageOrientation: 'from-image'`, solely so a preview thumbnail is upright.

## 5. Modules

Nine new files in `web-app/`, each an IIFE assigning one global (the page
scripts share a single global scope — see §10), loaded after `format.js` in
dependency order.

| File | Global | Interface | Dart source (lines) |
|---|---|---|---|
| `rgb-buffer.js` | `CimbarRgbBuffer` | `fromImageData(d)`, `.r/g/b(x,y)`, `.bilinear(x,y,out,off)` | `rgb_buffer.dart` (107) |
| `luma-plane.js` | `CimbarLumaPlane` | `fromRgb(buf)`, `.at`, `.bilinear`, `.downscale2()`, `.mean3x3` | `luma_plane.dart` (114) |
| `homography.js` | `CimbarHomography` | `solve(from,to)`, `HomographyGridModel.fromFinders({tl,tr,bl,br})` | `homography.dart` (115) + `grid_model.dart` (20) |
| `finder-locator.js` | `CimbarFinderLocator` | `locate(luma) → LocateResult` | `finder_locator.dart` (405) |
| `white-point.js` | `CimbarWhitePoint` | `fromFinders(rgb, grid) → [r,g,b] \| null` | `white_point.dart` (41) |
| `cell-sampler.js` | `CimbarCellSampler` | `new(image, grid, luma?)`, `.sample(...)`, `.sampleLuma(...)` | `cell_sampler.dart` (90) |
| `cell-classifier.js` | `CimbarCellClassifier` | `.classify(patch, whitePoint)`, `.bestSymbol(luma)` | `cell_classifier.dart` (94) |
| `drift-solver.js` | `CimbarDriftSolver` | `new(sampler, classifier).solve() → DriftField` | `drift_solver.dart` (145) |
| `photo-decoder.js` | `CimbarPhoto` | `decode(imageData) → FrameResult` | `frame_decoder.dart` (191) |

`LocateResult` and `FrameResult` keep their Dart field names
(`{tl,tr,bl,br,candidates,clusters,devNorm,tlLuma,failReason,ok,module}` and
`{status,data,blocksFailed,header,diag}`) so diagnostics read the same on both
sides.

The 16 tiles, the 4 palette colours and the finder cell centres
`(3.5,3.5) (60.5,3.5) (3.5,60.5) (60.5,60.5)` come from `format.js`. They are
not re-declared.

### 5.1 One approximation to preserve

`CellSampler` interpolates a cell's 64 sample positions from its 4 corners
rather than evaluating the homography 64 times — justified in Dart because the
projective error over a 9 px cell is far below bilinear sampling resolution.
**Port the approximation.** An exact JS version would be more correct and would
produce different cells from Android on the same photo.

## 6. Page integration

`web-app/index.html`, Decode tab (renamed from "Decode GIF"):

```js
let photoSession = null;   // { asm, photos, accepted }
```

- `accept` widens to `image/gif,image/*`; a second input with
  `capture="environment"` opens the native camera on mobile.
- `onFileSelect` branches on the file's **magic bytes** (`GIF8`), not
  `file.type`: a GIF takes today's path and clears any photo session, any
  other image goes to `addPhoto(file)`. Android learned this the hard way —
  `share_intake.dart` calls `isGif(file.bytes)` because galleries hand over a
  GIF labelled `image/*`. A file input is more trustworthy than a share
  intent, but the check costs four bytes and removes the class of bug.
- `addPhoto`: `createImageBitmap(file, {imageOrientation:'from-image'})` →
  downscale to ≤1920 long edge → canvas → `getImageData` →
  `CimbarPhoto.decode` → wrong-file guard (§7.3) → `asm.add(...)` → update the
  `rank / total` progress → at `rank === total`, run the existing tail and
  render the existing result card.
- The passphrase is read at completion, not per photo, as in the GIF path.

## 7. Error handling

### 7.1 Frame decode failures

`CimbarPhoto.decode` returns Dart's `DecodeStatus` values plus one new case.
Beyond `ok`, the failures are:

| Status | Cause | Message |
|---|---|---|
| `notLocated` | finders not found | "No barcode found in this photo" (+ `failReason` logged) |
| `tooSmall` | located, px/cell below the floor | "Barcode too small in frame — move closer" |
| `unsupportedGrid` | grid estimate outside 64 ± 10 | "This doesn't look like a CimBar v2 barcode" |
| `rsFailed` | located, RS could not correct | "Blurry or angled — try again, straighter" |
| `badHeader` | RS ok, header invalid | "Frame damaged" |

`tooSmall` fires when `LocateResult.module` is below **6 px** — reusing
`CapturePolicy.minModulePx`, already tuned as the threshold at which Android
tells a live-scan user to move closer. (The locator has its own, lower floor
of 3 px on the 2×-downscaled plane, below which photo texture aliases into
false candidates; `tooSmall` is the user-facing threshold, not that one.)

The status itself has no Android equivalent, because live scan simply drops
such frames, whereas someone who uploaded a single photo deserves to know why
it failed.

### 7.2 Assembler rejections

`rateless.js` emits seven reasons (`rs`, `short`, `total`, `flags`,
`uncoded`, `duplicate`, `dependent`), and `decodeHeader` adds `version` and
`seq` (its `short`, `flags` and `total` share names with the above). All get
i18n keys, closing the "untranslated reason tokens" item deferred from the
v2.1 work.

Two must not be presented as failures: `duplicate` ("you already have this
frame") and `dependent` ("no new information"). Both are the normal result of
re-photographing a loop.

### 7.3 Wrong-file guard

`rateless.js:104` resets the whole collection when a frame carries a different
`fileId`:

```js
if (this.fileId !== null && h.fileId !== this.fileId) this.reset();
```

This is harmless for a GIF — one file, one `fileId` — but destructive in a
photo session: one photo of the wrong barcode silently discards every frame
collected so far.

Therefore the page decodes the header itself with
`CimbarFormat.decodeHeader(data)` **before** calling `add()` and compares
`fileId` against `photoSession.asm.fileId`. On mismatch it does not add, and
asks: *"This photo is from a different file. Discard N frames of progress and
start over?"* `rateless.js` is not modified — the guard lives in the caller, so
the GIF path and the Android port keep identical assembler semantics.

## 8. Testing

### 8.1 Per-module unit tests

`web-app/tests/` gains tests mirroring the Dart test files case for case, with
the same inputs and expected numbers: homography identity / scale+translate /
rotated-keystoned round trip; white point pure-white, colour cast, too-dark
null; classifier over all 64 symbol×colour combinations; luma BT.601 weights
and `downscale2` averaging; drift correcting a known (2, −1) px offset.

### 8.2 Shared scene fixtures — the anti-drift mechanism

A new Dart tool renders the existing `SceneSpec` degradation matrix (scale,
rotations 37/90/180/271°, keystone 0.12, blur, brightness 0.7/1.3, noise σ8,
photo composites) to PNG under `test-data/scenes/`, each with a JSON sidecar
holding the ground truth the harness already computes exactly: the four finder
centres, the homography, and the expected 3840 cells.

Both suites consume those files. This extends the contract
`test-data/goldens/` already provides for the GIF path, and keeps **one scene
renderer, in Dart**. Porting `synthetic_scene.dart` to JS would create two
ground truths, and a disagreement between them would be undiagnosable.

### 8.3 Equivalence invariant

On a pristine 608×608 golden frame, `CimbarPhoto.decode` must produce cells
byte-identical to `decodeFrameExact`. Locate, fit, white-balance and drift
should all be no-ops on a perfect image.

This is the highest value-per-line test here: it reduces "are 1300 ported lines
correct?" to one comparison against already-trusted code, and it fails
immediately on sign errors, transposed axes and off-by-one grid origins.

### 8.4 Performance guard

Mirroring `benchmark_test.dart`: decode a 1920×1080 fixture, print
`totalMs locateMs sampleMs driftMs rsMs`, assert a loose ceiling (1500 ms) to
catch order-of-magnitude regressions without CI flakiness.

Measured expectation, from a throwaway JS model of the two dominant kernels
(2026-09-21, this machine): RGB sample + classify 7.1 ms, drift hill-climb
74.6 ms on Node 22 — against Dart's desktop-JIT `sampleMs=141 driftMs=125`.
JS on modern V8 runs the hot path roughly 3× faster than the Dart JIT, so a
desktop browser should land near 110–130 ms per photo. A phone browser is
3–4× slower.

### 8.5 Browser load

`test_browser_load.js` gains the nine scripts, their load order and their
globals. It is the only test that catches a duplicate top-level `const` across
files, which is a `SyntaxError` in the browser and invisible to Node.

## 9. Why live scan is a separate phase

`getUserMedia` works on iOS (the WKWebView restriction was lifted in
iOS 14.3), so live scan is possible there — but focus and exposure *lock* is
not. `CapturePolicy` locks both on the first located frame specifically to stop
the camera hunting mid-scan; hunting frames blur and fail to locate.

`ImageCapture` and the `focusMode`/`exposureMode` constraints ship in Chrome
(desktop 59+, Android) and in no version of Safari or Firefox. Every iOS
browser — Chrome included — renders with WebKit: Apple's `BrowserEngineKit`
(iOS 17.4) nominally permits alternative engines in the EU, but as of 2026 no
App Store browser ships one.

Consequences that keep the phases apart:

- The photo path is unaffected: a still image has no focus to hunt, and
  `capture="environment"` hands the job to the *native* camera app, which has
  better autofocus and exposure than `getUserMedia` would expose anyway. It
  works identically in every browser.
- Live scan would be strong in Chrome and best-effort elsewhere, needs a Web
  Worker, and needs capability detection. That is a different design.

v2.1's rateless coding does soften the blow when live scan arrives: any N
independent rows complete the file, so a hunting camera lowers the accept rate
without ever stalling on one specific frame.

## 10. Repository constraints

All are enforced by existing tests and are not optional.

1. **One global scope.** Page scripts are classic `<script>` tags; two files
   declaring the same top-level `const` is a `SyntaxError` in the browser that
   no Node test catches. All nine files are IIFEs.
2. **`deploy-webapp.yml`** — nine entries in the staging list. `*.js` already
   has a Content-Type row, so the type table is unchanged.
3. **`test_browser_load.js`** — script count, order, globals.
4. **`test_web_icons.js`** — asserts every staged file is linked and typed.
5. **`i18n.js`** — every new string in all five languages (en, ru, uk, tr, ka)
   or `test_i18n.js` fails. New keys: the camera button, "frame N of M
   accepted", the five statuses in §7.1, the reasons in §7.2, the
   wrong-file prompt, and "start over".

## 11. Decisions

- **Mirror the Dart module split 1:1** rather than one large file or two
  layered ones. This code must stay behaviourally identical to Dart
  indefinitely; the repo has already paid this cost three times for that
  reason, and a divergence bug is tractable when `drift-solver.js` sits beside
  `drift_solver.dart`.
- **Port the drift solver** despite it being ~90% of the hot-path cost.
  `drift_solver_test.dart` shows barrel distortion decodes *only* with drift
  on, and `hammingMean` is 4.08 with it against 10.32 without on the same
  scene. Omitting it would be cheap and unreliable.
- **Main thread, no Web Worker.** At ~110–130 ms per photo on desktop a brief
  block is acceptable. A worker costs a deploy artifact, Content-Type rows in
  both the upload and rollback tables and a test change, for no photo-path
  benefit. The worker boundary belongs to live scan.
- **Accumulate across photos** rather than matching Android's single-frame
  restriction, because `RatelessAssembler` already works this way and the web
  app has no Live Scan to redirect users to.

## 12. Risks

- **Silent numerical divergence.** The likeliest failure is a ported constant
  or an "improved" approximation that decodes subtly differently from Android.
  Mitigated by §8.2 shared fixtures and §8.3 equivalence.
- **`finder-locator.js` is 31% of the port** and carries the most tuned magic
  numbers. It should be the first module ported and the first tested against
  the scene fixtures.
- **Large-photo memory.** A 12 MP RGBA `ImageData` is ~48 MB before downscale.
  Downscale during `drawImage` (draw straight into a ≤1920 canvas) rather than
  reading full-resolution pixels and shrinking afterwards.
- **Unmeasured on a real phone browser.** The 3–4× mobile estimate is
  extrapolation, not measurement — as is still true of the Android app's own
  on-device timing.

## 13. Implementation outline (for the plan)

1. `rgb-buffer.js`, `luma-plane.js` + unit tests.
2. `homography.js` (with `GridModel`) + unit tests.
3. Dart scene-fixture tool; commit `test-data/scenes/`.
4. `finder-locator.js` + tests against the fixtures.
5. `white-point.js`, `cell-sampler.js`, `cell-classifier.js` + tests.
6. `drift-solver.js` + tests.
7. `photo-decoder.js`; the §8.3 equivalence test against the goldens.
8. Page integration: input, session, wrong-file guard, progress, i18n in five
   languages.
9. Deploy staging list, `test_browser_load.js`, performance guard.
