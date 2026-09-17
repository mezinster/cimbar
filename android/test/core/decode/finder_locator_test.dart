import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/finder_locator.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

import '../../test_utils/synthetic_scene.dart';

void main() {
  final frame = loadGoldenFrame('lorem_12k', 2);
  const locator = FinderLocator();

  void expectCorners(LocateResult r, Scene scene, double tol) {
    expect(r.ok, isTrue, reason: 'locate failed: ${r.failReason} (candidates ${r.candidates}, clusters ${r.clusters})');
    final got = [r.tl!, r.tr!, r.bl!, r.br!];
    for (var i = 0; i < 4; i++) {
      expect(got[i].x, closeTo(scene.finderCenters[i].$1, tol), reason: 'corner $i x');
      expect(got[i].y, closeTo(scene.finderCenters[i].$2, tol), reason: 'corner $i y');
    }
  }

  test('exact placement at scale 1 on black', () {
    final scene = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    final r = locator.locate(LumaPlane.fromRgb(scene.image));
    expectCorners(r, scene, 1.5);
    expect(r.module, closeTo(9, 1.0));
    expect(r.devNorm, lessThan(0.02));
    expect(r.tlLuma - r.secondLuma, greaterThan(100));
  });

  test('scale 1.8 rotated 90, 180, 271 and 37 degrees keeps TL/TR/BL/BR assignment', () {
    for (final rot in [90.0, 180.0, 271.0, 37.0]) {
      final scene = renderScene(frame, 1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = rot..centerX = 850..centerY = 850);
      final r = locator.locate(LumaPlane.fromRgb(scene.image));
      expectCorners(r, scene, 2.0);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('keystone 0.18 at scale 1.6', () {
    final scene = renderScene(frame, 1200, 1200, SceneSpec()..scale = 1.6..keystone = 0.18..rotationDeg = 12..centerX = 600..centerY = 600);
    final r = locator.locate(LumaPlane.fromRgb(scene.image));
    expectCorners(r, scene, 2.0);
  });

  test('composited on a real photo background, scale 1.0 and 0.9 rotated 15', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_a.png');
    final a = renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360, background: photo);
    expectCorners(locator.locate(LumaPlane.fromRgb(a.image)), a, 2.0);
    final b = renderScene(frame, 1280, 720, SceneSpec()..scale = 0.9..rotationDeg = 15..centerX = 700..centerY = 360, background: photo);
    expectCorners(locator.locate(LumaPlane.fromRgb(b.image)), b, 2.0);
  });

  test('blurred (sigma 2.5 px) and noisy (sigma 8) at scale 1.5', () {
    final scene = renderScene(frame, 1100, 1100, SceneSpec()..scale = 1.5..blurSigma = 2.5..noiseSigma = 8..centerX = 550..centerY = 550);
    expectCorners(locator.locate(LumaPlane.fromRgb(scene.image)), scene, 2.5);
  });

  test('photo without a v2 barcode fails to locate', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_b.png');
    final r = locator.locate(LumaPlane.fromRgb(photo));
    expect(r.ok, isFalse);
    expect(r.failReason, isNotEmpty);
  });

  test('a v1 barcode photo (a) fails to locate as v2', () {
    final r = locator.locate(LumaPlane.fromRgb(loadPhoto('test/fixtures/camera_raw_1280x720_a.png')));
    expect(r.ok, isFalse);
  });

  test('blank image', () {
    final r = locator.locate(LumaPlane.fromRgb(RgbBuffer(64, 64, Uint8List(64 * 64 * 3))));
    expect(r.ok, isFalse);
  });
}
