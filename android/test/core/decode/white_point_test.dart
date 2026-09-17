import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/white_point.dart';

import '../../test_utils/synthetic_scene.dart';

void main() {
  final frame = loadGoldenFrame('hello', 0);

  test('exact frame: white point is pure white', () {
    final wp = WhitePoint.fromFinders(frame, const ExactGridModel())!;
    expect(wp[0], closeTo(255, 1));
    expect(wp[1], closeTo(255, 1));
    expect(wp[2], closeTo(255, 1));
  });

  test('a color cast shows in the white point', () {
    final scene = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    // tint the whole scene: blue x 0.5
    for (var i = 2; i < scene.image.rgb.length; i += 3) {
      scene.image.rgb[i] = (scene.image.rgb[i] * 0.5).round();
    }
    final wp = WhitePoint.fromFinders(scene.image, const ExactGridModelOffset(96, 96))!;
    expect(wp[0], closeTo(255, 2));
    expect(wp[2], closeTo(128, 3));
  });

  test('too dark returns null', () {
    final dark = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400..brightness = 0.05);
    expect(WhitePoint.fromFinders(dark.image, const ExactGridModelOffset(96, 96)), isNull);
  });
}

/// Exact grid shifted by a pixel offset (the frame drawn at (ox, oy) in a larger canvas).
class ExactGridModelOffset extends GridModel {
  final double ox, oy;
  const ExactGridModelOffset(this.ox, this.oy);
  @override
  (double, double) toSource(double cx, double cy) {
    final (x, y) = const ExactGridModel().toSource(cx, cy);
    return (x + ox, y + oy);
  }
}
