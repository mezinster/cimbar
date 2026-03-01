import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/decode_tuning_config.dart';
import 'shared_preferences_provider.dart';

final decodeTuningProvider =
    StateNotifierProvider<DecodeTuningNotifier, DecodeTuningConfig>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DecodeTuningNotifier(prefs);
});

class DecodeTuningNotifier extends StateNotifier<DecodeTuningConfig> {
  final dynamic _prefs; // SharedPreferences

  DecodeTuningNotifier(this._prefs)
      : super(DecodeTuningConfig.fromPrefs(_prefs));

  void setSymbolThreshold(double value) {
    state = state.copyWith(symbolThreshold: value);
    state.toPrefs(_prefs);
  }

  void setEnableWhiteBalance(bool value) {
    state = state.copyWith(enableWhiteBalance: value);
    state.toPrefs(_prefs);
  }

  void setUseRelativeColor(bool value) {
    state = state.copyWith(useRelativeColor: value);
    state.toPrefs(_prefs);
  }

  void setQuadrantOffset(double value) {
    state = state.copyWith(quadrantOffset: value);
    state.toPrefs(_prefs);
  }

  void setUseHashDetection(bool value) {
    state = state.copyWith(useHashDetection: value);
    state.toPrefs(_prefs);
  }

  void setDebugModeEnabled(bool value) {
    state = state.copyWith(debugModeEnabled: value);
    state.toPrefs(_prefs);
  }

  void resetDefaults() {
    state = const DecodeTuningConfig();
    state.toPrefs(_prefs);
  }
}
