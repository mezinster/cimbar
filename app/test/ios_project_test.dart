import 'dart:io';
import 'dart:typed_data';

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

  test('camera, photo library and (never-requested) microphone usage strings', () {
    expect(plistString(info, 'NSCameraUsageDescription'), isNotEmpty);
    expect(plistString(info, 'NSPhotoLibraryUsageDescription'), isNotEmpty);
    // camera_avfoundation links audio-capture APIs, which App Store Connect
    // flags as ITMS-90683 without this string. The app never asks for the mic.
    expect(plistString(info, 'NSMicrophoneUsageDescription'), contains('never'));
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
      test('$lang.lproj/InfoPlist.strings has every usage string and is in the project', () {
        final s = read('ios/Runner/$lang.lproj/InfoPlist.strings');
        expect(s, contains('"NSCameraUsageDescription" = "'));
        expect(s, contains('"NSPhotoLibraryUsageDescription" = "'));
        expect(s, contains('"NSMicrophoneUsageDescription" = "'));
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

    test('both targets share the App Group, and share_handler is told its name', () {
      // group.com.nfcarchiver.cimbar (share_handler's default, group.<bundle id>)
      // belongs to another team; without AppGroupId share_handler would look there.
      const group = 'group.com.nfcarchiver.cimbarscanner';
      for (final f in ['ios/Runner/Runner.entitlements', 'ios/ShareExtension/ShareExtension.entitlements']) {
        expect(plistStrings(read(f), 'com.apple.security.application-groups'), [group], reason: f);
      }
      for (final f in ['ios/Runner/Info.plist', 'ios/ShareExtension/Info.plist']) {
        expect(plistString(read(f), 'AppGroupId'), group, reason: f);
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

  group('App Store / TestFlight', () {
    const team = 'C6LYTC662B';

    test('every signing xcconfig sets the team; project.pbxproj never does', () {
      for (final f in [
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
        'ios/ShareExtension/Debug.xcconfig',
        'ios/ShareExtension/Release.xcconfig',
      ]) {
        expect(read(f), contains('DEVELOPMENT_TEAM = $team'), reason: f);
      }
      // Target settings beat xcconfig values; Xcode's Signing tab writes one there.
      expect(pbx, isNot(contains('DEVELOPMENT_TEAM')));
    });

    test('deployment target is iOS 15 everywhere (App Store Connect refuses less from April 2027)', () {
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);')
          .allMatches(pbx)
          .map((m) => m.group(1))
          .toSet();
      expect(targets, {'15.0'});
      expect(read('ios/Podfile'), contains("platform :ios, '15.0'"));
      expect(read('ios/tool/configure_xcode_project.rb'), contains("DEPLOYMENT = '15.0'"));
    });

    test('privacy manifest: no tracking, FileTimestamp C617.1, in Runner resources', () {
      final p = read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(p, matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')));
      expect(p, contains('NSPrivacyAccessedAPICategoryFileTimestamp'));
      expect(p, contains('<string>C617.1</string>'));
      expect(pbx, contains('PrivacyInfo.xcprivacy in Resources'));
    });

    test('export compliance: no YES without the code Apple issues', () {
      // A YES without ITSEncryptionExportComplianceCode is rejected at upload
      // ("Invalid Export Compliance Code"); NFC Archiver hit it. Answered per
      // build in App Store Connect instead.
      final m = RegExp('<key>ITSAppUsesNonExemptEncryption</key>\\s*<(true|false)/>').firstMatch(info);
      if (m?.group(1) == 'true') {
        expect(info, contains('ITSEncryptionExportComplianceCode'));
      }
    });

    test('ExportOptions.plist uploads to App Store Connect with automatic signing', () {
      final e = read('ios/ExportOptions.plist');
      expect(plistString(e, 'method'), 'app-store-connect');
      expect(plistString(e, 'destination'), 'upload');
      expect(plistString(e, 'signingStyle'), 'automatic');
      expect(plistString(e, 'teamID'), team);
    });
  });

  group('launch screen', () {
    const set = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

    test('launch images are the generated 120 pt mosaic, not Flutter\'s 1x1 placeholder', () {
      for (final (name, px) in [('LaunchImage.png', 120), ('LaunchImage@2x.png', 240), ('LaunchImage@3x.png', 360)]) {
        final png = File('$set/$name').readAsBytesSync();
        final ihdr = ByteData.sublistView(png, 16, 24);
        expect([ihdr.getUint32(0), ihdr.getUint32(4)], [px, px], reason: name);
      }
      expect(File('$set/README.md').existsSync(), isFalse, reason: 'Flutter template placeholder README');
    });

    test('storyboard paints the icon\'s black and sizes the image at 120 pt', () {
      final sb = read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
      expect(sb, contains('<color key="backgroundColor" red="0" green="0" blue="0" alpha="1"'));
      expect(sb, contains('<image name="LaunchImage" width="120" height="120"/>'));
      expect(sb, contains('image="LaunchImage"'));
    });
  });

  group('native photo channel', () {
    test('PhotoEncoder.swift is in Runner\'s sources and registered', () {
      expect(RegExp(r'PhotoEncoder\.swift in Sources').hasMatch(pbx), isTrue);
      expect(read('ios/Runner/AppDelegate.swift'),
          contains('registrar(forPlugin: "PhotoEncoder")'));
      final swift = read('ios/Runner/PhotoEncoder.swift');
      expect(swift, contains('"com.nfcarchiver.cimbar/photo"'));
      expect(swift, contains('"decodePixels"'));
    });
  });
}
