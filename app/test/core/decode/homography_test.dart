import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';

void main() {
  const square = [(0.0, 0.0), (10.0, 0.0), (0.0, 10.0), (10.0, 10.0)];

  test('identity', () {
    final h = Homography.solve(square, square)!;
    final (x, y) = h.map(3.0, 7.0);
    expect(x, closeTo(3.0, 1e-9));
    expect(y, closeTo(7.0, 1e-9));
  });

  test('scale and translate', () {
    const to = [(100.0, 50.0), (120.0, 50.0), (100.0, 70.0), (120.0, 70.0)];
    final h = Homography.solve(square, to)!;
    final (x, y) = h.map(5.0, 5.0);
    expect(x, closeTo(110.0, 1e-9));
    expect(y, closeTo(60.0, 1e-9));
  });

  test('perspective quad maps corners exactly and inverse round-trips', () {
    const to = [(10.0, 20.0), (200.0, 5.0), (30.0, 180.0), (220.0, 210.0)];
    final h = Homography.solve(square, to)!;
    for (var i = 0; i < 4; i++) {
      final (x, y) = h.map(square[i].$1, square[i].$2);
      expect(x, closeTo(to[i].$1, 1e-6));
      expect(y, closeTo(to[i].$2, 1e-6));
    }
    final inv = Homography.solve(to, square)!;
    final (mx, my) = h.map(2.5, 8.0);
    final (bx, by) = inv.map(mx, my);
    expect(bx, closeTo(2.5, 1e-6));
    expect(by, closeTo(8.0, 1e-6));
  });

  test('fromFinders with exact frame finder centers reproduces ExactGridModel', () {
    final gm = HomographyGridModel.fromFinders(
      tl: (47.5, 47.5), tr: (560.5, 47.5), bl: (47.5, 560.5), br: (560.5, 560.5),
    )!;
    const exact = ExactGridModel();
    for (final (cx, cy) in [(0.0, 0.0), (32.0, 32.0), (8.5, 0.5), (63.9, 63.9)]) {
      final (ax, ay) = gm.toSource(cx, cy);
      final (ex, ey) = exact.toSource(cx, cy);
      expect(ax, closeTo(ex, 1e-6));
      expect(ay, closeTo(ey, 1e-6));
    }
  });
}
