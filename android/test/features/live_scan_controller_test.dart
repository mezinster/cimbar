import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/services/capture_policy.dart';
import 'package:cimbar_scanner/core/services/decode_isolate.dart';
import 'package:cimbar_scanner/features/camera/live_scan_controller.dart';

/// Device-free tests for the live-scan state machine: no camera, no isolate
/// (never call startScan) — outcomes are fed straight in.
void main() {
  /// Four finder corners of a plausibly-placed barcode (tl, tr, bl, br).
  Float64List quad() => Float64List.fromList([200, 200, 600, 200, 200, 600, 600, 600]);

  FrameOutcome outcome({
    required DecodeStatus status,
    Uint8List? data,
    Float64List? corners,
    double module = 12,
    int? seq,
    int? total,
  }) =>
      FrameOutcome(
        status: status,
        data: data,
        blocksFailed: 0,
        seq: seq,
        total: total,
        corners: corners,
        module: module,
        roi: corners == null ? null : const [100, 100, 600, 600],
        diag: const {},
        totalMs: 20,
        width: 1280,
        height: 720,
      );

  late Uint8List frameData;

  setUpAll(() {
    frameData = GoldenSidecar.load('../test-data/goldens/hello.json').frames[0].data;
    expect(frameData.length, 2112);
  });

  test('an ok outcome fills its sequence slot and completes the file', () {
    final c = LiveScanController();
    c.onOutcomeForTest(outcome(status: DecodeStatus.ok, data: frameData, corners: quad()));
    expect(c.state.filled, 1);
    expect(c.state.total, 1);
    expect(c.state.isComplete, isTrue);
    expect(c.state.framesAnalyzed, 1);
    expect(c.state.corners, isNotNull);
    c.dispose();
  });

  test('a notLocated outcome clears the corners and reports no hint', () {
    final c = LiveScanController();
    c.onOutcomeForTest(outcome(status: DecodeStatus.ok, data: frameData, corners: quad()));
    expect(c.state.corners, isNotNull);
    c.onOutcomeForTest(outcome(status: DecodeStatus.notLocated));
    expect(c.state.corners, isNull);
    expect(c.state.hint, ScanHint.none);
    c.dispose();
  });

  test('three consecutive isolate errors surface, and an outcome clears them', () {
    final c = LiveScanController();
    c.onIsolateErrorForTest('boom');
    expect(c.state.errorMessage, isNull);
    c.onIsolateErrorForTest('boom');
    expect(c.state.errorMessage, isNull);
    c.onIsolateErrorForTest('boom');
    expect(c.state.errorMessage, startsWith('decoder_failed:'));
    // The panel is stale as soon as a frame comes back.
    c.onOutcomeForTest(outcome(status: DecodeStatus.ok, data: frameData, corners: quad()));
    expect(c.state.errorMessage, isNull);
    c.dispose();
  });

  test('normal teardown errors are ignored, not counted', () {
    final c = LiveScanController();
    for (var i = 0; i < 5; i++) {
      c.onIsolateErrorForTest(StateError('DecodeIsolate disposed'));
    }
    expect(c.state.errorMessage, isNull);
    c.dispose();
  });

  test('the first located outcome asks for a focus/exposure lock once', () {
    final c = LiveScanController();
    expect(c.state.pendingLock, LockAction.none);
    c.onOutcomeForTest(outcome(status: DecodeStatus.ok, data: frameData, corners: quad()));
    expect(c.state.pendingLock, LockAction.lock);
    c.consumeLockAction();
    expect(c.state.pendingLock, LockAction.none);
    // Already locked: a second located frame does not ask again.
    c.onOutcomeForTest(outcome(status: DecodeStatus.ok, data: frameData, corners: quad()));
    expect(c.state.pendingLock, LockAction.none);
    c.dispose();
  });
}
