import 'dart:io';

import 'package:cimbar_scanner/features/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English and unknown languages open the root policy', () {
    expect(
      privacyPolicyUrl('en'),
      'https://nfcarchiver.com/cimbar/docs/privacy/',
    );
    expect(
      privacyPolicyUrl('de'),
      'https://nfcarchiver.com/cimbar/docs/privacy/',
    );
  });

  test('a translated language opens its own policy', () {
    expect(
      privacyPolicyUrl('ru'),
      'https://nfcarchiver.com/cimbar/docs/ru/privacy/',
    );
    expect(
      privacyPolicyUrl('ka'),
      'https://nfcarchiver.com/cimbar/docs/ka/privacy/',
    );
  });

  // The URL must exist on the docs site for every app language: a new ARB
  // without a docs translation (or the reverse) would otherwise link to a 404
  // or to English silently.
  test('every app language maps to a privacy page in site-docs', () {
    final langs = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .map((f) => RegExp(r'app_(\w+)\.arb$').firstMatch(f.path)?.group(1))
        .whereType<String>()
        .toList();
    expect(langs, hasLength(greaterThanOrEqualTo(5)));
    for (final lang in langs) {
      expect(
        File('../site-docs/docs/$lang/privacy.md').existsSync(),
        isTrue,
        reason: 'site-docs has no $lang/privacy.md',
      );
      final expected = lang == 'en'
          ? 'https://nfcarchiver.com/cimbar/docs/privacy/'
          : 'https://nfcarchiver.com/cimbar/docs/$lang/privacy/';
      expect(privacyPolicyUrl(lang), expected, reason: lang);
    }
  });
}
