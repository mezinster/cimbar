# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Application

There is no build step. Open `web-app/index.html` directly in a browser, or serve the web-app directory with a local static server (required for Web Crypto API in some browsers):

```bash
cd web-app
python3 -m http.server 8080
# then open http://localhost:8080
```

No npm, no compilation, no install step.

## Architecture

This repo has two components:

- **`web-app/`** — A single-page browser app that encodes any file into an animated GIF where each frame is a grid of colored geometric symbols (Color Icon Matrix Barcode), and decodes it back. Everything runs client-side; there is no server.
- **`app/`** — A Flutter Android app that decodes CimBar GIFs via file import, in-app photo capture, or live camera scanning. Ports the full decode pipeline to Dart. See `app/CLAUDE.md` for Android-specific details.

### Web App

**Encoding pipeline:**

```
File → build container → [compress (compress.js), if it saves ≥5%] → [optional: encrypt (crypto.js)] → length-prefix + pad →
  split into N source frames → [+ repair frames (rateless.js)] → RS encode (rs.js) → draw frames (cimbar.js) → GIF encode (gif-encoder.js) → Animated GIF
```

**Decoding pipeline:**

```
Animated GIF → GIF decode (gif-decoder.js) → sample pixels (cimbar.js) → RS decode (rs.js) → RatelessAssembler assembles any N
  independent source/repair frames (rateless.js) → strip length prefix → [auto-detect: decrypt (crypto.js)] → [inflate if compressed
  (compress.js)] → File
```

Encryption is optional. On encode, if a passphrase is provided, the payload is encrypted with AES-256-GCM after compression and before RS encoding. On decode, encryption is auto-detected by checking for magic bytes `CB 42` at the start of the decrypted-or-not payload. Compression (zlib deflate) is applied automatically whenever it saves at least 5% of the container's size, and reversed automatically on decode from the frame header's `compressed` flag — there is no user-facing compression toggle. A downloadable GIF appends `ceil(0.25 × N)` repair frames after its N source frames (see "Format v2.1" below); present mode instead streams the N source frames once and then repair frames forever, since any N of the N + R total frames — in any order — reconstruct the file. Present mode loops the source pass for single-frame files and for files above the 4096-frame coding cap (there are no repair frames to stream in those cases).

**Module responsibilities (all in `web-app/`):**

- `index.html` — all UI (the Encode / Decode GIF / About tabs, drag-drop, progress, stats, present mode, language picker) and the orchestrating inline `<script>` that drives the full encode/decode flow
- `format.js` — CimBar v2 format constants and pure helpers shared by encoder, decoder and tests: loads `spec/cimbar-v2.json` in Node or `format-data.js` in the browser. Exposes cell geometry (`usableCellPositions`, `cellOrigin`), header codec (`encodeHeader`/`decodeHeader`), bit packing (`packCells`/`unpackCells`, `cellValue`/`cellSymbol`/`cellColor`), and frame byte-budget helpers (`rawBytesPerFrame`, `rsBlockSizes`, `dataBytesPerFrame`, `fileBytesPerFrame`). Exposes `window.CimbarFormat`
- `format-data.js` — **generated**; a browser-loadable mirror of `spec/cimbar-v2.json` (the browser cannot `require()` JSON). Sets `window.CIMBAR_SPEC`. Regenerate with `node tools/gen_format_data.js` whenever the spec changes
- `rateless.js` — GF(256) repair-frame coding for v2.1: non-linear splitmix32+fmix32 coefficient generator (`codingCoefficients` in `format.js`) drives `combineBodies` (XOR/GF-multiply source bodies into one repair body) and `class RatelessAssembler`, which accepts source/repair frames in any order (`add(data, blocksFailed)` → `{accepted, reason}`, reasons include `short`/`dependent`/`uncoded`/`duplicate`), tracks `rank`/`total`/`compressed`/`counts`, and reassembles the file once `rank === total` via `framedData()`. Exposes `window.CimbarRateless`
- `cimbar.js` — core v2 barcode logic built on `format.js`: `renderFrame`/`decodeFrameExact` (draw/read frame pixels), `encodeRSFrame`/`decodeRSFrame` (RS encode/decode with byte-stride interleaving), `splitIntoFrames`/`repairFrame`/`frameBodies`/`gifRepairCount` (chunk a payload into headered source frames and generate GF(256) repair frames via `rateless.js`), `RatelessAssembler` (re-exported from `rateless.js`), `buildPayload`/`parsePayload`/`withLengthPrefix`/`stripLengthPrefix` (file container). Exposes `window.Cimbar`
- `i18n.js` — UI strings in English, Russian, Ukrainian, Turkish and Georgian (the Android app's five languages): `data-i18n`/`data-i18n-html`/`data-i18n-placeholder`/`data-i18n-title` attributes are filled by `CimbarI18n.apply()`, dynamic messages use `CimbarI18n.t(key, params)`; language from localStorage (`cimbar.lang`), then the browser, then English; English is the fallback for any key. Exposes `window.CimbarI18n`
- `crypto.js` — AES-256-GCM via Web Crypto API; wire format is `[CB 42 01 00 magic | 16-byte salt | 12-byte IV | ciphertext+tag]`. PBKDF2 with 150,000 SHA-256 iterations for key derivation. Exposes `window.CimbarCrypto`
- `compress.js` — optional zlib deflate/inflate for the container (spec §4): `maybeDeflate(bytes)` compresses only when it saves at least the configured minimum, else returns the input untouched; `inflateBytes(bytes, maxBytes)` reverses it, refusing output above `compression.maxInflatedBytes` (128 MB) with an error marked `tooLarge`. Browser: `CompressionStream`/`DecompressionStream('deflate')`; a browser without them still encodes (payload left raw) and reports a translated message on decode (error marked `unsupported`) — the `_impl.hasCompression()`/`hasDecompression()` predicates exist so tests can exercise both branches. Node (tests/tools): the `zlib` module. Exposes `window.CimbarCompress`
- `rs.js` — Reed-Solomon RS(255, 191) over GF(256): 64 ECC bytes per 255-byte block, tolerates up to 32 byte errors. Berlekamp-Massey + Chien search + Forney. Exposes `class ReedSolomon`
- `gif-encoder.js` — pure-JS GIF89a encoder; builds a 256-color palette seeded with the v2 spec palette, quantizes frames, LZW-compresses. Exposes `class GifEncoder`
- `gif-decoder.js` — pure-JS GIF89a parser; handles LZW decode, interlacing, disposal modes. Returns `Array<{imageData, width, height, delay}>`. Exposes `class GifDecoder`
- `tools/tile_rules.js` — tile representation and the §3.4 constraints (fill ratio, pairwise Hamming distance, shifted-tile Hamming distance, rotation/mirror uniqueness) shared by the generator and `test_tiles.js`
- `tools/gen_tiles.js` — seeded random search that produces the 16-tile set committed to `spec/cimbar-v2.json`. Usage: `node tools/gen_tiles.js [startSeed]`
- `tools/gen_format_data.js` — writes `format-data.js` from `spec/cimbar-v2.json`. Usage: `node tools/gen_format_data.js`
- `tools/gen_goldens.js` — renders reference GIFs with the production encoder into `test-data/goldens/<name>.gif` plus a `<name>.json` ground-truth sidecar (payload, per-frame header, raw bytes, per-cell symbol/color). Usage: `node tools/gen_goldens.js`
- `tools/healthcheck.js` — post-deploy verifier for the S3/CloudFront pipeline (`.github/workflows/deploy-webapp.yml`): fetches the public page and one script, requires the `<!-- cimbar-build:<sha> -->` marker the workflow stamps into `index.html`. Usage: `node tools/healthcheck.js https://nfcarchiver.com/cimbar/ <sha>`
- `tools/node_crypto.js` — Node implementation of the `crypto.js` wire format (Node has no Web Crypto) used only so `gen_goldens.js` can produce encrypted goldens without a browser

## Format v2.1

Format constants (grid, finders, palette, tiles, RS sizes, header field layout, and the v2.1 `coding`/`compression` blocks) live in `spec/cimbar-v2.json`, loaded by `web-app/format.js`. Layout rules that are not constants — MSB-first bit order with symbol bits high and color bits low, row-major cell order skipping the four corner blocks, the RS block partition loop, the interleave rule, the GIF palette slot order — are defined in the design spec `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md`. The v2.1 additions below — header flag bits, the coefficient generator, compression, GIF/present-mode composition — are defined in `docs/superpowers/specs/2026-09-18-cimbar-v2.1-rateless-and-compression-design.md` and implemented in `web-app/format.js` / `web-app/rateless.js` / `web-app/compress.js` / `web-app/cimbar.js`.

- **Grid:** 64×64 cells. Each cell is 8×8 px with a 1 px black gap after it (9 px pitch), giving a 576 px grid plus a 16 px quiet zone on each side = 608 px frame.
- **Finders:** four QR-style 7×7-cell finder patterns at the grid corners (1:1:3:1:1 ratio), each reserving an 8×8-cell corner block. `usableCells = 4096 − 256 = 3840`.
- **Bits per cell:** 4 colors (green/cyan/yellow/magenta) × 16 tile shapes (8×8 binary tiles from `spec/cimbar-v2.json`, generated by `tools/gen_tiles.js`) = 6 bits/cell (4 symbol bits + 2 color bits).
- **Per-frame byte budget:** `3840 × 6 bits = 2880` raw bytes → RS(255,191) framing gives `2112` data bytes → minus the 8-byte frame header = `2104` file bytes per frame.
- **Frame header** (first 8 bytes of a frame's protected data): `[ver 0x02][flags][fileId u16][seq u16][total u16]`, big-endian. `flags` bit 0 = encrypted, bit 1 = repair (this frame is a GF(256) repair row rather than a source frame; `seq` is then the repair id `r`, not a source index), bit 2 = compressed (the container was zlib-deflated before framing); bits 3–7 are reserved and must be 0 (a decoder rejects the frame, reason `flags`). `total` is always N, the source frame count, on every frame including repair frames.
- **RS layout:** RS(255,191) blocks 11×255 + 1×75 per frame, byte-stride interleaved with the stride-skip-short rule (see design spec §4.3): for byte index j the loop appends byte j of every block that has one.
- **Compression:** the file container is zlib-deflated before encryption whenever deflate saves at least `compression.minSaving` (5%) of its size; otherwise it is sent unmodified and flag bit 2 stays clear, so already-compressed media costs nothing extra. Decoders refuse inflated output above `compression.maxInflatedBytes` (128 MB) on both sides, and a browser without the Compression Streams API encodes uncompressed and reports a translated error when asked to decode a compressed file.
- **Coding layer:** every frame carries a row over GF(256) — a source frame's row is the unit vector for its `seq`; a repair frame's coefficients are derived from `[fileId, r, total]` alone by a splitmix32-style state advance plus a murmur3 fmix32 output mix (`codingCoefficients` in `format.js`; a generator that is linear over GF(2) in its state does not work here — see design spec §5.3). `RatelessAssembler` recovers all N source bodies from any N linearly independent rows, source and/or repair, received in any order. Coding applies only up to `coding.maxFrames` = 4096 source frames; larger files fall back to plain framing with no repair frames.
- **GIF composition:** a downloadable GIF holds the N source frames followed by `R = ceil(gifRepairRatio · N)` repair frames (`gifRepairRatio` = 0.25, `Cimbar.gifRepairCount`), so a viewer that misses up to R frames per loop still completes. Present mode instead never loops: one pass over the N source frames, then repair frames `r = 0, 1, 2, …` without end, each generated on demand. The exceptions are single-frame files and files above the 4096-frame coding cap: with no repair frames available, present mode loops the source pass.

**Breaking change:** v1 GIFs (7 bits/cell, 8 colors, corner-dot symbols, center metadata block, no per-frame header) do not decode with v2/v2.1 software, and v2/v2.1 GIFs do not decode with v1 software.

## Interoperability

The web app and the Android app are both on CimBar v2.1: the v2 frame geometry, finders, tiles and RS layer are unchanged, and both sides add the v2.1 header flags, GF(256) repair-frame coding (`RatelessAssembler`, which replaced the old sequence-slot assembler class on both sides) and optional zlib compression. The Android app decodes v2 and v2.1 via GIF import, live camera scanning, and in-app photo capture — all three share the same `FrameDecoder`/`RatelessAssembler` decode layer. `test-data/goldens/` (golden GIFs plus JSON ground-truth sidecars, generated by `web-app/tools/gen_goldens.js`, including two v2.1 "coded" goldens exercising compression and repair frames) is the interoperability contract both sides are tested against. Encryption is optional — unencrypted GIFs can be decoded without a passphrase, and encrypted payloads are auto-detected by their `CB 42 01 00` magic header.

A v0.9.1 (plain-v2) decoder still assembles an **uncompressed** v2.1 GIF from its source frames — its repair frames are simply rejected as an unrecognized flag combination, which doesn't matter once the source frames alone complete the file. It refuses a **compressed** v2.1 GIF outright: compression sets a flag bit v0.9.1 doesn't know, on every frame including the source frames, so no frame is ever accepted.

The web app is available at https://nfcarchiver.com/cimbar/

## Store Metadata, F-Droid and Releasing

The Android app's application id is **`com.nfcarchiver.cimbar`** (namespace too; `MainActivity` lives in `app/android/app/src/main/java/com/nfcarchiver/cimbar/`). Up to v0.10.1 it was `com.cimbar.scanner` — a different app to Android, so 0.11.0 installs beside it rather than upgrading it.

- **Fastlane listings** (`fastlane/metadata/android/<locale>/`): `title.txt` (≤ 50), `short_description.txt` (≤ 80), `full_description.txt` (≤ 4000), `changelogs/<versionCode>.txt` (≤ 500 chars). Locales `en-US`, `ru-RU`, `uk`, `tr-TR`, `ka-GE` — one per `app/lib/l10n/app_<lang>.arb`; adding an app language needs a listing too. Changelogs are named by the **versionCode** (the `+N` in pubspec), not the version name, and every locale needs one per release. `en-US/images/` holds `icon.png` + `featureGraphic.png` (generated — see below) and, once taken on a device, `phoneScreenshots/` (`images/README.md` has the shot list).
- **`tools/validate_store_metadata.py`** (CI job *Validate Store Metadata*; needs PyYAML) checks all of the above plus: the recipe's commit is a full sha or `v<versionName>`, `CurrentVersion`/`CurrentVersionCode` match a build entry and don't run ahead of pubspec, the recipe's `UpdateCheckData` regexes read the same `name+code` out of `app/pubspec.yaml`, `release.yml`'s `FLUTTER_VERSION` is an exact `x.y.z`, `applicationId` matches the recipe, store image sizes, and ARB ↔ listing coverage in both directions.
- **`tools/gen_store_graphics.js`** generates the adaptive launcher icon (`res/drawable/ic_launcher_foreground.xml`, `res/mipmap-anydpi-v26/ic_launcher.xml`, `res/values/ic_launcher_background.xml`), the legacy `mipmap-*/ic_launcher.png` (minSdk 24 predates adaptive icons), and the store `icon.png`/`featureGraphic.png` — a finder pattern plus real spec tiles and palette colors. The XML needs only Node; the PNGs need Playwright's Chromium (`NODE_PATH=<a node_modules with playwright> node tools/gen_store_graphics.js`; `~/banana_split/node_modules` has one on the dev machine). The mosaic side (44 of 108 dp) keeps it inside the 66 dp adaptive-icon safe circle.
- **F-Droid recipe** (`fdroid/com.nfcarchiver.cimbar.yml`) is the local copy of what is submitted to fdroiddata (`metadata/com.nfcarchiver.cimbar.yml`); once merged there, the canonical file wins — read it (`curl -sL https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/com.nfcarchiver.cimbar.yml`) before reasoning about the real recipe. `subdir: app` (the Flutter root; `scandelete: app/.pub-cache`); the prebuild greps `FLUTTER_VERSION: '<x.y.z>'` out of `../.github/workflows/release.yml` and `git checkout`s it in the Flutter srclib (so it must be an exact tag, never a range like `3.44.x`), then `flutter pub get --enforce-lockfile`. The first build entry says `commit: v0.11.0` because the tag doesn't exist yet; pin the full sha after tagging (the validator accepts either).
- **`app/pubspec.lock` is committed** and must resolve under the pinned Flutter: F-Droid's `--enforce-lockfile` refuses any drift, and CI's *Analyze & Test* runs the same flag, so a pubspec dependency change without re-running `flutter pub get` (with Flutter 3.44.8) fails CI. There is no FOSS/non-FOSS split (unlike Banana Split's `mobile_scanner`): no dependency pulls Google Play Services, Firebase or ML Kit — keep it that way, or F-Droid needs a stripped variant and a second lockfile.
- **Versioning:** the committed `app/pubspec.yaml` `version: X.Y.Z+CODE` is the single source of truth. `release.yml` builds with it and refuses to release a version name the committed pubspec disagrees with — F-Droid's `checkupdates` bot parses that line at each new tag (`UpdateCheckData`), so a pubspec left behind hides a release from F-Droid. The code goes up by one per release (v0.10.1 = 186, v0.11.0 = 187). Three version declarations must agree (tests enforce it): the newest `## [X.Y.Z]` CHANGELOG heading, pubspec, and `web-app/index.html`'s `data-version`.
- **Permissions:** the APK requests only `CAMERA`. `AndroidManifest.xml` strips what plugins merge in — `READ_EXTERNAL_STORAGE`/`READ_MEDIA_*` (`open_filex`), `RECORD_AUDIO`/`WRITE_EXTERNAL_STORAGE` (`camera_android_camerax`; safe because both `CameraController`s pass `enableAudio: false`) — and `test/android_manifest_test.dart` asserts `CAMERA` is the only one left. F-Droid shows every permission on the app page and the listings/privacy policy promise "camera only", so check `build/app/outputs/logs/manifest-merger-release-report.txt` after adding any plugin. The APK also omits AGP's dependency-metadata block (`dependenciesInfo.includeInApk = false`).
- **Release flow:** bump pubspec (name + code), `index.html` version, CHANGELOG heading, and write the five `changelogs/<code>.txt` → PR → merge → run the Release workflow on master (`gh workflow run release.yml --ref master -f version=X.Y.Z -f branch=master -f prerelease=false`). The fdroiddata update after that is automatic (the bot copies the previous build entry with the new tag's commit); an MR is only needed when the build steps themselves change. A failed F-Droid build is pinned to its tag commit — fixing master doesn't help it, only a new release does. Signing: GitHub APKs are signed with the CI runner's debug key (no release keystore yet); F-Droid signs its builds with its own key, so the two can't upgrade each other.

## Web App Tests

All tests live in `web-app/tests/`. Run from the `web-app/` directory (no install needed beyond Node.js):

```bash
cd web-app
sh tests/run_all.sh          # run all tests (tiles + format + frame + rateless + RS + compress + goldens + pipeline + i18n + browser load + deploy healthcheck)
node tests/test_tiles.js     # single test
node tests/test_format.js
node tests/test_frame.js
node tests/test_rateless.js
node tests/test_rs.js
node tests/test_compress.js
node tests/test_goldens.js
node tests/test_pipeline_node.js
node tests/test_i18n.js
node tests/test_browser_load.js
node tests/test_healthcheck.js
python3 tests/test_pipeline.py                              # Python orchestrator (runs six of the eleven Node tests; sh tests/run_all.sh runs all)
python3 tests/test_pipeline.py ../test-data/goldens/hello.gif 608   # also runs GIF structure check
python3 tests/test_gif.py path/to/output.gif [size]          # standalone GIF check (needs Pillow)
```

| File | What it tests |
|------|--------------|
| `tests/test_tiles.js` | `tools/tile_rules.js` and `tools/gen_tiles.js`: hex↔tile round trip, Hamming/shift/rotation/mirror helpers, `checkTile`/`checkPair`/`checkSet`, deterministic seeded generation, uniform 2×2-block tile structure. |
| `tests/test_format.js` | `format.js` and `spec/cimbar-v2.json`: grid/finder constant self-consistency, palette, tile set validity, capacity derivation (2880/2112/2104), `format-data.js` freshness, reserved-cell geometry, header encode/decode, `packCells`/`unpackCells` round trip, `cellValue`/`cellSymbol`/`cellColor`. |
| `tests/test_frame.js` | `cimbar.js` v2 API: `renderFrame` finder/cell painting, `decodeFrameExact` round trip, `encodeRSFrame`/`decodeRSFrame` (including failed-block zero-fill), `splitIntoFrames` header/padding, a basic `RatelessAssembler` accept/dedup/reject/complete smoke test (full coverage in `test_rateless.js`), payload helpers, and a full GIF round trip via `MockCanvas`. |
| `tests/test_rateless.js` | `rateless.js`'s coding layer: `combineBodies` GF(256) math, `repairFrame` header/body correctness, `RatelessAssembler` reaching full rank from any N independent rows (source-only, repair-only, mixed, shuffled, and exactly-N-repair-rows-with-no-slack) for N ∈ {7, 64, 345}, duplicate/dependent/flags-mismatch rejection and counters, the systematic fast path never touching GF arithmetic, and the two memory-bound cases (`denseRows` stays 0 for an in-order source-only file; `total` beyond `coding.maxFrames` accepts source frames only), a short frame buffer rejected with reason `short` before header decode, and a timing guard that `repairFrame` at N=345 stays under 50 ms (median of 5 runs, printed). |
| `tests/test_rs.js` | Reed-Solomon encode/decode: clean round-trip, ≤32 error correction, >32 error detection, Forney/Omega correctness. |
| `tests/test_compress.js` | `compress.js`: a compressible text file deflates and round-trips through `maybeDeflate`/`inflateBytes`; incompressible random bytes are left alone (below the 5% `compression.minSaving` threshold); `inflateBytes` rejects non-deflate garbage; with `_impl.hasCompression()` stubbed false the payload stays raw and with `hasDecompression()` stubbed false inflate throws an `unsupported` error; a 2 MB zero stream trips the lowered inflate cap (`tooLarge`) and inflates fine under it. |
| `tests/test_goldens.js` | Decodes each GIF in `test-data/goldens/` — including the two v2.1 "coded" goldens (compressed, with repair frames) — and checks frames, cells, headers and payload against its `<name>.json` ground-truth sidecar (see `tools/gen_goldens.js`); for a coded golden, verifies full reassembly from all frames, from source frames only, and from every-k-th-frame dropped. The Dart suite consumes the same goldens via `GoldenSidecar` (`frame_decoder_golden_test.dart`, `decode_pipeline_v2_test.dart`). |
| `tests/test_pipeline_node.js` | Full GIF encode→decode pipeline. Tests the 4-byte length prefix that prevents AES-GCM auth-tag corruption from RS zero-padding. Three cases: multi-frame, out-of-order assembly, single-frame. |
| `tests/test_i18n.js` | `i18n.js`: every language defines every English key with no empty strings and the same `{placeholders}`, `t()` interpolates and falls back to English, language detection (stored choice → browser languages → English), and every `data-i18n*` key used in `index.html` exists. |
| `tests/test_browser_load.js` | Loads the ten page scripts in `index.html` order inside one shared global scope with no `module`/`require` (what a browser does), checks the dependency order (`format-data.js` before `format.js`, `format.js` before `rateless.js`/`cimbar.js`/`gif-encoder.js`, `i18n.js` last) and asserts `ReedSolomon`, `CIMBAR_SPEC`, `CimbarFormat`, `CimbarRateless`, `Cimbar`, `CimbarCrypto`, `CimbarCompress`, `GifEncoder`, `GifDecoder`, `CimbarI18n` exist. Catches top-level `const` collisions between files, which Node module tests cannot. |
| `tests/test_healthcheck.js` | `tools/healthcheck.js`, the post-deploy verifier used by `.github/workflows/deploy-webapp.yml`: build-marker match, content types, no redirect following, retry/backoff, CLI exit codes (0 healthy, 1 unhealthy, 2 usage) against a local `http` server. |
| `tests/test_gif.py` | Structural check on a real GIF: `GIF89a` magic, 608×608 dimensions, global color table flag, frame count, palette slots 0–5 against the v2 spec palette (+ black, white). Palette/frame checks require Pillow; the rest run without it. |
| `tests/test_pipeline.py` | Python subprocess orchestrator: runs six of the eleven Node scripts above (tiles, format, frame, RS, goldens, pipeline — not `test_rateless.js`, `test_compress.js`, `test_i18n.js`, `test_browser_load.js` or `test_healthcheck.js`) and, if a GIF path is given, `test_gif.py`. `sh tests/run_all.sh` is what runs all eleven. |
| `tests/mock_canvas.js` | Node.js mock of Canvas 2D API. `getImageData` returns a copy of the pixel buffer (matching browser behavior). |

### Known Subtleties (Web)

- The page scripts are classic `<script>` tags, so every file's top-level `const`/`let`/`class` lives in ONE shared global scope: two files declaring `const SPEC` is a `SyntaxError` in the browser (and `Cimbar` ends up undefined) even though every Node test passes, because Node gives each file its own module scope. `rateless.js`, `cimbar.js`, `compress.js` and `i18n.js` are wrapped in IIFEs for that reason; `tests/test_browser_load.js` enforces it for all ten scripts.
- `decodeFrameExact` unpacks exactly `usableCells × 6 / 8 = 2880` bytes (an exact division, no rounding); `decodeRSFrame` uses `format.js`'s `rawBytesPerFrame()` as the byte limit so block boundaries match the encoder.
- `MockCanvas.getImageData` must return a copy (`_pixels.slice()`), not a reference — the real DOM API always copies, and GifEncoder stores the returned object by reference.
- The 4-byte big-endian length prefix in frame data is the only mechanism that strips RS zero-padding before AES-GCM decryption.
