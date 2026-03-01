import 'package:shared_preferences/shared_preferences.dart';

/// Immutable configuration for camera decode tuning parameters.
///
/// All values have sensible defaults for camera scanning. The GIF decode path
/// ignores these (it uses null/default params in decodeFramePixels).
class DecodeTuningConfig {
  final double symbolThreshold;
  final bool enableWhiteBalance;
  final bool useRelativeColor;
  final double quadrantOffset;
  final bool useHashDetection;
  final bool debugModeEnabled;

  const DecodeTuningConfig({
    this.symbolThreshold = 0.85,
    this.enableWhiteBalance = true,
    this.useRelativeColor = true,
    this.quadrantOffset = 0.28,
    this.useHashDetection = true,
    this.debugModeEnabled = false,
  });

  DecodeTuningConfig copyWith({
    double? symbolThreshold,
    bool? enableWhiteBalance,
    bool? useRelativeColor,
    double? quadrantOffset,
    bool? useHashDetection,
    bool? debugModeEnabled,
  }) {
    return DecodeTuningConfig(
      symbolThreshold: symbolThreshold ?? this.symbolThreshold,
      enableWhiteBalance: enableWhiteBalance ?? this.enableWhiteBalance,
      useRelativeColor: useRelativeColor ?? this.useRelativeColor,
      quadrantOffset: quadrantOffset ?? this.quadrantOffset,
      useHashDetection: useHashDetection ?? this.useHashDetection,
      debugModeEnabled: debugModeEnabled ?? this.debugModeEnabled,
    );
  }

  static const _keySymbolThreshold = 'tuning_symbol_threshold';
  static const _keyWhiteBalance = 'tuning_white_balance';
  static const _keyRelativeColor = 'tuning_relative_color';
  static const _keyQuadrantOffset = 'tuning_quadrant_offset';
  static const _keyHashDetection = 'tuning_hash_detection';
  static const _keyDebugMode = 'tuning_debug_mode';

  void toPrefs(SharedPreferences prefs) {
    prefs.setDouble(_keySymbolThreshold, symbolThreshold);
    prefs.setBool(_keyWhiteBalance, enableWhiteBalance);
    prefs.setBool(_keyRelativeColor, useRelativeColor);
    prefs.setDouble(_keyQuadrantOffset, quadrantOffset);
    prefs.setBool(_keyHashDetection, useHashDetection);
    prefs.setBool(_keyDebugMode, debugModeEnabled);
  }

  static DecodeTuningConfig fromPrefs(SharedPreferences prefs) {
    return DecodeTuningConfig(
      symbolThreshold: prefs.getDouble(_keySymbolThreshold) ?? 0.85,
      enableWhiteBalance: prefs.getBool(_keyWhiteBalance) ?? true,
      useRelativeColor: prefs.getBool(_keyRelativeColor) ?? true,
      quadrantOffset: prefs.getDouble(_keyQuadrantOffset) ?? 0.28,
      useHashDetection: prefs.getBool(_keyHashDetection) ?? true,
      debugModeEnabled: prefs.getBool(_keyDebugMode) ?? false,
    );
  }
}
