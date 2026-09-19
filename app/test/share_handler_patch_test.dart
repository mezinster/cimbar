import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// share_handler_android 0.0.11 wrote shared streams to
/// `File(cacheDir, <display name chosen by the sending app>)` — a path
/// traversal any installed app could use to overwrite CimBar's private files.
/// The app builds a patched vendored copy instead (third_party/, see its
/// CIMBAR_PATCH.md); these checks fail if the override or the patch is lost,
/// e.g. by re-vendoring a new upstream version without re-applying it.
/// The sanitizer itself is unit-tested in Kotlin (SafeCacheFileTest, CI job
/// "share_handler patch tests").
void main() {
  const plugin = 'third_party/share_handler_android/android/src/main/kotlin/com/shoutsocial/share_handler';

  test('pubspec overrides share_handler_android with the vendored copy', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      matches(RegExp(r'dependency_overrides:\s*\n\s+share_handler_android:\s*\n\s+path: third_party/share_handler_android')),
    );
    expect(File('pubspec.lock').readAsStringSync(), contains('path: "third_party/share_handler_android"'));
  });

  test('every cache write in the plugin goes through safeCacheFile', () {
    for (final name in ['FileDirectory.kt', 'ShareHandlerPlugin.kt']) {
      final src = File('$plugin/$name').readAsStringSync();
      expect(src, contains('safeCacheFile('), reason: '$name must sanitize the display name');
      // The only remaining raw cache write is the generated "<PREFIX>_<time>.<ext>" fallback name.
      final raw = RegExp(r'(?<![A-Za-z])File\((context|applicationContext)\.cacheDir,\s*(?![\s"])').allMatches(src).toList();
      expect(raw, isEmpty, reason: '$name writes into cacheDir with an unsanitized name');
    }
    expect(File('$plugin/SafeCacheFile.kt').existsSync(), isTrue);
  });
}
