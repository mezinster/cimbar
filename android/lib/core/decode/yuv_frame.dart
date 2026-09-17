import 'dart:typed_data';

/// A camera frame in Android YUV_420_888 layout, as the camera plugin exposes it:
/// Y plane with [yRowStride]; U and V planes with [uvRowStride] and
/// [uvPixelStride] (1 = planar, 2 = interleaved/semi-planar).
class YuvFrame {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;

  const YuvFrame({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });
}

/// A region (absolute pixels) where the barcode was last seen.
class RoiHint {
  final int x;
  final int y;
  final int w;
  final int h;
  const RoiHint(this.x, this.y, this.w, this.h);
}
