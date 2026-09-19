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

## Tests

- Kotlin, from `app/`: `flutter build apk --config-only && cd android && ./gradlew :share_handler_android:testDebugUnitTest`
  (CI job *share_handler patch tests*).
- Dart guard, `app/test/share_handler_patch_test.dart`: the override is in place and
  no cache write uses an unsanitized name. It fails if a re-vendored upstream copy
  loses the patch.

## Upgrading

Re-vendor the new release, re-apply this patch, and keep both tests green. Once a
release includes PR #147 (or another fix for issue #140), drop the override and this
directory.
