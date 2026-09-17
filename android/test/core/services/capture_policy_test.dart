import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/services/capture_policy.dart';
import 'package:cimbar_scanner/core/services/decode_isolate.dart';

FrameOutcome outcome(DecodeStatus s, {double module = 12, double ox = 0}) => FrameOutcome(
      status: s,
      data: null,
      blocksFailed: s == DecodeStatus.rsFailed ? 3 : 0,
      corners: s == DecodeStatus.notLocated ? null : Float64List.fromList([100 + ox, 100, 700 + ox, 100, 100 + ox, 700, 700 + ox, 700]),
      module: module,
      roi: null,
      diag: const {},
      totalMs: 10,
      width: 1280,
      height: 720,
    );

void main() {
  test('locks after the first located frame, unlocks 2 s after losing it', () {
    final p = CapturePolicy();
    expect(p.update(outcome(DecodeStatus.notLocated), 0).$2, LockAction.none);
    expect(p.update(outcome(DecodeStatus.rsFailed), 100).$2, LockAction.lock);
    expect(p.locked, isTrue);
    expect(p.update(outcome(DecodeStatus.ok), 300).$2, LockAction.none);
    expect(p.update(outcome(DecodeStatus.notLocated), 1000).$2, LockAction.none);
    expect(p.update(outcome(DecodeStatus.notLocated), 2400).$2, LockAction.unlock);
    expect(p.locked, isFalse);
  });

  test('hints from module size, motion and rsFailed', () {
    final p = CapturePolicy();
    expect(p.update(outcome(DecodeStatus.ok, module: 4), 0).$1, ScanHint.moveCloser);
    expect(p.update(outcome(DecodeStatus.ok, module: 50), 100).$1, ScanHint.moveBack);
    expect(p.update(outcome(DecodeStatus.ok, module: 12), 200).$1, ScanHint.none);
    expect(p.update(outcome(DecodeStatus.ok, module: 12, ox: 25), 300).$1, ScanHint.holdStill);
    expect(p.update(outcome(DecodeStatus.rsFailed, module: 12, ox: 25), 400).$1, ScanHint.adjustAngle);
    expect(p.update(outcome(DecodeStatus.notLocated), 500).$1, ScanHint.none);
  });
}
