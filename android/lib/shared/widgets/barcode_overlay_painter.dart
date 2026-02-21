import 'package:flutter/material.dart';

import '../../core/models/barcode_rect.dart';

/// Paints an AR-style overlay highlighting the detected barcode region.
///
/// Maps barcode coordinates from camera image space to screen space,
/// accounting for sensor orientation and FittedBox.cover scaling.
class BarcodeOverlayPainter extends CustomPainter {
  final BarcodeRect barcodeRect;
  final int sourceImageWidth;
  final int sourceImageHeight;
  final int sensorOrientation;

  BarcodeOverlayPainter({
    required this.barcodeRect,
    required this.sourceImageWidth,
    required this.sourceImageHeight,
    required this.sensorOrientation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Determine rotated camera frame dimensions.
    //    Camera frames are always landscape (e.g. 1920x1080).
    //    For portrait display with 90°/270° sensor orientation, swap w↔h.
    final bool rotated = sensorOrientation == 90 || sensorOrientation == 270;
    final double rotatedW =
        rotated ? sourceImageHeight.toDouble() : sourceImageWidth.toDouble();
    final double rotatedH =
        rotated ? sourceImageWidth.toDouble() : sourceImageHeight.toDouble();

    // 2. Compute BoxFit.cover scale and centering offset.
    final double scaleX = size.width / rotatedW;
    final double scaleY = size.height / rotatedH;
    final double scale = scaleX > scaleY ? scaleX : scaleY;
    final double offsetX = (size.width - rotatedW * scale) / 2;
    final double offsetY = (size.height - rotatedH * scale) / 2;

    // 3. Transform barcode rect from camera coords to rotated coords.
    double rx, ry, rw, rh;
    if (sensorOrientation == 90) {
      // 90° CW rotation: (x, y) → (y, imgW - x - w)
      rx = barcodeRect.y.toDouble();
      ry = (sourceImageWidth - barcodeRect.x - barcodeRect.width).toDouble();
      rw = barcodeRect.height.toDouble();
      rh = barcodeRect.width.toDouble();
    } else if (sensorOrientation == 270) {
      // 270° CW rotation: (x, y) → (imgH - y - h, x)
      rx = (sourceImageHeight - barcodeRect.y - barcodeRect.height).toDouble();
      ry = barcodeRect.x.toDouble();
      rw = barcodeRect.height.toDouble();
      rh = barcodeRect.width.toDouble();
    } else {
      rx = barcodeRect.x.toDouble();
      ry = barcodeRect.y.toDouble();
      rw = barcodeRect.width.toDouble();
      rh = barcodeRect.height.toDouble();
    }

    // 4. Apply scale and offset to get screen coordinates.
    final Rect screenRect = Rect.fromLTWH(
      offsetX + rx * scale,
      offsetY + ry * scale,
      rw * scale,
      rh * scale,
    );

    // 5. Draw semi-transparent fill.
    final fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(screenRect, const Radius.circular(8)),
      fillPaint,
    );

    // 6. Draw corner brackets (bright green).
    final strokePaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final double bracketLen = screenRect.width * 0.15;
    _drawCornerBrackets(canvas, screenRect, bracketLen, strokePaint);
  }

  void _drawCornerBrackets(
      Canvas canvas, Rect rect, double len, Paint paint) {
    // Top-left
    canvas.drawLine(
        Offset(rect.left, rect.top + len), Offset(rect.left, rect.top), paint);
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.left + len, rect.top), paint);

    // Top-right
    canvas.drawLine(Offset(rect.right - len, rect.top),
        Offset(rect.right, rect.top), paint);
    canvas.drawLine(Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + len), paint);

    // Bottom-left
    canvas.drawLine(Offset(rect.left, rect.bottom - len),
        Offset(rect.left, rect.bottom), paint);
    canvas.drawLine(Offset(rect.left, rect.bottom),
        Offset(rect.left + len, rect.bottom), paint);

    // Bottom-right
    canvas.drawLine(Offset(rect.right - len, rect.bottom),
        Offset(rect.right, rect.bottom), paint);
    canvas.drawLine(Offset(rect.right, rect.bottom),
        Offset(rect.right, rect.bottom - len), paint);
  }

  @override
  bool shouldRepaint(BarcodeOverlayPainter oldDelegate) =>
      barcodeRect != oldDelegate.barcodeRect ||
      sourceImageWidth != oldDelegate.sourceImageWidth ||
      sourceImageHeight != oldDelegate.sourceImageHeight ||
      sensorOrientation != oldDelegate.sensorOrientation;
}
