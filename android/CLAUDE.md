# Android App — CLAUDE.md

Flutter project in `android/` (the Flutter root; native Android config is at `android/android/`).

## Build

```bash
cd android
flutter pub get
flutter gen-l10n
flutter build apk --debug
flutter test
```

Requires Flutter 3.24+ and Java 17.

## Project Structure

```
android/lib/
├── app.dart                    — Root MaterialApp.router + go_router config
├── main.dart                   — Entry point; initializes SharedPreferences, ProviderScope
├── core/
│   ├── constants/cimbar_constants.dart  — Cell size, ECC bytes, frame sizes, 8-color palette, magic
│   ├── models/                 — DecodeProgress, DecodeState, DecodeResult, BarcodeRect, DecodeTuningConfig
│   ├── providers/              — SharedPreferencesProvider, LocaleProvider, DecodeTuningProvider
│   ├── services/               — All decode/crypto/camera/file logic (see below)
│   └── utils/byte_utils.dart   — readUint32BE, writeUint32BE, concatBytes, bytesToHex
├── features/
│   ├── import/                 — GIF import: ImportScreen + ImportController
│   ├── import_binary/          — Binary import: ImportBinaryScreen + ImportBinaryController
│   ├── camera/                 — Camera: CameraScreen, CameraController, LiveScanScreen, LiveScanController
│   ├── files/                  — File explorer: FilesScreen + FilesController
│   └── settings/               — SettingsScreen (decode tuning, language, about)
├── shared/
│   ├── theme/app_theme.dart    — Material 3, forest green seed, light + dark
│   └── widgets/                — AppShell, PassphraseField, FilePickerZone, ProgressCard, ResultCard, LanguageSelector, LanguageSwitcherButton, BarcodeOverlayPainter
└── l10n/
    ├── app_en.arb … app_ka.arb — 5 language ARB files
    └── generated/app_localizations.dart — Stub (replaced by flutter gen-l10n)
```

## Decoding Pipelines (Dart ports of the web-app JS modules)

```
GIF import:    GIF → parse frames (image pkg) → decode pixels (cimbar_decoder) → RS decode (reed_solomon) → decrypt (crypto_service) → File
Camera photo:  Photo → locate barcode (frame_locator) → white balance + try frame sizes → RS decode → decrypt → File
Live scan:     Camera stream → YUV→RGB (yuv_converter) → locate + white balance + decode per-frame (live_scanner) → adjacency-chain assembly → decrypt → File
```

## Core Services (`lib/core/services/`)

- `galois_field.dart` — GF(256) arithmetic with lookup tables (port of rs.js:13-73)
- `reed_solomon.dart` — RS(255,191) encode/decode with Berlekamp-Massey + Chien + Forney (port of rs.js:76-235)
- `cimbar_decoder.dart` — frame pixel decoding: color detection via weighted distance (GIF path) or Von Kries white-balanced relative color matching (camera path), symbol detection via quadrant luma thresholding (GIF path) or average hash matching with drift tracking (camera path, via `SymbolHashDetector`), RS frame splitting
- `symbol_hash_detector.dart` — average-hash symbol detection for camera decode: pre-computes 64-bit reference hashes for all 16 symbols, matches camera cells via Hamming distance (tolerates ~20 bits of noise), supports fuzzy 9-position drift-aware matching (center + 8 neighbors at ±1px), drift accumulates across cells (capped ±15px)
- `crypto_service.dart` — AES-256-GCM + PBKDF2 via PointyCastle, matching exact wire format (port of crypto.js)
- `gif_parser.dart` — wrapper around `image` package GifDecoder
- `decode_pipeline.dart` — full GIF decode orchestration with `Stream<DecodeProgress>` for UI updates
- `camera_decode_pipeline.dart` — single-frame decode from camera photo: locate barcode region, try all frame sizes, RS decode, decrypt
- `frame_locator.dart` — finds the CimBar barcode region via anchor-based finder pattern detection (bright→dark→bright run-length scanning for the 3×3 finder blocks), with luma-threshold bounding-box fallback. Returns `LocateResult` with cropped image, `BarcodeRect`, and optional finder centers for perspective transform
- `yuv_converter.dart` — converts Android YUV_420_888 camera frames to RGB images using ITU-R BT.601 coefficients; accepts raw plane bytes + strides (not CameraImage) for testability
- `live_scanner.dart` — multi-frame live scanning engine: content-based deduplication (FNV-1a hash), adjacency-chain frame ordering, frame 0 detection via length prefix, auto-completion. Accepts `DecodeTuningConfig` for runtime-adjustable decode parameters
- `perspective_transform.dart` — pure-Dart perspective warp: DLT homography, inverse mapping + nearest-neighbor sampling with `.floor()` (not `.round()` — Dart's banker's rounding corrupts cell alignment). Used by `frame_decode_isolate.dart` as "try warp first, fallback to crop+resize"
- `frame_decode_isolate.dart` — isolate entry point for live scan: runs all heavy computation (YUV→RGB, locate, warp, decode) in `Isolate.run()` to keep UI at 30fps. Returns `IsolateFrameResult` with decoded bytes, bounding box, optional debug captures, and two-channel diagnostics. Stateful tracking (adjacency chains, dedup) stays on main isolate via `LiveScanner.processDecodedData()`
- `file_service.dart` — centralized file operations: sharing decoded files via `share_plus`

## State Management (Riverpod)

All feature controllers follow `State + StateNotifier` pattern:

```dart
class XyzState {
  final bool isDecoding;
  final DecodeResult? result;
  // ... immutable fields, const constructor, copyWith with clearXyz flags
}

final xyzControllerProvider = StateNotifierProvider<XyzController, XyzState>((ref) {
  return XyzController();
});
```

Screens use `ref.watch(provider)` to rebuild on state changes and `ref.read(provider.notifier)` to call controller methods. State objects are immutable with `copyWith` + optional `clearField` flags to null out fields.

## Navigation (go_router)

```dart
GoRouter(
  initialLocation: '/import',
  routes: [
    ShellRoute(
      builder: (_, __, child) => AppShell(child: child),  // bottom nav bar
      routes: [
        GoRoute(path: '/import',   ...ImportScreen),
        GoRoute(path: '/binary',   ...ImportBinaryScreen),
        GoRoute(path: '/camera',   ...CameraScreen),
        GoRoute(path: '/files',    ...FilesScreen),
        GoRoute(path: '/settings', ...SettingsScreen),
      ],
    ),
  ],
);
```

`NoTransitionPage` for instant tab switching. `LiveScanScreen` is pushed **outside the shell** via `Navigator.of(context).push(MaterialPageRoute(...))` as a full-screen modal (no bottom nav).

## Camera Implementation

- **`CameraController`** with `ResolutionPreset.high` (720p) and `ImageFormatGroup.yuv420` (native format)
- **`startImageStream`** delivers ~30fps YUV frames; plane bytes copied with `Uint8List.fromList(plane.bytes)` (ephemeral during callback)
- **`WidgetsBindingObserver`** for camera lifecycle: dispose on `inactive`, reinitialize on `resumed`
- **Portrait lock** via `SystemChrome.setPreferredOrientations` while live scanning
- **`PopScope`** wrapper ensures Android back button exits camera mode and stops the image stream

## Live Scanning Architecture

CimBar frames have no per-frame identifiers. Frames are distinguished only by content:
- **Content-based deduplication** — FNV-1a hash of first 64 decoded bytes
- **Adjacency-chain ordering** — tracks frame-to-frame transitions (A→B) to reconstruct correct sequence
- **Frame 0 detection** — first 4 bytes form a valid big-endian length prefix (payload ≥ 32 bytes, 1–255 frames)
- **Completion condition** — all unique frames captured AND adjacency chain from frame 0 is complete
- **Dual crop strategy** — tries FrameLocator first; if crop covers >80% of image area, falls back to center-square crop
- **RS quality gate** — rejects frames where first 64 decoded bytes are all zero
- **LAB color space failover** — when quality gate rejects, retry decode with CIELAB color matching
- **Frame size locking** — after first successful decode, skips try-all-sizes for subsequent frames
- **AR overlay** — `BarcodeOverlayPainter` maps camera coordinates to screen space (sensor rotation + `BoxFit.cover` scaling)

### Isolate Architecture

Heavy per-frame computation runs in a background isolate via `Isolate.run()` to keep the UI thread responsive:

- **`IsolateFrameInput`** — all primitive/transferable types (YUV planes as `Uint8List`, strides, tuning config, flags)
- **`IsolateFrameResult`** — decoded bytes, frame size, bounding box, optional PNG captures, `debugInfo` (verbose), `overlayLine` (short)
- **`_runIsolate`** — top-level function wrapper required because `Isolate.run()` closures cannot capture `this` (Riverpod's `SynchronousFuture` is not sendable). See [Dart SDK #52661](https://github.com/dart-lang/sdk/issues/52661)
- **State split:** compute in isolate → return result → state tracking (adjacency, dedup, frame counting) on main isolate via `LiveScanner.processDecodedData()`

### Two-Channel Debug Logging

Debug diagnostics are generated inside the isolate (where all data is available) and returned as strings:

- **ADB logcat (`debugInfo`)** — verbose multi-line: timing breakdown, finder coordinates, per-strategy attempt results (RS outcome, quality gate, DecodeStats with hamming/drift/color histograms)
- **AR overlay (`overlayLine`)** — short one-liner: `OK 256px 4pt 180ms f=4` or `FAIL 200ms f=3`
- **Triple-tap** toggles the AR debug overlay; also auto-enables `_debugMode` and ADB logging if not already on
- **Capture button** (visible when debug overlay is open) saves raw + warped PNGs to app documents; warped image captured even on decode failure for diagnostic analysis

## Dependencies (`pubspec.yaml`)

| Category | Package | Purpose |
|----------|---------|---------|
| State | `flutter_riverpod` | Provider-based state management |
| Navigation | `go_router` | Type-safe routing with ShellRoute |
| Camera | `camera` | Full camera control for live streaming |
| Image | `image` | Pure Dart GIF decode + pixel manipulation |
| Crypto | `pointycastle` | AES-GCM, PBKDF2 |
| Files | `file_picker`, `image_picker` | File/photo selection |
| Storage | `path_provider`, `shared_preferences` | Save files, persist settings |
| Permissions | `permission_handler` | Camera + storage permissions |
| Sharing | `share_handler` | Receive shared GIF/binary files |
| Sharing | `share_plus` | Outbound file sharing via system share sheet |
| Other | `url_launcher`, `intl` | Open web links, i18n formatting |

## Localization

5 languages via ARB files (`lib/l10n/app_*.arb`). Run `flutter gen-l10n` to regenerate. Manual stub at `lib/l10n/generated/app_localizations.dart` allows compilation before generation. Access via `AppLocalizations.of(context)!.keyName`. Locale preference persisted in `SharedPreferences` via `LocaleProvider`.

## Android Manifest

- Permissions: `CAMERA`, `READ_EXTERNAL_STORAGE` (maxSdkVersion 32)
- `android.hardware.camera` feature declared as `required="false"`
- Intent filters accept shared `image/gif` and `application/octet-stream` files
- Activity uses `singleTop` launch mode, handles `configChanges` for orientation/keyboard

## Features

- **Import GIF** — pick a CimBar GIF, enter passphrase, decode and save/share
- **Import Binary** — decrypt raw binary from C++ scanner, save/share result
- **Camera** — single-photo capture + live multi-frame scanning with AR overlay
- **Files** — browse decoded files, swipe-to-delete, share via system share sheet
- **Settings** — decode tuning sliders/toggles, language selection (5 languages), about
- **Language Switcher** — globe icon in AppBar on all tabbed screens
- **File Sharing** — `ResultCard` wires `onShare` via `FileService.shareResult`

## Design Decisions and Known Patterns

**TextEditingController listener pattern:** Screens checking `_passphraseController.text.isNotEmpty` to enable/disable buttons must add `_passphraseController.addListener(() => setState(() {}))` in `initState`. `PassphraseField` is self-contained — its internal `setState` only rebuilds itself, not the parent screen.

**`Future.microtask` for camera state updates:** The camera `startImageStream` callback can fire during widget tree builds. Synchronous state updates trigger Riverpod's "modify provider during build" exception. Fix: wrap in `Future.microtask(() { ... })`.

**Material 3 theming:** Forest green (#2E7D32) seed color. Both light/dark themes provided; follows system preference via `ThemeMode.system`.

**AR overlay coordinate mapping:** `BarcodeOverlayPainter` maps barcode bounding box from camera to screen in 3 steps: (1) rotate by `sensorOrientation`, (2) scale by `BoxFit.cover` factor, (3) offset by centering delta. Uses `shouldRepaint` with rect equality check.

**`LanguageSwitcherButton` as `ConsumerWidget`:** Needs Riverpod access for `localeProvider`. Uses `showModalBottomSheet` with `RadioListTile` options. Not included in `LiveScanScreen` (no AppBar).

**Camera-specific decode flags:** `decodeFramePixels()` accepts: `enableWhiteBalance`, `useRelativeColor`, `symbolThreshold`, `quadrantOffset`, `useHashDetection`, `useLabColor`. Camera paths set via `DecodeTuningConfig` (defaults: `enableWhiteBalance=true`, `useRelativeColor=true`, `symbolThreshold=0.85`, `quadrantOffset=0.28`, `useHashDetection=true`). `useLabColor` is failover-only (not directly configurable). GIF decode uses default/null params (exact pixel colors need no correction).

**Two-pass decode (camera path):** When `useHashDetection=true`, Pass 1 runs hash-based symbol detection with fuzzy drift matching (stores drift/symbol in typed arrays). Pass 2 samples color at drift-corrected center positions. This fixes color misclassification when perspective distortion shifts cells by 3–15 pixels. GIF path remains single-pass.

**White balance finder sampling:** Von Kries white reference from outer corner cells of all four 3×3 finder patterns (grid positions 0,0 / cols-1,0 / 0,rows-1 / cols-1,rows-1), per-channel max across 4 samples. NOT the center cell (1,1) which is dark gray.

**Symbol threshold camera vs GIF:** Original `c * 0.5 + 20` works for GIF but fails under camera auto-exposure. Camera defaults to hash-based detection. Fallback uses `symbolThreshold` (default 0.85): multiplicative-only `c * symbolThreshold`.

**CameraController disposed guard:** `LiveScanScreen` sets `_disposed = true` in `dispose()` and checks it in `_initCamera()`, `_onCameraImage()`, `didChangeAppLifecycleState(resumed)`, and `CameraPreview` render condition.

**Decode tuning config wiring:** `DecodeTuningConfig` is immutable, persisted in SharedPreferences via `DecodeTuningProvider`. Decoder is stateless — accepts tuning params as optional function arguments (testable without Riverpod).

**Isolate decode strategy chain:** `frame_decode_isolate.dart` tries strategies in order: (1) FrameLocator → for each candidate frame size: 4-point warp → 2-point warp → crop+resize, (2) center-square crop → for each candidate frame size: resize. Each attempt runs RS decode + quality gate + optional LAB failover. The `_DecodeOutcome` class tracks which strategy succeeded and its `DecodeStats`. Per-attempt diagnostics are collected via a `List<String>? log` threaded through all decode functions.

## Camera Decode Improvements (from libcimbar C++ analysis)

Reference: [sz3/libcimbar](https://github.com/sz3/libcimbar/tree/master/src/lib)

### Priority 1 — White-balance from finder patterns ✓

Von Kries 3×3 chromatic adaptation matrix from observed white (4×4 pixel regions at outer corner cells of TL and BR finders) to true (255,255,255). Applied per-pixel before color matching. Falls back if observed white luma < 30.

### Priority 2 — Perspective transform ✓

Pure-Dart homography warp in `perspective_transform.dart`.

**4-point method (`computeBarcodeCornersFrom4`):** x-axis from TL→TR, y-axis from TL→BL independently — handles trapezoidal distortion.

**2-point fallback (`computeBarcodeCorners`):** Assumes square barcode. Derives x/y unit vectors from TL-BR diagonal: `ux = ((dx+dy)/(2n), (dy-dx)/(2n))`, `uy = (-(dy-dx)/(2n), (dx+dy)/(2n))`.

**Homography:** DLT with 4 point pairs → 8×8 system, Gaussian elimination with partial pivoting. Maps destination to source (inverse mapping).

**Warp:** Nearest-neighbor sampling with `.floor()` for pixel coordinate quantization (bilinear blurs 8px cell boundaries, defeating color/symbol detection). **Critical:** Dart's `.round()` uses banker's rounding (round-half-to-even), which causes systematic ~0.5px sampling bias that corrupts cell extraction — must use `.floor()`. 256×256 = 65K pixels, within 4fps budget.

**Fallback chain:** 4-point warp → 2-point warp → crop+resize.

### Priority 3 — Anchor-based finder pattern detection ✓

In `frame_locator.dart` as primary path, luma-threshold fallback kept.

1. Downscale 2× and build luma buffer
2. Horizontal scan every 2 rows — bright→dark→bright patterns (bright threshold 180: distinguishes white finder cells from colored barcode cells luma 64–171)
3. Vertical confirmation at each hit — local window ±3× hSize (avoids colored cell interference)
4. Deduplication — merge within `imageSize/30` radius
5. **Brightness-based classification** (rotation-invariant):
   - Sample 5×5 patch at each candidate center in **full-resolution** luma (not downscaled — the ~8px center cell is only ~4px after 2× downscale, too coarse to distinguish dot vs no-dot)
   - **TL = darkest center** (asymmetric finder: no inner white dot → luma ~51 vs ~120-180 for others)
   - **BR = farthest from TL** (Euclidean distance)
   - **TR vs BL = cross-product**: `(BR-TL) × (candidate-TL)` sign — works at any rotation (0°, 90°, 180°, 270°)
   - Fallback: if brightness gap < 20 → use coordinate-extreme method (backward compat with symmetric finders)
6. Crop computation — cell size from finder width `/3`, 1.5-cell padding + 2% margin
7. Fallback — <2 finders → luma > 30 bounding-box

**Asymmetric finder patterns:** TL finder has no inner white dot (solid dark center); TR/BL/BR have white inner dot. This enables rotation-aware identification purely from brightness.

`LocateResult` includes optional `tlFinderCenter`/`trFinderCenter`/`blFinderCenter`/`brFinderCenter` for perspective transform.

### Priority 4 — Average hash symbol detection with drift tracking ✓

`symbol_hash_detector.dart`: 64-bit average hashes for 16 symbols, matched via Hamming distance. `detectSymbolFuzzy()` tries 9 positions (center + 8 neighbors at ±1px), drift accumulates in row-scan order (capped ±15px). Gated by `DecodeTuningConfig.useHashDetection`.

**Not yet implemented:** libcimbar's flood-fill drift propagation from anchor corners (Priority 4b).

### Priority 5 — Relative color matching ✓

Channel-range normalization (minVal capped at 48), then `(R-G, G-B, B-R)` comparison. Palette relative colors pre-computed through same normalization pipeline.

### LAB Color Space Failover ✓

Camera decode paths retry with CIELAB when RS quality gate rejects (nonZero==0). sRGB → linear → XYZ (D65) → LAB. Only used as failover, never in GIF path.

### Priority 6 — Lens distortion correction (planned)

Radial distortion coefficient from edge midpoint deviation, corrected via `initUndistortRectifyMap()`.

### Priority 7 — Pre-processing: adaptive threshold + sharpening (planned)

Grayscale → optional 3×3 high-pass sharpen → adaptive threshold → bitmatrix. Sharpening only when barcode appears smaller than target resolution.

## Tests

Run: `flutter test` from `android/` directory.

| File | What it tests |
|------|--------------|
| `galois_field_test.dart` | GF(256) table wraparound, mul/div inverse, polynomial arithmetic. |
| `reed_solomon_test.dart` | Clean round-trip, 32-error correction, uncorrectable detection, Forney/Omega, full-block round-trips. |
| `cimbar_decoder_test.dart` | 128-combo draw+detect round-trips, white balance, relative color, camera-exposure symbol detection, hash detection (distinctness, drift, blur robustness), two-pass decode, LAB color matching, RS block interleaving + error spreading. |
| `crypto_service_test.dart` | AES-256-GCM round-trip, wrong passphrase rejection, bad magic, strength scoring. |
| `decode_pipeline_test.dart` | RS frame encode→draw→read→decode round-trip with length prefix. Three payload cases. |
| `frame_locator_test.dart` | Centered/offset/full-image barcode, dark image, noisy background, finder center validation, fallback behavior, rotation-invariant classification (0°/90°/180°/270°). |
| `yuv_converter_test.dart` | YUV420→RGB: white/black, UV subsampling, stride configs, semi-planar UV. |
| `perspective_transform_test.dart` | 2-point and 4-point corner derivation (axis-aligned + rotated), identity warp, rotated barcode warp, RS decode round-trips, fallback path. 9 tests. |
| `live_scanner_test.dart` | Single/multi-frame scanning, duplicate handling, out-of-order adjacency chains, frame 0 detection, dark image, reset. |

### Known Subtleties (Android)

- `decodeFramePixels` returns `ceil(usableCells × 7 / 8)` bytes, but `rawBytesPerFrame` is `floor(...)`. `decodeRSFrame` uses `rawBytesPerFrame(frameSize)` as the byte limit.
- `live_scanner_test.dart` tests via `processDecodedData(dataBytes, frameSize)` not `processFrame(image)`, because FrameLocator crop+resize introduces subpixel interpolation error.
- `CameraImage` plane bytes are ephemeral — copy with `Uint8List.fromList(plane.bytes)` before passing to controller.
- Live scan controller throttles to ~4fps (250ms interval) via timestamp check, not Timer.
- **Dart `.round()` is banker's rounding** — use `.floor()` for pixel coordinates in perspective warp. `.round()` rounds 0.5 to nearest even integer (3.5→4, 4.5→4), causing systematic sampling misalignment that corrupts every warped cell.
- **`_runIsolate` must be top-level** — `Isolate.run()` captures its closure; if it captures `this` from a `StateNotifier`, Riverpod's `SynchronousFuture` (not `Sendable`) causes a runtime error. Solution: top-level wrapper function.
- **Full-res luma for finder classification** — after 2× downscale, the ~8px finder center cell becomes ~4px, too coarse to distinguish the asymmetric TL pattern (no dot, luma ~51) from TR/BL/BR (dot, luma ~120+). Sample in full-res image.
