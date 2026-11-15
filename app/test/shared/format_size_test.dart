import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:cimbar_scanner/shared/format_size.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppLocalizations l(String code) => lookupAppLocalizations(Locale(code));

  test('English keeps the familiar format', () {
    expect(formatSize(l('en'), 62), '62 B');
    expect(formatSize(l('en'), 2048), '2.0 KB');
    expect(formatSize(l('en'), 200 * 1024 * 1024), '200.0 MB');
  });

  test('every language formats a size with its own separator and units', () {
    expect(formatSize(l('ru'), 15155), '14,8 КБ');
    expect(formatSize(l('uk'), 512), '512 Б');
    expect(formatSize(l('be'), 15155), '14,8 КБ');
    expect(formatSize(l('pl'), 15155), '14,8 KB');
    expect(formatSize(l('tr'), 15155), '14,8 KB');
    for (final locale in AppLocalizations.supportedLocales) {
      final s = formatSize(lookupAppLocalizations(locale), 3 * 1024 * 1024);
      expect(s, matches(RegExp(r'^3[.,]0 \S+$')), reason: locale.languageCode);
    }
  });

  test('live-scan progress agrees with the total', () {
    expect(l('en').liveScanProgress(0, 1), 'Scanning... 0/1 frame');
    expect(l('en').liveScanProgress(2, 5), 'Scanning... 2/5 frames');
    expect(l('ru').liveScanProgress(2, 21), 'Сканирование... 2/21 кадра');
    expect(l('ru').liveScanProgress(2, 3), 'Сканирование... 2/3 кадров');
    expect(l('be').liveScanProgress(1, 5), 'Сканаванне... 1/5 кадраў');
  });

  test('the truncation note groups the digits', () {
    expect(l('en').textTruncated(100000), contains('100,000'));
    expect(l('ru').textTruncated(100000), contains('100 000'));
  });
}
