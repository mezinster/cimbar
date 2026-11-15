import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every non-English ARB must translate every message. `flutter gen-l10n`
/// only checks that keys exist, so a value copied from app_en.arb as a
/// placeholder ships as English in that language: the live-scan hints
/// ("Move closer", "Hold still", ...) did, in all four languages, until 0.13.
/// Keys whose value is legitimately the same in every language go here.
const _sameInEveryLanguage = {'webAppUrl'};

Map<String, dynamic> _read(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

void main() {
  final en = _read(File('lib/l10n/app_en.arb'));
  final messages = en.keys.where((k) => !k.startsWith('@')).toList();
  final arbs = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'app_\w+\.arb$').hasMatch(f.path))
      .where((f) => !f.path.endsWith('app_en.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('finds the translated locales', () {
    expect(arbs.length, greaterThanOrEqualTo(4));
  });

  for (final arb in arbs) {
    final lang = RegExp(r'app_(\w+)\.arb$').firstMatch(arb.path)!.group(1);
    test('$lang translates every message', () {
      final tr = _read(arb);
      final untranslated = [
        for (final k in messages)
          if (!_sameInEveryLanguage.contains(k) && tr[k] == en[k]) k,
      ];
      expect(untranslated, isEmpty, reason: 'still English in app_$lang.arb');
    });
  }
}
