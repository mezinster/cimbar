import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';
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
      for (var i = 0; i < want.length; i++) if (res.cells![i] != want[i]) wrong++;
      // Same tolerance as the JS-side fixture test: a little per-cell noise
      // from degradation (blur, noise, etc.) is expected and is what these
      // fixtures are meant to exercise -- RS is what must correct it cleanly.
      expect(wrong / want.length, lessThan(0.01),
          reason: '${side['name']}: $wrong of ${want.length} cells wrong (>1%)');
      expect(res.diag.rsFailed, 0,
          reason: '${side['name']}: RS reported ${res.diag.rsFailed} failed block(s) ($wrong of ${want.length} cells wrong)');
    }
  });
}
