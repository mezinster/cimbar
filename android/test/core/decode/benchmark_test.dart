import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  test('1080p scene: stage timings printed, loose desktop bound', () {
    final frame = loadGoldenFrame('lorem_12k', 3);
    final truth = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json')).frames[3].data;
    // 1920x1080 scene, barcode ~790 px wide (scale 1.3), 15 deg rotation, mild
    // keystone. Rotated extent 790*(cos15+sin15) ~= 967 px < 1080, so the whole
    // barcode stays inside the canvas.
    final scene = renderScene(frame, 1920, 1080, SceneSpec()..scale = 1.3..rotationDeg = 15..keystone = 0.05..centerX = 960..centerY = 540);
    final yuv = rgbToYuv420(scene.image, semiPlanar: true);
    final decoder = FrameDecoder();
    // Warm up both the RGB conversion and the live-scan entry point itself:
    // decodeYuv420 is what the camera path actually calls (Y-plane locate,
    // then RGB conversion of the ROI only), so that is what we time.
    RgbBuffer.fromYuv420(yuv);
    decoder.decodeYuv420(yuv);
    final sw = Stopwatch()..start();
    final r = decoder.decodeYuv420(yuv);
    final total = sw.elapsedMilliseconds;
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, truth);
    final d = r.diag.toMap();
    final line = 'benchmark totalMs=$total locateMs=${d['locateMs']} roiMs=${d['roiMs']} sampleMs=${d['sampleMs']} driftMs=${d['driftMs']} rsMs=${d['rsMs']}';
    stdout.writeln(line);
    Directory('build').createSync(recursive: true);
    File('build/benchmark.txt').writeAsStringSync('$line\n');
    // Loose desktop JIT bound: catches order-of-magnitude regressions only.
    expect(total, lessThan(1500), reason: line);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
