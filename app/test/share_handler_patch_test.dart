import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';

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

  test('both copy sites check the reported size and copy through copyCapped', () {
    for (final name in ['FileDirectory.kt', 'ShareHandlerPlugin.kt']) {
      final src = File('$plugin/$name').readAsStringSync();
      expect(src, contains('copyCapped('), reason: '$name must cap its copy');
      expect(src, contains('reportedSize('), reason: '$name must check the size first');
    }
  });

  test('every content:// URI is copied, never resolved to a path (third fix)', () {
    final src = File('$plugin/FileDirectory.kt').readAsStringSync();
    // Upstream's DocumentsContract heuristics returned paths CimBar can't read
    // with CAMERA as its only permission: the `_data` column (a path under
    // /storage/emulated/0) and getExternalFilesDir(null)/<relative path>.
    expect(src, isNot(contains('"_data"')), reason: 'no _data column lookup');
    expect(src, isNot(contains('getExternalFilesDir')), reason: 'no external-files path for a document');
    expect(src, isNot(contains('DocumentsContract')), reason: 'documents take the same copy as any content URI');
    expect(src, contains('isContentScheme('), reason: 'content URIs are recognised by isContentScheme');
    for (final name in ['FileDirectory.kt', 'ShareHandlerPlugin.kt']) {
      expect(File('$plugin/$name').readAsStringSync(), contains('shouldSkipCopy('),
          reason: '$name must decide on the reported size through shouldSkipCopy');
    }
  });

  test('the Kotlin share cap equals CimbarSpec.maxInflatedBytes', () {
    final src = File('$plugin/SafeCacheFile.kt').readAsStringSync();
    final m = RegExp(r'const val SHARE_SIZE_CAP: Long = (\d+)L').firstMatch(src);
    expect(m, isNotNull);
    expect(int.parse(m!.group(1)!), CimbarSpec.maxInflatedBytes);
    expect(src, contains('const val TOO_LARGE_PREFIX = "cimbar-too-large:"'));
  });
}
