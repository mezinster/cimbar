import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the manifest entries that make Open / Share work on Android 11+:
/// package-visibility queries for the intents we fire, and the removal of the
/// media permissions open_filex would otherwise merge into the app.
void main() {
  late String manifest;

  setUpAll(() {
    manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  });

  test('declares SEND, SEND_MULTIPLE and VIEW queries for share/open target resolution', () {
    final queries = RegExp(r'<queries>([\s\S]*?)</queries>').firstMatch(manifest)?.group(1);
    expect(queries, isNotNull, reason: 'no <queries> block');
    for (final action in ['android.intent.action.SEND', 'android.intent.action.SEND_MULTIPLE', 'android.intent.action.VIEW']) {
      expect(queries, contains(action));
    }
  });

  test('removes the storage and media permissions merged from open_filex', () {
    for (final p in ['READ_EXTERNAL_STORAGE', 'READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO', 'READ_MEDIA_AUDIO']) {
      expect(
        manifest,
        matches(RegExp('android:name="android.permission.$p"\\s+tools:node="remove"')),
        reason: '$p must be removed with tools:node="remove"',
      );
    }
  });

  test('removes the microphone and storage permissions merged from camera_android_camerax', () {
    for (final p in ['RECORD_AUDIO', 'WRITE_EXTERNAL_STORAGE']) {
      expect(
        manifest,
        matches(RegExp('android:name="android.permission.$p"\\s+tools:node="remove"')),
        reason: '$p must be removed with tools:node="remove"',
      );
    }
  });

  // The store listings and the privacy policy promise "camera only"; F-Droid
  // shows every requested permission on the app's page.
  // Any file or text can be shared in; ShareIntake decides (barcode photo or
  // CimBar GIF -> decode, anything else -> Send).
  List<String> filters() => RegExp(r'<intent-filter>[\s\S]*?</intent-filter>').allMatches(manifest).map((m) => m.group(0)!).toList();

  for (final action in ['SEND', 'SEND_MULTIPLE']) {
    test('accepts any shared content ($action */*)', () {
      final f = filters().where((x) => x.contains('android.intent.action.$action"')).toList();
      expect(f, hasLength(1), reason: 'one $action intent filter');
      expect(f.single, contains('android:mimeType="*/*"'));
      expect(f.single, contains('android.intent.category.DEFAULT'));
    });
  }

  // singleTop would let another app's share chooser start a second activity and
  // Flutter engine in the sender's task.
  test('launcher activity is singleTask', () {
    expect(manifest, contains('android:launchMode="singleTask"'));
    expect(manifest, isNot(contains('singleTop')));
  });

  test('CAMERA is the only permission the app itself requests', () {
    final kept = RegExp(r'<uses-permission\s+android:name="([^"]+)"([^>]*)/>')
        .allMatches(manifest)
        .where((m) => !m.group(2)!.contains('tools:node="remove"'))
        .map((m) => m.group(1))
        .toList();
    expect(kept, ['android.permission.CAMERA']);
  });
}
