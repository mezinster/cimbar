# Send a photo + share into CimBar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Choose photo + a frame-budget photo optimiser in the Send tab, and share-into-CimBar for any file or text, with shared barcode photos / CimBar GIFs still routed to decode.

**Architecture:** Port NFC Archiver's photo feature (`~/nfcarchiver/lib/features/photo/`, `PhotoEncoder.kt`, `PhotoEncoder.swift`) into `app/lib/features/photo/` with frames in place of tags; one shared frame-budget helper feeds both the optimiser and the Send tab's estimate. Share-in keeps the vendored `share_handler` plugin, widens its filters, patches the Android copy path for size, and routes in `ShareIntake` through a pure `routeShare` decision fed by native-pixel detection.

**Tech Stack:** Flutter 3.44.8 / Dart, Riverpod `StateNotifier`, go_router, Kotlin (Android `ImageDecoder`), Swift (ImageIO), `share_handler` 0.0.21 (Android side vendored).

**Spec:** `docs/superpowers/specs/2026-11-25-photo-send-and-share-in-design.md` — read it before any task.

## Global Constraints

- All commands run from `app/` unless stated. Single test file: `flutter test <path> --reporter expanded 2>&1 | tail -30`. Full suite: `sh tests/run_all.sh`. Before every commit that touches Dart: `flutter analyze` must print exactly `No issues found!`.
- No new pub dependencies; `pubspec.lock` must not change.
- Android permissions stay `CAMERA` only; no new iOS usage strings.
- Every new user-visible string: add to `lib/l10n/app_en.arb` (with `@key` description) then `app_ru.arb`, `app_uk.arb`, `app_tr.arb`, `app_ka.arb`; run `flutter gen-l10n`; commit `lib/l10n/generated/` with the ARB edits. Never write "CimBar v2" in user text.
- `CimbarSpec.fileBytesPerFrame` = 2104, `CimbarSpec.maxInflatedBytes` = 134217728 (128 MB), `maxSendFrames` = 4096, `maxGifFrames` = 500, encryption overhead = 48 B.
- Presets `320, 480, 640, 800, 1024, 1280, 1440, 1600, 1920, 2560, 3840` + Original; fit rule: largest side reaching q ≥ 50, else largest fitting at q ≥ 30, else smallest result unfit. Starting N = frames of the 640 px / q70 encode. Stepper range 1 … min(original's frames, 4096).
- Native channel name `com.nfcarchiver.cimbar/photo`. Detection pixel cap 12 MP (12 000 000 px).
- Full-screen routes are pushed with `Navigator.of(context, rootNavigator: true)`.
- iOS project edits go through `ios/tool/configure_xcode_project.rb`, never by hand in `project.pbxproj`. iOS is compile-checked by CI only.
- Work on branch `feat/photo-send-share-in`. PR 1 = Tasks 1–7; PR 2 = Tasks 8–13, branched from PR 1's head.

## Review Focus

- A file name with non-ASCII characters (Cyrillic, emoji) must count UTF-8 bytes in the budget, or "50 frames" becomes 51 → test in Task 1.
- The count typed into the stepper as 0, negative, or above the max must clamp to 1 … max rather than throw or fit to nonsense → test in Task 5.
- A share replacing the optimiser's photo while the first one is still opening must close the first native session (no leak, no stale result shown) → test in Task 5.
- A zero-byte / corrupt "image" share must reach the optimiser and show its decode error, never crash detection → tests in Tasks 10 and 12.
- A cold-start share of text only (`initialMedia` with `content`, no attachments) must land in Send Text mode → test in Task 12.

---

## PR 1 — Choose photo and the optimiser

### Task 1: Shared frame-budget helper

**Files:**
- Create: `lib/core/encode/frame_budget.dart`
- Modify: `lib/features/send/send_controller.dart:38-44` (`estimateFrames`)
- Test: `test/core/encode/frame_budget_test.dart`, update `test/features/send_controller_test.dart` if its estimate expectations change

**Interfaces:**
- Produces:
  - `const int encryptionOverheadBytes = 48;`
  - `int framedBytes({required int nameBytes, required int dataBytes, required bool encrypted})` = `4 + 4 + nameBytes + dataBytes + (encrypted ? 48 : 0)` (length prefix + name-length field + name + data + AES-GCM envelope).
  - `int framesForFramed(int framed)` = `max(1, ceil(framed / 2104))` (matches `PayloadEncoder`'s `total`).
  - `int photoByteBudget(int frames, String fileName)` = `frames * 2104 - framedBytes(nameBytes: utf8(fileName).length, dataBytes: 0, encrypted: true)`; may be ≤ 0.
  - `int framesForFile(String fileName, int dataBytes, {required bool encrypted})`.
  - `estimateFrames(SendState, {required bool encrypted})` keeps its signature; now uses exact UTF-8 name length via `framesForFile` (text mode name = `TextMessage.fileName(DateTime(2000))`, 27 B).

- [ ] **Step 1: Write the failing tests** in `frame_budget_test.dart`:
  - `framedBytes(nameBytes: 5, dataBytes: 100, encrypted: false) == 113`, `…encrypted: true) == 161`.
  - `framesForFramed(0) == 1`, `framesForFramed(2104) == 1`, `framesForFramed(2105) == 2`.
  - `photoByteBudget(1, 'a.jpg') == 2104 - 8 - 5 - 48`.
  - Non-ASCII: `photoByteBudget(3, 'фото😀.jpg')` uses `utf8.encode('фото😀.jpg').length` (16), not `.length`.
  - Encryption reserve holds through the real encoder: for N in {1, 7, 50}, random (incompressible, `Random(N)`) bytes of length `photoByteBudget(N, 'IMG_1.jpg')` encoded with `PayloadEncoder.encode(name: 'IMG_1.jpg', bytes: b, passphrase: 'pw')` give `total == N`; one byte more gives `total == N + 1`; without a passphrase `total <= N`.
  - `framesForFile` agrees with `PayloadEncoder.encode(...).total` for the same random inputs, encrypted and not.
- [ ] **Step 2: Run** `flutter test test/core/encode/frame_budget_test.dart --reporter expanded 2>&1 | tail -30` — expected FAIL (file missing).
- [ ] **Step 3: Implement** `frame_budget.dart` (pure Dart, no Flutter import) and switch `estimateFrames` to it.
- [ ] **Step 4: Run** the new test and `test/features/send_controller_test.dart` — expected PASS (adjust any send-controller expectation that relied on the old `length * 4` upper bound, with a comment that the estimate is now exact).
- [ ] **Step 5: Commit** — `git commit -m "feat(send): one frame-budget helper for the estimate and the photo optimiser"`

### Task 2: Photo domain (fit, metadata strip, output name)

**Files:**
- Create: `lib/features/photo/domain/photo_fit.dart`, `lib/features/photo/domain/jpeg_metadata.dart`, `lib/features/photo/domain/optimised_file_name.dart` — ported from `~/nfcarchiver/lib/features/photo/domain/` (same names)
- Test: `test/features/photo/photo_fit_test.dart`, `test/features/photo/jpeg_metadata_test.dart`, `test/features/photo/optimised_file_name_test.dart` — port from `~/nfcarchiver/test/photo_fit_test.dart` (and the stripper/naming cases it or neighbouring tests hold)

**Interfaces:**
- Produces (unchanged from NFC Archiver): `photoPresets`, `abstract interface class JpegEncoderSession { int get width; int get height; Future<Uint8List> encode({required int maxSide, required int quality}); Future<void> close(); }`, `List<int> candidateSides(int longestSide)`, `class PhotoFitResult { int maxSide; int quality; Uint8List bytes; bool fits; }`, `Future<PhotoFitResult> fitToBudget(JpegEncoderSession s, int budgetBytes)`, `Future<PhotoFitResult> encodeManual(JpegEncoderSession s, {required int maxSide, required int quality, required int budgetBytes})`, `Uint8List stripJpegMetadata(Uint8List jpeg)`, `String optimisedFileName(String? original, DateTime now)`.
- Change in `optimisedFileName`: a stem matching `^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$` is treated like no name.

- [ ] **Step 1: Port the tests**, changing imports to `package:cimbar_scanner/...`; add `optimisedFileName('3F2504E0-4F89-11D3-9A0C-0305E82C3301.png', DateTime(2026,11,25,9,5,7)) == 'photo-20261125-090507.jpg'` and `optimisedFileName('IMG_1234.HEIC', …) == 'IMG_1234.jpg'`.
- [ ] **Step 2: Run** the three tests — expected FAIL (files missing).
- [ ] **Step 3: Port the three domain files** verbatim (they are Flutter-free), plus the UUID rule.
- [ ] **Step 4: Run** — expected PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(photo): port the fit rule, JPEG metadata stripper and output naming"`

### Task 3: Photo channel (Dart side) and temp cleanup

**Files:**
- Create: `lib/features/photo/data/platform_jpeg_session.dart`, `lib/features/photo/data/photo_temp.dart` — ported from NFC Archiver's `data/`
- Modify: `lib/main.dart` (call `clearPhotoTemp(olderThan: launchTime)` unawaited after `ensureInitialized`)
- Test: `test/features/photo/platform_jpeg_session_test.dart`, `test/features/photo/photo_temp_test.dart` (port `~/nfcarchiver/test/photo_temp_test.dart`)

**Interfaces:**
- Consumes: `JpegEncoderSession`, `stripJpegMetadata` (Task 2).
- Produces:
  - `const photoChannel = MethodChannel('com.nfcarchiver.cimbar/photo');`
  - `PhotoDecodeException`, `PhotoMemoryException`; `PlatformJpegSession.open(String path)`; `encode`/`close` as in NFC Archiver.
  - `class DecodedPixels { final int width; final int height; final Uint8List rgba; }` and `Future<DecodedPixels> decodePixels(String path, {int maxPixels = 12000000})` — channel method `decodePixels` with args `{path, maxPixels}`, reply `{width, height, rgba}`; throws `PhotoDecodeException` on `decode_failed`, `PhotoMemoryException` on `out_of_memory`. (Native implementations arrive in Tasks 4/5 and PR 2's Task 10 uses it.)
  - `photoOptimiserDirName = 'photo_optimiser'`, `shareInDirName = 'share_in'`, `photoTempDirProvider`, `Future<void> clearPhotoTemp({required DateTime olderThan, Directory? base})`. Replace NFC Archiver's `log.warn` with a silent catch (CimBar has no diagnostics log).

- [ ] **Step 1: Write the failing tests:** with `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(photoChannel, …)`: `open` returns `{id: 3, width: 4000, height: 3000}` → session width/height; `encode` sends `{id: 3, maxSide: 640, quality: 70}` and the returned bytes are passed through `stripJpegMetadata` (mock returns a JPEG with an APP1 segment; result has none); `PlatformException(code: 'decode_failed')` from `open` → `PhotoDecodeException`; `out_of_memory` → `PhotoMemoryException`; `decodePixels('/x.heic')` sends `maxPixels: 12000000` and returns width/height/rgba. Port the temp-cleanup tests (old files deleted, files newer than launch kept, missing dirs fine).
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** both files and the `main.dart` hook.
- [ ] **Step 4: Run** — expected PASS; `flutter analyze` clean.
- [ ] **Step 5: Commit** — `git commit -m "feat(photo): Dart side of the native photo channel; clear photo temp on launch"`

### Task 4: Android native encoder

**Files:**
- Create: `android/app/src/main/kotlin/com/nfcarchiver/cimbar/PhotoEncoder.kt` — port of `~/nfcarchiver/android/app/src/main/kotlin/com/nfcarchiver/nfc_archiver/PhotoEncoder.kt`
- Modify: `android/app/src/main/java/com/nfcarchiver/cimbar/MainActivity.java` — override `configureFlutterEngine(FlutterEngine)`: call super, then `new PhotoEncoder(flutterEngine.getDartExecutor().getBinaryMessenger());`
- Test: `test/android_photo_encoder_test.dart` (source-level guard, like `share_handler_patch_test.dart`)

**Interfaces:**
- Consumes: channel contract from Task 3.
- Produces: native `open`/`encode`/`close` exactly as NFC Archiver (16 MP decode cap, sRGB, orientation baked, white flatten, gain map dropped, `out_of_memory`), plus `decodePixels(path, maxPixels)`: decode once (`ImageDecoder` with `setTargetSize` so `w*h <= maxPixels`, preserving aspect; legacy `BitmapFactory` path with `inSampleSize` then scale), `ARGB_8888` sRGB, return `{width, height, rgba}` (RGBA byte order via `copyPixelsToBuffer`), errors `decode_failed` / `out_of_memory`. Run off the main thread the same way the existing methods do.

- [ ] **Step 1: Write the failing guard test:** `PhotoEncoder.kt` exists and contains `"com.nfcarchiver.cimbar/photo"`, `"open"`, `"encode"`, `"close"`, `"decodePixels"`, `"out_of_memory"`; `MainActivity.java` contains `new PhotoEncoder(`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Port** the Kotlin file (package `com.nfcarchiver.cimbar`, channel name changed), add `decodePixels`, wire `MainActivity`.
- [ ] **Step 4: Verify:** the guard test passes; `flutter build apk --debug` succeeds; `test/android_manifest_test.dart` still passes.
- [ ] **Step 5: Commit** — `git commit -m "feat(android): native photo encoder (port of NFC Archiver) with decodePixels"`

### Task 5: Optimiser state (frames)

**Files:**
- Create: `lib/features/photo/presentation/photo_optimiser_provider.dart` — port of NFC Archiver's, tags → frames, tag-type picker removed
- Test: `test/features/photo/photo_optimiser_test.dart` — port `~/nfcarchiver/test/photo_optimiser_test.dart` (+ the "continue with" cases)

**Interfaces:**
- Consumes: Tasks 1–3 (`photoByteBudget`, `framesForFile`, `fitToBudget`, `encodeManual`, `JpegEncoderSession`, `PlatformJpegSession.open`, `optimisedFileName`).
- Produces:
  - `class PendingPhoto { final String path; final String? name; }`, `final pendingPhotoProvider = StateProvider<PendingPhoto?>((_) => null);`
  - `final jpegSessionOpenerProvider = Provider<Future<JpegEncoderSession> Function(String path)>((_) => PlatformJpegSession.open);` (test seam).
  - `PhotoOptimiserState` with fields: `opening`, `fitting`, `frames`, `maxFrames`, `auto`, `manualSide`, `manualQuality`, `result` (`PhotoFitResult?`), `neededFrames` (`int?`, set when unfit), `outputName`, `originalBytes`, `error` (`'decode' | 'memory' | 'failed' | null`), `handingOver`.
  - `PhotoOptimiserNotifier` methods: `setFrames(int n)` (clamps to 1 … `maxFrames`), `beginHold()/endHold()`, `setManual({int? side, int? quality})`, `backToAuto()`, `Future<({String name, Uint8List bytes})?> continueWithResult()`, `Future<({String name, Uint8List bytes})?> continueAtNeeded()`, `skip()` returning the original path/name.
  - `final photoOptimiserProvider = StateNotifierProvider.autoDispose<PhotoOptimiserNotifier, PhotoOptimiserState>(…)` reading `pendingPhotoProvider`; when `pendingPhotoProvider` changes, the notifier closes the old session (even mid-open) and opens the new one.
  - `maxFrames = min(framesForFile(name, originalLength, encrypted: true), maxSendFrames)`; starting frames = frames of the 640 px / q70 encode (clamped to `maxFrames`).

- [ ] **Step 1: Port the tests with a fake `JpegEncoderSession`** (size = f(maxSide, quality)) and add:
  - starting `frames` equals `framesForFile(outputName, size(640,70), encrypted: true)`;
  - `setFrames(0) → 1`, `setFrames(-3) → 1`, `setFrames(maxFrames + 10) → maxFrames`;
  - auto result bytes length ≤ `photoByteBudget(frames, outputName)`;
  - unfit → `neededFrames == M`; `continueAtNeeded()` sets `frames = M`, re-fits, returns a result that fits;
  - a count set while `opening` is kept after open (PR #160);
  - `handingOver` true during `continueWithResult` (Continue disabled);
  - opener throwing `PhotoDecodeException` → `error == 'decode'`; `PhotoMemoryException` → `'memory'`;
  - replacing `pendingPhotoProvider` while the first open is still pending: the first session's `close()` is called once it resolves and its result never reaches state.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the port (keep NFC Archiver's 250 ms refit debounce, generation guard and `_GuardedSession`).
- [ ] **Step 4: Run** — expected PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(photo): optimiser state fitting a photo to N frames"`

### Task 6: iOS native encoder

**Files:**
- Create: `ios/Runner/PhotoEncoder.swift` — port of `~/nfcarchiver/ios/Runner/PhotoEncoder.swift`
- Modify: `ios/Runner/AppDelegate.swift` (hold `private let photoEncoder = PhotoEncoder()`; in `didInitializeImplicitFlutterEngine`, after `GeneratedPluginRegistrant`, `if let r = engineBridge.pluginRegistry.registrar(forPlugin: "PhotoEncoder") { photoEncoder.register(with: r.messenger()) }` — NFC Archiver's AppDelegate is the reference), `ios/tool/configure_xcode_project.rb` (add `Runner/PhotoEncoder.swift` to the Runner target's sources, idempotently), then run the script so `project.pbxproj` changes
- Test: `test/ios_project_test.dart` — new case

**Interfaces:**
- Produces: same channel contract on iOS, including `decodePixels` (ImageIO `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` chosen so `w*h <= maxPixels`, `kCGImageSourceCreateThumbnailWithTransform` true, draw into an sRGB RGBA8 `CGContext`, return `FlutterStandardTypedData(bytes:)`); errors `decode_failed`.

- [ ] **Step 1: Write the failing test:** `project.pbxproj` lists `PhotoEncoder.swift` in Runner's sources build phase; `AppDelegate.swift` contains `registrar(forPlugin: "PhotoEncoder")`; `PhotoEncoder.swift` contains `"com.nfcarchiver.cimbar/photo"` and `"decodePixels"`.
- [ ] **Step 2: Run** `flutter test test/ios_project_test.dart --reporter expanded 2>&1 | tail -30` — expected FAIL.
- [ ] **Step 3: Implement** the Swift port, AppDelegate wiring and script change; run `ruby ios/tool/configure_xcode_project.rb` (needs the `xcodeproj` gem; if unavailable locally, say so and rely on CI's *Build iOS (unsigned)* job).
- [ ] **Step 4: Verify** the test passes; after pushing, CI *Build iOS (unsigned)* compiles.
- [ ] **Step 5: Commit** — `git commit -m "feat(ios): native photo encoder (port of NFC Archiver) with decodePixels"`

### Task 7: Optimise photo screen, Choose photo, docs → open PR 1

**Files:**
- Create: `lib/features/photo/presentation/photo_optimiser_screen.dart` — port of NFC Archiver's screen without the tag-type picker
- Modify: `lib/features/send/send_screen.dart` (Choose photo button beside `FilePickerZone`; `_pickFile` sends `jpg/jpeg/png/heic/heif/webp` picks to the optimiser), `lib/l10n/app_*.arb`, `app/CLAUDE.md`
- Test: `test/features/photo/photo_optimiser_screen_test.dart`, `test/features/send_screen_test.dart`, `test/features/send_navigation_test.dart`

**Interfaces:**
- Consumes: Task 5's provider/state/methods; `SendController.setFile`, `SendController.loadFile`, `SendState.delayMs`.
- Produces: `Future<void> openPhotoOptimiser(BuildContext context, WidgetRef ref, PendingPhoto photo)` in `photo_optimiser_screen.dart` — sets `pendingPhotoProvider` and pushes `PhotoOptimiserScreen` on the root navigator; if the screen is already on top it only replaces the pending photo. Continue/Continue-with-M → `setMode(SendMode.file)` + `setFile(name, bytes)` + pop; Skip → `loadFile(original name, …)` + pop. `final photoOptimiserOpenProvider = StateProvider<bool>((_) => false)` set while the screen is mounted (used by PR 2).
- Strings (keys): `sendChoosePhoto`, `photoOptimiseTitle`, `photoFramesToSend`, `photoTransferTime` (`{frames} frames · ≈ {seconds} s at {delay} ms`), `photoGifCapNote` (`Share GIF holds up to {max} frames; Present only`), `photoManual`, `photoBackToAuto`, `photoQuality`, `photoSide`, `photoOriginal`, `photoSkip`, `photoContinue`, `photoContinueWith` (plural, `{count}` frames), `photoDoesNotFit` (plural, `{frames}`, `{needed}`), `photoDecodeError`, `photoMemoryError`, `photoResultLabel` (`{width}×{height} · q{quality} · {kb} KB`). Russian/Ukrainian plurals use ICU `one/few/many/other`.

- [ ] **Step 1: Write the failing widget tests** (override `jpegSessionOpenerProvider` with the fake session from Task 5's test, extracted to `test/features/photo/fake_jpeg_session.dart`):
  - Send tab File mode shows a `Key('sendChoosePhoto')` button;
  - opening the optimiser pushes on the root navigator (tab bar still switches after pop — same pattern as `send_navigation_test.dart`);
  - the screen shows the frame count and `photoTransferTime` using the Send tab's delay (200 ms default → `N × 0.2` s);
  - `frames > 500` shows `photoGifCapNote`; ≤ 500 does not;
  - touching quality switches to manual, Back to auto returns;
  - unfit shows `photoDoesNotFit` and a `photoContinueWith` button;
  - Continue lands in Send File mode with `fileName == outputName` and the result bytes; Skip lands with the original name;
  - a `.heic` pick through Choose file opens the optimiser; a `.gif` and a `.pdf` do not.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the screen (layout per spec: preview + label, Frames to send stepper with hold-to-repeat and tap-to-type, transfer time, GIF note, Manual presets + quality slider, pinned Skip/Continue), the Send tab changes (Choose photo = `FilePicker.pickFiles(type: FileType.image)`), the strings in five languages, `flutter gen-l10n`.
- [ ] **Step 4: Verify:** the tests pass; `sh tests/run_all.sh` all green; `flutter analyze` → `No issues found!`; `flutter build apk --debug` succeeds.
- [ ] **Step 5: Docs:** in `app/CLAUDE.md` add `features/photo/` to Project Structure, a "Photo optimiser" bullet under the Send tab section (native channel + `decodePixels`, frame budget with 48 B reserve via `frame_budget.dart`, metadata stripped natively and by `stripJpegMetadata`, `temp/share_in`/`temp/photo_optimiser` cleared on launch), new test files in the Tests table, the PR's device checks (Choose photo without a permission prompt, portrait upright, no GPS after transfer) in the device checklist.
- [ ] **Step 6: Commit and open PR 1** — `git commit -m "feat(send): Choose photo and the Optimise photo screen"`; `git push -u origin feat/photo-send-share-in`; `gh pr create --base master --title "Send: Choose photo and photo optimiser"` with a body summarising Tasks 1–7 and linking the spec.

---

## PR 2 — Share anything into CimBar

Branch: `git checkout -b feat/share-in-send` from PR 1's head. Open the PR against `feat/photo-send-share-in`; retarget to `master` after PR 1 merges (CI only runs automatically on PRs to master — trigger with `gh workflow run ci.yml --ref feat/share-in-send` until then).

### Task 8: Android plugin — refuse oversized shares before copying

**Files:**
- Modify: `third_party/share_handler_android/android/src/main/kotlin/com/shoutsocial/share_handler/SafeCacheFile.kt`, `FileDirectory.kt` (`getDataColumn` copy), `ShareHandlerPlugin.kt` (`copyFile` in `attachmentForUri`), `third_party/share_handler_android/CIMBAR_PATCH.md`
- Test: `third_party/share_handler_android/android/src/test/kotlin/com/shoutsocial/share_handler/CappedCopyTest.kt`, `test/share_handler_patch_test.dart`

**Interfaces:**
- Produces (Kotlin, in `SafeCacheFile.kt`):
  - `internal const val SHARE_SIZE_CAP: Long = 134217728L`
  - `internal const val TOO_LARGE_PREFIX = "cimbar-too-large:"`
  - `internal fun copyCapped(input: InputStream, out: OutputStream, cap: Long): Boolean` — copies, returns false (stopping) once more than `cap` bytes were seen.
  - `internal fun reportedSize(resolver: ContentResolver, uri: Uri): Long?` — `OpenableColumns.SIZE`, null when absent/unknown.
- Behaviour: in both copy sites, if `reportedSize > SHARE_SIZE_CAP` skip the copy; if the copy is cut off by `copyCapped`, delete the partial file. In either case the attachment's path becomes `"$TOO_LARGE_PREFIX<size or -1>"` (type unchanged) so Dart can say "too big". (Dart side: Task 9.)

- [ ] **Step 1: Write the failing Kotlin test:** `copyCapped` with cap 10 copies 10 bytes → true and 11 bytes → false; `TOO_LARGE_PREFIX` value. Extend `share_handler_patch_test.dart`: both `FileDirectory.kt` and `ShareHandlerPlugin.kt` call `copyCapped(` and `reportedSize(`; `SafeCacheFile.kt`'s `SHARE_SIZE_CAP` equals `CimbarSpec.maxInflatedBytes` (parse the Kotlin literal).
- [ ] **Step 2: Run** `flutter build apk --config-only && (cd android && ./gradlew :share_handler_android:testDebugUnitTest)` and the Dart test — expected FAIL.
- [ ] **Step 3: Implement** the Kotlin changes and a new "Second fix: size cap" section in `CIMBAR_PATCH.md` (why: `*/*` filter + synchronous main-thread copy).
- [ ] **Step 4: Run** both — expected PASS.
- [ ] **Step 5: Commit** — `git commit -m "fix(share_handler_android): don't copy shares above 128 MB on the main thread"`

### Task 9: Reading a share (text, file, too large, several items)

**Files:**
- Modify: `lib/core/services/incoming_share.dart`
- Test: `test/core/services/incoming_share_test.dart`

**Interfaces:**
- Produces (replacing `firstSharedFile`/`SharedFile`; update `share_intake.dart`'s call site minimally so the build stays green):
  - `sealed class ShareItem`; `class SharedText extends ShareItem { final String text; }`; `class SharedFileItem extends ShareItem { final String name; final String path; final int length; }`; `class ShareTooLarge extends ShareItem { final int? length; }`; `class ShareUnreadable extends ShareItem {}`.
  - `Future<({ShareItem? item, int count})> readShare(SharedMedia media, {int cap = CimbarSpec.maxInflatedBytes})` — `count` = number of attachments; first usable attachment wins; a path starting with `cimbar-too-large:` → `ShareTooLarge`; `File.length() > cap` → `ShareTooLarge` without reading; no attachments but non-empty `media.content` → `SharedText` (a URL-only share arrives as content too).
  - `Future<String> stageSharedFile(SharedFileItem f, {required Directory tempBase, required String cacheDir})` — copies into `<tempBase>/share_in/<timestamp>/<FileService.safeBasename(name)>`, returns the new path, then deletes the original iff its path is under `cacheDir` or contains `/Shared/AppGroup/`.

- [ ] **Step 1: Write the failing tests:** attachments + content → file wins, `count == 2` for two attachments; first unreadable then readable → readable; only unreadable → `ShareUnreadable`; `cimbar-too-large:999999999` → `ShareTooLarge(length: 999999999)`; a 2 KB file with `cap: 1024` → `ShareTooLarge(length: 2048)` (the decision comes from `File.length()`; `readShare` never reads file bytes at all — it returns paths); text-only → `SharedText`; empty content and no attachments → `item == null`; `stageSharedFile` copies and deletes an original under `cacheDir`, keeps one outside it; a name `../../evil.png` stages as `evil.png`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** this test and `test/features/share_intake_test.dart` — expected PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(share): read text, files and too-large shares; stage shared files"`

### Task 10: Detection (native pixels, split error codes, CimBar GIF check)

**Files:**
- Modify: `lib/core/services/photo_decoder.dart`, `lib/features/camera/camera_screen.dart` (`_localized` maps new codes to the existing generic message), `lib/core/services/gif_parser.dart`
- Create: `lib/core/services/share_detection.dart`
- Test: `test/core/services/photo_decode_test.dart`, `test/core/services/share_detection_test.dart`

**Interfaces:**
- Consumes: `decodePixels`, `DecodedPixels`, `PhotoDecodeException`, `PhotoMemoryException` (Task 3).
- Produces:
  - In `photo_decoder.dart`: new error codes `unreadable_image` (bytes not decodable) and `unsupported_grid`; `String photoErrorCode(DecodeStatus s)` maps `notLocated → 'not_located'`, `unsupportedGrid → 'unsupported_grid'`, everything else → `'decode_failed'`; `PhotoDecodeResult decodePhotoBuffer(RgbBuffer image, String passphrase)` — the shared core after image decoding (`decodePhotoSync` becomes `img.decodeImage` → `decodePhotoBuffer`); `Future<PhotoDecodeResult> decodePhotoPixels(DecodedPixels px, String passphrase)` — `Isolate.run`, RGBA→RGB into `RgbBuffer(width, height, rgb)`, then `decodePhotoBuffer`.
  - In `gif_parser.dart`: `static bool isCimbarGif(Uint8List bytes)` — logical screen width/height (bytes 6–9, little-endian) both 608, then `parseFirstFrame` → `FrameDecoder().decodeExact(RgbBuffer.fromImage(frame))` has a non-null valid header; any exception → false.
  - In `share_detection.dart`: `enum ShareKind { image, gif, other }`; `ShareKind sniffKind(Uint8List head)` (JPEG `FF D8 FF`, PNG `89 50 4E 47`, GIF `GIF8`, WebP `RIFF....WEBP`, HEIC/HEIF `....ftyp` + brand in {`heic`,`heix`,`hevc`,`heim`,`heis`,`mif1`,`msf1`}); `typedef PixelDecoder = Future<DecodedPixels> Function(String path, {int maxPixels});` and `final pixelDecoderProvider = Provider<PixelDecoder>((_) => decodePixels);`; `Future<PhotoDecodeResult> detectSharedPhoto(String path, PixelDecoder decode)` — `decode(path, maxPixels: 12000000)`; a `PhotoDecodeException`/`PhotoMemoryException` → `PhotoDecodeResult(errorCode: 'unreadable_image', …)`; else `decodePhotoPixels(px, '')`; `bool isBarcodeOutcome(PhotoDecodeResult r)` = `r.errorCode` not in {`not_located`, `unsupported_grid`, `unreadable_image`}.

- [ ] **Step 1: Write the failing tests:** `decodePhotoSync` on random bytes → `unreadable_image`; on `test/fixtures/crop_frame_1.png`-style blank → `not_located` (existing case keeps passing); `photoErrorCode` for all five `DecodeStatus` values; `decodePhotoPixels` on RGBA built from a single-frame golden scene decodes the payload; `isCimbarGif` true for `../test-data/goldens/hello.gif`, false for a 608×608 GIF of noise and a 100×100 GIF (build both with `package:image`'s `encodeGif`); `sniffKind` table; `detectSharedPhoto` with a fake decoder throwing `PhotoDecodeException` → `unreadable_image` and `isBarcodeOutcome == false`; with a fake returning a golden scene → decoded result, `isBarcodeOutcome == true`; `multi_frame` and `passphrase_required` count as barcode outcomes.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the two tests plus `test/features/camera_navigation_test.dart` — expected PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(share): detect barcode photos via native pixels; CimBar GIF check"`

### Task 11: Manifest and Share Extension activation

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml` (the `image/*` SEND filter → two filters, `SEND` and `SEND_MULTIPLE`, each `<data android:mimeType="*/*" />`; `launchMode="singleTask"`; update the XML comment), `ios/ShareExtension/Info.plist` (add `NSExtensionActivationSupportsText` true and `NSExtensionActivationSupportsWebURLWithMaxCount` 1), `app/CLAUDE.md` Android Manifest bullets
- Test: `test/android_manifest_test.dart`, `test/ios_project_test.dart`

- [ ] **Step 1: Write the failing assertions:** the launcher activity has `launchMode="singleTask"`; an intent filter with action `SEND` and `mimeType="*/*"`; one with `SEND_MULTIPLE` and `*/*`; `CAMERA` still the only permission; Info.plist contains `NSExtensionActivationSupportsText` and `NSExtensionActivationSupportsWebURLWithMaxCount`, and `PHSupportedMediaTypes` lists only `Image`.
- [ ] **Step 2: Run** both tests — expected FAIL.
- [ ] **Step 3: Edit** the manifest and plist.
- [ ] **Step 4: Run** — expected PASS; `flutter build apk --debug` succeeds.
- [ ] **Step 5: Commit** — `git commit -m "feat(share): accept any file and text; singleTask so a share can't start a second instance"`

### Task 12: Routing in ShareIntake

**Files:**
- Create: `lib/shared/widgets/share_routing.dart`
- Modify: `lib/shared/widgets/share_intake.dart`, `lib/features/camera/camera_controller.dart`, `lib/features/send/send_controller.dart`, `lib/l10n/app_*.arb`
- Test: `test/shared/share_routing_test.dart`, `test/features/share_intake_test.dart`

**Interfaces:**
- Consumes: Task 9 (`readShare`, `stageSharedFile`, `ShareItem` types), Task 10 (`sniffKind`, `GifParser.isCimbarGif`, `detectSharedPhoto`, `isBarcodeOutcome`, `pixelDecoderProvider`), Task 7 (`openPhotoOptimiser`, `PendingPhoto`).
- Produces:
  - `sealed class ShareRoute`: `ToSendText(String text)`, `ToSendFile(String name, Uint8List bytes)`, `ToImport(String name, Uint8List bytes)`, `ToOptimiser(PendingPhoto photo)`, `ToCamera(Uint8List bytes, String path, PhotoDecodeResult result)`, `ShowTooLarge(int? length)`, `ShowUnreadable()`.
  - `Future<ShareRoute> routeShare(ShareItem item, {required PixelDecoder decodePixels, required Future<String> Function(SharedFileItem) stage})` implementing the spec's routing table (GIF: `isCimbarGif` → `ToImport` else `ToSendFile`; image: stage → `detectSharedPhoto` → barcode outcome ? `ToCamera` : `ToOptimiser(PendingPhoto(path: staged, name: item.name))`; other → `ToSendFile` read via `File.readAsBytes`).
  - `CameraController.adoptDetected(Uint8List bytes, String path, PhotoDecodeResult r)` — sets the photo, result/error exactly as `decode` would after `decodePhotoBytes` (including `_autoSave` on success) and `fromShare: true` in state (`CameraState.fromShare`, cleared by `setPhoto`/`pickFromGallery`).
  - `SendController.loadShared(SendMode mode, {String? text, String? name, Uint8List? bytes})`.
  - Strings: `shareChecking` ("Checking shared photo…"), `shareOnlyFirst` (plural `{count}`: "Only the first of {count} items is sent"), `shareTooLarge` (reuse `sendFileTooBig` formatting if it fits; else a new key).
- `ShareIntake._handle`: `readShare` → `routeShare` (showing `shareChecking` in a SnackBar while an image is detected) → act on the route (`_goTo('/send')`, `/import`, `/camera`, or `openPhotoOptimiser` via `rootNavigatorKey.currentContext`) → `shareOnlyFirst` when `count > 1`. Existing decode busy checks stay; the new guards are Task 13.

- [ ] **Step 1: Write the failing tests:** `routeShare` for each row with fakes (text → `ToSendText`; golden GIF → `ToImport`; noise GIF → `ToSendFile`; PNG with fake decoder returning not-located → `ToOptimiser` with the staged path; fake returning a decoded golden → `ToCamera`; fake throwing `PhotoDecodeException` on a zero-byte `.jpg` → `ToOptimiser`; PDF → `ToSendFile`; `ShareTooLarge` → `ShowTooLarge`). In `share_intake_test.dart` (existing `FakeShareSource`, `pixelDecoderProvider` overridden): cold-start text-only `initialMedia` lands on `/send` in Text mode with the text; a PDF share lands on `/send` File mode; two attachments show `shareOnlyFirst`; the existing GIF cases still land on Import.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** routing, controller entry points, strings, `flutter gen-l10n`.
- [ ] **Step 4: Run** both tests and `sh tests/run_all.sh` — expected PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(share): route shared text, files, photos and GIFs to send or decode"`

### Task 13: Busy guards, escape hatch, docs → open PR 2

**Files:**
- Modify: `lib/shared/widgets/share_intake.dart`, `lib/features/send/present_screen.dart` (set/clear `presentActiveProvider` in `initState`/`dispose`), `lib/features/camera/camera_screen.dart` (escape hatch), `lib/l10n/app_*.arb`, `app/CLAUDE.md`, `README.md`, `README.ru.md` (repo root)
- Test: `test/features/share_intake_test.dart`, `test/features/camera_screen_share_test.dart`

**Interfaces:**
- Consumes: Task 12's routes; `SendState.busy`, `SendState.mode/text`; `photoOptimiserOpenProvider` (Task 7).
- Produces: `final presentActiveProvider = StateProvider<bool>((_) => false);` in `present_screen.dart`; `Future<bool> confirmShareReplace(BuildContext context, String message)` (an `AlertDialog` on `rootNavigatorKey.currentContext`, Yes/No).
- Guards, checked after routing and before acting: Import/Camera decoding → existing behaviour; `SendState.busy` and the route targets Send or the optimiser → go to `/send` + `shareWhileEncoding` SnackBar, drop; `presentActiveProvider` → `confirmShareReplace(sharePresentConfirm)`, Yes pops Present then acts, No drops; Send in Text mode with non-empty text and route is `ToSendText` or `ToSendFile`/`ToOptimiser` → `confirmShareReplace(shareReplaceTextConfirm)`; optimiser open → replace silently (`openPhotoOptimiser` already only swaps the pending photo).
- Escape hatch: when `CameraState.fromShare` and the state holds an error (no `result`), `CameraScreen` shows `Key('sendPhotoInstead')` labelled `shareSendInstead`, which calls `openPhotoOptimiser(context, ref, PendingPhoto(path: capturedPhotoPath!, name: null))`.
- Strings: `shareWhileEncoding`, `sharePresentConfirm` ("Stop presenting and load the shared item?"), `shareReplaceTextConfirm` ("Replace the text you typed?"), `shareSendInstead` ("Send this photo instead"), `commonYes`/`commonNo` only if no equivalent keys exist.

- [ ] **Step 1: Write the failing tests:** Send busy + PDF share → stays, SnackBar `shareWhileEncoding`, file unchanged; Present on screen + share → dialog; No keeps Present and the old payload; Yes pops Present and loads the share; typed text + text share → dialog; No keeps the typed text; a staged file + PDF share → replaced without a dialog; optimiser open + photo share → no dialog, pending photo replaced; Camera tab with `fromShare` and `errorCode: 'decode_failed'` shows `sendPhotoInstead`, tapping it pushes the optimiser; without `fromShare` the button is absent.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** guards, provider, dialog, escape hatch, strings, `flutter gen-l10n`.
- [ ] **Step 4: Verify:** `sh tests/run_all.sh` green, `flutter analyze` → `No issues found!`, `flutter build apk --debug` succeeds.
- [ ] **Step 5: Docs:** `app/CLAUDE.md` — replace the Sharing row's routing description and the Android Manifest bullets with the routing table, `singleTask`, text shares, the second plugin patch, `decodePixels` detection, the escape hatch; add the spec's device checklist items to the iOS first-install list and the Android device checklist; READMEs (EN + RU) get one line each: share any file or text to CimBar to send it; photos are shrunk to fit.
- [ ] **Step 6: Commit and open PR 2** — `git commit -m "feat(share): busy guards, send-this-photo-instead, docs"`; `git push -u origin feat/share-in-send`; `gh pr create --base feat/photo-send-share-in --title "Share anything into CimBar to send it"`; then `gh workflow run ci.yml --ref feat/share-in-send`.
