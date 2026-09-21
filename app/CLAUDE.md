# Android App — CLAUDE.md

Flutter project in `app/` (the Flutter root; native Android config is at `app/android/`, native iOS at `app/ios/`).

## Build

```bash
cd app                        # the Flutter root, from the repo root
flutter pub get
flutter gen-l10n
flutter build apk --debug
sh tests/run_all.sh           # app/tests/run_all.sh: clean summary via JSON reporter
sh tests/run_all.sh --verbose  # list each test name
flutter analyze               # CI runs this bare -> info-level lints are FATAL
```

Note: `tests/run_all.sh` does not run the analyzer, and CI's *Analyze & Test* job (`.github/workflows/ci.yml`) runs bare `flutter analyze`, which fails the build on `info` lints too (e.g. `curly_braces_in_flow_control_structures`). Run `flutter analyze` alongside the suite before pushing, and expect literally "No issues found!" — fix the lint rather than excluding it or passing `--no-fatal-infos`.

Note: Do not use bare `flutter test` — its `\r`-based progress animation produces a single huge line that triggers output truncation in CLI tools. The wrapper parses the JSON reporter into clean output.

Requires Flutter 3.44+ and Java 17.

**Toolchain pins:** Gradle 9.1.0 (`app/android/gradle/wrapper/gradle-wrapper.properties`), AGP 9.0.1 and Kotlin 2.3.20 (`app/android/settings.gradle`), Java 17, `compileSdk`/`targetSdk` taken from the Flutter SDK — the same versions Flutter 3.44's `flutter create` template uses. CI and the release workflow pin Flutter 3.44.8 exactly (the F-Droid recipe checks out `FLUTTER_VERSION` from `release.yml`), and `pubspec.lock` is committed — resolve it with that Flutter (see the root `CLAUDE.md`'s Store Metadata section). `gradle.properties` keeps `android.newDsl=false` and `android.builtInKotlin=false` (as the Flutter template does) so the Groovy build files and the external Kotlin plugin keep working under AGP 9. Flutter's supported Gradle range is 8.7–9.x; an older Flutter (3.24) will not build against AGP 9.

**Per-ABI version codes:** `app/android/app/build.gradle` ends with an `android.applicationVariants.configureEach` block that sets `versionCodeOverride = 10 * versionCode + abi` (armeabi-v7a 1, arm64-v8a 2, x86_64 3) on every output carrying an ABI filter. It exists to *undo* Flutter's own override — `FlutterPlugin.kt` sets `abi * 1000 + versionCode` for `--split-per-abi` builds, which puts the ABI digit in the high position, so arm64 of one release (2189) outranks armeabi-v7a of every later one (1190, 1191, …) and arm64 users would never be offered an update. F-Droid requires the ABI digit lowest and builds one APK per ABI from this. A build without `--split-per-abi` has no ABI filter, so the universal APK and the AAB are untouched and keep the plain pubspec code.

## Project Structure

```
app/lib/
├── app.dart                    — Root MaterialApp.router + go_router config
├── main.dart                   — Entry point; initializes SharedPreferences, ProviderScope
├── core/
│   ├── format/                 — v2.1 format layer (see "v2.1 Format and Decode Layer" below)
│   ├── decode/                 — v2.1 decode layer (see "v2.1 Format and Decode Layer" below)
│   ├── models/decode_result.dart — DecodeProgress, DecodeState, DecodeResult
│   ├── providers/              — SharedPreferencesProvider, LocaleProvider, DebugModeNotifier (`debugModeProvider`)
│   ├── services/               — All decode/crypto/camera/file logic (see below)
│   └── utils/byte_utils.dart   — readUint32BE, writeUint32BE, concatBytes, bytesToHex
├── features/
│   ├── import/                 — GIF import: ImportScreen + ImportController
│   ├── camera/                 — Camera: CameraScreen, CameraController, LiveScanScreen, LiveScanController, PhotoCaptureScreen
│   ├── files/                  — File explorer: FilesScreen + FilesController
│   └── settings/               — SettingsScreen — the "About" tab (Developer debug switch, language, about/links)
├── shared/
│   ├── theme/app_theme.dart    — Material 3, forest green seed, light + dark
│   └── widgets/                — AppShell, PassphraseField, FilePickerZone, ProgressCard, ResultCard, LanguageSelector, LanguageSwitcherButton, CornersOverlayPainter
└── l10n/
    ├── app_en.arb … app_ka.arb — 5 language ARB files (en, ru, uk, tr, ka)
    └── generated/                — Committed `flutter gen-l10n` output: app_localizations.dart + one file per locale
```

## Decoding Pipelines

All three paths are on v2.1 and share `FrameDecoder` (`core/decode/`), `RatelessAssembler` (`core/decode/rateless_assembler.dart`) and `decodeFramedPayload` (`core/services/payload_decoder.dart`) for the strip-length-prefix / detect-encryption / decrypt / inflate-if-compressed / parse-container tail:

```
GIF import:  GIF → parse frames (image pkg) → FrameDecoder.decodeExact → RatelessAssembler → decodeFramedPayload(..., compressed: assembler.compressed) → File

Photo:       PhotoCaptureScreen.takePicture() (ResolutionPreset.max) or gallery pick → decodePhotoBytes (Isolate.run) →
             FrameDecoder.decode (single frame only — a frame whose header total > 1 or repair bit set errors naming
             the total, "use Live Scan") → RatelessAssembler → decodeFramedPayload(..., compressed: asm.compressed) → File

Live scan:   CameraController stream (ResolutionPreset.veryHigh, YUV420) → LiveScanController.wantsFrame gates the
             callback so a frame is dropped before any copy while the isolate is busy → YuvFrame →
             DecodeIsolate.decode (one long-lived worker owning one FrameDecoder) → FrameDecoder.decodeYuv420
             (Y-plane locate, trying a RoiHint from the previous frame's located region first at 25% expansion, then
             falling back to a full-frame locate; RGB conversion only for the finder bounding box ± 4.5 modules via
             RgbBuffer.fromYuv420, which carries originX/originY so downstream coordinates stay absolute) →
             RatelessAssembler on the main isolate (source and repair frames both feed rank; a frame that adds no new
             information is `dependent` and rank holds) + CapturePolicy.update (lock/unlock, hints) → finish() →
             decodeFramedPayload(..., compressed: _assembler.compressed) → File
```

## v2.1 Format and Decode Layer (`lib/core/format/`, `lib/core/decode/`)

Pure-Dart, no Flutter/UI dependencies — matches the web-app JS `format.js`/`rateless.js`/`cimbar.js` split. Files:

- `format/cimbar_spec.dart` — `CimbarSpec`: grid/finder/palette/tile/RS/header/capacity constants, mirroring `spec/cimbar-v2.json`. `usableCellPositions` (3840 cells, row-major, skipping the four finder corners). v2.1 additions: `flagEncrypted`/`flagRepair`/`flagCompressed`/`flagReserved` header-flag masks, `codingIncrement`/`codingMixMul1`/`codingMixMul2` (the coefficient generator's constants), `codingMaxFrames` (4096), `gifRepairRatio` (0.25) and `gifRepairCount(n)`
- `format/tiles.dart` — `Tiles`: the 16 symbol tiles as 64-entry 0/1 arrays plus `bits`/`hamming` helpers
- `format/bit_packing.dart` — `BitPacking`: 6-bit cell values (`cellValue`/`cellSymbol`/`cellColor`) <-> the frame's raw MSB-first byte stream (`packCells`/`unpackCells`)
- `format/frame_header.dart` — `FrameHeader`: the 8-byte `[ver][flags][fileId][seq][total]` header, now with `repair`/`compressed` flags alongside `encrypted`; `FrameHeader.decode` returns `HeaderDecode{header, reason, valid}` and rejects reserved flag bits (reason `flags`). `seq >= total` is only checked for source frames — a repair frame's `seq` is its repair id `r`, not bounded by `total`
- `format/rs_framing.dart` — `RsFraming.encodeFrame`/`decodeFrame`: RS(255,191) block partition + byte-stride interleave for one frame, returning `RsFrameResult{data, blocksOk, blocksFailed}`
- `format/file_container.dart` — `FileContainer`: the v1-compatible file container (`parsePayload`, `stripLengthPrefix`, `isEncrypted`)
- `format/rateless.dart` — `Rateless`: the v2.1 coding layer (spec §5), a bit-exact Dart port of `web-app/format.js`'s `codingCoefficients` and `web-app/rateless.js`'s `combineBodies`. `Rateless.coefficients(fileId, r, n)` derives a repair row's GF(256) coefficients from the header alone via a splitmix32-style state advance plus a murmur3 fmix32 output mix (not a generator linear over GF(2) — a linear one caps independent rows at 32 bits' worth); `Rateless.combine(bodies, coef)` computes Σ coef[j]·bodies[j] over GF(256)
- `decode/yuv_frame.dart` — `YuvFrame`: a camera frame in Android YUV_420_888 layout (Y/U/V planes, `yRowStride`, `uvRowStride`, `uvPixelStride`: 1 = planar, 2 = semi-planar) — the input type `FrameDecoder.decodeYuv420` takes
- `decode/rgb_buffer.dart` — `RgbBuffer`: flat 8-bit RGB buffer with bilinear sampling (`RgbBuffer.fromImage`, `RgbBuffer.fromYuv420`)
- `decode/grid_model.dart` — `GridModel.toSource(cx, cy) -> (double, double)`; `ExactGridModel` for GIF-exact pixel positions
- `decode/luma_plane.dart` — `LumaPlane`: `fromRgb` (BT.601 integer weights 77/150/29), `at`, `downscale2` (area-average 2x2, odd trailing row/column dropped), `bilinear`, `mean3x3` — the locator's and drift solver's luma source
- `decode/homography.dart` — `Homography`: 3x3 projective `map(x, y)`, `solve` (DLT from four point correspondences, null if singular); `HomographyGridModel.fromFinders(tl:, tr:, bl:, br:)` fits a `GridModel` to four located finder centers
- `decode/finder_locator.dart` — `FinderLocator.locate(LumaPlane) -> LocateResult{tl,tr,bl,br,candidates,clusters,devNorm,tlLuma,secondLuma,failReason,ok,module}` (spec §6.2): downscale 2x, binarize with a local mean, strict 1:1:3:1:1 row scan plus a dotted 7-run pattern (25% tolerance) anchored at the hit row for the tr/bl/br core dot, cluster and refine centers by alternating row/column extent (3 iterations), select four candidates by parallelogram closure (`maxDevNorm` 0.35) with a side/module ratio gate (36–75), classify TL by core brightness (`tlMargin` 40) and orient TR/BL by cross product, correct the module estimate by cos(rotation). Module floor 3 downscaled px (below which photo texture aliases into false candidates)
- `decode/white_point.dart` — `WhitePoint.fromFinders(image, grid) -> List<double>?` (spec §6.3): per-channel 90th percentile over the eight core cells around each of the four finder cores (five samples per cell through the grid model, center dot cell excluded), null when any channel is below 30 (too dark)
- `decode/drift_solver.dart` — `DriftSolver(sampler, classifier).solve() -> DriftField{dx,dy,widened,meanAbs,maxAbs}` (spec §6.5): BFS flood-fill of per-cell drift starting from the cells adjacent to the four finder corners, each cell searching the ±1 px 3x3 offsets (luma-only sampling, symbol-only Hamming) widened to the ±2 px ring when the best Hamming exceeds `wideThreshold` (20), seed cells (no decided neighbours) always search the ±2 ring, clamped to ±6 px
- `decode/cell_sampler.dart` — `CellSampler.sample`: reads a cell's 8×8 tile into a `CellPatch{luma, rgb}` through a `GridModel`
- `decode/cell_classifier.dart` — `CellClassifier.classify -> CellClassification{symbol, hamming, color, colorMargin}`: symbol via average-hash Hamming distance to the 16 tiles, color via nearest palette entry
- `decode/diagnostics.dart` — `DecodeStatus` enum (`ok, notLocated, unsupportedGrid, rsFailed, badHeader`) and `Diagnostics`/`FrameResult{status, cells, raw, data, header, diag}`
- `decode/frame_decoder.dart` — `FrameDecoder`: `decode(image, {grid, useDrift = true})` runs the camera path (LumaPlane → FinderLocator → HomographyGridModel → grid-size check (64 ± 10) → WhitePoint → DriftSolver → cells → RS → header); `decodeExact(image)` is the GIF path; `decodeWithGrid(image, grid, {whitePoint, useDrift, luma, diag})` is the shared core
- `decode/rateless_assembler.dart` — `RatelessAssembler.add(data, {blocksFailed}) -> AddResult{accepted, reason, header}` (spec §7): recovers the N source bodies from any N linearly independent source/repair rows by incremental Gaussian elimination over GF(256), matching web-app's `RatelessAssembler` (`rateless.js`) reason-for-reason (`rs`, header reasons, `total`, `flags`, `uncoded`, `duplicate`, `dependent`). `rank`/`total`/`compressed` track progress; `sourceCount`/`repairCount` count accepted rows only (duplicate/dependent/uncoded rows are not counted); an in-order source-only file never materializes a dense coefficient array (`denseRows == 0`) — only a repair row, or a source row landing on a column a repair pivot already holds, is stored densely. A `total` above `CimbarSpec.codingMaxFrames` (4096) rejects repair frames outright (`uncoded`), so a crafted large `total` can't force dense elimination. `framedData()` back-substitutes once `rank == total` and returns the concatenated bodies
- `decode/golden_sidecar.dart` — `GoldenSidecar.load`/`GoldenSidecar.gifPathFor`: loader for `test-data/goldens/<name>.json` ground truth (v2.1 adds `compressed`/`sourceFrames`/`repairFrames`/`frameCount` at the top level and `repair`/`r`/`coef12` per frame; all default false/absent so the five pre-v2.1 sidecars still load unmodified), shared by Dart and JS test suites
- `decode/decode_report.dart` — `DecodeReport.compare` (`Uint8List` cells vs. truth -> `TruthComparison{symbolAccuracy, colorAccuracy, cellAccuracy, wrongCellIndices}`), `DecodeReport.lines` (structured `frame=N stage=… key=value` diagnostic lines), `DecodeReport.heatmap` (PNG marking wrong cells)

No Flutter imports under these directories; `tool/decode_image.dart` runs with `dart run`.

### Plan 4 decoder changes

- `CellSampler` interpolates each cell's 64 sample positions from the 4 tile corners (bilinear over the corner-to-corner grid), so one cell costs 4 homography evaluations (the corners) rather than 64.
- `FinderLocator`'s column scan is bounded to ±7 modules around each row hit (the row scan itself still runs every row — an attempted stride of 2 lost hits on small, rotated finders and was reverted).
- `DriftSolver`'s hill-climb is capped at 3 steps (measured drift on the degradation matrix stays ≤ 2.1 px, so 3 steps of the ±1/±2 px search always converge).

## CLI decoder

Offline decoder, no Flutter/emulator needed:

```bash
cd android
dart run tool/decode_image.dart <image.png|jpg|gif> [--frame N] [--golden name.json] [--heatmap out.png] [--mode exact|camera] [--no-drift]
```

Example (GIF, exact path):

```bash
dart run tool/decode_image.dart ../test-data/goldens/hello.gif --golden ../test-data/goldens/hello.json --heatmap /tmp/hm.png
```

```
frame=0 stage=input path=../test-data/goldens/hello.gif width=608 height=608 frames=1 mode=exact
frame=0 stage=cells hammingMax=0 hammingMean=0.00 hammingHist=3840/0/0/0 colorMarginMin=1.414 sampleMs=34
frame=0 stage=rs blocks=12 ok=12 failed=0 rsMs=3
frame=0 stage=header valid=true version=2 fileId=0x1001 seq=0 total=1 encrypted=false
frame=0 stage=result status=ok
frame=0 stage=truth symbolAcc=1.000 colorAcc=1.000 cellAcc=1.000 wrongCells=0
frame=0 stage=heatmap path=/tmp/hm.png
```

Example (rendered camera-like PNG via `renderScene`, camera path, `--mode` defaults to `camera` for non-GIF input):

```
frame=2 stage=locate ok=true candidates=129 clusters=8 module=16.64 corners=616.0,258.0;1409.0,547.0;227.0,1097.0;1166.0,1440.0 tlLuma=252 secondLuma=1 devNorm=0.169 locateMs=243
frame=2 stage=grid estimate=60
frame=2 stage=wb rgb=255,255,255
frame=2 stage=drift meanAbs=0.72 maxAbs=2.07 widened=0 driftMs=381
frame=2 stage=cells hammingMax=14 hammingMean=4.08 hammingHist=3386/454/0/0 colorMarginMin=1.117 sampleMs=459
frame=2 stage=rs blocks=12 ok=12 failed=0 rsMs=13
frame=2 stage=header valid=true version=2 fileId=0x1002 seq=2 total=6 encrypted=false
frame=2 stage=result status=ok
frame=2 stage=truth symbolAcc=0.995 colorAcc=1.000 cellAcc=0.995 wrongCells=19
```

(`stage=grid estimate=60` above; 60–64 typical; gate 64 ± 10)

`--no-drift` skips the `stage=drift` line and the `DriftSolver` pass (`decode(image, useDrift: false)`); on the same scene it still decodes (`status=ok`) but with a higher `hammingMean` (10.32 vs. 4.08 above) since drift is what corrects the residual per-cell misalignment homography alone can't model. A photo with no barcode in it reports `stage=locate ok=false … fail=<reason>` and `stage=result status=notLocated` with exit code 1.

Exit 0 iff the frame decodes (`status=ok`); non-GIF images default to `--mode camera`, which now runs the full locate → homography → white point → drift → RS chain (Plan 3).

## Synthetic scenes

`test/test_utils/synthetic_scene.dart` composites a golden GIF frame into a camera-like scene with known ground-truth geometry, so the locator, homography, white point and drift solver can be tested against exact expected finder positions instead of only real captures. `loadGoldenFrame(name, frameIndex)` loads a frame from `test-data/goldens/`; `loadPhoto(path)` loads a background photo. `SceneSpec` fields: `scale`, `rotationDeg`, `keystone` (top edge shrunk / bottom edge widened by this fraction before rotation, simulating tilt), `centerX`/`centerY` (frame placement in the output canvas), `blurSigma` (destination-pixel Gaussian blur), `brightness`, `noiseSigma`, `barrelK` (scene-space barrel distortion the homography can't model), `seed`. `renderScene(frame, outW, outH, spec, {background})` returns a `Scene{image, finderCenters, frameToScene}` — `finderCenters` and the `Homography` are exact, derived from `sceneQuad(spec)`, not estimated. Degradation suites built on it: `camera_path_test.dart` (full `FrameDecoder.decode` through the degradation matrix — scale, rotation, keystone, blur, brightness, noise, photo composites, negative cases), `finder_locator_test.dart` (the locator alone across the same matrix plus photo backgrounds and v1-barcode/blank negatives), `drift_solver_test.dart` (drift correctness including barrel distortion, which only decodes with drift on, and a timing report).

`tool/gen_scene_fixtures.dart` (`cd app && dart run tool/gen_scene_fixtures.dart`; test-only, ships in neither APK) renders a subset of that same degradation matrix to `test-data/scenes/<name>.png` + `<name>.json`, so the JS port of the camera decode layer (`web-app/finder-locator.js`, `web-app/photo-decoder.js`, etc.) can be tested against the exact pixels this suite uses, not a re-implementation of scene rendering in JS. Each sidecar carries the analytic `finderCenters`/`homography` (geometric ground truth) plus what **this** `FinderLocator` and `FrameDecoder.decode` actually produced from the rendered PNG (`locate`/`decode` blocks) and the frame's true per-cell values (`cells`) — see `test-data/scenes/README.md` for the full shape. `test/tool/scene_fixtures_test.dart` asserts the committed fixtures still reproduce their recorded `locate`/`decode` blocks; `web-app/tests/test_finder_locator.js`/`test_photo_decode.js` assert the same recorded blocks from the JS side. Because both suites assert the exact same recorded numbers, a genuine improvement to either decoder — Dart or JS — makes it disagree with the frozen sidecar and fails both suites until the fixtures are regenerated; regeneration needs the Flutter toolchain, so it cannot be done from the web app alone.

## Corpus benchmark

Real-capture regression scaffold: see `test/fixtures/corpus/README.md` for the case format and capture checklist. `test/core/decode/corpus_benchmark_test.dart` decodes every case under `test/fixtures/corpus/`, asserts each case's `expect` block, and writes one table row per case to `build/corpus_report.txt` (`case | status | symbolAcc | colorAcc | rsOk/blocks | hammingMean | ms`), echoed by `tests/run_all.sh` after the test summary.

## Core Services (`lib/core/services/`)

- `galois_field.dart` — GF(256) arithmetic with lookup tables (port of rs.js:13-73)
- `reed_solomon.dart` — RS(255,191) encode/decode with Berlekamp-Massey + Chien + Forney (port of rs.js:76-235)
- `crypto_service.dart` — AES-256-GCM + PBKDF2 via PointyCastle, matching exact wire format (port of crypto.js)
- `gif_parser.dart` — wrapper around `image` package GifDecoder
- `decode_pipeline.dart` — GIF import orchestration: GIF → frames → `FrameDecoder.decodeExact` → `RatelessAssembler` → `decodeFramedPayload(..., compressed: assembler.compressed)`, exposed as a `Stream<DecodeProgress>` for UI updates. Per-frame progress message is `'ok'` / `'no new information'` (a `dependent` row) / `'rejected (<reason>)'`; the incomplete message reads `'Incomplete: rank <rank> of <total> (<rejected> rejected)'`. Mirrors web-app `index.html`'s `startDecode`
- `payload_decoder.dart` — `decodeFramedPayload(framed, passphrase, {bool compressed = false, int maxInflatedBytes = CimbarSpec.maxInflatedBytes}) -> ParsedFile`: the shared tail of every v2/v2.1 decode path once frame(s) are fully assembled — strip the u32 length prefix, detect encryption via the `CB 42` magic, decrypt if needed, inflate (a chunked `dart:io` `ZLibDecoder` conversion that counts bytes and stops at `maxInflatedBytes`, 128 MB by default) if `compressed` — which comes from the assembled frames' header flag, not sniffed from the bytes — then parse the file container. Throws `PassphraseRequiredException` when the payload is encrypted and no passphrase was given, and `FormatException` when inflation fails or the inflated size passes the cap (`maxInflatedBytes` exists so tests can lower it)
- `photo_decoder.dart` — `decodePhotoBytes(bytes, passphrase)` runs `Isolate.run(() => decodePhotoSync(...))`: decode one image (PNG/JPEG) via `FrameDecoder.decode`, reject a frame whose header `total > 1` or repair bit is set with an error naming the total ("use Live Scan"), assemble via `RatelessAssembler`, then `decodeFramedPayload(..., compressed: asm.compressed)`. Returns `PhotoDecodeResult{result, error, errorCode, diag, total}` — `errorCode` is a stable, l10n-mappable tag (`multi_frame`, `passphrase_required`, `not_located`, `decode_failed`) that `CameraState` carries (with `errorTotal`) and `CameraScreen._localized` renders through `AppLocalizations`, falling back to the English `error` only when the code is null
- `capture_policy.dart` — `CapturePolicy` (spec §8): locks focus + exposure (`LockAction.lock`) on the first `FrameOutcome` with all four finders located (`DecodeStatus.ok`, `rsFailed`, `badHeader` and `unsupportedGrid` all count as "located" — only `notLocated` doesn't), unlocks (`LockAction.unlock`) after `unlockAfterMs` (2000 ms) without one. Derives a `ScanHint` from the outcome: `module < minModulePx` (6 px) → `moveCloser`; `module > maxModulePx` (40 px) → `moveBack`; corner motion since the last located frame > `motionPx` (10 px) → `holdStill`; located but `rsFailed` → `adjustAngle`
- `decode_isolate.dart` — `DecodeIsolate`: one long-lived background isolate owning one `FrameDecoder`, spawned once per scan and reused for every frame; `busy` while a job is in flight (a second `decode()` call while busy throws `StateError`); `dispose()` kills the isolate and fails any in-flight job's `Future` with a `StateError` (the controller recognizes this by message and ignores it as normal teardown). The reply port is created *before* the spawn and doubles as the isolate's `onExit`/`onError` port, so a worker that dies wakes the wrapper instead of leaving the caller's `Future` pending forever: the in-flight job fails with `StateError('decode isolate exited')` and `isDead` turns true, after which every `decode()` throws `StateError('DecodeIsolate is dead')` synchronously and `LiveScanController` respawns. `FrameJob{frame, useDrift, hint, capture}` in, `FrameOutcome{status, data, blocksFailed, fileId, seq, total, encrypted, corners, module, roi, diag, totalMs, width, height, capturePng}` out — `capturePng` (a full RGB render via `RgbBuffer.fromYuv420` + the `image` package) is only produced when `capture: true` was set on that job, so normal frames pay no PNG-encode cost
- `file_service.dart` — centralized file operations for decoded files: `shareFile`/`shareResult` (`share_plus`), `openFile`/`openResult` (`open_filex`, `ACTION_VIEW` through its FileProvider → `OpenOutcome.opened/noApp/failed`), `exportFile`/`exportBytes` (`file_picker`'s `saveFile`, the system save-as picker, so the file lands where other apps can reach it — decoded files are otherwise auto-saved only to the app's private documents directory). **Every file handed to another app carries an explicit MIME type from `mimeTypeFor` (`mime` package, `application/octet-stream` fallback)** — without it Android reports octet-stream, the share sheet shrinks to the few apps accepting anything, and strict targets (Telegram) refuse the file. `AndroidManifest.xml` declares `SEND`/`SEND_MULTIPLE`/`VIEW` `<queries>` for Android 11+ package visibility and strips the `READ_MEDIA_*` permissions `open_filex` would merge in (`test/android_manifest_test.dart` guards both)

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
        GoRoute(path: '/camera',   ...CameraScreen),
        GoRoute(path: '/files',    ...FilesScreen),
        GoRoute(path: '/settings', ...SettingsScreen),
      ],
    ),
  ],
);
```

`NoTransitionPage` for instant tab switching. The two full-screen routes, `LiveScanScreen` and `PhotoCaptureScreen`, are pushed **on the root navigator** — `Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(...))` from `CameraScreen` — so they sit above the shell instead of inside its nested navigator. Pushed on the nested navigator they float over go_router's pages: tapping a bottom tab then moves the tab highlight and switches the route underneath while the scanner keeps covering it, leaving the tab bar apparently dead. `test/features/camera_navigation_test.dart` is the regression guard.

## Camera Implementation

- **Live scan** (`LiveScanScreen`) uses `CameraController` at `ResolutionPreset.veryHigh` with `ImageFormatGroup.yuv420` (native format); `startImageStream` delivers frames to `_onCameraImage`, which checks `LiveScanController.wantsFrame` (scanning, isolate spawned, not busy) *before* copying anything — while the decoder is busy the frame is dropped with zero allocation. When wanted, plane bytes are copied with `Uint8List.fromList(plane.bytes)` (ephemeral during the callback) into a `YuvFrame` and handed to `controller.onCameraFrame`
- **Photo** (`PhotoCaptureScreen`) uses a separate `CameraController` at `ResolutionPreset.max` (no image stream) and `takePicture()`
- **`WidgetsBindingObserver`** for camera lifecycle on both `LiveScanScreen` and `PhotoCaptureScreen`: on `inactive` the controller is nulled *and* disposed, on `resumed` it is re-initialized when null. The null-and-reinit order matters — an `isInitialized` guard placed before the branch made `resumed` return early once `inactive` had nulled the controller, so live scan never came back from backgrounding
- **Portrait lock** via `SystemChrome.setPreferredOrientations` while live scanning
- **`PopScope`** wrapper ensures Android back button exits camera mode and stops the image stream
- **Focus/exposure lock** — `LiveScanScreen._applyLock` calls `setFocusMode`/`setExposureMode` (`locked`/`auto`) in response to `LiveScanState.pendingLock`, which `CapturePolicy.update` sets; devices that reject a lock mode are ignored (scanning continues without it)

## Live Scanning Architecture

CimBar frames carry an 8-byte header (`ver`, `flags`, `fileId`, `seq`, `total`; `FrameHeader`) but no other identifier. `RatelessAssembler` (`lib/core/decode/rateless_assembler.dart`) does the GF(256) row bookkeeping — accept/dedup/eliminate/complete by `seq`/`total`/`fileId`/coefficients, matching the web-app's `RatelessAssembler` (`rateless.js`) — on the **main isolate**, once each frame comes back from the background decode.

Per-frame flow (`LiveScanController`):
1. `wantsFrame` — scanning, isolate spawned, not busy.
2. `onCameraFrame(frame)` — builds a `FrameJob` (carrying the previous frame's `RoiHint`, if any) and calls `_isolate.decode(job)`.
3. `_onOutcome(n, outcome, captureRequested)` — feeds the outcome to `CapturePolicy.update` (hint + lock/unlock action), stashes the outcome's `roi` as the next `RoiHint`, adds `ok` data to the `RatelessAssembler`, updates `LiveScanState` (`rank`/`total`/`hint`/`corners`/`pendingLock` — `rank` is progress: it climbs on both accepted source and accepted repair frames, and holds on a `dependent` frame that adds no new information), and — after 3 consecutive isolate errors — surfaces `errorMessage`.
4. When `RatelessAssembler.isComplete` (`rank == total`), the screen stops the image stream and calls `controller.finish(passphrase)`, which calls `decodeFramedPayload(..., compressed: _assembler.compressed)` and auto-saves the result.

### Isolate Architecture

`DecodeIsolate` (`lib/core/services/decode_isolate.dart`) is a single long-lived background isolate spawned once per scan (`LiveScanController.startScan`) and disposed on screen teardown (`disposeIsolate`, called from `dispose()`). It owns one `FrameDecoder` instance and processes `FrameJob`s one at a time — `busy` while a job is outstanding, and a second `decode()` call while busy throws. `dispose()` kills the isolate immediately and fails any pending job's `Future` with a `StateError`, which `LiveScanController._onIsolateError` recognizes by message (`'DecodeIsolate disposed'`) and ignores as normal teardown rather than surfacing it as a decode error. A `_gen` counter guards against a slow `DecodeIsolate.spawn()` completing after `disposeIsolate()` already ran (the late isolate is killed immediately instead of adopted). The still-photo path uses a different, one-shot pattern instead: `decodePhotoBytes` is a plain `Isolate.run(() => decodePhotoSync(...))` call with no long-lived worker to manage.

### Two-Channel Debug Logging

Per-frame diagnostics (`Diagnostics.toMap()`, stage keys like `locateMs`, `rsBlocks`, `roi`) are consumed two ways when `debugModeProvider` is on:

- **ADB logcat** — `debugPrint('[cimbar_scan] frame=$n status=... ms=... rank=.../... src=... rep=... dup=... dep=...[ rejected=...] <diag key=value...>')`, one line per frame (`adb logcat | grep cimbar_scan`). `rank`/`total` is assembler progress; `src`/`rep` count accepted source/repair rows, `dup`/`dep` count duplicate/dependent rejections — all four are `RatelessAssembler` counters (accepted rows only for `src`/`rep`).
- **On-screen overlay** — triple-tapping the status panel (3 taps within 500 ms) toggles `LiveScanState.debugEnabled`, showing a scrollable log panel (`debugLog`, capped at 50 entries) fed by a short per-frame summary line (`'#$n <status> <ms>ms r=<rank>/<total>'`), plus a camera icon that calls `captureDebugFrame()`.
- **Capture button** — marks the *next* decoded frame for capture; that frame's `FrameOutcome.capturePng` (produced only when `capture: true` was set on the job) and its diagnostics are saved to the app documents directory as `capture_<ts>.png` / `capture_<ts>.txt` (`status=<name>` + one `key=value` line per diagnostic). These two files are the corpus inputs — see `test/fixtures/corpus/README.md`.

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
| Open / export | `open_filex`, `file_picker` (`saveFile`), `mime` | Open a decoded file in another app, save-as picker, MIME types for share/open |
| Permissions | `permission_handler` | Currently unused in `lib/` (the `camera` plugin requests its own permission) |
| Sharing | `share_handler` | Receive shared files: Android SEND intent, iOS Share Extension → `ShareIntake` (`lib/shared/widgets/share_intake.dart`) → Import tab for a GIF, the Camera tab's photo decoder for any other image. The Android side is a **vendored, security-patched copy** (`third_party/share_handler_android`, `dependency_overrides`; see its `CIMBAR_PATCH.md` — upstream wrote shared streams to `cacheDir` under the sender's display name) |
| Sharing | `share_plus` | Outbound file sharing via system share sheet |
| Other | `url_launcher`, `intl` | Open web links, i18n formatting |

## Localization

5 languages (en, ru, uk, tr, ka) via ARB files (`lib/l10n/app_*.arb`). English (`app_en.arb`) is the template: add a key there first, then to the other four. Run `flutter gen-l10n` after any ARB change — the output under `lib/l10n/generated/` (`app_localizations.dart` plus one file per locale) is committed, so regenerate and commit it together with the ARB edit or the build uses stale strings. CI runs `flutter gen-l10n` before analyze and test. Access via `AppLocalizations.of(context)!.keyName`. Locale preference persisted in `SharedPreferences` via `LocaleProvider`. The web app keeps its own parallel five-language tables in `web-app/i18n.js`, guarded by `web-app/tests/test_i18n.js`.

## Android Manifest

- Application id / namespace `com.nfcarchiver.cimbar` (`com.cimbar.scanner` up to v0.10.1)
- Permissions: `CAMERA` only. Plugin-merged `READ_EXTERNAL_STORAGE`/`READ_MEDIA_*` (`open_filex`) and `RECORD_AUDIO`/`WRITE_EXTERNAL_STORAGE` (`camera_android_camerax`) are stripped with `tools:node="remove"`; `test/android_manifest_test.dart` asserts `CAMERA` is the only permission left
- Launcher icon: adaptive (`mipmap-anydpi-v26/ic_launcher.xml` + vector foreground) with legacy PNGs, all generated by `tools/gen_store_graphics.js`
- `android.hardware.camera` feature declared as `required="false"`
- Intent filter accepts shared `image/*` (galleries share even a GIF as `image/*`); `ShareIntake` routes by content: `isGif` → Import, any other image → the Camera tab's photo decoder
- Activity uses `singleTop` launch mode, handles `configChanges` for orientation/keyboard

## Features

- **Import GIF** — pick a CimBar GIF, optionally enter passphrase, decode and save/share. Encryption auto-detected via `CB 42` magic bytes
- **Camera** — in-app photo capture (`PhotoCaptureScreen.takePicture`) or gallery pick, decoded via `decodePhotoBytes`; plus live multi-frame scanning (`LiveScanScreen`) with focus/exposure lock, an aiming square, contextual hints, and a rank progress bar
- **Files** — browse decoded files, swipe-to-delete, share via system share sheet
- **Settings** — Developer debug switch (enables the live-scan overlay/logcat and capture button), language selection (5 languages), about
- **Language Switcher** — globe icon in AppBar on all tabbed screens
- **File Sharing** — `ResultCard` wires `onShare` via `FileService.shareResult`

## Design Decisions and Known Patterns

**TextEditingController listener pattern:** Screens use `_passphraseController.addListener(() => setState(() {}))` in `initState` to rebuild when the passphrase changes. Passphrase is optional — buttons are enabled without it. Encryption is auto-detected at decode time via `CB 42` magic bytes. `PassphraseField` is self-contained — its internal `setState` only rebuilds itself, not the parent screen.

**`Future.microtask` for camera state updates:** The camera `startImageStream` callback can fire during widget tree builds. Synchronous state updates trigger Riverpod's "modify provider during build" exception. Fix: wrap in `Future.microtask(() { ... })`.

**Material 3 theming:** Forest green (#2E7D32) seed color. Both light/dark themes provided; follows system preference via `ThemeMode.system`.

**AR overlay coordinate mapping:** `CornersOverlayPainter` maps the located finder quad and the static aiming square from camera-frame coordinates to a `BoxFit.contain` screen in 2 steps: (1) rotate by `sensorOrientation` (90°/270°/180° cases each have their own mapping, e.g. 90° CW is `(x, y) → (H − y, x)`), (2) scale + center by the `contain` factor. The mapping is the static `CornersOverlayPainter.mapPoint` (unit-tested in `test/shared/corners_overlay_painter_test.dart`), and `LiveScanScreen` sizes its preview from the same `CornersOverlayPainter.isRotated` rule so preview and overlay can't disagree. `shouldRepaint` compares `corners`/dimensions/orientation. The rotation mapping has **not yet been validated on a physical device** — check it first if the aiming square or located quad look offset during on-device testing.

**`LanguageSwitcherButton` as `ConsumerWidget`:** Needs Riverpod access for `localeProvider`. Uses `showModalBottomSheet` with `RadioListTile` options. Not included in `LiveScanScreen` (no AppBar).

**CameraController disposed guard:** `LiveScanScreen` sets `_disposed = true` in `dispose()` and checks it in `_initCamera()`, `_onCameraImage()`, `didChangeAppLifecycleState(resumed)`, and `CameraPreview` render condition.

**Frame dropping before copy:** `LiveScanController.wantsFrame` (`state.isScanning && _isolate != null && !_isolate!.busy`) is checked in `_onCameraImage` *before* any `Uint8List.fromList(plane.bytes)` copy runs, so a busy decoder costs zero allocation per dropped frame — this is what keeps the UI thread responsive without a separate throttle timer.

**ROI reuse across frames:** `LiveScanController` stashes each `FrameOutcome.roi` as a `RoiHint` and passes it into the next `FrameJob`; `FrameDecoder.decodeYuv420` tries locating within that hint region (expanded 25%) before falling back to a full-frame locate, so a barcode that stays roughly in place decodes without re-scanning the whole frame.

## Performance

`test/core/decode/benchmark_test.dart` renders a 1920×1080 synthetic camera scene (barcode ~790 px wide via scale 1.3, 15° rotation, 0.05 keystone; the rotated extent ≈967 px still fits the 1080 px canvas), decodes it through **`FrameDecoder.decodeYuv420`** — the entry point the live-scan isolate actually calls, so the Y-plane locate and the ROI-only RGB conversion are both inside the measurement — and prints `benchmark totalMs=… locateMs=… roiMs=… sampleMs=… driftMs=… rsMs=…` to stdout and `build/benchmark.txt` (uploaded by CI as the `decode-reports` artifact, alongside `build/corpus_report.txt`). It only asserts a loose desktop-JIT bound (`total < 1500`ms) to catch order-of-magnitude regressions, not a real performance target. Last measured on the dev machine: `benchmark totalMs=187 locateMs=35 roiMs=7 sampleMs=141 driftMs=125 rsMs=2`.

The spec target is **≤150 ms per 1080p frame on a mid-range 2022 phone** — this is **not yet measured on-device**. To measure it: enable the About tab → Developer → debug switch, start Live Scan, triple-tap the status panel to turn on the overlay/logcat, and read the `ms=` field of the `[cimbar_scan]` lines in `adb logcat | grep cimbar_scan` (or the on-screen overlay log) for real camera frames.

`test/core/decode/benchmark_test.dart` also has a second benchmark for the coding layer's elimination cost in isolation, feeding `RatelessAssembler` N repair-only rows (worst case: every row dense, eliminated against every prior pivot). `RatelessAssembler` elimination is cubic in N (each of N rows eliminates against up to N pivots, each subtraction touching O(N) coefficients), so it uses N = 2048, not the `coding.maxFrames` ceiling of 4096 — at 4096 the same test would cost roughly 4 minutes on this desktop, too slow for every suite run — and the committed assertion is a per-row bound (`perRowMs < 100`) rather than a fixed total, which is what actually guards the 4096 ceiling. Last measured (desktop JIT): `elimination N=2048 totalMs=34805 perRowMs=16.995`. Real GIFs never approach the worst case: they carry `R = ceil(0.25·N)` repair rows against mostly-sparse, in-order source rows, so the practical cost is far lower — but 4096 is a hard ceiling on what the format will code, not a performance target, and on-device elimination timing at realistic N is not yet measured either.

## Tests

Run: `sh tests/run_all.sh` from `app/` (never bare `flutter test`; see Build).

| File | What it tests |
|------|--------------|
| `services/galois_field_test.dart` | GF(256) table wraparound, mul/div inverse, polynomial arithmetic. |
| `services/reed_solomon_test.dart` | Clean round-trip, 32-error correction, uncorrectable detection, Forney/Omega, full-block round-trips. |
| `services/crypto_service_test.dart` | AES-256-GCM round-trip, wrong passphrase rejection, bad magic, strength scoring. |
| `services/decode_pipeline_v2_test.dart` | GIF import pipeline on v2/v2.1: unencrypted goldens including the compressed/repair-coded `lorem_coded`, an encrypted golden with right/wrong/empty passphrase plus a coded-and-encrypted golden (`lorem_coded_enc`), v1 GIF rejection. |
| `services/payload_decoder_test.dart` | `decodeFramedPayload(..., {compressed})`: an unencrypted payload round-trips; an encrypted payload decodes with the right passphrase and throws `PassphraseRequiredException` when empty; a wrong passphrase throws; a deflated-then-prefixed payload round-trips with `compressed: true` and throws `FormatException` with `compressed: false`; inflating non-deflate bytes throws `FormatException`; a compressed-and-encrypted payload decodes with its passphrase; a tiny zlib stream expanding to 300 KB throws `FormatException` under a lowered `maxInflatedBytes` cap and decodes fine above it. |
| `services/photo_decode_test.dart` | `decodePhotoSync`/`decodePhotoBytes`: a single-frame golden photo decodes to the file; a frame of a multi-frame file (including a repair frame of a coded file) reports `errorCode: 'multi_frame'` with the total; an image with no barcode reports an error. |
| `services/capture_policy_test.dart` | `CapturePolicy`: locks on the first located frame and unlocks 2 s after losing it; hints derived from module size, corner motion and `rsFailed`; `reset()` clears the lock and stale corner history. |
| `services/decode_isolate_test.dart` | `DecodeIsolate`: spawn, decode two frames sequentially, `busy` flag, `dispose()`; `dispose()` fails an in-flight decode instead of hanging forever; a killed worker (`killForTest`) fails the in-flight decode, sets `isDead` and makes every later `decode()` throw synchronously. |
| `format/cimbar_spec_test.dart` | `CimbarSpec` constants match `spec/cimbar-v2.json` (grid, finder, palette, tiles, RS, header, capacity, gif); reserved-cell geometry; `usableCellPositions` (3840, row-major, first (8,0), last (55,63)); cell origins; derived RS block sizes; `Tiles` hex round trip and pairwise Hamming ≥ 24; v2.1 flag masks and `coding` constants against the spec JSON; `gifRepairCount(1/2/5/345) == 0/1/2/87`. |
| `format/bit_packing_test.dart` | `cellValue`/`cellSymbol`/`cellColor`; `packCells`/`unpackCells` MSB-first round trip. |
| `format/frame_header_test.dart` | Encode layout; decode round trip; rejections with JS-compatible reasons; decode reads only the first 8 bytes of a longer buffer; repair+compressed round trip at `seq = 65535, total = 3`; independent flag bits; reserved bits 3/7 rejected while a repair+compressed combination is accepted; `seq >= total` is still checked for a source frame but not for a repair frame (whose `seq` is its repair id). |
| `format/rs_framing_test.dart` | `encodeFrame` reproduces the golden raw bytes (interleave cross-check with JS); `decodeFrame` recovers golden data with 12 ok blocks; corrects 30 spread errors; reports failed blocks and zero-fills them; tail block positions follow stride-skip-short. |
| `format/file_container_test.dart` | `parsePayload` (valid + bad name length); `stripLengthPrefix` (strips zero padding, validates); `isEncrypted` via the `CB 42` magic. |
| `format/rateless_test.dart` | `Rateless.coefficients` against the four amended spec vectors, determinism, and the constants table; `Rateless.combine` (unit row, coefficient 1, general GF(256), all-zero row); the rank guard — exactly N repair rows `r = 0..N-1` with no slack reach full rank with byte-exact bodies, for N ∈ {7, 64, 345}. |
| `decode/cell_sampler_test.dart` | `RgbBuffer.fromImage` copies pixels and clamps at edges; bilinear exact-at-center and halfway blend; `ExactGridModel` cell-unit mapping; `CellSampler` reads an exact tile. |
| `decode/luma_plane_test.dart` | `fromRgb` BT.601 integer weights; `downscale2` averages 2x2 blocks and floors odd sizes; `bilinear` exact at centers and clamped at edges; `mean3x3` clamps at the corner; `sampleLuma` through a `LumaPlane` matches the RGB path and `bestSymbol` is exact. |
| `decode/homography_test.dart` | Identity map; scale-and-translate map; a rotated/keystoned quad maps its four corners exactly and the inverse round-trips; `fromFinders` with exact frame finder centers reproduces `ExactGridModel`. |
| `decode/cell_classifier_test.dart` | All 64 symbol/color combinations classify exactly; dimmed cells still classify (brightness-normalized chroma); white point rescales channels before chroma; a flipped-bit patch still finds the nearest tile with hamming > 0. |
| `decode/rateless_assembler_test.dart` | Accepts source/repair frames in any order, dedups, completes, assembles, for N ∈ {1, 2, 7, 64, 345} source-only / repair-only / shuffled mixes; rejects RS-failed frames before the header; rejects a buffer shorter than `dataBytesPerFrame` as `short` before the header is decoded; rejects invalid headers with the header reason; a different `total`/mismatched flags for the same `fileId` is rejected; a new `fileId` resets the collection; duplicate and dependent rows leave `rank` unchanged with the right counters; the systematic fast path (in-order source frames) never touches GF arithmetic (`denseRows == 0`); one repair row makes `denseRows == 1`; `total = codingMaxFrames + 1` accepts source frames and rejects repair frames as `uncoded`; a source frame landing on a column a repair pivot already holds; `reset()`. |
| `decode/decode_report_test.dart` | `compare` counts symbol/color/cell correctness; `lines` contain the stage keys and truth accuracy; `heatmap` is 608×608 and marks wrong cells. |
| `decode/frame_decoder_golden_test.dart` | At least five goldens present; `decodeExact` matches each golden sidecar byte-for-byte, including per-frame `repair`/`compressed` header flags and `coef12` (`Rateless.coefficients` for repair frames, `null` for source frames); non-608 images report `unsupportedGrid` (v1 GIF); `decode` without a grid on a tiny blank buffer is `notLocated`; corrupted cells report `rsFailed` with block counts; every golden's assembled payload round-trips through `decodeFramedPayload(..., compressed: side.compressed)`; for the coded goldens, three reassembly modes — all frames, source frames only, and dropping every k-th frame — all recover the file byte-exact. |
| `decode/frame_decoder_scaled_test.dart` | 2x and 3x nearest-neighbour upscaled frames decode `ok` through a resolution-independent `GridModel`; a 0.5x downscaled frame is below the spec §11 px/cell floor and does not decode. |
| `decode/white_point_test.dart` | Exact frame's white point is pure white; a color cast shows in the white point; too-dark image returns null. |
| `decode/finder_locator_test.dart` | Exact placement at scale 1; rotations 37/90/180/271 at scale 1.8 keep TL/TR/BL/BR assignment; keystone 0.12 at scale 1.6; composited on a real photo background (scale 1.0, 0.9 rotated 15); blurred (sigma 2.5 px) and noisy (sigma 8) at scale 1.5; a photo with no v2 barcode and a v1 barcode photo both fail to locate; blank image. |
| `decode/drift_solver_test.dart` | Exact frame keeps zero drift; a grid model off by (2, -1) px is corrected by the solver; barrel distortion the homography can't model still recovers via drift; the full camera-path geometry matrix still decodes with drift on; a timing report (not asserted). |
| `decode/synthetic_scene_test.dart` | `renderScene`/`SceneSpec` ground truth: finder centers land at the expected offset for scale 1; a grid built from known finder centers decodes at scale 1, at scale 2.3/rotation 33°/keystone 0.15, and under blur+noise+brightness; a photo composite keeps the source photo outside the barcode quad. |
| `decode/camera_path_test.dart` | Full `FrameDecoder.decode` through the degradation matrix: scale 1.5–2.5 unrotated; rotations 37/90/180/271 at scale 1.8; keystone 0.12 (~20° tilt); blur sigma 1.0 source px (2 px at scale 2); brightness 0.7 and 1.3; noise sigma 8; combined mild degradation; composited on a real photo at scale 1.0; a photo without a barcode is `notLocated` with locate diagnostics. |
| `decode/roi_buffers_test.dart` | `rgbToYuv420` round-trips within ±4 through `RgbBuffer.fromYuv420` (planar and semi-planar, padded); ROI conversion carries an origin and bilinear reads absolute coordinates; `LumaPlane.fromYPlane` honours `rowStride`, `crop` keeps an origin, bilinear is absolute; corner-interpolated cell sampling stays exact on a golden frame (RGB and luma); decoding through an ROI buffer equals decoding the full buffer. |
| `decode/yuv_decode_test.dart` | `FrameDecoder.decodeYuv420`: planar and semi-planar frames decode with an ROI; a correct `RoiHint` decodes and a wrong one falls back to the full frame; a frame without a barcode is `notLocated`. |
| `decode/benchmark_test.dart` | Two benchmarks, both appending to `build/benchmark.txt` with loose desktop-JIT bounds (order-of-magnitude regressions only, not real targets): renders a 1920×1080 camera-like scene and times `FrameDecoder.decodeYuv420` (see Performance, `< 1500 ms`); and times `RatelessAssembler` elimination over N = 2048 repair-only rows (`perRowMs < 100`) — see Performance for why N is 2048, not the 4096 ceiling. |
| `decode/corpus_benchmark_test.dart` | Decodes every case in `test/fixtures/corpus/` (see its `README.md`), asserts each case's `expect` block, writes `build/corpus_report.txt`. |
| `tool/scene_fixtures_test.dart` | `test-data/scenes/` fixtures (generated by `tool/gen_scene_fixtures.dart`, shared with the web app's photo-decode tests): at least eight PNGs, each with a sidecar; each fixture decodes to its recorded `cells` (within 1% wrong, RS reporting zero failed blocks) through a grid built from its recorded `finderCenters`; each fixture reproduces its recorded camera-path `decode` digest exactly — the Dart↔JS parity contract for the photo decode layer. |
| `shared/corners_overlay_painter_test.dart` | `CornersOverlayPainter.mapPoint`: a 1280×720 landscape frame on a 720×1280 portrait canvas maps its corners as expected for `sensorOrientation` 90 (frame origin → preview top-right) and 270 (the point-symmetric mirror); orientation 0 is identity with contain letterboxing; `isRotated` agrees with the mapping. |
| `features/camera_navigation_test.dart` | Live Scan and Photo Capture are pushed on the **root** navigator, not the shell's nested one, so the bottom tab bar keeps working after a scan. |
| `features/live_scan_controller_test.dart` | `LiveScanController` without a camera or isolate (`onOutcomeForTest`/`onIsolateErrorForTest`): an `ok` outcome carrying a golden frame fills its slot and completes; a `notLocated` outcome clears the corners and reports no hint; three consecutive isolate errors surface `decoder_failed:` and the next outcome clears the panel; `'DecodeIsolate disposed'` errors are ignored; the first located outcome asks for a focus/exposure lock exactly once (`consumeLockAction` resets it); rateless assembly — feeding source and repair frames from a coded golden in mixed order climbs `state.rank` to completion, then further duplicate/dependent/already-seen frames leave `rank` unchanged. |

### Known Subtleties (Android)

- **`CameraImage` plane bytes are ephemeral** — `_onCameraImage` copies them with `Uint8List.fromList(plane.bytes)` into a `YuvFrame` only after `wantsFrame` confirms the frame will actually be used; a dropped frame is never copied.
- **Frame dropping replaces a fixed-fps throttle** — `LiveScanController.wantsFrame` gates every camera callback on `!_isolate!.busy`, so throughput self-adapts to how long each frame actually takes to decode instead of a fixed interval.
- **`DecodeIsolate` disposal races an in-flight job** — `dispose()` completes the pending job's `Future` with a `StateError` rather than leaving it hanging; `LiveScanController._onIsolateError` matches the message `'DecodeIsolate disposed'` to distinguish "normal teardown" from a real decode failure. A `_gen` counter also discards a `DecodeIsolate.spawn()` that resolves after `disposeIsolate()` already ran.
- **A dead worker is recovered, not waited on** — the reply port is also the isolate's `onExit`/`onError` port, so a crashed worker fails the in-flight job and flips `isDead`; `LiveScanController.onCameraFrame` treats `isDead` like "no isolate": it disposes the dead wrapper (bumping `_gen`), counts the death towards the 3-consecutive-errors rule and spawns a replacement, dropping frames until it is up.
- **Decoded filenames come from the payload** — every `_autoSave` and `FileService.shareResult` runs the name through `FileService.safeBasename`, which strips everything up to the last `/` or `\`, so a crafted barcode can't write outside the documents (or temp) directory.
- **`CornersOverlayPainter`'s rotation mapping is unverified on-device** — the 90°/180°/270° `sensorOrientation` mappings (e.g. 90° CW: `(x, y) → (H − y, x)`) are internally consistent and unit-tested (`mapPoint`), but were derived from the old (removed) overlay painter's logic and have not been confirmed against a real device's `sensorOrientation`; check this first if the aiming square or located quad look rotated wrong on-device.
- **ROI margin is 4.5 modules, not 1** — the finder centers sit 3.5 cells inside the grid edge, so `FrameDecoder`'s camera-path ROI (finder bounding box + margin) uses `module * 4.5` to guarantee full grid coverage with one module of safety, not the smaller margin an initial reading of spec §8 might suggest.
- **Full-res luma for finder classification** — `FinderLocator` samples the finder cores in the *full-resolution* luma plane (`full.mean3x3`), not the 2× downscaled plane used for the initial scan — after downscale the ~8px finder center cell is only ~4px, too coarse to classify reliably.

## iOS

- **Project:** `ios/` from `flutter create --platforms=ios`; bundle id `com.nfcarchiver.cimbar`, display name "CimBar", deployment target **iOS 14 or newer** (`file_picker_darwin` 2.1.0 requires iOS 14; the Podfile and `configure_xcode_project.rb` set it, and the script re-applies it on every run). **CocoaPods only** (`flutter: config: enable-swift-package-manager: false` in `pubspec.yaml`), because `share_handler_ios` has no Swift package. `ios/Podfile.lock` is committed from CI's macOS runner (the *Build iOS (unsigned)* job uploads it as `ios-podfile-lock`, fails on drift, and asserts `Runner.app/PlugIns/ShareExtension.appex` is embedded). `.github/workflows/ci.yml` runs automatically only for pushes/PRs targeting main/master/develop, so a PR based on a non-default-branch base (e.g. stacked on another open PR) shows no checks until it's retargeted; until then, trigger a run manually with `gh workflow run ci.yml --ref <branch>`.
- **Project edits go through `ios/tool/configure_xcode_project.rb`** (xcodeproj gem, idempotent): the `InfoPlist.strings` variant group (en/ru/uk/tr/ka permission prompts), Runner's App Group entitlements, and the `ShareExtension` target. Don't hand-edit `project.pbxproj`; change the script and re-run it. `test/ios_project_test.dart` guards the result (ids, usage strings, no microphone, URL scheme, localizations, extension embedding, App Group, activation rule).
- **Share Extension:** `ShareExtension/ShareViewController.swift` subclasses `share_handler`'s `ShareHandlerIosViewController`, which copies the items into the App Group container and opens `ShareMedia-com.nfcarchiver.cimbar://…`. The template's UIScene lifecycle is kept: Flutter 3.44 forwards scene URL events to non-scene plugins (`sceneFallbackOpenURLContexts`), so no `SceneDelegate` code is needed. No `CFBundleDocumentTypes`: the Share Extension already covers sharing, and "Open in CimBar" (registering as a handler for files opened directly, e.g. from Files) isn't needed yet — a possible later addition. (`share_handler_ios` 0.0.15's `hasMatchingSchemePrefix` does accept `file://` opens; the extension is simply the only integration wired up.) `Info.plist` sets `FlutterDeepLinkingEnabled` false so the extension's `ShareMedia-…://` URL, which Flutter's engine would otherwise also hand to go_router as a deep link, only reaches `share_handler`.
- **Camera frames:** iOS delivers `420YpCbCr8BiPlanarVideoRange` (2 planes, luma 16–235). `YuvFrame.fromPlanes` builds the frame and sets `videoRange`, which `RgbBuffer.fromYuv420` and `LumaPlane.fromYPlane` expand to full range.
- **Icon:** `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, a single opaque universal icon from `tools/gen_store_graphics.js` (the metadata check rejects an alpha channel).
- **Known for distribution:** App Store Connect has flagged Flutter camera apps with ITMS-90683 (missing `NSMicrophoneUsageDescription`) even with `enableAudio: false`, because `camera_avfoundation` links audio-capture APIs regardless. Not an issue for the compile-check-only build today; revisit when signing/distribution starts — the camera-only permission rule above (no microphone string, matching Android) may need a microphone usage string added then.
- **Not verified on a device yet.** First-install checklist (a free Apple ID in Xcode is enough for a 7-day build, but the App Group needs a team id):
  1. Live scan locates and decodes a barcode shown by the web app. If not, check `videoRange` and the NV12 plane view first.
  2. The AR overlay lines up (`CornersOverlayPainter`'s `sensorOrientation` mapping is unverified on any device).
  3. Share a GIF from Photos, Files and Telegram to CimBar: the app opens on Import with the file selected (cold start and while running).
  4. Open / Save to device / Share a decoded file; the in-place passphrase prompt; the camera permission prompt appears in the phone's language.
  5. Share a GIF while Live Scan is open: it should close and the Import tab should show the file selected.
  6. Share a GIF while a GIF import decode is running: a SnackBar should ask to finish first, and the file being decoded should stay unchanged.
