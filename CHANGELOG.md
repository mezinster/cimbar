# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Android: Open and Save to device.** The result card (GIF import, photo, live scan) and the Files tab now offer *Open* (`ACTION_VIEW` chooser via `open_filex`) and *Save to device* (the system save-as picker via `file_picker`, Downloads by default) next to *Share*; tapping a row in the Files tab opens it. Decoded files were previously reachable only through the share sheet, since they auto-save into the app's private documents directory.
- **Android: passphrase asked in place after a live scan.** When a fully assembled scan turns out to be encrypted and no (or a wrong) passphrase was given up front, the scan screen now shows a passphrase field and retries the decrypt from the frames it already holds — no rescan. Previously it only showed an error and required cancelling, typing the passphrase on the Camera tab and scanning everything again.

### Fixed
- **Android: share sheet listed only a few apps.** Shared files now carry an explicit MIME type (`mime` package) and the manifest declares `SEND`/`SEND_MULTIPLE`/`VIEW` package-visibility queries, the same fix NFC Archiver needed for Telegram and other strict targets. The `READ_MEDIA_*` permissions `open_filex` would merge in are stripped.
- **Android: `errorPassphraseRequired` was untranslated** in Russian, Ukrainian, Turkish and Georgian.
- **Web: encode stats panel.** The fourth stat (compression) no longer sits alone on a second row with an empty cell beside it (the grid now auto-fits its columns), and the frames stat shows a short `45 + 12` value with "Frames (source + repair)" as its label instead of a wrapped sentence in the big-number font. The compression stat is labelled "Compressed to" so `92%` reads as a size, not a saving.

## [0.10.0] — 2026-09-18

### Added
- **CimBar v2.1: rateless repair frames.** Every barcode's N source frames are now followed by extra GF(256) repair frames (a downloadable GIF adds `ceil(0.25 × N)` of them); any N of the N + R total frames — source or repair, captured in any order — reconstruct the file. Web app: `web-app/rateless.js` (`codingCoefficients`/`combineBodies`/`RatelessAssembler`). Android: `lib/core/format/rateless.dart` + `lib/core/decode/rateless_assembler.dart`. `RatelessAssembler` replaces the old sequence-slot assembler on both sides in GIF import, live scan and photo capture.
- **Optional payload compression.** The file container is zlib-deflated before encryption whenever that saves at least 5% of its size, and left alone otherwise (already-compressed media costs nothing extra). `web-app/compress.js` (browser `CompressionStream`/`DecompressionStream`, Node `zlib`); Android decodes it via `dart:io`'s `ZLibCodec` in `payload_decoder.dart`. Recorded in a new frame-header flag bit and reversed automatically on decode — no user-facing toggle either side.
- Web app present mode no longer loops a static GIF: it streams the N source frames once, then repair frames forever, so a receiver joining at any point keeps gaining progress instead of waiting on a fixed loop.
- Two new coded goldens, `lorem_coded` and `lorem_coded_enc` (compressed, with repair frames), alongside the five existing v2 goldens in `test-data/goldens/`.
- Web test suite: `test_rateless.js` (16 tests), `test_compress.js` (6 tests). Android: `rateless_test.dart`, `rateless_assembler_test.dart`, plus rateless/compression coverage added to the golden, payload-decoder, photo-decode and live-scan-controller suites — 233 tests total (`sh tests/run_all.sh`).

### Changed
- Decode progress is now **rank** (independent frames captured, source or repair) rather than a plain frames-captured count, in both the web app ("Rank r / N") and the Android live-scan/GIF-import/photo paths.
- Frame header flags gain two bits: `repair` (bit 1) and `compressed` (bit 2), alongside the existing `encrypted` (bit 0); reserved bits 3–7 must still be zero, and a decoder rejects any frame that sets one.
- The encode stats panel gains a fourth figure, "Compressed", showing the compressed size as a percentage of the original (or "—" when the payload was left raw).
- Repair frames for a downloadable GIF are now generated inside the rendering loop that already yields to the browser, so encoding a large file no longer freezes the page while the whole repair batch is built up front.

### Security
- **Inflate cap.** Both decoders refuse compressed payloads that expand past `compression.maxInflatedBytes` = 128 MB (new constant in `spec/cimbar-v2.json`), streaming the inflate and stopping at the cap rather than buffering the whole expansion: a few KB of crafted zlib would otherwise expand to gigabytes.
- `RatelessAssembler.add` (both apps) rejects a short frame buffer with reason `short` before the header is decoded.

### Fixed
- Browsers without the Compression Streams API: encoding now falls back to an uncompressed payload instead of failing, and a decode of a compressed file reports a translated "this browser cannot decompress v2.1 files" message instead of an opaque error.

### Compatibility
- A v0.9.1 (plain v2) decoder still assembles an **uncompressed** v2.1 file from its source frames — its repair frames are simply rejected as an unrecognized flag combination, which doesn't matter once the source frames alone complete the file. It cannot decode a **compressed** v2.1 GIF at all: compression sets a flag bit v0.9.1 doesn't recognize on every frame, including the source frames, so none of them are ever accepted.

## [0.9.1] — 2026-09-18

### Added
- Web app localization: English, Russian, Ukrainian, Turkish and Georgian with a language selector in the header (`web-app/i18n.js`, stored in localStorage, browser language by default).
- Manual S3 + CloudFront deploy workflow for the web app (`.github/workflows/deploy-webapp.yml`) with OIDC credentials, build-marker healthcheck and automatic rollback; `web-app/tools/healthcheck.js` with tests.
- Golden GIFs with ground-truth sidecars (`test-data/goldens/`) shared by the JS and Dart test suites.
- Offline Dart CLI decoder `android/tool/decode_image.dart` and a real-capture corpus benchmark scaffold.
- v2 camera decode stages in Dart: finder locator, homography grid model, finder-core white balance, per-cell drift solver; synthetic degradation test harness (scale, rotation, perspective, blur, brightness, noise, barrel distortion, photo backgrounds).
- Live scan and in-app photo capture on v2: focus/exposure lock (`CapturePolicy`) with an aiming guide and contextual hints, in-app photo capture (`PhotoCaptureScreen`), ROI-based per-frame decode with hint reuse across frames, and a single long-lived background decode isolate (`DecodeIsolate`) that drops frames instead of queuing them while busy.
- `test/core/decode/benchmark_test.dart`: a synthetic-scene decode timing benchmark, writing `build/benchmark.txt`.
- Web app present mode: shows the encoded GIF full screen, scaled to fit the viewport, for another device's camera to scan.

### Removed
- The v1 decoder and its Dart camera pipeline (`camera_decode_pipeline`, `frame_locator`, `symbol_hash_detector`, `image_preprocessing`, `perspective_transform`, `frame_decode_isolate`, `live_scanner`, `cimbar_decoder`, `yuv_converter`), its constants file, and its Settings decode-tuning sliders/toggles.
- The v1-era Dart tests and test-only synthetic encoder that exercised the above.
- The web app's frame-size menu: v2 has a single 608 px frame.

### Changed
- Android toolchain: Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20, Java 17, `compileSdk`/`targetSdk` from the Flutter SDK (matching the Flutter 3.44 template); CI builds with Flutter 3.44.x.
- **CimBar v2 format** (breaking): 64×64 grid of 8 px tiles with 1 px gaps, four QR-style finders, 4 colors × 16 tiles = 6 bits/cell, RS(255,191), per-frame header `[ver][flags][fileId][seq][total]`, single 608 px frame. Web app and Android app (GIF import, live scan, photo capture) all encode/decode (or decode) v2. v1 GIFs must be re-encoded.
- CI (`.github/workflows/ci.yml`) now runs both test suites: the Flutter test runner (`android/tests/run_all.sh`, including the corpus benchmark table) and the web-app Node test suite (`web-app/tests/run_all.sh`), and uploads the corpus/benchmark reports as a build artifact.

### Fixed
- Web app failed to load in the browser (`Cimbar is not defined`): `format.js` and `cimbar.js` both declared top-level `const SPEC`/`API` in the shared global scope; `cimbar.js` is now an IIFE and a browser-load test guards all scripts.
- Bottom tab bar went dead after a scan: Live Scan and Photo Capture were pushed on the shell's nested navigator, so they kept covering the screen while tab taps switched the route underneath. Both are now pushed on the root navigator, with a regression test.
- `ResultCard`'s save/share buttons overflowed on narrow phones with long translated labels; they now wrap.
- Release workflow failed on Flutter 3.44: it is pinned to Flutter 3.44.x and `pubspec.yaml`'s SDK floor matches the toolchain.

## [0.8.7] — 2026-03-04

### Added
- Persistent **Debug Mode** toggle in Settings, and a camera frame capture button that saves the current frame plus its diagnostics for offline analysis.
- Two-channel debug logging: structured `key=value` diagnostics per stage to logcat, plus a short on-screen overlay line.
- Center 3×3 metadata block and adaptive-threshold preprocessing (integral-image local mean) for camera decode.
- Center-cross color averaging — a 5-pixel cross per cell absorbs JPEG noise and interpolation artifacts on the camera path.
- Asymmetric TL finder pattern (no inner dot) with rotation-aware, brightness-based finder classification, so a barcode decodes at any orientation.
- Color diagnostic instrumentation in the camera decode pipeline.

### Changed
- Encryption is now optional in both apps: encode without a passphrase, and decode auto-detects encryption from the payload's `CB 42` magic bytes instead of always demanding one.
- Color palette updated to high-saturation, perceptually distinct colors.
- Camera frame processing moved to a background isolate so the UI stays responsive.
- Adaptive hash search radius and finder classification tuning.
- Camera decode pipeline unified between Live Scan and photo capture to reduce code drift.

### Removed
- The **Import Binary** feature from both the web app and the Android app.

### Fixed
- Perspective warp sampling bug: Dart's `.round()` is banker's rounding, which biased every warped cell by ~0.5 px; pixel quantization now uses `.floor()`.
- Live scan performance regression and several debug UX issues.

## [0.8.6] — 2026-02-23

### Added
- **Four-corner finder patterns** with a 4-point perspective transform, replacing the 2-point homography.

### Fixed
- Double `v` prefix in the release workflow's run name.

## [0.8.5] — 2026-02-23

### Added
- **RS block interleaving** — byte-stride interleaving spreads each RS block's bytes across the entire frame, so spatially concentrated camera errors distribute evenly across all blocks instead of overwhelming a single one
- **LAB color space failover** (Android) — when primary RGB/relative color matching fails the quality gate, camera decode retries with perceptually-uniform CIELAB color matching
- **Perspective transform** — pure-Dart homography warp from 2 finder centers; tries warp first, falls back to crop+resize if RS decode fails
- **Anchor-based finder pattern detection** — bright→dark→bright run-length scanning replaces simple luma-threshold bounding box for locating barcode region in camera photos
- **Average hash symbol detection** — 64-bit average hashes with fuzzy 9-position drift matching (±1px) and drift accumulation (capped ±15px) for camera decode
- **Two-pass camera decode** — Pass 1 discovers per-cell drift via hash detection; Pass 2 samples color at drift-corrected positions, fixing systematic color misclassification from perspective distortion
- **Von Kries white balance** from finder patterns for camera decode
- **Relative color matching** with brightness normalization for camera decode
- Runtime decode tuning settings: symbol sensitivity, white balance, relative color, quadrant offset, hash detection toggles — all persisted in SharedPreferences
- 4 new tests: LAB palette self-mapping, LAB clean frame round-trip, interleave→de-interleave round-trip, error-spreading verification (76 total)

### Changed
- RS parameters upgraded from RS(255,223) to **RS(255,191)** — 64 ECC bytes per block, corrects up to 32 errors (12.5%), enabling camera decode at real-world error rates
- Camera resolution set to 720p for optimal ~1.58× oversampling of 8px cells
- Drift cap increased from ±7px to ±15px for crop+resize fallback paths

### Fixed
- Live camera decode producing all-0xFF bytes: symbol detection threshold now uses multiplicative `c * symbolThreshold` (default 0.85) instead of `c * 0.5 + 20`
- `CameraPreview` crash when controller is disposed during navigation/lifecycle transitions (added `_disposed` guard)
- Color misclassification from sampling at raw grid positions before drift was known (fixed by two-pass architecture)

### Breaking
- RS block interleaving changes the wire format — GIFs encoded with previous versions will not decode

## [0.8.4] — 2026-02-21

### Fixed
- Language switching: replace English-only stub with real `flutter gen-l10n` output so picking a language actually switches the UI
- Import GIF and camera decode failures (`decodeRSFrame` now exactly matches the JS reference — removes erroneous `paddedBlock` intermediary)

### Changed
- Settings tab renamed to About; language selector moved exclusively to the globe icon in the AppBar
- About page now shows Privacy Policy, MIT License, and Source Code links

## [0.8.3] — 2026-02-21

### Added
- File sharing, file explorer, language switcher, and AR overlay (Phase 4)

### Fixed
- Live scan: frame detection, rotation, and back-button handling
- Decode button not activating after passphrase entry
- Riverpod "modify provider during build" crash in live scan
- Lint errors in `BarcodeOverlayPainter`

## [0.8.2] — 2026-02-20

### Changed
- Reworked release workflow to match nfcarchiver approach

### Fixed
- Live Scan button not activating when passphrase was entered
- Shell injection in release workflow when release notes contained special characters

## [0.8.1] — 2026-02-20

### Added
- Camera photo decode and live multi-frame scanning

### Changed
- Release workflow: added branch picker and release description inputs

## [0.7.1] — 2026-02-20

### Added
- Initial CimBar web app with full encode/decode pipeline, AES-256-GCM encryption, Reed-Solomon RS(255,223), pure-JS GIF89a encoder/decoder, and test suite
- Flutter Android app with full on-device decode pipeline (GF(256), RS, CimBar pixel decoder, AES-256-GCM crypto via PointyCastle)

### Fixed
- Flutter analyze errors, warnings, and infos
- Android build: bumped `compileSdk` to 35, added launcher icons

[Unreleased]: https://github.com/mezinster/cimbar/compare/v0.9.1...HEAD
[0.9.1]: https://github.com/mezinster/cimbar/compare/v0.8.7...v0.9.1
[0.8.7]: https://github.com/mezinster/cimbar/compare/v0.8.6...v0.8.7
[0.8.6]: https://github.com/mezinster/cimbar/compare/v0.8.5...v0.8.6
[0.8.5]: https://github.com/mezinster/cimbar/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/mezinster/cimbar/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/mezinster/cimbar/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/mezinster/cimbar/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/mezinster/cimbar/compare/v0.7.1...v0.8.1
[0.7.1]: https://github.com/mezinster/cimbar/releases/tag/v0.7.1
