# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/mezinster/cimbar/compare/v0.8.4...HEAD
[0.8.4]: https://github.com/mezinster/cimbar/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/mezinster/cimbar/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/mezinster/cimbar/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/mezinster/cimbar/compare/v0.7.1...v0.8.1
[0.7.1]: https://github.com/mezinster/cimbar/releases/tag/v0.7.1
