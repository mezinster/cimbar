import 'dart:math' as math;
import 'dart:typed_data';

import '../decode/diagnostics.dart';
import 'decode_isolate.dart';

enum ScanHint { none, moveCloser, moveBack, holdStill, adjustAngle }

enum LockAction { none, lock, unlock }

/// Camera acquisition policy (spec §8): lock focus/exposure once a barcode is
/// located, unlock after [unlockAfterMs] without one; derive a user hint from
/// the finder module size, corner motion and the decode status.
class CapturePolicy {
  final double minModulePx;
  final double maxModulePx;
  final double motionPx;
  final int unlockAfterMs;

  bool _locked = false;
  int? _lastLocatedMs;
  Float64List? _lastCorners;

  CapturePolicy({this.minModulePx = 6, this.maxModulePx = 40, this.motionPx = 10, this.unlockAfterMs = 2000});

  bool get locked => _locked;

  void reset() {
    _locked = false;
    _lastLocatedMs = null;
    _lastCorners = null;
  }

  (ScanHint, LockAction) update(FrameOutcome o, int nowMs) {
    final located = o.corners != null && (o.status == DecodeStatus.ok || o.status == DecodeStatus.rsFailed || o.status == DecodeStatus.badHeader || o.status == DecodeStatus.unsupportedGrid);
    var action = LockAction.none;
    var hint = ScanHint.none;
    if (located) {
      _lastLocatedMs = nowMs;
      if (!_locked) {
        _locked = true;
        action = LockAction.lock;
      }
      if (o.module < minModulePx) {
        hint = ScanHint.moveCloser;
      } else if (o.module > maxModulePx) {
        hint = ScanHint.moveBack;
      } else if (_lastCorners != null && _motion(_lastCorners!, o.corners!) > motionPx) {
        hint = ScanHint.holdStill;
      } else if (o.status == DecodeStatus.rsFailed) {
        hint = ScanHint.adjustAngle;
      }
      _lastCorners = o.corners;
    } else {
      _lastCorners = null;
      if (_locked && _lastLocatedMs != null && nowMs - _lastLocatedMs! >= unlockAfterMs) {
        _locked = false;
        action = LockAction.unlock;
      }
    }
    return (hint, action);
  }

  static double _motion(Float64List a, Float64List b) {
    var worst = 0.0;
    for (var i = 0; i < 8; i += 2) {
      final dx = a[i] - b[i], dy = a[i + 1] - b[i + 1];
      final d = dx * dx + dy * dy;
      if (d > worst) worst = d;
    }
    return worst == 0 ? 0 : math.sqrt(worst);
  }
}
