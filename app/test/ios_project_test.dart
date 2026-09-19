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

  test('deep linking is disabled, so the Share Extension\'s ShareMedia-… URL never reaches go_router', () {
    final m = RegExp('<key>FlutterDeepLinkingEnabled</key>\\s*<(true|false)/>').firstMatch(info);
    expect(m, isNotNull, reason: 'FlutterDeepLinkingEnabled key missing from Info.plist');
    expect(m!.group(1), 'false');
  });

  test('CFBundleLocalizations lists exactly the ARB locales', () {
    expect(plistStrings(info, 'CFBundleLocalizations')..sort(), arbLocales());
  });

  test('CocoaPods only: SPM disabled in pubspec, Podfile targets Runner', () {
    expect(read('pubspec.yaml'), contains('enable-swift-package-manager: false'));
    expect(read('ios/Podfile'), contains("target 'Runner' do"));
  });

  group('localized permission prompts', () {
    for (final lang in arbLocales()) {
      test('$lang.lproj/InfoPlist.strings has both usage strings and is in the project', () {
        final s = read('ios/Runner/$lang.lproj/InfoPlist.strings');
        expect(s, contains('"NSCameraUsageDescription" = "'));
        expect(s, contains('"NSPhotoLibraryUsageDescription" = "'));
        expect(pbx, contains('$lang.lproj/InfoPlist.strings'));
      });
    }
  });

  group('Share Extension', () {
    late String extInfo;
    setUpAll(() => extInfo = read('ios/ShareExtension/Info.plist'));

    test('target exists with its own bundle id and is embedded in Runner', () {
      expect(pbx, contains('PRODUCT_BUNDLE_IDENTIFIER = com.nfcarchiver.cimbar.ShareExtension;'));
      expect(pbx, contains('ShareExtension.appex in Embed Foundation Extensions'));
    });

    test('both targets share the App Group', () {
      for (final f in ['ios/Runner/Runner.entitlements', 'ios/ShareExtension/ShareExtension.entitlements']) {
        expect(read(f), contains('<string>group.com.nfcarchiver.cimbar</string>'), reason: f);
      }
      expect(pbx, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'));
      expect(pbx, contains('CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;'));
    });

    test('is a share extension for images and files only (no TRUEPREDICATE)', () {
      expect(plistString(extInfo, 'NSExtensionPointIdentifier'), 'com.apple.share-services');
      expect(extInfo, contains('NSExtensionActivationSupportsImageWithMaxCount'));
      expect(extInfo, contains('NSExtensionActivationSupportsFileWithMaxCount'));
      expect(extInfo, isNot(contains('TRUEPREDICATE')));
    });

    test('versions follow the app (App Store requires them to match)', () {
      expect(plistString(extInfo, 'CFBundleShortVersionString'), r'$(FLUTTER_BUILD_NAME)');
      expect(plistString(extInfo, 'CFBundleVersion'), r'$(FLUTTER_BUILD_NUMBER)');
    });

    test('subclasses share_handler\'s controller and gets its pod', () {
      expect(read('ios/ShareExtension/ShareViewController.swift'),
          contains('class ShareViewController: ShareHandlerIosViewController'));
      final podfile = read('ios/Podfile');
      expect(podfile, contains("target 'ShareExtension' do"));
      expect(podfile, contains('share_handler_ios_models'));
    });
  });
}
