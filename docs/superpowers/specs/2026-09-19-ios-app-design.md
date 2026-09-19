# CimBar Scanner for iOS — design

**Date:** 2026-09-19 · **Status:** approved 2026-09-19; plan: `docs/superpowers/plans/2026-09-19-ios-app.md` · **Branch:** `feat/ios` (stacked on PR #14, `chore/fdroid-readiness`)

## Goal

The Flutter app in `app/` also builds for iOS, with feature parity with Android: GIF import, photo/gallery decode, live scan, Files tab, Open / Save to device / Share, receiving GIFs shared from other apps (Share Extension), About, and five languages.

## Decisions (agreed 2026-09-19)

| Question | Decision |
|---|---|
| Distribution | **Compile-check only for now.** CI proves the iOS app (and its Share Extension) builds unsigned; no IPA artifact, no signing, no App Store/TestFlight. |
| Layout | Flutter root renamed `android/` → `app/` (done in PR #14): `app/android/` + `app/ios/`. |
| Scope | **Full parity including a Share Extension** for share-in. |
| Share-in approach | `share_handler`'s own iOS integration (URL scheme + Share Extension target), one Dart code path on both platforms. **Found while planning:** Android never had a Dart side either (the `SEND image/gif` filter opened the app and dropped the file), so share-in is implemented for both platforms here. |
| Order | This work lands after PR #14, in its own PR stacked on it. |

## Non-goals

- Signing, provisioning, App Store listing, privacy nutrition labels, export-compliance answers. The project is shaped so these are additions (secrets + an export step), not rework.
- Running on a device or simulator from this environment (WSL has no Xcode). Everything iOS-specific is verified on GitHub's macOS runners; on-device behavior is a checklist for whoever first installs it (below).
- A version bump. iOS lands under CHANGELOG `[Unreleased]`, and the next release takes it.

## Identity

| Item | Value |
|---|---|
| App bundle id | `com.nfcarchiver.cimbar` (same as the Android application id) |
| Share Extension bundle id | `com.nfcarchiver.cimbar.ShareExtension` |
| App Group (both targets) | `group.com.nfcarchiver.cimbar`, the default `share_handler` derives from the main bundle id |
| Display name | `CFBundleDisplayName` = `CimBar` (the home screen truncates past ~12 characters); `CFBundleName` = `CimBar Scanner` |
| Deployment target | the Flutter 3.44.8 template default (iOS 13), unless a plugin raises it |
| Version | `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` from pubspec, in both targets (the extension must match the app, or App Store validation fails later) |

## iOS project (`app/ios/`)

1. **Scaffold** with `flutter create --platforms=ios --org com.nfcarchiver --project-name cimbar_scanner .` from `app/` (this works on Linux). Then set `PRODUCT_BUNDLE_IDENTIFIER = com.nfcarchiver.cimbar`; the template would otherwise produce `com.nfcarchiver.cimbarScanner`.
2. **`Runner/Info.plist`**:
   - `NSCameraUsageDescription` (live scan and in-app photo) and `NSPhotoLibraryUsageDescription` (gallery pick; `share_handler` for shared photos).
   - **No** `NSMicrophoneUsageDescription`: both `CameraController`s pass `enableAudio: false`. This mirrors the Android camera-only permission rule.
   - `share_handler`'s block: `CFBundleURLTypes` with scheme `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`. **No `CFBundleDocumentTypes`**: `share_handler_ios` 0.0.15 only handles URLs with its `ShareMedia-` scheme, so "Open in CimBar" would drop the file. `NSUserActivityTypes` / `INSendMessageIntent` is omitted (no conversation suggestions).
   - The template's UIScene lifecycle (`SceneDelegate`) is kept unchanged: Flutter 3.44 forwards scene URL events to non-scene plugins (`sceneFallbackOpenURLContexts` / `sceneWillConnectFallback`), which is how `share_handler_ios` receives the extension's URL.
   - `CFBundleLocalizations`: `en`, `ru`, `uk`, `tr`, `ka`.
   - Orientation: portrait plus landscape for iPhone, same as Android. Live scan locks portrait itself via `SystemChrome`.
3. **Localized permission prompts**: `Runner/<lang>.lproj/InfoPlist.strings` for the five languages (camera and photo-library texts), matching the Android app's languages.
4. **Share Extension target** `ShareExtension`, added by a committed, re-runnable script **`app/ios/tool/configure_xcode_project.rb`**. The same script also registers the `InfoPlist.strings` variant group, which needs a project edit too. It uses the `xcodeproj` gem (pure Ruby, runs on Linux; install with `gem install --user-install xcodeproj`), and the script is idempotent (it exits if the target exists). It creates:
   - `ShareExtension/ShareViewController.swift`: `class ShareViewController: ShareHandlerIosViewController {}`, the plugin's documented subclass.
   - `ShareExtension/Info.plist`: `NSExtensionPointIdentifier` `com.apple.share-services`, principal class `$(PRODUCT_MODULE_NAME).ShareViewController`, and an activation rule accepting **only images and files, at most 10 each** (the `NSExtensionActivationSupportsImageWithMaxCount` / `…FileWithMaxCount` dictionary form, no `TRUEPREDICATE`, which App Review rejects). Version keys are tied to the Flutter build variables.
   - Entitlements files for both targets with the App Group, and `CODE_SIGN_ENTITLEMENTS` set on each.
   - The extension embedded in Runner ("Embed Foundation Extensions" build phase), plus a target dependency. The extension's `IPHONEOS_DEPLOYMENT_TARGET` matches Runner's.
   - Build settings: `SWIFT_VERSION`, `TARGETED_DEVICE_FAMILY` and `SKIP_INSTALL=YES` for the extension; the bundle id as in Identity.
5. **`Podfile`**: the Flutter template's plus the plugin's documented extension target:
   ```ruby
   target 'ShareExtension' do
     inherit! :search_paths
     pod 'share_handler_ios_models', :path => '.symlinks/plugins/share_handler_ios/ios/Models'
   end
   ```
   **CocoaPods only:** SPM (on by default in Flutter 3.44 stable) is disabled per project with `flutter: config: enable-swift-package-manager: false` in `pubspec.yaml`, since `share_handler_ios` and the extension's models pod exist only as CocoaPods. `Podfile.lock` can only be produced on macOS: the first CI run uploads it as an artifact, and it is committed from there (as NFC Archiver does), so later runs are reproducible.
6. **App icon**: `Runner/Assets.xcassets/AppIcon.appiconset` as a single 1024×1024 "universal" icon (Xcode 14+), generated by `tools/gen_store_graphics.js`. It's the same mosaic as Android, but **full-bleed and opaque** (iOS applies its own corner mask, and App Store validation rejects alpha). The generator gets a job for it that writes a PNG without an alpha channel; a test asserts the color type.

## Dart changes (all platform-neutral, tested on Linux)

1. **`YuvFrame` from any `CameraImage` plane layout.** A new pure function, `yuvFrameFromPlanes(...)` in `lib/core/decode/`, replaces the inline construction in `live_scan_screen.dart`:
   - 3 planes (Android YUV_420_888): as today.
   - **2 planes (iOS NV12)**: `uPlane` = plane 1, `vPlane` = a one-byte-offset view of plane 1 (`Uint8List.sublistView(p1, 1)`), and `uvPixelStride` = 2, `uvRowStride` = plane 1's `bytesPerRow`. `RgbBuffer.fromYuv420` already indexes semi-planar data this way.
   - Anything else returns null (frame dropped), as the `planes.length < 3` guard does now.
2. **Video-range luma/chroma.** iOS delivers `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (Y 16–235, CbCr 16–240). Android camera frames are full range. `YuvFrame` gains `videoRange` (default false), and when it's true, `RgbBuffer.fromYuv420` and `LumaPlane.fromYPlane` expand to full range (`(y − 16)·255/219`, chroma `·255/224`). Without this, finder cores never reach full white and every luma threshold tuned on Android shifts. The plane adapter sets it for the 2-plane case.
3. **Share-in (both platforms):** a `ShareIntake` widget (in `MaterialApp.router`'s `builder`) reads `share_handler`'s initial and streamed `SharedMedia` through an injectable `ShareSource`, selects the first readable attachment on the Import tab (`ImportController.loadSharedFile`) and navigates there. An unreadable attachment shows a translated SnackBar (`shareReadFailed`); on Android a document-provider URI can resolve to storage the app has no permission to read.
4. Nothing else needs platform branching. There are no `Platform.*` checks today; `file_picker.saveFile(bytes:)`, `open_filex`, `share_plus`, `image_picker` and `path_provider` all support iOS.

## CI

- **`ci.yml` gains a job "Build iOS (unsigned)"** on `macos-latest`: Flutter 3.44.8 → `flutter pub get --enforce-lockfile` → `flutter gen-l10n` → `flutter build ios --release --no-codesign`. That builds Runner and the embedded extension. It also uploads `ios/Podfile.lock` as an artifact (see Podfile). It is not a required check at first; add it to the ruleset once it's stable.
- The release workflow is unchanged (compile-check only).

## Tests

- `test/core/decode/yuv_frame_from_planes_test.dart`: 3-plane and 2-plane inputs produce identical RGB for the same image. It uses the existing `rgbToYuv420` helper, interleaved into NV12 with padded row strides. A golden frame round-trips through `FrameDecoder.decodeYuv420` from NV12 **video-range** input, which proves the expansion. Other plane counts return null.
- `test/ios_project_test.dart` (like `android_manifest_test.dart`), reading the plists and `project.pbxproj` as text:
  - bundle ids for both targets; App Group in both entitlements
  - camera and photo usage strings present, microphone absent
  - the URL scheme; `CFBundleLocalizations` equals the ARB locales
  - the extension's activation rule contains no `TRUEPREDICATE`
  - the extension is embedded in Runner
  - `InfoPlist.strings` exists for every ARB locale
- The generator's iOS icon is 1024×1024 with no alpha channel (asserted by `tools/validate_store_metadata.py`'s image check, extended to it).
- Existing suites (257 Android, all web) stay green, and the Android release APK's permissions are unchanged.

## Docs

`app/CLAUDE.md`: an iOS section covering the targets, bundle ids, App Group, the extension script, video range, and the device checklist. README: the iOS status (builds in CI, not distributed yet). CHANGELOG `[Unreleased]`: Added (iOS project, NV12/video-range camera input).

## Risks and the first-device checklist

These can't be verified without an iPhone; they're recorded in `app/CLAUDE.md` for the first install (free Apple ID + Xcode is enough for a 7-day development build):

1. Live scan locates and decodes. If not, check the video-range expansion and the NV12 plane view first.
2. The AR overlay orientation: the `sensorOrientation` mapping in `CornersOverlayPainter` is still unverified on any device.
3. Share a GIF from Photos, Files and Telegram to CimBar: the app opens with the file queued. (Needs a real App Group, so a team id, even for development builds.)
4. Open / Save to device / Share on a decoded file; the in-place passphrase prompt; localized camera permission prompt.

## Implementation order

1. `yuvFrameFromPlanes` plus video range (TDD, Linux).
2. Scaffold `app/ios/` and configure Runner (Info.plist, strings, icon generator job).
3. The Share Extension script, run to create the target; the Podfile.
4. `ios_project_test.dart`.
5. The CI iOS job, iterating on the macOS runner until it builds; commit `Podfile.lock` from its artifact.
6. Docs and CHANGELOG.
