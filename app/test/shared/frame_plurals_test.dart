import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frame counts take the right plural form: no "1 frames", and Russian and
/// Ukrainian agree with the number (1 кадр, 3 кадра, 5 кадров).
void main() {
  AppLocalizations l(String code) => lookupAppLocalizations(Locale(code));

  test('English: one frame, many frames', () {
    expect(l('en').sendEstimate('62 B', 1), '62 B · at most 1 frame');
    expect(l('en').sendEstimate('9 KB', 5), '9 KB · at most 5 frames');
    expect(l('en').liveScanFramesAnalyzed(1), '1 frame analyzed');
    expect(l('en').liveScanFramesAnalyzed(12), '12 frames analyzed');
  });

  test('Russian agrees with the number', () {
    expect(l('ru').sendEstimate('1 KB', 1), '1 KB · не более 1 кадра');
    expect(l('ru').sendEstimate('1 KB', 3), '1 KB · не более 3 кадров');
    expect(l('ru').liveScanFramesAnalyzed(21), '21 кадр проанализирован');
    expect(l('ru').liveScanFramesAnalyzed(3), '3 кадра проанализировано');
    expect(l('ru').liveScanFramesAnalyzed(11), '11 кадров проанализировано');
    expect(l('ru').sendTooLarge(502, 500), 'Слишком много: 502 кадра (лимит 500).');
  });

  test('Ukrainian agrees with the number', () {
    expect(l('uk').sendEstimate('1 KB', 1), '1 KB · не більше 1 кадру');
    expect(l('uk').liveScanFramesAnalyzed(1), '1 кадр проаналізовано');
    expect(l('uk').liveScanFramesAnalyzed(4), '4 кадри проаналізовано');
    expect(l('uk').sendTooLarge(505, 500), 'Забагато: 505 кадрів (ліміт 500).');
  });
}
