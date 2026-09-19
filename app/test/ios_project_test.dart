import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the iOS project configuration, which nothing in Dart exercises and
/// which can only be built on macOS (CI's "Build iOS (unsigned)" job).
String read(String path) => File(path).readAsStringSync();

List<String> arbLocales() => Directory('lib/l10n')
    .listSync()
    .map((e) => RegExp(r'app_([a-z]{2,3})\.arb$').firstMatch(e.path)?.group(1))
    .whereType<String>()
    .toList()
  ..sort();

/// The <string> values of a plist array under [key] (flat, one level).
List<String> plistStrings(String plist, String key) {
  final m = RegExp('<key>$key</key>\\s*<array>([\\s\\S]*?)</array>').firstMatch(plist);
  if (m == null) return const [];
  return RegExp(r'<string>([^<]*)</string>').allMatches(m.group(1)!).map((x) => x.group(1)!).toList();
}

String? plistString(String plist, String key) =>
    RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(plist)?.group(1);

void main() {
  late String pbx, info;

  setUpAll(() {
    pbx = read('ios/Runner.xcodeproj/project.pbxproj');
    info = read('ios/Runner/Info.plist');
  });

  test('Runner bundle id is com.nfcarchiver.cimbar (no template leftovers)', () {
    expect(pbx, contains('PRODUCT_BUNDLE_IDENTIFIER = com.nfcarchiver.cimbar;'));
    expect(pbx, isNot(contains('cimbarScanner')));
  });

  test('names: display CimBar, bundle name CimBar Scanner', () {
    expect(plistString(info, 'CFBundleDisplayName'), 'CimBar');
    expect(plistString(info, 'CFBundleName'), 'CimBar Scanner');
  });

  test('camera and photo library usage strings; no microphone', () {
    expect(plistString(info, 'NSCameraUsageDescription'), isNotEmpty);
    expect(plistString(info, 'NSPhotoLibraryUsageDescription'), isNotEmpty);
    expect(info, isNot(contains('NSMicrophoneUsageDescription')));
  });

  test('share_handler URL scheme is registered', () {
    expect(info, contains(r'<string>ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)</string>'));
  });

  test('CFBundleLocalizations lists exactly the ARB locales', () {
    expect(plistStrings(info, 'CFBundleLocalizations')..sort(), arbLocales());
  });

  test('CocoaPods only: SPM disabled in pubspec, Podfile targets Runner', () {
    expect(read('pubspec.yaml'), contains('enable-swift-package-manager: false'));
    expect(read('ios/Podfile'), contains("target 'Runner' do"));
  });
}
