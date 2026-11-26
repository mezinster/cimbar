# Web app: Choose photo, photo optimiser and HEIC everywhere — design

Status: draft for approval, 2026-11-26. Branch `feat/web-photo-optimiser`.

## Intent

The Android/iPhone app (PRs #50/#51, design `2026-11-25-photo-send-and-share-in-design.md`) and NFC Archiver's web app can send a photo by shrinking it to fit a frame count the user picks. The user wants the CimBar **web app to behave the same way when working with images**: the same Choose photo entry, the same optimiser screen, and the same fit rules and frame budget. ("Same" means the same rules and budget arithmetic: the app encodes with the platform JPEG encoder and the web with the browser's canvas encoder, and browsers differ from each other, so the same photo can land on slightly different sizes and frame counts. Identical bytes would need one deterministic encoder shipped everywhere, which is out of scope.) HEIC photos must work **in every browser**, not just Safari.

## Goals

- **G1 Choose photo** on the web Send screen (`#/send`, File mode), beside Choose a file.
- **G2 Optimise photo** screen at `#/send/photo`: a behavioural port of NFC Archiver's web optimiser (`~/nfcarchiver/webapp/src/photo/*.ts`, `app/ui/canvas-jpeg.ts`, `app/ui/photo-optimiser.ts`), with frames in place of tags and the app's rules where they differ (below).
- **G3 One frame-budget helper** shared by the optimiser, the Send screen's text estimate and a new file estimate, giving the same numbers as the app's `frame_budget.dart`.
- **G4 HEIC/HEIF in every browser.** The browser's own decoder first; where it can't decode, a vendored WebAssembly build of libheif, loaded only when needed. The same decode path serves the Receive screen's "Photograph frames" / pick-a-photo input, so a HEIC photo of a barcode also decodes in Chrome/Firefox.

## Non-goals

- **No build step and no TypeScript** (approach A, chosen). The new code is plain JS in the existing classic-script style. A TypeScript/bundler migration may come later as its own project.
- **No share-into-the-web-app** (Web Share Target needs a service worker and an installed PWA).
- No change to the camera decode chain (`photo-decoder.js` and the eight modules under it), the format, or the Dart↔JS parity fixtures.
- No documentation-site (`site-docs/`) pages in this change.
- No AVIF or other new formats beyond what the browser decodes natively plus HEIC/HEIF.

## Anti-goals (failure even if it "works")

- **A frame count that lies.** If the optimiser says N frames, encoding the result must need at most N source frames whether or not a passphrase is typed afterwards (encryption is always reserved, as in the app).
- **Leaking metadata.** The optimised JPEG carries no EXIF/GPS/XMP/camera data; orientation is baked into the pixels.
- **Any network request to a third party.** The decoder is served from our own origin like every other script (`tests/test_markup.js` already forbids CDN scripts), and nothing leaves the device.
- **Making every visitor download the decoder.** libheif (~1.5 MB) loads only when a picked file is HEIF and the browser couldn't decode it.
- **Freezing the page.** HEIC decoding (seconds on a phone for a 12–48 MP photo) runs in a Web Worker, not on the main thread.
- **Breaking the zero-install contract.** `web-app/` still runs from `python3 -m http.server` with no npm step, and the 21 existing page scripts are untouched apart from the wiring the screens need.

## Approaches considered

- **A. No build step, vendored decoder (chosen).** Hand-port ~840 lines of NFC Archiver TypeScript to plain JS; vendor libheif-js unmodified under `web-app/vendor/libheif/`. Least risk: the decode chain isn't touched, and the deploy keeps its shape. Costs a manual port, manual libheif upgrades, and no type checking.
- **B. esbuild bundling, still JS.** npm manages libheif, but all 21 scripts, the worker, the tests and the deploy move to a bundled `dist/`. A large migration whose only gain here is dependency management.
- **C. Full TypeScript like NFC Archiver.** The photo code could be copied almost verbatim, but every module gets rewritten, including the camera decode chain, which is pinned to Dart bit for bit and has broken parity before over `%`, rounding, sort order and float associativity. Highest risk, no gain in image parity.

The user's goal is image parity, not the tooling; A delivers it.

## New files (all in `web-app/`, classic scripts, IIFE-wrapped, one `window.Cimbar*` export each)

| File | Export | Port of / role |
|---|---|---|
| `photo-fit.js` | `CimbarPhotoFit` | NFC Archiver `src/photo/fit.ts` + `budget.ts`: presets, `candidateSides`, `fitToBudget`, `encodeManual`, `optimisedFileName`, `isOptimisable(name, type)`, and the frame-budget helpers (G3) |
| `jpeg-metadata.js` | `CimbarJpegMeta` | `src/photo/jpeg-metadata.ts`: `stripJpegMetadata` |
| `image-decode.js` | `CimbarImageDecode` | new: `decodeImage(blob) → ImageBitmap` — native `createImageBitmap` first, libheif worker fallback for HEIF (G4) |
| `canvas-jpeg.js` | `CimbarCanvasJpeg` | `app/ui/canvas-jpeg.ts`: the encoder session (16 MP canvas cap, two live canvases, white flatten, `SideTooLargeError`/`PhotoDecodeError`) |
| `photo-optimiser.js` | `CimbarPhotoOptimiser` | `app/ui/photo-optimiser.ts`: DOM-free controller behind an IO seam (session factory, clock, change callback), `HoldRepeater`, debounce, state |
| `heic-worker.js` | — (Worker) | not a page script: sets `self.window = self` like `scan-worker.js`, `importScripts('vendor/libheif/libheif.js')`, decodes the primary image with its transformations applied, replies RGBA + size |
| `vendor/libheif/` | — | `libheif.js` + `libheif.wasm` from **libheif-js 1.23.5** (`libheif-wasm/`), byte-for-byte unmodified, plus that directory's `LICENSE` (libheif notice + LGPL-3.0 text), a notice for **dav1d** (BSD-2-Clause, linked into the wasm), and a `README.md` naming the version, source URL and SHA-256 of each file |

The DOM glue (screen rendering, button wiring) stays in `index.html`'s inline script, as for every other screen. Load order: `photo-fit.js` and `jpeg-metadata.js` after `cimbar.js`; `image-decode.js`, `canvas-jpeg.js`, `photo-optimiser.js` after them; all before `i18n.js`.

## The optimiser (G2)

Behaviour is NFC Archiver's web optimiser, with frames for tags and the app's rules where they differ.

### Screen `#/send/photo`

```
 ←  Optimise photo
 ┌──────────────────────────────┐
 │          [ preview ]         │   1600 × 1200 · q72 · 182 KB
 └──────────────────────────────┘
 Frames to send   [−]  87  [+]        ≈ 17 s at 200 ms
 Manual   320 480 640 … 3840 Original      Quality ━━━●━━  72
          [Back to auto]
 note / error line
 [ Skip (keep original) ]         [ Continue ]
   unfit:  [ Continue with M frames ]  [ Continue with this image (K frames) ]
```

- **Preview** of the result with pixel size, JPEG quality and size in KB; a "working" badge while encoding.
- **Frames to send** stepper: −/+ with hold-to-repeat (NFC Archiver's schedule: first repeat 400 ms, then 300/100/50 ms, ×10 steps after 3 s), and a number field to type into. Beside it the transfer time `≈ N × delay` at the Send screen's current **Frame speed** (100/200/400 ms).
- **Manual**: preset chips and a quality slider (1–100); touching either switches to manual; **Back to auto** returns.
- **Skip** stages the original file untouched; **Continue** stages the optimised JPEG. When the result is unfit, the action bar follows the app (`photo_optimiser_screen.dart`): **Continue with M frames** (only when M ≤ 4,096; sets N = M, re-fits, continues) and **Continue with this image (K frames)**, which stages the shown result as it is with its true frame count — the only way forward besides Skip when M > 4,096. Strings `photoContinueWith` / `photoContinueAsIs` come from the app's ARB files. Either returns to `#/send` in File mode with the file pill showing. **Back** (topbar or browser) cancels and leaves whatever was staged before.
- `resolveRoute`: `#/send/photo` with no pending photo falls back to `#/send` (a reload or a pasted URL lands on Send).
- The Send screen's Create code button can't be pressed while the optimiser is open (it isn't on screen).
- No 500-frame note: that note in the app is about Share GIF's cap, which the web app doesn't have.

### Fit (unchanged from the app and NFC Archiver)

- Presets **320, 480, 640, 800, 1024, 1280, 1440, 1600, 1920, 2560, 3840, Original**; never upscale.
- Per side, binary-search the quality. Pick **the largest side reaching q ≥ 50, else the largest that fits at q ≥ 30, else the smallest result marked unfit**: "Doesn't fit in N frames; needs at least M". When unfit, the two buttons described under Screen.
- **Starting N:** the frame count of the 640 px / q70 encode.
- **Stepper range:** 1 … min(frames of the original file as picked, 4,096).
- Stepper and slider changes re-fit after a 250 ms debounce; a count typed while the photo is still opening is kept; Continue is disabled while a fit is running.
- **Output name:** original stem + `.jpg` (`IMG_1234.HEIC` → `IMG_1234.jpg`); no name or a bare-UUID stem → `photo-yyyyMMdd-HHmmss.jpg` (same rule as the app's `optimised_file_name.dart`).
- Always re-encode, in auto and manual; `stripJpegMetadata` runs on every encode even though canvas output already has no metadata.

### Frame budget (G3)

The web container is the same as the app's: 4 (length prefix) + 4 (name length) + UTF-8 name + data, + 48 when encrypted (`CB 42 01 00` 4 + salt 16 + IV 12 + tag 16). `photo-fit.js` exposes:

- `framedBytes(nameBytes, dataBytes, encrypted)`
- `framesForFile(name, dataBytes, encrypted)` = max(1, ceil(framed / 2104))
- `photoByteBudget(frames, name)` = frames × 2104 − framedBytes(name, 0, true)

`updateTextInfo` switches from its hard-coded `4 + 4 + 27 + bytes + 48` to these helpers. The File-mode pill gains a frame estimate ("182 KB · ≈ 87 frames", encryption counted), so the count the optimiser promised is visible after Continue. Compression is not counted (a JPEG never deflates past the 5% threshold; if anything else does, it only needs fewer frames).

### Which picks go to the optimiser

- **Choose photo** (`accept="image/*"`, no `capture`, so phones offer the gallery): always, except a GIF (identified by magic bytes, as `isGifBytes` already does), which is staged as a plain file.
- **Choose a file** and drag-and-drop: when `isOptimisable` says so — JPEG/PNG/WebP/HEIC/HEIF by type or extension, or HEIF by content sniffing (galleries often label HEIC `application/octet-stream`). GIF and SVG never; Skip is one tap away for everything else.
- An optimiser-bound pick above **128 MB** (`compression.maxInflatedBytes`) is not opened in the optimiser; it is staged as a plain file, exactly as Choose a file does today. Plain-file picks keep today's behaviour (no new size limit on Send).

## HEIC everywhere (G4)

`CimbarImageDecode.decodeImage(blob)`:

1. Try `createImageBitmap(blob, { imageOrientation: 'from-image' })`. Safari decodes HEIC this way, and every browser decodes JPEG/PNG/WebP.
2. If that fails and the first bytes are an ISO-BMFF `ftyp` box whose **major brand** is a HEIF brand (`heic`, `heix`, `heim`, `heis`, `hevc`, `hevx`, `mif1`, `msf1`) and no compatible brand is `avif`/`avis` (AVIF files list `mif1` too; the vendored build could decode them via dav1d, but AVIF is a non-goal and modern browsers decode it natively), decode in `heic-worker.js`. The worker is **terminated after each decode** (libheif's WebAssembly memory grows to the peak of a 48–64 MP decode and never shrinks, which would starve a later live scan or encode). To avoid recompiling, the main thread compiles `libheif.wasm` once (`WebAssembly.compileStreaming`), keeps the `WebAssembly.Module`, and posts it to each new worker, which instantiates it via libheif's `instantiateWasm` hook. Inside the worker `libheif.js` resolves the wasm URL relative to the worker (`web-app/`), not `vendor/libheif/`, so the worker passes `locateFile` explicitly — the Node test does not catch a mistake here, so `test_page_logic.js`/`test_web_icons.js` check the path string.
3. libheif applies the HEIF transformations (`irot`/`imir`/crop), which are authoritative for orientation in HEIF. The worker returns RGBA; the main thread turns it into an `ImageBitmap`, downscaled so width × height ≤ 16 MP (the canvas cap the encoder session already enforces).
4. Anything else, or a decode error, is a `PhotoDecodeError` → "This photo can't be read" with **Send as a file** (stages the original, as Skip does).

Limits: a HEIF whose primary image exceeds **64 MP** is refused ("too large to optimise", Send as a file still offered), which covers 48 MP phone photos while keeping the worker's RGBA buffer ≤ 256 MB. Worker load or decode failures never break the page.

The Receive screen's photo input (`addPhoto` → `createImageBitmap(file, …)`) calls `decodeImage` instead, so a HEIC barcode photo decodes everywhere. The live-scan worker is untouched (camera frames are never HEIC).

**Licensing.** libheif and libde265 are LGPL-3.0, and dav1d (also inside the wasm) is BSD-2-Clause; CimBar is MIT. Compliance: ship the two files unmodified and separate from our code, ship the license text beside them, and name the exact upstream version and source URL in `vendor/libheif/README.md`, the repo README and the web app's How it works → under the hood list. HEVC is patent-encumbered; widely used libraries ship a decoder anyway, and the user accepted this.

## Deploy (`.github/workflows/deploy-webapp.yml`)

- Stage the five new page scripts, `heic-worker.js`, and `vendor/libheif/{libheif.js,libheif.wasm,LICENSE}` at their paths (the staging loop learns subdirectories).
- Add `*.wasm → application/wasm` to the upload **and** rollback type tables and to the verify step's allow-list. `LICENSE` needs a type too (`text/plain; charset=utf-8`), or is staged as `LICENSE.txt`.
- `tests/test_web_icons.js`'s worker check (every `new Worker('…')` target and its `importScripts` are staged) must cover `heic-worker.js` → `vendor/libheif/libheif.js`, and that `libheif.wasm` is staged next to it.

## Localization

Every new string in all seven languages in `i18n.js` (`test_i18n.js` enforces it), using the existing plural machinery for frame counts. Where the app already has the string (`app_<lang>.arb`: optimiser title, Frames to send, Manual, Back to auto, Skip, Continue with M frames, doesn't-fit message), the web copy reuses the app's translation so the two read the same.

## Testing (`web-app/tests/`, added to `run_all.sh`)

- **`test_photo_fit.js`**: ports NFC Archiver's fit/budget/name tests; budget values equal the Dart `frame_budget_test.dart` cases.
- **Shared fit fixture `test-data/photo-fit.json`**: cases of (deterministic fake encoder size model, budget) → expected `{maxSide, quality, fits}` and budget/frame cases; asserted by both `test_photo_fit.js` and a new Dart test beside `photo_fit_test.dart`, the way `text-message.json` is shared. This is the "same frame counts" guarantee.
- **`test_jpeg_metadata.js`**: port of NFC Archiver's tests (APPn/COM dropped, APP0 kept, trailing gain map dropped, malformed input throws).
- **`test_photo_optimiser.js`**: the controller under a fake clock and fake session (start N from 640/q70, debounce, manual/auto, Continue with M, typed count during open, Continue disabled while fitting, `HoldRepeater` schedule).
- **`test_image_decode.js`**: HEIF sniffing (brands, octet-stream type, short/garbage input); and a **real decode of a committed HEIC fixture through the vendored `libheif.js` in Node** (it runs there), checking dimensions and that an `irot` rotation is applied. Fixture: a small (≤ 50 KB) HEIC with a rotation under `test-data/photos/`, provenance noted in a README beside it.
- **`test_vendor_libheif.js`** (or inside the above): the vendored files' SHA-256 match `vendor/libheif/README.md`.
- `test_browser_load.js`: 21 → 26 page scripts, the new globals exist, load order holds, `heic-worker.js` is not a page script.
- `test_page_logic.js`: picking a photo routes to `#/send/photo`; a GIF via Choose photo stages as a file; Skip/Continue stage the right file and return to `#/send`; Back leaves the earlier staged file; `addPhoto` goes through `decodeImage`.
- `test_router.js`: `#/send/photo` without a pending photo redirects to `#/send`.

## Docs

Root `CLAUDE.md` (module list, test table, page-script count, the vendored-decoder rule and how to upgrade it), `web-app` sections of `README.md`/`README.ru.md` (feature + libheif credit), and an *Unreleased* CHANGELOG entry if the repo keeps one (otherwise the next release's entry). No version bump.

## Delivery

One PR to master from `feat/web-photo-optimiser`. CI's *Web App Tests* and *Analyze & Test* (for the Dart side of the shared fixture) must pass. Deploying the web app (`deploy-webapp.yml`) happens after merge, as usual.

## Left to the builder

- How the RGBA crosses from the worker (transfer the `ArrayBuffer`) and how the bitmap is downscaled (`createImageBitmap` resize options or a canvas).
- The fake-encoder size model used in `photo-fit.json`.
- Markup and CSS for the screen, following the existing design tokens and the NFC Archiver layout.
- How the HEIC fixture is produced (`heif-enc` from libheif's examples or a phone photo cropped and re-encoded), as long as it is small, carries a rotation and has no personal metadata.

## Decisions record

- 2026-11-26: user wants web image behaviour to match the app; chose **approach A** (no build step, vendored libheif) after asking for a build step and HEIC everywhere — a build step is not needed for either.
- Builder check (2026-11-26) settled: unfit action bar as in the app (both buttons); parity means rules and budget, not identical bytes across encoders; HEIC worker terminated after each decode with the compiled module cached; 128 MB applies only to optimiser-bound picks (staged plain above it); major-brand sniff excluding AVIF; dav1d notice vendored.
- Designer's calls (user may override): optimiser on its own route like the app's screen; the Receive photo input also gains HEIC; 64 MP HEIF limit; frame estimate on the File pill; shared JSON fixture for Dart↔JS fit parity; no site-docs pages yet.
