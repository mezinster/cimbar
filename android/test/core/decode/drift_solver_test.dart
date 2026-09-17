import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/cell_classifier.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/drift_solver.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

/// Exact grid shifted by a constant source-pixel offset: every cell should
/// resolve to drift == (−ox, −oy) relative to the model.
class ShiftedExactGrid extends GridModel {
  final double ox, oy;
  const ShiftedExactGrid(this.ox, this.oy);
  @override
  (double, double) toSource(double cx, double cy) {
    final (x, y) = const ExactGridModel().toSource(cx, cy);
    return (x + ox, y + oy);
  }
}

void main() {
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json'));
  final frame = loadGoldenFrame('lorem_12k', 1);
  final truth = golden.frames[1].data;

  test('exact frame: drift stays at zero', () {
    final luma = LumaPlane.fromRgb(frame);
    final f = DriftSolver(CellSampler(frame, const ExactGridModel(), luma: luma), CellClassifier()).solve();
    expect(f.maxAbs, lessThanOrEqualTo(0.0));
    expect(f.widened, 0);
  });

  test('a grid model that is off by (2, -1) px is corrected by the solver', () {
    final luma = LumaPlane.fromRgb(frame);
    final f = DriftSolver(CellSampler(frame, const ShiftedExactGrid(2, -1), luma: luma), CellClassifier()).solve();
    expect(f.meanAbs, closeTo(1.5, 0.3)); // mean of |dx|=2 and |dy|=1
    const k = 32 * 64 + 32;
    expect(f.dx[k], closeTo(-2, 0.01));
    expect(f.dy[k], closeTo(1, 0.01));
    final r = FrameDecoder().decodeWithGrid(frame, const ShiftedExactGrid(2, -1), useDrift: true, luma: luma);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, truth);
    expect(r.diag.driftUsed, isTrue);
  });

  test('barrel distortion the homography cannot model: drift recovers the frame', () {
    final spec = SceneSpec()
      ..scale = 1.8
      ..barrelK = 0.02
      ..centerX = 750
      ..centerY = 750;
    final scene = renderScene(frame, 1500, 1500, spec);
    final off = FrameDecoder().decode(scene.image, useDrift: false);
    final on = FrameDecoder().decode(scene.image, useDrift: true);
    expect(on.status, DecodeStatus.ok, reason: 'with drift: ${on.diag.toMap()}');
    expect(on.data, truth);
    expect(on.diag.driftMeanAbs, greaterThan(0.3), reason: 'drift should be non-trivial here');
    // Document the effect: without drift the frame should be worse (more hamming), whatever its status.
    expect(off.diag.hammingMean, greaterThan(on.diag.hammingMean));
  });

  test('camera path with drift on all Task 5 geometries still decodes', () {
    for (final spec in [
      SceneSpec()..scale = 1.5,
      SceneSpec()..scale = 2.2..rotationDeg = 200,
      SceneSpec()..scale = 1.8..keystone = 0.12..rotationDeg = 8,
    ]) {
      final size = (608 * spec.scale * 1.5).ceil(); // room for any rotation
      spec
        ..centerX = size / 2
        ..centerY = size / 2;
      final scene = renderScene(frame, size, size, spec);
      final r = FrameDecoder().decode(scene.image);
      expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
      expect(r.data, truth);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('timing report (not asserted)', () {
    final scene = renderScene(frame, 1500, 1500, SceneSpec()..scale = 1.8..centerX = 750..centerY = 750);
    final r = FrameDecoder().decode(scene.image);
    // Visible with --verbose in the JSON reporter; kept as a data point for Plan 4.
    expect(r.diag.toMap()['driftMs'], isNotNull);
    expect(Uint8List(0), isEmpty);
  });
}
