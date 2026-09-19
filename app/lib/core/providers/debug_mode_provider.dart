import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

const _key = 'tuning_debug_mode';

/// Whether the v2 live-scan debug overlay (frame log + capture button) is enabled.
final debugModeProvider = StateNotifierProvider<DebugModeNotifier, bool>((ref) {
  return DebugModeNotifier(ref.watch(sharedPreferencesProvider));
});

class DebugModeNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  DebugModeNotifier(this._prefs) : super(_prefs.getBool(_key) ?? false);

  void set(bool enabled) {
    state = enabled;
    _prefs.setBool(_key, enabled);
  }
}
