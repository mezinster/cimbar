import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));
  final frame = loadGoldenFrame('hello', 0);

  test('scale 1 unrotated: finder centers land at offset + 47.5', () {
    final spec = SceneSpec()..centerX = 400..centerY = 400;
    final scene = renderScene(frame, 800, 800, spec);
    expect(scene.image.width, 800);
    expect(scene.finderCenters[0].$1, closeTo(96 + 47.5, 1e-6));
    expect(scene.finderCenters[0].$2, closeTo(96 + 47.5, 1e-6));
    expect(scene.finderCenters[3].$1, closeTo(96 + 560.5, 1e-6));
    // pixel at the frame's TL finder outer ring is white, quiet zone black
    expect(scene.image.r(96 + 16, 96 + 16), 255);
    expect(scene.image.r(96 + 2, 96 + 2), 0);
    expect(scene.image.r(10, 10), 0);
  });

  FrameDecoder decoder() => FrameDecoder();

  test('decodes with a grid built from the known finder centers (scale 1)', () {
    final scene = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    final gm = HomographyGridModel.fromFinders(
      tl: scene.finderCenters[0], tr: scene.finderCenters[1], bl: scene.finderCenters[2], br: scene.finderCenters[3],
    )!;
    final r = decoder().decodeWithGrid(scene.image, gm);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.diag.hammingMax, 0);
    expect(r.data, golden.frames[0].data);
  });

  test('scale 2.3, rotation 33°, keystone 0.15 decodes from known finders', () {
    final spec = SceneSpec()
      ..scale = 2.3
      ..rotationDeg = 33
      ..keystone = 0.15
      ..centerX = 900
      ..centerY = 900;
    final scene = renderScene(frame, 1800, 1800, spec);
    final gm = HomographyGridModel.fromFinders(
      tl: scene.finderCenters[0], tr: scene.finderCenters[1], bl: scene.finderCenters[2], br: scene.finderCenters[3],
    )!;
    final r = decoder().decodeWithGrid(scene.image, gm);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, golden.frames[0].data);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('blur 2.5 px + noise 8 + brightness 0.8 at scale 2.3 still decodes from known finders', () {
    final spec = SceneSpec()
      ..scale = 2.3
      ..blurSigma = 2.5
      ..noiseSigma = 8
      ..brightness = 0.8
      ..centerX = 800
      ..centerY = 800;
    final scene = renderScene(frame, 1600, 1600, spec);
    final gm = HomographyGridModel.fromFinders(
      tl: scene.finderCenters[0], tr: scene.finderCenters[1], bl: scene.finderCenters[2], br: scene.finderCenters[3],
    )!;
    final r = decoder().decodeWithGrid(scene.image, gm);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, golden.frames[0].data);
    expect(r.diag.hammingMax > 0, isTrue, reason: 'degradation should be visible in hamming');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('background composite keeps the photo outside the quad', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_a.png');
    final scene = renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360, background: photo);
    expect(scene.image.r(5, 5), photo.r(5, 5));
    expect(scene.image.g(5, 5), photo.g(5, 5));
  });
}
