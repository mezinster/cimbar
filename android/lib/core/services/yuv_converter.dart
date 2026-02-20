import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Converts Android YUV_420_888 camera frames to RGB images.
///
/// Takes raw plane bytes + strides (not CameraImage) so it's testable
/// without the camera package.
class YuvConverter {
  YuvConverter._();

  /// Convert a YUV420 frame to an [img.Image].
  ///
  /// Uses ITU-R BT.601 conversion coefficients:
  ///   R = Y + 1.402 * (V - 128)
  ///   G = Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)
  ///   B = Y + 1.772 * (U - 128)
  static img.Image yuv420ToImage({
    required int width,
    required int height,
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    final image = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x;
        final uvRow = y ~/ 2;
        final uvCol = x ~/ 2;
        final uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride;

        final yVal = yPlane[yIndex];
        final uVal = uPlane[uvIndex];
        final vVal = vPlane[uvIndex];

        final r = (yVal + 1.402 * (vVal - 128)).round();
        final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
            .round();
        final b = (yVal + 1.772 * (uVal - 128)).round();

        image.setPixelRgba(
          x,
          y,
          max(0, min(255, r)),
          max(0, min(255, g)),
          max(0, min(255, b)),
          255,
        );
      }
    }

    return image;
  }
}
