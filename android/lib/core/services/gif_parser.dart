import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Wrapper around the `image` package's GIF decoder.
/// Returns per-frame images suitable for CimBar decoding.
class GifParser {
  /// Parse a GIF file and return individual frame images.
  static List<img.Image> parseFrames(Uint8List gifBytes) {
    final decoder = img.GifDecoder();
    final animation = decoder.decode(gifBytes);

    if (animation == null) {
      throw ArgumentError('Failed to decode GIF file');
    }

    return animation.frames.toList();
  }

  /// Parse and return the first frame only.
  static img.Image? parseFirstFrame(Uint8List gifBytes) {
    final decoder = img.GifDecoder();
    return decoder.decode(gifBytes);
  }

  /// Get the frame size (width, assumed square) from GIF data.
  static int getFrameSize(Uint8List gifBytes) {
    final decoder = img.GifDecoder();
    final info = decoder.startDecode(gifBytes);
    if (info == null) {
      throw ArgumentError('Failed to read GIF header');
    }
    return info.width;
  }
}
