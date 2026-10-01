import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

abstract class ScreenControls {
  Future<void> keepAwake(bool on);
  Future<void> maxBrightness();
  Future<void> restoreBrightness();
}

/// App-level only: screen_brightness changes this window's brightness, not the
/// system setting, so no WRITE_SETTINGS permission is involved.
class PluginScreenControls implements ScreenControls {
  const PluginScreenControls();
  @override
  Future<void> keepAwake(bool on) => on ? WakelockPlus.enable() : WakelockPlus.disable();
  @override
  Future<void> maxBrightness() => ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
  @override
  Future<void> restoreBrightness() => ScreenBrightness.instance.resetApplicationScreenBrightness();
}
