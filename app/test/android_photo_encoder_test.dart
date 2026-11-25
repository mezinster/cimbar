import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guard: the native half of the photo channel
/// (platform_jpeg_session.dart) must exist and be wired into the activity.
void main() {
  const kt = 'android/app/src/main/kotlin/com/nfcarchiver/cimbar/PhotoEncoder.kt';
  const activity = 'android/app/src/main/java/com/nfcarchiver/cimbar/MainActivity.java';

  test('PhotoEncoder.kt implements the channel contract', () {
    final src = File(kt).readAsStringSync();
    for (final s in [
      '"com.nfcarchiver.cimbar/photo"',
      '"open"',
      '"encode"',
      '"close"',
      '"decodePixels"',
      '"out_of_memory"',
      '"decode_failed"',
    ]) {
      expect(src, contains(s));
    }
  });

  test('MainActivity registers PhotoEncoder', () {
    final src = File(activity).readAsStringSync();
    expect(src, contains('new PhotoEncoder('));
    expect(src, contains('configureFlutterEngine'));
  });
}
