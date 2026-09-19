import 'dart:typed_data';

/// Video-range ("studio swing", BT.601) to full-range lookup tables: luma
/// 16..235 -> 0..255 and chroma 16..240 -> -128..128 (centred, not offset).
/// iOS delivers camera frames in video range; Android's YUV_420_888 is full range.
final Uint8List videoRangeLuma = Uint8List.fromList(
    List.generate(256, (y) => (((y - 16) * 255 + 109) ~/ 219).clamp(0, 255)));
final Int16List videoRangeChroma =
    Int16List.fromList(List.generate(256, (c) => ((c - 128) * 255 / 224).round().clamp(-128, 128)));

/// A camera frame in Android YUV_420_888 layout, as the camera plugin exposes it:
/// Y plane with [yRowStride]; U and V planes with [uvRowStride] and
/// [uvPixelStride] (1 = planar, 2 = interleaved/semi-planar). [videoRange]
/// marks 16..235 luma / 16..240 chroma (iOS), expanded to full range on read.
class YuvFrame {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final bool videoRange;

  const YuvFrame({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    this.videoRange = false,
  });

  /// Builds a frame from a camera plugin image's planes, copying the bytes
  /// (the plugin reuses its buffers after the callback returns):
  /// - 3 planes: Android YUV_420_888 (full range), strides as reported;
  /// - 2 planes: iOS NV12 `420YpCbCr8BiPlanarVideoRange` — plane 1 is
  ///   interleaved CbCr, so U is its even bytes and V a one-byte-offset view;
  /// - anything else: null (the caller drops the frame).
  static YuvFrame? fromPlanes({
    required List<Uint8List> planes,
    required List<int> rowStrides,
    required List<int?> pixelStrides,
    required int width,
    required int height,
  }) {
    if (planes.length == 3) {
      return YuvFrame(
        yPlane: Uint8List.fromList(planes[0]),
        uPlane: Uint8List.fromList(planes[1]),
        vPlane: Uint8List.fromList(planes[2]),
        width: width,
        height: height,
        yRowStride: rowStrides[0],
        uvRowStride: rowStrides[1],
        uvPixelStride: pixelStrides[1] ?? 1,
      );
    }
    if (planes.length == 2) {
      final cbcr = Uint8List.fromList(planes[1]);
      return YuvFrame(
        yPlane: Uint8List.fromList(planes[0]),
        uPlane: cbcr,
        vPlane: Uint8List.sublistView(cbcr, 1),
        width: width,
        height: height,
        yRowStride: rowStrides[0],
        uvRowStride: rowStrides[1],
        uvPixelStride: 2,
        videoRange: true,
      );
    }
    return null;
  }
}

/// A region (absolute pixels) where the barcode was last seen.
class RoiHint {
  final int x;
  final int y;
  final int w;
  final int h;
  const RoiHint(this.x, this.y, this.w, this.h);
}
