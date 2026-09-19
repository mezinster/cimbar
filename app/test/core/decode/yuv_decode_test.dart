import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/yuv_frame.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final frame = loadGoldenFrame('lorem_12k', 1);
  final truth = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json')).frames[1].data;
  final scene = renderScene(frame, 1280, 720, SceneSpec()..scale = 1.0..rotationDeg = 8..centerX = 700..centerY = 360);

  test('decodeYuv420: planar and semi-planar frames decode with an ROI', () {
    for (final semi in [false, true]) {
      final r = FrameDecoder().decodeYuv420(rgbToYuv420(scene.image, semiPlanar: semi, yPad: 32));
      expect(r.status, DecodeStatus.ok, reason: 'semi=$semi ${r.diag.toMap()}');
      expect(r.data, truth);
      final roi = r.diag.roi!;
      expect(roi[2], lessThan(1280), reason: 'ROI narrower than the frame');
      expect(roi[2], greaterThan(600));
      expect(r.diag.toMap()['roi'], isNotNull);
    }
  });

  test('a correct hint decodes; a wrong hint falls back to the full frame', () {
    final yuv = rgbToYuv420(scene.image);
    final base = FrameDecoder().decodeYuv420(yuv);
    final c = base.diag.corners!;
    final good = RoiHint((c[0] - 30).floor(), (c[1] - 30).floor(), 700, 700);
    final withGood = FrameDecoder().decodeYuv420(yuv, hint: good);
    expect(withGood.status, DecodeStatus.ok, reason: '${withGood.diag.toMap()}');
    expect(withGood.data, truth);
    expect(withGood.diag.corners![0], closeTo(c[0], 2.0));
    const bad = RoiHint(0, 0, 200, 200);
    final withBad = FrameDecoder().decodeYuv420(yuv, hint: bad);
    expect(withBad.status, DecodeStatus.ok, reason: '${withBad.diag.toMap()}');
    expect(withBad.data, truth);
  });

  test('a frame without a barcode is notLocated', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_b.png');
    final r = FrameDecoder().decodeYuv420(rgbToYuv420(photo));
    expect(r.status, DecodeStatus.notLocated);
  });
}
