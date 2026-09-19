import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/shared/widgets/corners_overlay_painter.dart';

/// The overlay maps camera-frame points onto a BoxFit.contain preview.
/// A landscape 1280x720 sensor shown on a 720x1280 portrait canvas fills it
/// exactly (scale 1, no letterbox), so the corners are easy to name.
void main() {
  const canvas = Size(720, 1280);
  const srcW = 1280, srcH = 720;

  Offset map(double x, double y, int orientation) =>
      CornersOverlayPainter.mapPoint(x, y, canvas, srcW, srcH, orientation);

  test('sensorOrientation 90 rotates the landscape frame clockwise', () {
    // (x, y) -> (H - y, x): the frame's origin lands top-right, and the
    // frame's bottom-left corner (0, 720) lands top-left.
    expect(map(0, 0, 90), const Offset(720, 0));
    expect(map(0, 720, 90), const Offset(0, 0));
    // The remaining two corners complete the portrait rectangle.
    expect(map(1280, 0, 90), const Offset(720, 1280));
    expect(map(1280, 720, 90), const Offset(0, 1280));
  });

  test('sensorOrientation 270 is the mirror of 90', () {
    expect(map(0, 0, 270), const Offset(0, 1280));
    expect(map(0, 720, 270), const Offset(720, 1280));
    expect(map(1280, 0, 270), const Offset(0, 0));
    expect(map(1280, 720, 270), const Offset(720, 0));
    // Point-symmetric about the preview centre relative to the 90 mapping.
    for (final (x, y) in [(0.0, 0.0), (0.0, 720.0), (640.0, 360.0)]) {
      final a = map(x, y, 90), b = map(x, y, 270);
      expect(a.dx + b.dx, closeTo(canvas.width, 1e-9));
      expect(a.dy + b.dy, closeTo(canvas.height, 1e-9));
    }
  });

  test('sensorOrientation 0 is identity with contain scaling', () {
    // Unrotated 1280x720 in a 720x1280 canvas: scale 720/1280 = 0.5625,
    // letterboxed vertically by (1280 - 720 * 0.5625) / 2 = 437.5.
    const scale = 720 / 1280;
    const oy = (1280 - 720 * scale) / 2;
    expect(map(0, 0, 0), const Offset(0, oy));
    expect(map(1280, 720, 0), const Offset(720, oy + 720 * scale));
    expect(map(640, 360, 0), const Offset(640 * scale, oy + 360 * scale));
  });

  test('isRotated matches the mapping the painter uses', () {
    expect(CornersOverlayPainter.isRotated(90), isTrue);
    expect(CornersOverlayPainter.isRotated(270), isTrue);
    expect(CornersOverlayPainter.isRotated(0), isFalse);
    expect(CornersOverlayPainter.isRotated(180), isFalse);
  });
}
