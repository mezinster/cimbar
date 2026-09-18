import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/frame_header.dart';
import 'package:cimbar_scanner/core/format/rateless.dart';

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

  // Worst-case v2.1 elimination: N repair rows and no source row, so every row
  // is dense and has to be eliminated against every pivot before it. Bodies are
  // 64 meaningful bytes zero-padded to the real frame body length — the cost is
  // dominated by the O(N^3) coefficient work, not by the bodies.
  //
  // N is 2048, not the spec's 4096-frame ceiling: the work is cubic, and 4096
  // measures ~4 min here (2048 ~30 s), which is too slow for every suite run.
  // The per-row bound below is what guards the ceiling case.
  test('rateless elimination: N repair rows only, timing printed, loose desktop bound', () {
    const n = 2048;
    const short = 64;
    const fileId = 0x4096;
    Uint8List lcg(int len, int seed) {
      final b = Uint8List(len);
      var s = seed & 0xFFFFFFFF;
      for (var i = 0; i < len; i++) {
        s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
        b[i] = s >> 24;
      }
      return b;
    }

    final bodies = [for (var i = 0; i < n; i++) lcg(short, 1000 + i)];
    final frames = <Uint8List>[];
    for (var r = 0; r < n; r++) {
      final f = Uint8List(CimbarSpec.dataBytesPerFrame);
      f.setRange(0, CimbarSpec.headerLen,
          FrameHeader(version: 2, encrypted: false, repair: true, fileId: fileId, seq: r, total: n).encode());
      f.setRange(CimbarSpec.headerLen, CimbarSpec.headerLen + short,
          Rateless.combine(bodies, Rateless.coefficients(fileId, r, n)));
      frames.add(f);
    }

    final asm = RatelessAssembler();
    final sw = Stopwatch()..start();
    for (final f in frames) {
      asm.add(f);
    }
    expect(asm.isComplete, isTrue, reason: 'rank ${asm.rank}/${asm.total}');
    final out = asm.framedData();
    final total = sw.elapsedMilliseconds;

    for (var i = 0; i < n; i++) {
      expect(out.sublist(i * CimbarSpec.fileBytesPerFrame, i * CimbarSpec.fileBytesPerFrame + short), bodies[i],
          reason: 'source body $i');
    }
    final line = 'elimination N=$n totalMs=$total perRowMs=${(total / n).toStringAsFixed(3)}';
    stdout.writeln(line);
    Directory('build').createSync(recursive: true);
    File('build/benchmark.txt').writeAsStringSync('$line\n', mode: FileMode.append);
    // Loose desktop JIT bound: catches order-of-magnitude regressions only.
    expect(total / n, lessThan(100), reason: line);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
