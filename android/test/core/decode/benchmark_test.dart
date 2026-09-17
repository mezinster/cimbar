import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  test('1080p-class scene: stage timings printed, loose desktop bound', () {
    final frame = loadGoldenFrame('lorem_12k', 3);
    final truth = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json')).frames[3].data;
    // 1280x960 scene, barcode ~850 px wide (scale 1.4), 15° rotation, mild keystone
    final scene = renderScene(frame, 1280, 960, SceneSpec()..scale = 1.4..rotationDeg = 15..keystone = 0.05..centerX = 640..centerY = 480);
    final yuv = rgbToYuv420(scene.image, semiPlanar: true);
    final decoder = FrameDecoder();
    // warm-up
    decoder.decode(RgbBuffer.fromYuv420(yuv));
    final sw = Stopwatch()..start();
    final r = decoder.decode(RgbBuffer.fromYuv420(yuv));
    final total = sw.elapsedMilliseconds;
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, truth);
    final d = r.diag.toMap();
    final line = 'benchmark totalMs=$total locateMs=${d['locateMs']} sampleMs=${d['sampleMs']} driftMs=${d['driftMs']} rsMs=${d['rsMs']}';
    stdout.writeln(line);
    Directory('build').createSync(recursive: true);
    File('build/benchmark.txt').writeAsStringSync('$line\n');
    // Loose desktop JIT bound: catches order-of-magnitude regressions only.
    expect(total, lessThan(1500), reason: line);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
