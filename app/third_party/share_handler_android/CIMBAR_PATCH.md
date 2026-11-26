# CimBar patch to share_handler_android 0.0.11

This directory is [share_handler_android 0.0.11](https://pub.dev/packages/share_handler_android)
(MIT, see `LICENSE`), vendored so CimBar can fix a security bug. `app/pubspec.yaml`
points to it with `dependency_overrides`.

## The bug

Upstream: [issue #140](https://github.com/ShoutSocial/share_handler/issues/140) (CVE-2026-38102); our fix was offered upstream as [PR #147](https://github.com/ShoutSocial/share_handler/pull/147).

When another app shares a file, the plugin copies the `content://` stream into the
app's cache directory under the stream's **display name**. That name is chosen by the
*sending* app's content provider, and upstream used it as a path:
`File(cacheDir, displayName)`. The launcher activity is exported, so any installed app
can send an explicit `ACTION_SEND` with a name like
`../shared_prefs/FlutterSharedPreferences.xml` and overwrite CimBar's private files.
This is the "Dirty Stream" class of path traversal.

## The fix

- `android/src/main/kotlin/.../SafeCacheFile.kt`: `safeCacheFile(dir, name)` keeps
  only the name's last path segment, rejects null, empty, `.`, `..` and NUL-containing
  names, and returns null unless the result is a direct child of `dir`.
- `FileDirectory.kt` and `ShareHandlerPlugin.kt`: both cache writes go through it.
  `FileDirectory` falls back to its existing generated `<PREFIX>_<time>.<ext>` name when
  the display name is rejected; `ShareHandlerPlugin` skips that attachment.
- `android/src/test/kotlin/.../SafeCacheFileTest.kt` plus `testImplementation junit` and
  the `src/test/kotlin` source set in `android/build.gradle`.

The commit before the patch commit is the pristine upstream copy, so
`git log -p -- app/third_party/share_handler_android` shows exactly what changed.

## Second fix: size cap

The launcher accepts `*/*` shares and `handleIntent` copied every `content://` stream
into `cacheDir` synchronously on the main thread, so a multi-GB share froze the app and
filled the disk. Both copy sites (`FileDirectory.getDataColumn` and
`ShareHandlerPlugin.attachmentForUri` -> `copyFile`) now:

- ask the provider for `OpenableColumns.SIZE` first (`reportedSize`) and skip the copy
  above `SHARE_SIZE_CAP` (134217728 bytes, equal to `CimbarSpec.maxInflatedBytes`);
- otherwise copy through `copyCapped`, which stops once more than the cap was seen
  (providers can lie or omit the size) and the partial file is deleted.

The cap is one budget per share intent (`CopyBudget`), not per item: every attachment of an
`ACTION_SEND_MULTIPLE` draws from the same 128 MB, each copied item subtracts its size,
and a cut-off exhausts it. (Since the third fix every attachment is copied.)

Either way the attachment's `path` becomes `cimbar-too-large:<size or -1>` (type
unchanged); the Dart side reads that marker. `FileDirectory.getAbsolutePath` returns the
marker as its path string and `attachmentForUri` short-circuits on the prefix before
touching `File(path)`. Helpers live in `SafeCacheFile.kt`; tests in `CappedCopyTest.kt`
and `test/share_handler_patch_test.dart`.

## Third fix: copy every content URI

Upstream's `FileDirectory.getAbsolutePath` ran paulburke's path heuristics on
Storage Access Framework document URIs and returned a *path* instead of copying:
an `ExternalStorageProvider` `primary:<rel>` document became
`getExternalFilesDir(null)/<rel>` (the app's own external files dir, where the
file doesn't exist), and a `MediaProvider` document became the MediaStore `_data`
column (a path under `/storage/emulated/0`, which CimBar can't read with `CAMERA`
as its only permission). A PDF or image shared from Android's system Files
(DocumentsUI) app therefore reached Dart as an unreadable path.

- `FileDirectory.getAbsolutePath` now sends every `content://` URI
  (`isContentScheme`) through the capped stream copy (`getDataColumn`, now
  copy-only: the `_data` branch, the selection arguments and the document helpers
  are gone). A provider that throws makes that one attachment unreadable instead of
  crashing `handleIntent`, and a partial copy is deleted.
- Any other scheme, `file://` included, is refused (the attachment is skipped). A
  modern sender can't put a `file://` URI in an intent (`FileUriExposedException`),
  and with only `CAMERA` the files such a URI could name that CimBar can read are
  CimBar's own private files.
- The size decision is the pure `shouldSkipCopy(reported, remaining)`, used at both
  copy sites.
- Tests: `ContentCopyRuleTest.kt` (`shouldSkipCopy`, `isContentScheme`), and
  `test/share_handler_patch_test.dart` fails if a `"_data"` lookup,
  `getExternalFilesDir` or `DocumentsContract` reappears in `FileDirectory.kt`.

Every attachment is therefore a direct child of `cacheDir` (or the too-large
marker); the Dart side deletes exactly those, and only those, once the share is
handled (`deletePluginCopy`).

## Tests

- Kotlin, from `app/`: `flutter build apk --config-only && cd android && ./gradlew :share_handler_android:testDebugUnitTest`
  (CI job *share_handler patch tests*): `SafeCacheFileTest`, `CappedCopyTest`, `ContentCopyRuleTest`.
- Dart guard, `app/test/share_handler_patch_test.dart`: the override is in place,
  no cache write uses an unsanitized name, both copy sites are capped, and no
  content URI is resolved to a path. It fails if a re-vendored upstream copy
  loses the patch.

## Upgrading

Re-vendor the new release, re-apply this patch, and keep both tests green. Once a
release includes PR #147 (or another fix for issue #140), drop the override and this
directory.
