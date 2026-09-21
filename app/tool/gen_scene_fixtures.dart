// Renders the degradation matrix used by camera_path_test.dart to PNG +
// ground-truth JSON, so the JS port can be tested against the same pixels.
// Test-only: ships in neither APK. Usage: dart run tool/gen_scene_fixtures.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../test/test_utils/synthetic_scene.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/finder_locator.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
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
  // blurSigma = 2 matches camera_path_test.dart's known-good blur case
  // exactly. It leaves a handful of the 3840 cells misclassified before RS
  // correction (RS still recovers the frame cleanly) -- the fixture test
  // tolerates a small fraction of raw-cell mismatches for exactly this
  // reason (see scene_fixtures_test.dart) rather than requiring zero, so the
  // "blur" case stays a real blur test instead of a trivial one.
  'blur_s20':     Case(1600, 1600, SceneSpec()..scale = 2.0..blurSigma = 2..centerX = 800..centerY = 800),
  'dim_s15':      Case(1500, 1500, SceneSpec()..scale = 1.5..brightness = 0.7..centerX = 750..centerY = 750),
  // 1100x1100 (not the full 1500 the other scale-1.5 case uses): noise is
  // applied to the whole canvas buffer and is incompressible, so the empty
  // margin around the 912px barcode was pure PNG weight (this fixture alone
  // was 4.2 of the fixture set's 7.2 MB). 1100 leaves ~94px (~7 modules) of
  // margin per side -- comfortably above the decoder's 4.5-module ROI
  // assumption -- while cutting canvas area to 54% of the original.
  'noise_s15':    Case(1100, 1100, SceneSpec()..scale = 1.5..noiseSigma = 8..seed = 7..centerX = 550..centerY = 550),
};

/// Runs the Dart FinderLocator over the fixture's committed pixels and
/// records what it found. This is the Dart<->JS parity contract: the web
/// app's `web-app/finder-locator.js` is a transliteration of
/// `lib/core/decode/finder_locator.dart`, and both test suites assert against
/// these exact numbers, so either side drifting shows up as a test failure
/// instead of silently diverging. It is deliberately a record of the DETECTED
/// geometry, not the analytic `finderCenters` ground truth next to it -- the
/// two answer different questions ("is the locator good?" vs. "do the two
/// locators agree?").
Map<String, dynamic> locateRecord(RgbBuffer buffer) {
  final r = const FinderLocator().locate(LumaPlane.fromRgb(buffer));
  if (!r.ok) throw StateError('locator failed on a fixture: ${r.failReason}');
  List<double> pt(Finder f) => [f.x, f.y];
  return {
    'candidates': r.candidates,
    'clusters': r.clusters,
    'module': r.module,
    'devNorm': r.devNorm,
    'tlLuma': r.tlLuma,
    'secondLuma': r.secondLuma,
    'corners': {
      'tl': pt(r.tl!), 'tr': pt(r.tr!), 'bl': pt(r.bl!), 'br': pt(r.br!),
    },
  };
}

/// Runs the full Dart camera path (`FrameDecoder.decode`: locate ->
/// homography -> grid gate -> white point -> drift -> sample/classify -> RS)
/// over the fixture's committed pixels and records the outcome. Where
/// `locateRecord` pins the Dart <-> JS contract at the *locate* stage, this
/// pins it end to end: the drift field, the white point and the classifier
/// wiring could all diverge between the two ports with both suites still
/// green if the only shared assertion were "fewer than 1% of cells wrong".
/// `wrong`/`wrongIndices` are measured against the `cells` ground truth, and
/// both suites assert the exact index set -- 1% of 3840 is 38 cells, which
/// fits inside RS's 32-byte-per-block correction budget, so a real regression
/// (a transposed drift index, a sign flip on dx/dy) would otherwise stay
/// invisible.
Map<String, dynamic> decodeRecord(RgbBuffer buffer, List<int> truth) {
  final r = FrameDecoder().decode(buffer);
  if (r.status != DecodeStatus.ok) {
    throw StateError('camera path failed on a fixture: ${r.status} ${r.diag.note}');
  }
  final cells = r.cells!;
  if (cells.length != truth.length) {
    throw StateError('cell count ${cells.length} != truth ${truth.length}');
  }
  final wrong = <int>[];
  for (var i = 0; i < truth.length; i++) {
    if (cells[i] != truth[i]) wrong.add(i);
  }
  return {
    'wrong': wrong.length,
    'wrongIndices': wrong,
    'blocksFailed': r.diag.rsFailed,
    'hammingMean': r.diag.hammingMean,
    'hammingMax': r.diag.hammingMax,
    'driftMeanAbs': r.diag.driftMeanAbs,
    'driftMaxAbs': r.diag.driftMaxAbs,
  };
}

List<int> goldenCells(String name, int index) {
  final m = jsonDecode(File('../test-data/goldens/$name.json').readAsStringSync()) as Map<String, dynamic>;
  return ((m['frames'] as List)[index] as Map<String, dynamic>)['cells'].cast<int>();
}

void main() {
  final out = Directory('../test-data/scenes')..createSync(recursive: true);
  for (final e in cases.entries) {
    final frame = loadGoldenFrame('hello', 0);
    final scene = renderScene(frame, e.value.w, e.value.h, e.value.spec);
    final png = _pngOf(scene.image);
    File('${out.path}/${e.key}.png').writeAsBytesSync(png);
    // Locate through the PNG round trip, not `scene.image`: the recorded
    // numbers must describe the bytes that are committed and that both test
    // suites read back, not an in-memory buffer nobody else sees.
    final decoded = RgbBuffer.fromImage(img.decodePng(png)!);
    final cells = goldenCells('hello', 0);
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
      'locate': locateRecord(decoded),
      'decode': decodeRecord(decoded, cells),
      'cells': cells,
    }));
    stdout.writeln('wrote ${e.key}.png + .json');
  }
}
