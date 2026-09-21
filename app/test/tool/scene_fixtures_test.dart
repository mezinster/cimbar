import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/finder_locator.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:image/image.dart' as img;

void main() {
  final dir = Directory('../test-data/scenes');

  test('scene fixtures exist and every PNG has a sidecar', () {
    expect(dir.existsSync(), isTrue, reason: 'run: dart run tool/gen_scene_fixtures.dart');
    final pngs = dir.listSync().where((f) => f.path.endsWith('.png')).toList();
    expect(pngs.length, greaterThanOrEqualTo(8));
    for (final p in pngs) {
      expect(File(p.path.replaceAll('.png', '.json')).existsSync(), isTrue, reason: p.path);
    }
  });

  test('each fixture decodes to its recorded cells through its recorded geometry', () {
    for (final f in dir.listSync().where((f) => f.path.endsWith('.json'))) {
      final side = jsonDecode(File(f.path).readAsStringSync()) as Map<String, dynamic>;
      final image = img.decodeImage(File(f.path.replaceAll('.json', '.png')).readAsBytesSync())!;
      final c = side['finderCenters'] as Map<String, dynamic>;
      (double, double) pt(String k) => ((c[k][0] as num).toDouble(), (c[k][1] as num).toDouble());
      final grid = HomographyGridModel.fromFinders(tl: pt('tl'), tr: pt('tr'), bl: pt('bl'), br: pt('br'));
      expect(grid, isNotNull, reason: side['name'] as String);
      final res = FrameDecoder().decodeWithGrid(RgbBuffer.fromImage(image), grid!);
      final want = (side['cells'] as List).cast<int>();
      expect(res.cells!.length, want.length, reason: side['name'] as String);
      var wrong = 0;
      for (var i = 0; i < want.length; i++) {
        if (res.cells![i] != want[i]) wrong++;
      }
      // Same tolerance as the JS-side fixture test: a little per-cell noise
      // from degradation (blur, noise, etc.) is expected and is what these
      // fixtures are meant to exercise -- RS is what must correct it cleanly.
      expect(wrong / want.length, lessThan(0.01),
          reason: '${side['name']}: $wrong of ${want.length} cells wrong (>1%)');
      expect(res.diag.rsFailed, 0,
          reason: '${side['name']}: RS reported ${res.diag.rsFailed} failed block(s) ($wrong of ${want.length} cells wrong)');
    }
  });

  // The `decode` block records what THIS decoder's full camera path
  // (FrameDecoder.decode) produced from these exact pixels, as an exact
  // wrong-cell index set against the `cells` ground truth plus the hamming
  // and drift diagnostics. web-app/tests/test_photo_decode.js asserts the
  // same block, so it is the Dart <-> JS parity contract for everything
  // BELOW the locator -- homography, white point, drift field, sampler and
  // classifier -- which the `locate` block alone cannot pin. An index set
  // rather than a percentage: 1% of 3840 is 38 cells, inside RS's
  // 32-byte-per-block budget, so a genuine divergence would still decode.
  // This test is the other half: it stops Dart drifting out from under the
  // recorded values, which would otherwise only surface as a JS failure.
  test('each fixture reproduces its recorded camera-path decode digest', () {
    for (final f in dir.listSync().where((f) => f.path.endsWith('.json'))) {
      final side = jsonDecode(File(f.path).readAsStringSync()) as Map<String, dynamic>;
      final name = side['name'] as String;
      final rec = side['decode'] as Map<String, dynamic>?;
      expect(rec, isNotNull,
          reason: '$name has no `decode` block -- rerun: dart run tool/gen_scene_fixtures.dart');
      final image = img.decodeImage(File(f.path.replaceAll('.json', '.png')).readAsBytesSync())!;
      final r = FrameDecoder().decode(RgbBuffer.fromImage(image));
      expect(r.status, DecodeStatus.ok, reason: '$name: ${r.diag.note}');
      final truth = (side['cells'] as List).cast<int>();
      expect(r.cells!.length, truth.length, reason: '$name cell count');
      final wrong = <int>[];
      for (var i = 0; i < truth.length; i++) {
        if (r.cells![i] != truth[i]) wrong.add(i);
      }
      expect(wrong.length, rec!['wrong'], reason: '$name wrong count ($wrong)');
      expect(wrong, (rec['wrongIndices'] as List).cast<int>(), reason: '$name wrong-cell index set');
      expect(r.diag.rsFailed, rec['blocksFailed'], reason: '$name blocksFailed');
      expect(r.diag.hammingMax, rec['hammingMax'], reason: '$name hammingMax');
      // The observed delta between the Dart and JS runtimes on these
      // fixtures is exactly 0; the epsilon only guards the last ulp.
      const eps = 1e-12;
      expect(r.diag.hammingMean, closeTo((rec['hammingMean'] as num).toDouble(), eps), reason: '$name hammingMean');
      expect(r.diag.driftMeanAbs, closeTo((rec['driftMeanAbs'] as num).toDouble(), eps), reason: '$name driftMeanAbs');
      expect(r.diag.driftMaxAbs, closeTo((rec['driftMaxAbs'] as num).toDouble(), eps), reason: '$name driftMaxAbs');
    }
  });

  // The `locate` block records what THIS locator found in these exact pixels
  // (written by tool/gen_scene_fixtures.dart). web-app/tests/test_finder_locator.js
  // asserts the same numbers, so the block is the Dart<->JS parity contract
  // for the transliterated web locator. This test is the other half of it: it
  // stops Dart drifting out from under the recorded values, which would
  // otherwise only surface as an unexplained JS failure.
  test('each fixture reproduces its recorded FinderLocator output', () {
    for (final f in dir.listSync().where((f) => f.path.endsWith('.json'))) {
      final side = jsonDecode(File(f.path).readAsStringSync()) as Map<String, dynamic>;
      final name = side['name'] as String;
      final rec = side['locate'] as Map<String, dynamic>?;
      expect(rec, isNotNull,
          reason: '$name has no `locate` block -- rerun: dart run tool/gen_scene_fixtures.dart');
      final image = img.decodeImage(File(f.path.replaceAll('.json', '.png')).readAsBytesSync())!;
      final r = const FinderLocator().locate(LumaPlane.fromRgb(RgbBuffer.fromImage(image)));
      expect(r.ok, isTrue, reason: '$name: ${r.failReason}');
      // Integer stage counters must match exactly -- they move long before a
      // centre does when a threshold or run rule changes.
      expect(r.candidates, rec!['candidates'], reason: '$name candidates');
      expect(r.clusters, rec['clusters'], reason: '$name clusters');
      const eps = 1e-9;
      expect(r.module, closeTo((rec['module'] as num).toDouble(), eps), reason: '$name module');
      expect(r.devNorm, closeTo((rec['devNorm'] as num).toDouble(), eps), reason: '$name devNorm');
      expect(r.tlLuma, closeTo((rec['tlLuma'] as num).toDouble(), eps), reason: '$name tlLuma');
      expect(r.secondLuma, closeTo((rec['secondLuma'] as num).toDouble(), eps), reason: '$name secondLuma');
      final corners = rec['corners'] as Map<String, dynamic>;
      final got = {'tl': r.tl!, 'tr': r.tr!, 'bl': r.bl!, 'br': r.br!};
      for (final k in const ['tl', 'tr', 'bl', 'br']) {
        expect(got[k]!.x, closeTo((corners[k][0] as num).toDouble(), eps), reason: '$name $k.x');
        expect(got[k]!.y, closeTo((corners[k][1] as num).toDouble(), eps), reason: '$name $k.y');
      }
    }
  });
}
