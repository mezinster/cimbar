import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bottom-bar labels must fit on one line. Flutter's NavigationBar draws each
/// label as a plain Text with no line limit, so with five tabs on a 390 pt
/// wide iPhone a label wider than ~1/5 of the screen wraps mid-word
/// ("О / приложени / и"). The test font's glyph widths don't match iOS, so
/// this can't be measured in a widget test; the limit is calibrated on the
/// iPhone 16e simulator instead: "Импорт GIF" (10) is the widest label that
/// fits, and every one that wrapped had 11 or more.
const _maxLabelLength = 10;

const _tabKeys = ['tabSend', 'tabImport', 'tabCamera', 'tabFiles', 'tabSettings'];

void main() {
  final arbs = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'app_\w+\.arb$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('finds the app locales', () {
    expect(arbs.length, greaterThanOrEqualTo(5));
  });

  for (final arb in arbs) {
    final lang = RegExp(r'app_(\w+)\.arb$').firstMatch(arb.path)!.group(1);
    final strings = jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>;

    for (final key in _tabKeys) {
      test('$lang $key fits the bottom bar', () {
        final label = strings[key] as String?;
        expect(label, isNotNull, reason: '$key missing from ${arb.path}');
        expect(label!.runes.length, lessThanOrEqualTo(_maxLabelLength),
            reason: '"$label" would wrap in the 5-tab bar');
      });
    }
  }
}
