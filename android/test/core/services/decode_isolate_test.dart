import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/services/decode_isolate.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  test('spawn, decode two frames sequentially, busy flag, dispose', () async {
    final frame = loadGoldenFrame('hello', 0);
    final truth = GoldenSidecar.load(repoPath('test-data/goldens/hello.json')).frames[0].data;
    final scene = renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360);
    final yuv = rgbToYuv420(scene.image, semiPlanar: true);
    final iso = await DecodeIsolate.spawn();
    expect(iso.busy, isFalse);
    final f = iso.decode(FrameJob(frame: yuv, useDrift: true, capture: true));
    expect(iso.busy, isTrue);
    expect(() => iso.decode(FrameJob(frame: yuv, useDrift: true)), throwsStateError);
    final o = await f;
    expect(iso.busy, isFalse);
    expect(o.status, DecodeStatus.ok, reason: '${o.diag}');
    expect(o.data, truth);
    expect(o.seq, 0);
    expect(o.total, 1);
    expect(o.corners!.length, 8);
    expect(o.capturePng, isNotNull);
    expect(o.capturePng![0], 0x89); // PNG magic
    final o2 = await iso.decode(FrameJob(frame: yuv, useDrift: false, hint: RoiHint(o.roi![0], o.roi![1], o.roi![2], o.roi![3])));
    expect(o2.status, DecodeStatus.ok);
    iso.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
