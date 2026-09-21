// Renders the degradation matrix used by camera_path_test.dart to PNG +
// ground-truth JSON, so the JS port can be tested against the same pixels.
// Test-only: ships in neither APK. Usage: dart run tool/gen_scene_fixtures.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../test/test_utils/synthetic_scene.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

// RgbBuffer is a flat RGB buffer, not an image/image `img.Image`; encodePng
// needs the latter. Same conversion as test/core/services/photo_decode_test.dart's
// pngOf helper.
Uint8List _pngOf(RgbBuffer b) {
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

// SceneSpec has NO named constructor -- it is default-constructed and mutated
// with cascade syntax, exactly as camera_path_test.dart does it.
// centerX/centerY default to 0, which would put the barcode at the canvas
// corner, so every case sets them. Canvas size is per case because a 608 px
// frame at scale 1.8 rotated 37 degrees spans ~1533 px and does not fit a
// 1080 px tall canvas; only the unrotated case is true 1080p (and it is the
// one the JS performance guard uses).
class Case {
  final int w, h;
  final SceneSpec spec;
  const Case(this.w, this.h, this.spec);
}

final cases = <String, Case>{
  'plain_s13':    Case(1920, 1080, SceneSpec()..scale = 1.3..centerX = 960..centerY = 540),
  'rot37_s18':    Case(1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = 37..centerX = 850..centerY = 850),
  'rot90_s18':    Case(1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = 90..centerX = 850..centerY = 850),
  'rot271_s18':   Case(1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = 271..centerX = 850..centerY = 850),
  'keystone_s16': Case(1600, 1600, SceneSpec()..scale = 1.6..keystone = 0.12..rotationDeg = 8..centerX = 800..centerY = 800),
  // blurSigma = 2 (camera_path_test.dart's value, right at its documented RS
  // tolerance edge) leaves 5 of 3840 cells misclassified before RS correction
  // -- fine for that test's RS-corrected-data assertion, but this fixture's
  // test compares raw per-cell values with no RS credit. 1.8 keeps the same
  // "blurred camera photo" degradation intent with a hair more margin, and
  // decodes to zero cell mismatches.
  'blur_s20':     Case(1600, 1600, SceneSpec()..scale = 2.0..blurSigma = 1.8..centerX = 800..centerY = 800),
  'dim_s15':      Case(1500, 1500, SceneSpec()..scale = 1.5..brightness = 0.7..centerX = 750..centerY = 750),
  'noise_s15':    Case(1500, 1500, SceneSpec()..scale = 1.5..noiseSigma = 8..seed = 7..centerX = 750..centerY = 750),
};

List<int> goldenCells(String name, int index) {
  final m = jsonDecode(File('../test-data/goldens/$name.json').readAsStringSync()) as Map<String, dynamic>;
  return ((m['frames'] as List)[index] as Map<String, dynamic>)['cells'].cast<int>();
}

void main() {
  final out = Directory('../test-data/scenes')..createSync(recursive: true);
  for (final e in cases.entries) {
    final frame = loadGoldenFrame('hello', 0);
    final scene = renderScene(frame, e.value.w, e.value.h, e.value.spec);
    File('${out.path}/${e.key}.png').writeAsBytesSync(_pngOf(scene.image));
    File('${out.path}/${e.key}.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'name': e.key,
      'golden': 'hello',
      'frameIndex': 0,
      'width': e.value.w,
      'height': e.value.h,
      'finderCenters': {
        'tl': [scene.finderCenters[0].$1, scene.finderCenters[0].$2],
        'tr': [scene.finderCenters[1].$1, scene.finderCenters[1].$2],
        'bl': [scene.finderCenters[2].$1, scene.finderCenters[2].$2],
        'br': [scene.finderCenters[3].$1, scene.finderCenters[3].$2],
      },
      'homography': scene.frameToScene.h.toList(),
      'cells': goldenCells('hello', 0),
    }));
    stdout.writeln('wrote ${e.key}.png + .json');
  }
}
