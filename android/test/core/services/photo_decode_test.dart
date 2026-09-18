import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/photo_decoder.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

Uint8List pngOf(RgbBuffer b) {
  final im = img.Image(width: b.width, height: b.height);
  var i = 0;
  for (var y = 0; y < b.height; y++) {
    for (var x = 0; x < b.width; x++) {
      im.setPixelRgb(x, y, b.rgb[i], b.rgb[i + 1], b.rgb[i + 2]);
      i += 3;
    }
  }
  return img.encodePng(im);
}

void main() {
  test('single-frame golden photo decodes to the file', () async {
    final golden = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));
    final scene = renderScene(loadGoldenFrame('hello', 0), 1000, 1000, SceneSpec()..scale = 1.3..rotationDeg = 5..centerX = 500..centerY = 500);
    final r = await decodePhotoBytes(pngOf(scene.image), '');
    expect(r.error, isNull, reason: '${r.diag}');
    expect(r.result!.filename, golden.fileName);
    expect(r.result!.data, golden.fileBytes);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a frame of a multi-frame file reports multiFrame with the total', () async {
    final scene = renderScene(loadGoldenFrame('lorem_12k', 2), 1000, 1000, SceneSpec()..scale = 1.3..centerX = 500..centerY = 500);
    final r = await decodePhotoBytes(pngOf(scene.image), '');
    expect(r.result, isNull);
    expect(r.total, 6);
    expect(r.error, contains('6'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a repair frame of a coded multi-frame file reports multiFrame with the total', () async {
    final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_coded.json'));
    final scene = renderScene(
      loadGoldenFrame('lorem_coded', golden.sourceFrames),
      1000,
      1000,
      SceneSpec()
        ..scale = 1.3
        ..centerX = 500
        ..centerY = 500,
    );
    final r = await decodePhotoBytes(pngOf(scene.image), '');
    expect(r.result, isNull);
    expect(r.total, golden.sourceFrames);
    expect(r.errorCode, 'multi_frame');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('no barcode → error', () async {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_b.png');
    final r = await decodePhotoBytes(pngOf(photo), '');
    expect(r.result, isNull);
    expect(r.error, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
