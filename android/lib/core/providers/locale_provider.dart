import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

const _kLocaleKey = 'app_locale';

final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LocaleNotifier(prefs);
});

class LocaleNotifier extends StateNotifier<Locale?> {
  final SharedPreferences _prefs;

  LocaleNotifier(this._prefs) : super(null) {
    final saved = _prefs.getString(_kLocaleKey);
    if (saved != null && saved.isNotEmpty) {
      state = Locale(saved);
    }
  }

  void setLocale(Locale? locale) {
    state = locale;
    if (locale != null) {
      _prefs.setString(_kLocaleKey, locale.languageCode);
    } else {
      _prefs.remove(_kLocaleKey);
    }
  }
}
