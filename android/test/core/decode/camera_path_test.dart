import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json'));
  final frame = loadGoldenFrame('lorem_12k', 2);
  final truth = golden.frames[2].data;

  void expectDecodes(Scene scene, String label) {
    final r = FrameDecoder().decode(scene.image, useDrift: false);
    expect(r.status, DecodeStatus.ok, reason: '$label: ${r.diag.toMap()}');
    expect(r.data, truth, reason: '$label data');
    expect(r.header!.seq, 2);
  }

  test('scale 1.5, 2.0, 2.5 unrotated', () {
    for (final s in [1.5, 2.0, 2.5]) {
      final size = (608 * s + 200).ceil();
      expectDecodes(renderScene(frame, size, size, SceneSpec()..scale = s..centerX = size / 2..centerY = size / 2), 'scale $s');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rotations 37, 90, 180, 271 at scale 1.8', () {
    for (final rot in [37.0, 90.0, 180.0, 271.0]) {
      // 1094 px side rotated 37° needs a 1548 px bounding box: use 1700.
      expectDecodes(renderScene(frame, 1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = rot..centerX = 850..centerY = 850), 'rot $rot');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('keystone 0.12 (about 20 degrees of tilt) at scale 1.8', () {
    expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 1.8..keystone = 0.12..rotationDeg = 8..centerX = 750..centerY = 750), 'keystone');
  });

  test('blur sigma 1.5 source px (3 px at scale 2)', () {
    expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 2..blurSigma = 3..centerX = 750..centerY = 750), 'blur');
  });

  test('brightness 0.7 and 1.3', () {
    for (final b in [0.7, 1.3]) {
      expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 2..brightness = b..centerX = 750..centerY = 750), 'brightness $b');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('noise sigma 8', () {
    expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 2..noiseSigma = 8..centerX = 750..centerY = 750), 'noise');
  });

  test('combined mild degradation', () {
    final spec = SceneSpec()
      ..scale = 1.7
      ..rotationDeg = 12
      ..keystone = 0.1
      ..blurSigma = 1.4
      ..brightness = 0.85
      ..noiseSigma = 5
      ..centerX = 700
      ..centerY = 700;
    expectDecodes(renderScene(frame, 1400, 1400, spec), 'combined');
  });

  test('composited on a real photo at scale 1.0', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_a.png');
    expectDecodes(renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360, background: photo), 'photo background');
  });

  test('photo without barcode is notLocated with locate diagnostics', () {
    final r = FrameDecoder().decode(loadPhoto('test/fixtures/camera_raw_1280x720_b.png'));
    expect(r.status, DecodeStatus.notLocated);
    expect(r.diag.locateRan, isTrue);
    expect(r.diag.locateFail, isNotEmpty);
    expect(r.diag.toMap().containsKey('locateMs'), isTrue);
  });
}
