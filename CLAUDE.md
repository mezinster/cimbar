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
- **`android/`** — A Flutter Android app that decodes CimBar GIFs via file import, binary import, or live camera scanning. Ports the full decode pipeline to Dart.

### Web App

**Encoding pipeline:**

```
File → encrypt (crypto.js) → RS encode (rs.js) → draw frames (cimbar.js) → GIF encode (gif-encoder.js) → Animated GIF
```

**Decoding pipeline:**

```
Animated GIF → GIF decode (gif-decoder.js) → sample pixels (cimbar.js) → RS decode (rs.js) → decrypt (crypto.js) → File
```

**Module responsibilities (all in `web-app/`):**

- `index.html` — all UI (tabs, drag-drop, progress, stats) and the orchestrating inline `<script>` that drives the full encode/decode flow
- `cimbar.js` — core barcode logic: maps bytes→cells (3-bit color + 4-bit symbol = 7 bits/cell), draws finder patterns, reads pixel data back to bytes. Exposes `window.Cimbar`
- `crypto.js` — AES-256-GCM via Web Crypto API; wire format is `[CB 42 01 00 magic | 16-byte salt | 12-byte IV | ciphertext+tag]`. PBKDF2 with 150,000 SHA-256 iterations for key derivation. Exposes `window.CimbarCrypto`
- `rs.js` — Reed-Solomon RS(255, 223) over GF(256): 32 ECC bytes per 255-byte block, tolerates up to 16 byte errors. Berlekamp-Massey + Chien search + Forney. Exposes `class ReedSolomon`
- `gif-encoder.js` — pure-JS GIF89a encoder; builds a 256-color CimBar palette, quantizes frames, LZW-compresses. Exposes `class GifEncoder`
- `gif-decoder.js` — pure-JS GIF89a parser; handles LZW decode, interlacing, disposal modes. Returns `Array<{imageData, width, height, delay}>`. Exposes `class GifDecoder`

**Cell encoding:** Each cell is `CELL_SIZE=8` pixels. A `floor(frameSize/8) × floor(frameSize/8)` grid minus 18 finder-pattern cells gives usable cells. Each cell encodes 7 bits (3 = color index into 8 colors; 4 = symbol index into 16 shapes). Supported frame sizes: 128, 192, 256, 384 px.

**Symbol design (4-quadrant corner dots):** The 16 symbols are all possible combinations of 4 binary corner markers. For an 8×8 cell, `q = floor(8 × 0.28) = 2 px` and `h = floor(q × 0.75) = 1 px`. The cell is filled with the foreground color; then for each 0-bit in `symIdx`, a `2h × 2h` (2×2) black square is painted at the corresponding corner sample point:

```
bit 3 → TL corner at (q-h, q-h)
bit 2 → TR corner at (size-q-h, q-h)
bit 1 → BL corner at (q-h, size-q-h)
bit 0 → BR corner at (size-q-h, size-q-h)
```

`detectSymbol` samples luma at those same four points plus the center. For the GIF path (no `symbolThreshold`), a point brighter than `center × 0.5 + 20` reads as 1. For the camera path, a configurable multiplicative threshold `center × symbolThreshold` is used instead (default 0.85) — this scales with brightness and correctly handles camera auto-exposure where the additive formula fails. The `quadrantOffset` parameter (default 0.28) controls the corner sample position as a fraction of cell size. The center pixel is never covered by a dot, so it always reflects the foreground color and is used for color detection by `nearestColorIdx`. This design was chosen to guarantee a perfect encode→decode round-trip: every bit position is sampled at exactly the pixel that was drawn for it.

The visible result is colored squares with 0–4 small black dots at the corners. `symIdx=15` (all bits 1) has no dots — a plain solid square. `symIdx=0` (all bits 0) has all four corners dotted.

### Android App

**Flutter project** in `android/` (the Flutter root; native Android config is at `android/android/`).

#### Project structure

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

#### Decoding pipelines (Dart ports of the web-app JS modules)

```
GIF import:    GIF → parse frames (image pkg) → decode pixels (cimbar_decoder) → RS decode (reed_solomon) → decrypt (crypto_service) → File
Camera photo:  Photo → locate barcode (frame_locator) → white balance + try frame sizes → RS decode → decrypt → File
Live scan:     Camera stream → YUV→RGB (yuv_converter) → locate + white balance + decode per-frame (live_scanner) → adjacency-chain assembly → decrypt → File
```

#### Core services (`android/lib/core/services/`)

- `galois_field.dart` — GF(256) arithmetic with lookup tables (port of rs.js:13-73)
- `reed_solomon.dart` — RS(255,223) encode/decode with Berlekamp-Massey + Chien + Forney (port of rs.js:76-235)
- `cimbar_decoder.dart` — frame pixel decoding: color detection via weighted distance (GIF path) or Von Kries white-balanced relative color matching (camera path), symbol detection via quadrant luma thresholding (GIF path) or average hash matching with drift tracking (camera path, via `SymbolHashDetector`), RS frame splitting (port of cimbar.js decode side)
- `symbol_hash_detector.dart` — average-hash symbol detection for camera decode: pre-computes 64-bit reference hashes for all 16 symbols, matches camera cells via Hamming distance (tolerates ~20 bits of noise), supports fuzzy 9-position drift-aware matching (center + 8 neighbors at ±1px), drift accumulates across cells (capped ±7px)
- `crypto_service.dart` — AES-256-GCM + PBKDF2 via PointyCastle, matching exact wire format (port of crypto.js)
- `gif_parser.dart` — wrapper around `image` package GifDecoder
- `decode_pipeline.dart` — full GIF decode orchestration with `Stream<DecodeProgress>` for UI updates
- `camera_decode_pipeline.dart` — single-frame decode from camera photo: locate barcode region, try all frame sizes, RS decode, decrypt
- `frame_locator.dart` — finds the CimBar barcode region in a camera photo via anchor-based finder pattern detection (bright→dark→bright run-length scanning for the 3×3 finder blocks), with luma-threshold bounding-box fallback. Returns `LocateResult` containing the cropped square image, a `BarcodeRect` with bounding box coordinates in source image space (used for AR overlay), and optional `tlFinderCenter`/`brFinderCenter` (`Point<double>?`) for future perspective transform use
- `yuv_converter.dart` — converts Android YUV_420_888 camera frames to RGB images using ITU-R BT.601 coefficients; accepts raw plane bytes + strides (not CameraImage) for testability
- `live_scanner.dart` — multi-frame live scanning engine: content-based deduplication (FNV-1a hash), adjacency-chain frame ordering, frame 0 detection via length prefix, auto-completion when all frames captured and chain is complete. Accepts `DecodeTuningConfig` for runtime-adjustable decode parameters. `ScanProgress` includes `barcodeRect`, `sourceImageWidth`, `sourceImageHeight` for AR overlay rendering
- `perspective_transform.dart` — pure-Dart perspective warp: derives 4 barcode corners from 2 finder centers (assuming square barcode), computes 3×3 homography via DLT (8×8 linear system with Gaussian elimination), warps with inverse mapping + bilinear interpolation. Used by `live_scanner.dart` and `camera_decode_pipeline.dart` as a "try warp first, fallback to crop+resize" strategy
- `file_service.dart` — centralized file operations: sharing decoded files via `share_plus` (`shareResult` for `DecodeResult`, `shareFile` for existing paths)

#### State management (Riverpod)

All feature controllers follow a consistent `State + StateNotifier` pattern:

```dart
class XyzState {
  final bool isDecoding;
  final DecodeResult? result;
  // ... immutable fields, const constructor, copyWith with clearXyz flags
}

final xyzControllerProvider = StateNotifierProvider<XyzController, XyzState>((ref) {
  return XyzController();
});

class XyzController extends StateNotifier<XyzState> {
  XyzController() : super(const XyzState());
  // ... methods that update state via state = state.copyWith(...)
}
```

Screens use `ref.watch(provider)` to rebuild on state changes and `ref.read(provider.notifier)` to call controller methods. State objects are immutable with `copyWith` + optional `clearField` flags to null out fields.

#### Navigation (go_router)

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

#### Camera implementation

- **`CameraController`** with `ResolutionPreset.high` (720p — higher resolution provides ~1.58× oversampling at 12.7 camera pixels per 8px cell, improving color/symbol detection accuracy) and `ImageFormatGroup.yuv420` (native camera format, avoids in-camera RGB conversion)
- **`startImageStream`** delivers ~30fps YUV frames; plane bytes are copied with `Uint8List.fromList(plane.bytes)` because they're only valid during the callback
- **`WidgetsBindingObserver`** for camera lifecycle: dispose on `inactive`, reinitialize on `resumed`
- **Portrait lock** via `SystemChrome.setPreferredOrientations` while live scanning (camera preview dimensions don't update on rotation)
- **`PopScope`** wrapper ensures Android back button exits camera mode and stops the image stream

#### Live scanning architecture

CimBar frames have no per-frame identifiers. Frames are distinguished only by content. The live scanner uses:
- **Content-based deduplication** — FNV-1a hash of first 64 decoded bytes
- **Adjacency-chain ordering** — tracks frame-to-frame transitions (A→B) to reconstruct correct sequence across multiple animation cycles
- **Frame 0 detection** — identifies the frame whose first 4 bytes form a valid big-endian length prefix (payload ≥ 32 bytes, 1–255 total frames)
- **Completion condition** — all unique frames captured AND adjacency chain from frame 0 is complete (N-1 links for N frames)
- **Dual crop strategy** — tries FrameLocator first; if the crop covers >80% of the image area (common in well-lit rooms), falls back to center-square crop
- **RS quality gate** — rejects frames where the first 64 decoded bytes are all zero (every RS block failed = garbage data, not a real barcode)
- **Frame size locking** — after first successful decode, skips expensive try-all-sizes step for subsequent frames
- **AR overlay** — `FrameLocator` returns the bounding box via `LocateResult`; `ScanProgress` propagates it through the controller to `BarcodeOverlayPainter`, which maps camera coordinates to screen space (handling sensor rotation + `BoxFit.cover` scaling) and draws green corner brackets around the detected barcode

#### Dependencies (`pubspec.yaml`)

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

#### Localization

5 languages via ARB files (`lib/l10n/app_*.arb`). Run `flutter gen-l10n` to regenerate. A manual stub at `lib/l10n/generated/app_localizations.dart` allows the project to compile before generation. Access via `AppLocalizations.of(context)!.keyName`. Parameterized strings use `{placeholder}` syntax in ARB. Locale preference persisted in `SharedPreferences` via `LocaleProvider`.

#### Android manifest

- Permissions: `CAMERA`, `READ_EXTERNAL_STORAGE` (maxSdkVersion 32)
- `android.hardware.camera` feature declared as `required="false"`
- Intent filters accept shared `image/gif` and `application/octet-stream` files
- Activity uses `singleTop` launch mode, handles `configChanges` for orientation/keyboard

#### Build

```bash
cd android
flutter pub get
flutter gen-l10n
flutter build apk --debug
flutter test
```

Requires Flutter 3.24+ and Java 17.

#### Features

- **Import GIF** — pick a CimBar GIF, enter passphrase, decode and save/share the file
- **Import Binary** — decrypt raw binary from C++ scanner, save/share result
- **Camera** — single-photo capture (Take Photo / Gallery) for single-frame barcodes, plus live multi-frame scanning for animated barcodes with AR overlay (green corner brackets highlight detected barcode region)
- **Files** — browse decoded files saved to app storage, swipe-to-delete with confirmation, share via system share sheet, pull-to-refresh, file-type icons by extension
- **Settings** — decode tuning (symbol sensitivity, white balance, relative color, quadrant offset sliders/toggles persisted in SharedPreferences), language selection (5 languages), about with web app link
- **Language Switcher** — globe icon in AppBar on all tabbed screens; opens a bottom sheet with flag emojis for quick language switching without navigating to Settings
- **File Sharing** — all `ResultCard` instances wire `onShare` via `FileService.shareResult`, which writes to temp directory and invokes `share_plus`

#### Design decisions and known patterns

**TextEditingController listener pattern:** Screens that check `_passphraseController.text.isNotEmpty` to enable/disable buttons must add `_passphraseController.addListener(() => setState(() {}))` in `initState`. `PassphraseField` is a self-contained `StatefulWidget` whose internal `setState` only rebuilds itself (text field + strength bar), not the parent screen. Without the listener, buttons stay disabled after typing.

**`Future.microtask` for camera state updates:** The camera `startImageStream` callback can fire while the widget tree is building. Setting `state = state.copyWith(...)` synchronously inside the callback triggers Riverpod's "modify provider during build" exception. The fix: wrap state updates in `Future.microtask(() { ... })` to defer them past the current build cycle.

**Material 3 theming:** Forest green (#2E7D32) seed color generates the full Material 3 color scheme. Both light and dark themes are provided; the app follows system preference via `ThemeMode.system`.

**AR overlay coordinate mapping:** `BarcodeOverlayPainter` maps barcode bounding box from camera image coordinates to screen coordinates in three steps: (1) rotate by `sensorOrientation` (90° for typical back camera swaps x↔y), (2) scale by `BoxFit.cover` factor (`max(screenW/rotatedW, screenH/rotatedH)`), (3) offset by centering delta. The painter uses `shouldRepaint` with rect equality check to avoid unnecessary redraws at ~4fps.

**`LanguageSwitcherButton` as `ConsumerWidget`:** Needs Riverpod access to read/write `localeProvider`, so it can't be a plain `StatelessWidget`. Uses `showModalBottomSheet` with `RadioListTile` options matching the existing `LanguageSelector` pattern. Placed in AppBar `actions` on all 5 tabbed screens; `LiveScanScreen` (full-screen camera modal, no AppBar) does not include it.

**Camera-specific decode flags (`enableWhiteBalance`, `useRelativeColor`, `symbolThreshold`, `quadrantOffset`, `useHashDetection`):** `decodeFramePixels()` accepts optional flags that gate white balance correction, relative color matching, symbol detection sensitivity, corner sample positioning, and hash-based symbol detection. `enableWhiteBalance`, `useRelativeColor`, and `useHashDetection` default to `false`; `symbolThreshold` and `quadrantOffset` default to `null` (using the GIF formula and 0.28 respectively). Camera paths set all five via `DecodeTuningConfig` (defaults: `enableWhiteBalance=true`, `useRelativeColor=true`, `symbolThreshold=0.85`, `quadrantOffset=0.28`, `useHashDetection=true`). GIF decode doesn't need these corrections because pixel colors are exact from the encoder. The flags avoid any regression in the GIF path while improving camera robustness.

**Two-pass decode (camera path):** When `useHashDetection=true`, `decodeFramePixels` uses a two-pass architecture inspired by libcimbar's C++ implementation. Pass 1 iterates all cells in row-major order, running hash-based symbol detection with fuzzy drift matching. Per-cell drift offsets (accumulated ±7px max) and symbol indices are stored in pre-allocated typed arrays (`Uint8List`, `Int8List`). Pass 2 re-iterates cells, sampling color at drift-corrected center positions `(ox + driftX + cs/2, oy + driftY + cs/2)`. This fixes the root cause of camera decode failure: the original single-pass code sampled color at raw grid positions before drift was known, causing systematic color misclassification when perspective distortion shifted cells by 3–7 pixels. The GIF path remains single-pass (no drift, exact pixel colors).

**White balance finder sampling:** The Von Kries white reference is sampled from the outer corner cells of the 3×3 finder patterns (grid positions 0,0 and cols-1,rows-1), NOT the center cell (1,1) which is dark gray. The center cell has a dark fill with only a tiny white dot — sampling it would produce an incorrect white reference and amplify color errors.

**Symbol threshold for camera vs GIF:** The original `_detectSymbol` threshold `c * 0.5 + 20` works perfectly for GIF decode (exact pixel colors) but fails under camera auto-exposure. When center luma is ~200, the threshold (~120) is below blurred black dot corners (~130–160), so all corners read as 1 → `symIdx=15` → all bytes become 0xFF. The camera path now defaults to hash-based detection (`useHashDetection=true`), which bypasses threshold entirely by matching full 64-bit cell hashes via Hamming distance. When hash detection is disabled, the fallback camera threshold uses `symbolThreshold` (default 0.85): a multiplicative-only formula `c * symbolThreshold` that scales with brightness. The GIF path keeps the original formula (null `symbolThreshold`, no hash detection).

**CameraController disposed guard:** `LiveScanScreen` sets `_disposed = true` in `dispose()` and checks it in `_initCamera()`, `_onCameraImage()`, `didChangeAppLifecycleState(resumed)`, and the `CameraPreview` render condition. This prevents "CameraController used after dispose" crashes during navigation/lifecycle transitions where disposal can race with the camera stream callback or AppLifecycleState events.

**Decode tuning config wiring:** `DecodeTuningConfig` is an immutable value object persisted in SharedPreferences via `DecodeTuningProvider`. The Settings screen writes to the provider; camera screens (`LiveScanScreen`, `CameraScreen`) read it via `ref.watch(decodeTuningProvider)` and pass it through controllers to decoders. The decoder itself is stateless — it accepts tuning params as optional function arguments, keeping it testable without Riverpod. GIF decode ignores tuning entirely (uses default/null params).

## Camera Decode Improvements (from libcimbar C++ analysis)

Reference: [sz3/libcimbar](https://github.com/sz3/libcimbar/tree/master/src/lib)

Techniques from the C++ libcimbar scanner, identified for porting. Priorities 1–5 are implemented; the rest are planned for future work.

### ~~Priority 1 — White-balance from finder patterns~~ ✓ IMPLEMENTED

Implemented in `cimbar_decoder.dart` as `enableWhiteBalance` flag (enabled for camera decode paths, disabled for GIF decode). Samples 4×4 pixel regions at the outer corner cells of the TL and BR finder patterns (which are known to be solid white), takes per-channel maximum across both samples, then computes a full Von Kries 3×3 chromatic adaptation matrix (`M⁻¹ · diag(dst_cone/src_cone) · M`) to map observed white to true (255,255,255). Applied per-pixel before color matching. Falls back gracefully (skip correction) if observed white is too dark (luma < 30).

### ~~Priority 2 — Perspective transform~~ ✓ IMPLEMENTED

Implemented in `perspective_transform.dart` as a pure-Dart homography warp, integrated into both camera decode paths (`live_scanner.dart` and `camera_decode_pipeline.dart`). The transform is always additive — when finder centers are available, perspective warp is tried first; if RS decode fails, it falls back to the existing crop+resize path.

**Corner derivation from 2 finder centers:** The barcode is square. Given TL finder center at grid cell (1,1) and BR at (cols-2, rows-2), the diagonal vector `D = BR - TL` spans `(cols-3)*cs` pixels in each axis. The barcode's x/y unit vectors are: `ux = ((dx+dy)/(2n), (dy-dx)/(2n))`, `uy = (-(dy-dx)/(2n), (dx+dy)/(2n))`. The origin is `TL - 1.5*cs*(ux + uy)`, and the 4 corners are derived by stepping `frameSize` along each axis.

**Homography computation:** DLT (Direct Linear Transform) with 4 point pairs yields an 8×8 linear system (h₈=1 normalization), solved via Gaussian elimination with partial pivoting. The 3×3 matrix maps destination pixels to source coordinates (inverse mapping).

**Warp loop:** For each destination pixel `(x', y')`: multiply by the homography to get source coordinates, then bilinear interpolation from 4 neighboring source pixels (clamped at bounds). 256×256 output = 65K pixels, each requiring one 3×3 matrix-vector multiply and 4 pixel reads — well within the 4fps budget.

**Fallback chain:** (1) No finder centers → crop+resize unchanged. (2) Degenerate geometry → crop+resize. (3) Warp-based RS decode fails → crop+resize for same frame size. (4) All sizes fail → center-crop strategy. GIF decode path is unaffected.

### ~~Priority 3 — Anchor-based finder pattern detection~~ ✓ IMPLEMENTED

Implemented in `frame_locator.dart` as the primary detection path, with the old luma-threshold approach kept as fallback. The algorithm:

1. **Downscale 2×** and build a luma buffer for fast scanning
2. **Horizontal row scan** every 2 rows — tracks runs of bright (luma > 180) and not-bright pixels, looking for bright→dark→bright patterns. The high threshold (180) is critical: it distinguishes white finder cells (luma 255) from colored barcode cells (luma 64–171). Relaxed ratio check requires only the shorter bright run to be within 4× of the dark run (handles asymmetric patterns near image edges).
3. **Vertical confirmation** at each horizontal hit — scans the column at `centerX` for a matching vertical bright→dark→bright pattern within 2× of the horizontal width
4. **Deduplication** — merges candidates within `imageSize/30` radius (multiple scan lines hit the same finder)
5. **Selection & classification** — scores by hit count + aspect ratio + contrast, selects top 2, classifies as TL/BR by coordinate sum
6. **Crop computation** — estimates cell size from finder width (`finderPx / 3`), computes barcode bounding square with 1.5-cell padding (finder centers are at grid cell (1,1) and (cols-2, rows-2)) plus 2% margin
7. **Fallback** — if fewer than 2 finders found, reverts to original luma > 30 bounding-box approach

`LocateResult` now includes optional `tlFinderCenter` and `brFinderCenter` (`Point<double>?`) in original image coordinates, present when anchor detection succeeds (null on fallback). These are used by the perspective transform (Priority 2).

**Key tuning insight:** The finder's dark center is only ~4px wide after 2× downscale, and the 3px inner white dot splits the center row into complex sub-runs. Scanning every 2 rows ensures hitting the clean rows above/below the inner dot. The dense scan is affordable: O(w×h/4) pixel lookups on the downscaled image.

### ~~Priority 4 — Average hash symbol detection with drift tracking~~ ✓ IMPLEMENTED

Implemented in `symbol_hash_detector.dart` as a standalone class used by `cimbar_decoder.dart` when `useHashDetection` is true (camera paths). The detector pre-computes 64-bit average hashes for all 16 symbols using the same corner-dot geometry as `drawSymbol` (rendered on gray foreground, each bit = pixel luma > cell mean). For each camera cell, `detectSymbolFuzzy()` tries 9 overlapping positions (center + 8 neighbors at ±1px), computing a hash at each and matching via Hamming distance (`popcount(a ^ b)`) against all 16 reference hashes. The winning drift offset accumulates across cells in row-scan order (capped at ±7px), mimicking libcimbar's cell drift propagation. Gated by `DecodeTuningConfig.useHashDetection` (default true for camera, ignored for GIF decode). The GIF path continues using the existing 5-pixel quadrant luma threshold, which is exact for clean pixel data.

**Note:** This implementation uses simplified row-scan drift propagation rather than libcimbar's flood-fill from anchor corners via priority queue. The flood-fill approach (Priority 4b, not yet implemented) would decode high-confidence cells first and propagate drift outward, further improving robustness on severely distorted images.

### ~~Priority 5 — Relative color matching~~ ✓ IMPLEMENTED

Implemented in `cimbar_decoder.dart` as `useRelativeColor` flag (enabled for camera decode paths, disabled for GIF decode). Normalizes brightness by stretching the channel range to 0–255 (with `minVal` capped at 48 to prevent extreme scaling, and high-channel clamping to 255), then compares `(R-G, G-B, B-R)` differences against pre-normalized palette values. The palette relative colors are pre-computed through the same normalization pipeline to ensure consistent comparison. Combined with white balance for best results on camera-captured images.

### Priority 6 — Lens distortion correction (medium effort, medium impact)

libcimbar measures how edge midpoints deviate from the ideal straight line between anchors. The deviation maps to radial distortion coefficient `k1`, which is corrected via OpenCV `initUndistortRectifyMap()`. Phone cameras often have noticeable barrel distortion that shifts cell positions near the image edges.

### Priority 7 — Pre-processing: adaptive threshold + sharpening (low effort, medium impact)

libcimbar converts to grayscale → optional 3×3 high-pass sharpen (`[-0,-1,-0; -1,4.5,-1; -0,-1,-0]`) → adaptive threshold (block size 5-7) → compact bitmatrix (1 bit/pixel). This produces clean binary data for hash computation and eliminates lighting gradients.

**Note on sharpening:** Only applied when the barcode appears smaller than target resolution in the camera image (upscaling blur compensation).

### Techniques not planned for porting

- **Fountain codes** (wirehair) — libcimbar uses rateless fountain codes for multi-frame assembly (any N+1 of N frames suffice). Our adjacency-chain approach requires seeing a full animation cycle but is much simpler to implement. Fountain codes would require a significant new dependency.
- **RS block interleaving** — libcimbar interleaves ECC blocks across image positions so localized damage (e.g., finger covering part of barcode) doesn't wipe out a single block. Would require encoder changes (breaking web-app compatibility).

## Interoperability

The encrypted binary wire format is compatible across all three implementations: the web app, the Flutter Android app, and the open-source C++ `cimbar` scanner. A GIF encoded with the web app can be decoded by the Android app (via file import or live camera scanning) or scanned with a physical camera and decrypted via the "Import Binary" tab in either app.

The web app is available at https://nfcarchiver.com/cimbar/

## Key Constants (web-app/cimbar.js and android/lib/core/constants/cimbar_constants.dart)

- `CELL_SIZE = 8` (pixels per cell)
- `ECC_BYTES = 32` (RS parity bytes per 255-byte block)
- 8-color palette embedded in `web-app/cimbar.js`, `web-app/gif-encoder.js`, and `android/lib/core/constants/cimbar_constants.dart` — must stay in sync across all three

## Test Suite

### Web App Tests

All tests live in `web-app/tests/`. Run from the `web-app/` directory (no install needed beyond Node.js):

```bash
cd web-app
sh tests/run_all.sh          # run all tests (symbols + RS + pipeline)
node tests/test_symbols.js   # single test
node tests/test_rs.js
node tests/test_pipeline_node.js
python tests/test_pipeline.py                        # Python orchestrator
python tests/test_pipeline.py output.gif 256         # also runs GIF structure check
python tests/test_gif.py path/to/output.gif [size]   # standalone GIF check (needs Pillow)
```

### Test files

| File | What it tests |
|------|--------------|
| `tests/test_symbols.js` | `drawSymbol` / `detectSymbol` round-trip for all 128 `(colorIdx 0–7, symIdx 0–15)` combinations via `MockCanvas`. Each cell must encode and decode back to the exact same 7-bit value. |
| `tests/test_rs.js` | Reed-Solomon encode/decode: clean round-trip, correction of ≤16 injected errors, detection of >16 errors (uncorrectable), and Forney/Omega correctness with errors at known positions. |
| `tests/test_pipeline_node.js` | Full GIF encode → GIF decode pipeline in Node.js using `MockCanvas` + `GifEncoder` + `GifDecoder` + `encodeRSFrame`/`decodeRSFrame`. Tests the 4-byte length prefix that prevents AES-GCM auth-tag corruption from RS zero-padding. Three cases: non-dpf-aligned payload, exactly dpf-aligned payload, and single-frame tiny payload. |
| `tests/test_gif.py` | Structural check on a real GIF file: `GIF89a` magic, correct dimensions, global color table, frame count, and palette slots 0–7 matching the 8 CimBar base colors. Requires `pip install pillow`. |
| `tests/test_pipeline.py` | Python subprocess orchestrator: runs `test_symbols.js`, `test_rs.js`, and optionally `test_gif.py`, prints a PASS/FAIL summary. |
| `tests/mock_canvas.js` | Node.js mock of the browser Canvas 2D API (`fillStyle`, `fillRect`, `getImageData`). `getImageData` returns a copy of the pixel buffer (matching browser behavior — avoids shared-buffer bugs in multi-frame tests). |

### Android App Tests

Tests live in `android/test/`. Run from the `android/` directory (requires Flutter SDK):

```bash
cd android
flutter test
```

| File | What it tests |
|------|--------------|
| `test/core/services/galois_field_test.dart` | GF(256) table wraparound, mul/div inverse, polynomial arithmetic identities. |
| `test/core/services/reed_solomon_test.dart` | Port of `test_rs.js`: clean round-trip, 16-error correction, uncorrectable detection, Forney/Omega correctness. Also full-block (223-byte) round-trips. |
| `test/core/services/cimbar_decoder_test.dart` | Port of `test_symbols.js`: all 128 (colorIdx, symIdx) draw+detect round-trips using the `image` package instead of MockCanvas. Also tests Von Kries white balance correction (warm/cool tinted frames), relative color matching (brightness-shifted and clean frames), camera-exposure symbol detection with `symbolThreshold=0.85` (over-exposed frames), average hash symbol detection: reference hash distinctness (min pairwise Hamming distance ≥4), 128-combo round-trip with hash detection, ±1px drift tolerance via fuzzy matching, full frame round-trip, blur robustness, and two-pass decode: drift-corrected color on shifted cells, noisy frame handling, clean frame perfect round-trip, DecodeStats drift tracking. |
| `test/core/services/crypto_service_test.dart` | AES-256-GCM encrypt/decrypt round-trip, wrong passphrase rejection, bad magic detection, passphrase strength scoring. |
| `test/core/services/decode_pipeline_test.dart` | Port of `test_pipeline_node.js`: RS frame encode→draw→read→decode round-trip with length prefix. Three cases: non-dpf-aligned, dpf-aligned, and single-frame tiny payload. |
| `test/core/services/frame_locator_test.dart` | Barcode region detection from camera photos: centered barcode, offset barcode, barcode filling entire image, dark image (no barcode), noisy background with scattered bright pixels (verifies anchor detection ignores noise), finder center position validation (detected centers within 20px of known positions), and fallback behavior (uniform bright rectangle without finder structure triggers luma-threshold fallback with null finder centers). 7 tests total. |
| `test/core/services/yuv_converter_test.dart` | YUV420→RGB conversion: pure white/black, UV subsampling correctness, stride configurations (padded Y rows), semi-planar UV (uvPixelStride=2). |
| `test/core/services/perspective_transform_test.dart` | Corner derivation (axis-aligned and 30° rotated barcodes produce correct square corners, degenerate inputs return null), identity warp preserves content, warp corrects rotated barcode (>70% cell colors match palette), full RS decode round-trip through perspective warp (256px barcode rotated 10° at 2× in 900px photo), fallback path with no finder centers. 7 tests. |
| `test/core/services/live_scanner_test.dart` | Multi-frame scanning logic via `processDecodedData`: single-frame complete scan, 5-frame progressive capture with assembly, duplicate handling, out-of-order adjacency-chain resolution ([2,3,4,0,1] → correct [0,1,2,3,4]), frame 0 detection, dark image graceful handling, reset. |

### Known subtleties

- `decodeFramePixels` returns `ceil(usableCells × 7 / 8)` bytes, but `rawBytesPerFrame` is `floor(...)`. `decodeRSFrame` explicitly uses `rawBytesPerFrame(frameSize)` as the byte limit so block boundaries match the encoder exactly.
- `MockCanvas.getImageData` must return a copy (`_pixels.slice()`), not a reference — the real DOM API always copies, and GifEncoder stores the returned object by reference.
- The 4-byte big-endian length prefix in frame data (written by the encoder, read by the decoder) is the only mechanism that strips RS zero-padding before AES-GCM decryption.
- `live_scanner_test.dart` tests scanning logic via `processDecodedData(dataBytes, frameSize)` rather than `processFrame(image)`, because FrameLocator's crop+resize of synthetically generated barcode images introduces enough subpixel interpolation error to corrupt RS decoding. The camera decode pipeline (FrameLocator → CimbarDecoder → RS) is already tested independently in `decode_pipeline_test.dart` and `frame_locator_test.dart`.
- `CameraImage` plane bytes in `startImageStream` callbacks are ephemeral — they're only valid during the callback. `live_scan_screen.dart` copies them with `Uint8List.fromList(plane.bytes)` before passing to the controller.
- The live scan controller throttles frame processing to ~4fps (250ms interval) to avoid CPU overload from the 30fps camera stream. Throttling uses a timestamp check, not a Timer, to avoid frame queue buildup.
