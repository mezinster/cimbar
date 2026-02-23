# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/mezinster/cimbar/compare/v0.8.5...HEAD
[0.8.5]: https://github.com/mezinster/cimbar/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/mezinster/cimbar/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/mezinster/cimbar/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/mezinster/cimbar/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/mezinster/cimbar/compare/v0.7.1...v0.8.1
[0.7.1]: https://github.com/mezinster/cimbar/releases/tag/v0.7.1
