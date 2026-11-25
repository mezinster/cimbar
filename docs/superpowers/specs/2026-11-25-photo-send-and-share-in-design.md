# Send a photo: Choose photo, photo optimiser, share into CimBar — design

Date: 2026-11-25 · Status: draft for approval · Platforms: Flutter app (Android **and** iOS). The web app is out of scope.

## Intent

Bring NFC Archiver's photo work (`~/nfcarchiver`, spec `docs/superpowers/specs/2026-11-11-photo-archiving-design.md` there, shipped in 1.3.0) to CimBar's **Send** side, and make CimBar a share target for anything you want to send.

Why it matters here: one CimBar frame carries 2,104 file bytes (`CimbarSpec.fileBytesPerFrame`). A 3 MB phone photo is ~1,500 frames, about 5 minutes of Present at 200 ms, and three times Share GIF's 500-frame cap (`maxGifFrames`). The same photo shrunk to ~100 KB is 50 frames, about 10 seconds. Today there is also no way to reach the photo library from Send (`send_screen.dart:50` calls `FilePicker.pickFiles()` with no type, which on iOS opens only Files), and sharing into CimBar only ever means *decode*.

What success looks like: share a photo from Photos/Gallery (or pick one in Send), say how many frames you're willing to send, get the best-looking JPEG that fits, and Present or Share GIF it. Share a PDF, a text snippet or any other file and it lands in Send. Share a photo *of a CimBar barcode*, or a CimBar GIF, and it still decodes as today.

## Goals

- **G1 — Choose photo in Send.** Send tab, File mode: a **Choose photo** action beside the existing file pick, opening `FilePicker.pickFiles(type: FileType.image)` (PHPicker on iOS, the system picker on Android). **No photo-library permission**: no `NSPhotoLibraryUsageDescription` (the existing one, if any, is for the Camera tab's `image_picker` and stays untouched), no Android media permission. `test/android_manifest_test.dart` already asserts `CAMERA` is the only permission and stays green.
- **G2 — Optimise photo screen.** A full-screen route between choosing a photo and the Send tab, a port of NFC Archiver's optimiser with **frames** in place of tags.
- **G3 — Share anything into CimBar to send it.** Any file, or plain text, shared to CimBar from another app opens Send with it loaded. Photos go through G2 first.
- **G4 — Keep share-to-decode.** A shared photo *of a CimBar barcode* and a shared *CimBar GIF* still decode, routed by automatic detection (the maintainer chose detection over asking every time).

## Non-goals

- Web app changes (a canvas port of the optimiser, as NFC Archiver's web app has, is a possible follow-up).
- Several files per send, albums, folders. One item per share.
- Video optimisation, or offering CimBar in Photos' share sheet for videos.
- Output formats other than JPEG. Image editing (crop, rotate beyond baking EXIF orientation, filters).
- Any change to the CimBar-XL format, to Present, or to the decode pipelines.
- A release. Version bump, changelogs and store listings are a separate step after merge.

## Anti-goals (failure even if it "works")

- **A frame count that lies.** If the optimiser says 50 frames, Present and Share GIF must need **at most 50** whether or not a passphrase is then typed.
- **Leaking metadata.** The optimised JPEG carries no EXIF/GPS/camera metadata; orientation is baked into the pixels.
- **New permissions.** Still `CAMERA` only on Android (F-Droid listing and privacy policy promise it); no new iOS usage strings.
- **A photo of a barcode sent instead of decoded** (or vice versa) when the detection had a clear answer. See "Routing a share".
- **Silently killing a live transfer.** A share arriving while Present is on screen must ask before stopping it.
- **Reading a huge share into memory.** A shared item above the Send cap (128 MB, `CimbarSpec.maxInflatedBytes`) is refused by its length, before it is read.
- **New dependencies.** The native encoder is our own code; `pubspec.lock` doesn't change, so F-Droid's `--enforce-lockfile` and the no-Play-Services rule are untouched.

## Approaches considered (encoder engine)

1. **Port NFC Archiver's native encoder — chosen.** `PhotoEncoder.kt` (ImageDecoder, 275 lines) and `PhotoEncoder.swift` (ImageIO, 197 lines) behind a method channel, plus the Dart domain (`photo_fit.dart`, `jpeg_metadata.dart`, `optimised_file_name.dart`, `platform_jpeg_session.dart`, `photo_temp.dart`). Hardened on real phones already: HEIC on iOS, never decodes above 16 MP, decodes once per size to sRGB with orientation baked in, flattens transparency onto white, drops Android's Ultra HDR gain map, reports out-of-memory distinctly. Cost: native code on both platforms, but it is copied, not written.
2. **Pure Dart `image` package in an isolate.** No native code and already a dependency, but no HEIC decode (iPhone's default format — exactly the shared-from-Photos case) and slow/memory-heavy at 12 MP across 8–25 encodes.
3. **`flutter_image_compress`.** New dependency; NFC Archiver rejected it because it re-decodes the full photo per encode.

The maintainer picked 1.

For routing a shared image, the maintainer picked **automatic detection** over (a) asking "Decode / Send" on every shared image and (b) making sharing always mean send (dropping today's share-to-decode).

## The optimiser (G2)

A port of NFC Archiver's `lib/features/photo/` and native `PhotoEncoder`s, keeping their behaviour unless stated here.

### Screen

Pushed on the **root navigator** like `PresentScreen` (CLAUDE.md: a full-screen route on the shell's nested navigator leaves the tab bar dead; extend `test/features/send_navigation_test.dart`). Layout as in NFC Archiver, minus the tag-type picker:

- large **preview** of the result, labelled with pixel size, JPEG quality and size in KB;
- **Frames to send** stepper (−/+, hold-to-repeat, tappable count to type a number — NFC Archiver commit 323da96), with the transfer time beside it: `≈ N × delay` at the Send tab's current frame delay (e.g. "50 frames · ≈ 10 s at 200 ms");
- a note when N exceeds 500: "Share GIF holds up to 500 frames; Present only" (Present's cap is 4,096);
- **Manual**: longest-side presets and a quality slider (1–100); touching either switches to manual, **Back to auto** returns; live KB and frame count;
- **Skip (keep original)** and **Continue**, pinned at the bottom.

Continue/Skip set the Send tab to File mode with the chosen file (`SendController.setFile(name, bytes)` — the optimised JPEG is small; Skip goes through `loadFile` so the 128 MB cap still applies) and pop back to Send.

### Frame budget

`photoByteBudget(N, fileName)` = `N × 2104 − overhead(fileName)`, where overhead is the container and framing bytes with **encryption always reserved**: 4 (length prefix) + 4 + UTF-8 length of the output name + container bytes as `buildPayload` lays them out + **48** encryption bytes (`CB 42 01 00` magic 4 + salt 16 + IV 12 + GCM tag 16). The builder derives the exact container layout from `payload_encoder.dart`.

The budget and `estimateFrames` (`send_controller.dart`) must come from **one shared helper**, so the optimiser and the Send tab's frame estimate can't disagree. Today `estimateFrames` uses an upper bound for the name (`fileName.length * 4`); the shared helper uses the exact UTF-8 length, so the Send tab's estimate gets slightly more accurate (designer's call; its tests are updated accordingly). Compression is not counted: a JPEG never deflates by the 5% threshold, and if it ever did it would only need fewer frames.

### Fit

Unchanged from NFC Archiver: presets **320, 480, 640, 800, 1024, 1280, 1440, 1600, 1920, 2560, 3840, Original**, never upscale; binary-search quality per side; pick **the largest side reaching q ≥ 50, else the largest fitting at q ≥ 30, else the smallest result marked unfit** ("Doesn't fit in N frames; needs at least M"). When unfit, offer **"Continue with M frames"** (sets the count to M, re-fits, continues — NFC Archiver PR #152, `continueAtNeeded`) beside Continue on the smallest result. Also carry over PR #160's follow-ups: a count set while the photo is still opening is kept, Continue is disabled while the result is being handed over, out-of-memory has its own message. Always re-encode in auto and manual; Skip is the untouched original. Metadata stripped natively **and** by `stripJpegMetadata`.

- **Starting N:** the frame count of the 640 px / q70 encode.
- **Stepper range:** 1 … min(the original file's frame count, 4,096).
- **Output name:** original stem + `.jpg` (`IMG_1234.HEIC` → `IMG_1234.jpg`); no name, **or a stem that is a bare UUID** (share_handler_ios names images that arrive as data `<UUID>.png`) → `photo-yyyyMMdd-HHmmss.jpg`.

### Which picks go to the optimiser

- **Choose photo**: always.
- **Choose file** returning `jpg/jpeg/png/heic/heif/webp` (by extension): yes, Skip is one tap away. **GIF is excluded** (optimising flattens animation, and a GIF is what Send produces; it stays a file).
- A shared photo that detection says is *not* a barcode: yes (see below).

### Native channel

`com.nfcarchiver.cimbar/photo`, same methods and error codes as NFC Archiver's `com.nfcarchiver/photo` (`open` reads the header and a 640 px probe; `encode(maxSide, quality)`; `close`; Android `out_of_memory`, iOS `decode_failed`), **plus one CimBar-only method for share detection**: `decodePixels(path, maxPixels)` → `{width, height, rgba}`, decoding any format the platform reads (HEIC included) to sRGB with orientation baked in, downscaled so width × height ≤ `maxPixels` (detection uses **12 MP**, the size of a typical phone photo, so a barcode photographed at full resolution is never shrunk while a 50–200 MP photo can't exhaust the isolate). The Dart side wraps the RGBA in an `RgbBuffer` and runs the existing `FrameDecoder.decode`; the transfer mechanism (raw RGBA over the channel vs. a temp file) is the builder's call. Kotlin package `com.nfcarchiver.cimbar` beside `MainActivity`; Swift file in `ios/Runner/`, added to the project **through `ios/tool/configure_xcode_project.rb`** (never hand-edit `project.pbxproj`) and registered with the app's plugin registry the way this project's UIScene template allows (builder checks: CimBar keeps the UIScene lifecycle; NFC Archiver's AppDelegate registration may need adapting). The optimiser hands its result over in memory (`setFile`), so the only files it needs are **inputs**: `open` takes a path, so a shared photo is first written to `temp/share_in` (see "Plugin copies" below). `temp/share_in` and `temp/photo_optimiser` (anything the native side writes) are cleared on the next launch (files older than launch only).

## Routing a share (G3, G4)

`ShareIntake` (`lib/shared/widgets/share_intake.dart`) today reads the first attachment and sends a GIF to Import and any other image to the Camera tab's photo decoder. New routing, for the first usable item:

| Shared item | Check | Goes to |
|---|---|---|
| Text only (no attachment) | — | Send, **Text** mode, text filled in |
| GIF (by magic bytes) | CimBar GIF? 608×608 logical screen **and** its first frame passes `decodeExact` with a valid v2 header | yes → **Import** (as today); no → **Send**, File mode, unchanged |
| Image (JPEG/PNG/HEIC/HEIF/WebP by magic bytes) | Decode natively to ≤ 12 MP (`decodePixels`), then the photo decode chain (`FrameDecoder.decode` → assembler → payload) | **not located**, **unsupported grid** (finder-like marks whose grid isn't 64 ± 10), or the platform can't decode the image → **Optimise photo**; anything else (decoded file, `multi_frame`, `passphrase_required`, located-but-RS-failed, bad header) → **Camera tab** showing that outcome |
| Anything else | — | **Send**, File mode |

- **HEIC barcode photos decode.** Detection goes through the native `decodePixels`, not `img.decodeImage`, so an iPhone (HEIC) photo of a barcode decodes like a JPEG one. This also bounds memory: today's Dart path decodes at full resolution.
- **Detection codes.** Split today's `decode_failed` so routing can tell "image unreadable" (`photo_decoder.dart:47`) and "unsupported grid" from "located but RS failed"; the Camera tab maps the new codes to the existing generic message. The Camera tab's own capture/gallery path is otherwise unchanged.
- **Escape hatch.** When a *shared* photo lands in the Camera tab with an error (not a decoded file), the Camera tab shows **"Send this photo instead"**, which opens Optimise photo with it. A false locate on an ordinary photo is then one tap from where the user wanted to go.
- **No double decode.** When detection decodes the barcode, hand its `PhotoDecodeResult` to the camera controller (a new entry beside `setPhoto`) instead of decoding again.
- **While detecting**, show a small progress indication ("Checking shared photo…"); detection runs in an isolate (it already does: `Isolate.run`).
- **Several items** (Android `SEND_MULTIPLE`, iOS up to 10): use the first usable one and show a SnackBar that only one item is sent.
- **Size guard, Dart.** `firstSharedFile` checks `File.length()` before `readAsBytes()`; above 128 MB the share is refused with the Send tab's existing "file too big" message and never read into memory.
- **Size guard, Android plugin.** The vendored `share_handler_android` copies most `content://` streams into `cacheDir` synchronously in `handleIntent` (main thread, during `onCreate`/`onNewIntent`) before Dart sees anything, so with `*/*` a 2 GB video share would copy 2 GB on the UI thread. **Patch it** (a second fix beside SafeCacheFile, recorded in `CIMBAR_PATCH.md`, guarded by `test/share_handler_patch_test.dart` and a Kotlin unit test run by the *share_handler patch tests* CI job): query `OpenableColumns.SIZE` first and skip the copy above 128 MB, reporting the item as too large so Dart shows the same message. A size the provider doesn't report is copied with a running byte count that stops at the cap. The 128 MB number is held to `CimbarSpec.maxInflatedBytes` by a test. iOS is not patched: the extension copies file URLs with `FileManager` (no memory spike) and the Dart guard then refuses them.
- **Plugin copies.** The first usable item is read (or, for a photo bound for the optimiser, copied into `temp/share_in`), then the plugin's copy is deleted if, and only if, its path is inside the app's cache directory or the App Group container. Otherwise it is left alone.
- **Text shares** come from `SharedMedia.content` (share_handler). A URL-only share (Safari's page share) is text too: the URL goes to Send's Text mode, so a link can be sent phone to phone.

### Busy guards

Checked after the async read, against the destination:

- Import or Camera decoding → as today (go there, SnackBar "finish first", drop the share).
- Send encoding or building a GIF (`SendState.busy`) → go to Send, SnackBar "finish first", drop the share.
- **Present on screen** → confirm "Stop presenting and load the shared item?"; Yes pops Present and continues, No drops the share.
- Optimise photo screen open → replace its photo silently (nothing is lost but unsaved settings).
- Send tab holding **typed text** the share would replace (a text share, or any share while Text mode has non-empty text) → confirm "Replace the text you typed?". A staged *file* is replaced silently (it can be picked again).
- Live Scan / Photo Capture open → closed silently, as today (`_goTo` pops the root navigator).

## Platform changes

### Android (`app/android/app/src/main/AndroidManifest.xml`)

- `ACTION_SEND` and `ACTION_SEND_MULTIPLE` intent filters with `*/*` (replacing the `image/*`-only filter), so files and `text/plain` arrive.
- `launchMode` `singleTop` → **`singleTask`**. NFC Archiver found (commit 5eb0413) that with `singleTop` another app's chooser can start a second activity and Flutter engine in the *sender's* task, which then clears the first instance's temp files. Warm shares then arrive via `onNewIntent`, which share_handler already handles.
- No new permissions. Extend `test/android_manifest_test.dart`: both filters present with `*/*`, `singleTask`, `CAMERA` still the only permission.

### iOS (`app/ios/ShareExtension/Info.plist`, via `configure_xcode_project.rb` where it touches the project)

- Activation rule: keep `NSExtensionActivationSupportsImageWithMaxCount` and `…FileWithMaxCount` (10), add `NSExtensionActivationSupportsText` and `NSExtensionActivationSupportsWebURLWithMaxCount` = 1 (share_handler_ios already turns URLs into text content). `PHSupportedMediaTypes` stays `Image` only (no videos from Photos).
- No new target, App Group or entitlement — the Share Extension and `group.com.nfcarchiver.cimbar` App Group exist already. Extend `test/ios_project_test.dart` for the activation rule.
- iOS remains compile-checked only in CI; the device checklist below covers it.

## Localization

Every new string in `app_en.arb` first, then ru, uk, tr, ka; `flutter gen-l10n`; commit the generated files with the ARB edit. User-facing text never says "CimBar v2" (CLAUDE.md naming rule).

## Docs

`app/CLAUDE.md`: a bullet for the optimiser (native channel, budget with the 48 B encryption reserve, metadata stripping, temp cleanup) and an updated share-in bullet (routing table, singleTask, text shares). Root `CLAUDE.md` Interoperability section only if wording there goes stale. README feature lists get a line each in EN and RU.

## Testing

- **Unit:** budget helper agrees with `estimateFrames` for names of various UTF-8 lengths, with and without a passphrase; the encryption reserve holds (fit for N, then encode with a passphrase through the real `payload_encoder`, `total ≤ N`); the fit rule with a fake `JpegEncoderSession` (ported NFC Archiver tests); `stripJpegMetadata` (ported); output naming; routing table with a fake detector and fake share source (each row, plus several items, oversize, unreadable); CimBar-GIF check against `test-data/goldens/` (positive) and a non-CimBar GIF (negative); the split detection codes; busy guards including the Present and typed-text confirmations; the UUID-name fallback; "Continue with M frames"; the Android plugin size patch (Kotlin: a provider reporting a size above the cap is not copied; an unreported size stops at the cap).
- **Widget:** optimiser auto/manual/back-to-auto, Skip, Continue landing in Send File mode, "doesn't fit", the >500 note; Send tab's Choose photo button; root-navigator push.
- **Config:** `android_manifest_test.dart`, `ios_project_test.dart` as above.
- Web tests are untouched; `sh tests/run_all.sh` in `app/` must stay green and CI's *Analyze & Test* passes with `--enforce-lockfile`.

### Device checklist (append to `app/CLAUDE.md`'s on-device list)

Android and iPhone: share a HEIC/JPEG photo from Photos/Gallery (cold and warm) → Optimise photo; portrait preview upright; optimised file received on the other phone has no GPS; share a photo (HEIC on iPhone) of a single-frame CimBar barcode → decodes; share a 50 MP+ photo → no crash; share a >128 MB video from Files on Android → "too big", no freeze; share a Safari page → Send Text with the URL; share a CimBar GIF from Telegram → Import; share a non-CimBar GIF → Send; share a PDF from Files → Send; share text from a browser/notes → Send Text; share three photos → first used + notice; share while Presenting → confirmation; Choose photo needs no permission prompt; Android: share from another app's chooser and confirm only one CimBar task exists in Recents.

## Delivery

Two PRs on top of each other (designer's call), the optimiser first because share routing targets it:

1. **Choose photo + optimiser + native encoder** (G1, G2).
2. **Share-in widening and routing** (G3, G4): manifest, Info.plist, Android plugin size patch, `ShareIntake`, native-decode detection (`decodePixels` lands here, on PR 1's channel), escape hatch, busy guards.

## Left to the builder

Exact container byte layout in the budget helper (derived from `payload_encoder.dart`); visual details within the layout above; how the progress indication during detection looks; the UIScene-compatible registration of the iOS channel; search bounds and tie-breaks inside the fit rule (deterministic and tested).

## Decisions record

- **Maintainer:** same functionality as NFC Archiver (photo picker, photo import, optimiser, share-in); share files directly to the app; shared images routed by **automatic detection**; **native encoder port**.
- **Designer's calls (open to change):** app only, web later; frames as the unit with a time estimate beside it; budget always reserves encryption; starting N from 640 px / q70; stepper capped at the original's frame count and 4,096; GIFs never go to the optimiser; text shares go to Send Text mode; no videos from Photos; first item of several plus a notice; Present asks before being replaced, the optimiser screen doesn't; `singleTask`; delete plugin copies only inside our own containers; two stacked PRs.
- **Settled after the builder check (designer's calls):** detection decodes natively (`decodePixels`, ≤ 12 MP) so HEIC barcode photos decode and huge photos can't crash the isolate; "unsupported grid" routes to the optimiser; a "Send this photo instead" escape hatch on the Camera tab for shared photos that failed; patch the vendored Android plugin to skip copying shares above 128 MB; shared photos staged in `temp/share_in`; "Continue with M frames" included; Safari URL shares accepted as text; replacing typed text asks first; UUID-named shares get the `photo-…` name; the shared size helper uses exact UTF-8 name length.
