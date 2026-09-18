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

  test('removes the READ_MEDIA_* permissions merged from open_filex', () {
    for (final p in ['READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO', 'READ_MEDIA_AUDIO']) {
      expect(
        manifest,
        matches(RegExp('android:name="android.permission.$p"\\s+tools:node="remove"')),
        reason: '$p must be removed with tools:node="remove"',
      );
    }
  });
}
