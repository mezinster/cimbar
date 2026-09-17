import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Draws the static aiming square and, when known, the located finder quad.
/// Maps camera-frame coordinates to the screen for a BoxFit.contain preview
/// rotated by [sensorOrientation] (landscape sensor shown in portrait).
class CornersOverlayPainter extends CustomPainter {
  final Float64List? corners; // tl,tr,bl,br as x,y pairs (frame px)
  final int sourceImageWidth;
  final int sourceImageHeight;
  final int sensorOrientation;

  CornersOverlayPainter({required this.corners, required this.sourceImageWidth, required this.sourceImageHeight, required this.sensorOrientation});

  Offset _map(double x, double y, Size size) {
    final rotated = sensorOrientation == 90 || sensorOrientation == 270;
    final rw = rotated ? sourceImageHeight.toDouble() : sourceImageWidth.toDouble();
    final rh = rotated ? sourceImageWidth.toDouble() : sourceImageHeight.toDouble();
    final scale = (size.width / rw < size.height / rh) ? size.width / rw : size.height / rh; // contain
    final ox = (size.width - rw * scale) / 2, oy = (size.height - rh * scale) / 2;
    double rx, ry;
    // 90° CW: (x, y) → (H − y, x). The legacy BarcodeOverlayPainter used the
    // CCW mapping and was never validated on a device; confirm on the first
    // device run.
    if (sensorOrientation == 90) {
      rx = sourceImageHeight - y;
      ry = x;
    } else if (sensorOrientation == 270) {
      rx = y;
      ry = sourceImageWidth - x;
    } else if (sensorOrientation == 180) {
      rx = sourceImageWidth - x;
      ry = sourceImageHeight - y;
    } else {
      rx = x;
      ry = y;
    }
    return Offset(ox + rx * scale, oy + ry * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Aiming square: 70% of the shorter side, centered.
    final side = (size.width < size.height ? size.width : size.height) * 0.7;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: side, height: side);
    final guide = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const tick = 28.0;
    for (final (cx, cy, sx, sy) in [
      (rect.left, rect.top, 1.0, 1.0),
      (rect.right, rect.top, -1.0, 1.0),
      (rect.left, rect.bottom, 1.0, -1.0),
      (rect.right, rect.bottom, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + sx * tick, cy), guide);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + sy * tick), guide);
    }
    final c = corners;
    if (c == null) return;
    final pts = [_map(c[0], c[1], size), _map(c[2], c[3], size), _map(c[6], c[7], size), _map(c[4], c[5], size)];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.green.withOpacity(0.15)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = Colors.greenAccent..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.drawCircle(pts[0], 6, Paint()..color = Colors.orangeAccent); // TL marker
  }

  @override
  bool shouldRepaint(CornersOverlayPainter old) =>
      old.corners != corners || old.sourceImageWidth != sourceImageWidth || old.sourceImageHeight != sourceImageHeight || old.sensorOrientation != sensorOrientation;
}
