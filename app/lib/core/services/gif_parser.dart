import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/frame_decoder.dart';
import '../decode/rgb_buffer.dart';
import '../format/cimbar_spec.dart';

/// Wrapper around the `image` package's GIF decoder.
/// Returns per-frame images suitable for CimBar decoding.
///
/// Uses [decodeFrame] per-frame instead of [decode] to avoid a bug in the
/// image package's multi-frame compositing: when disposal != 2, `setPixel`
/// writes the palette's RGB _value_ as the palette _index_, garbling all
/// frames after the first. Decoding each frame independently sidesteps this.
class GifParser {
  /// Parse a GIF file and return individual frame images.
  static List<img.Image> parseFrames(Uint8List gifBytes) {
    final decoder = img.GifDecoder();
    final info = decoder.startDecode(gifBytes);

    if (info == null) {
      throw ArgumentError('Failed to decode GIF file');
    }

    final frames = <img.Image>[];
    for (var i = 0; i < info.numFrames; i++) {
      final frame = decoder.decodeFrame(i);
      if (frame != null) frames.add(frame);
    }

    if (frames.isEmpty) {
      throw ArgumentError('GIF contains no decodable frames');
    }

    return frames;
  }

  /// Parse and return the first frame only.
  static img.Image? parseFirstFrame(Uint8List gifBytes) {
    final decoder = img.GifDecoder();
    if (decoder.startDecode(gifBytes) == null) return null;
    return decoder.decodeFrame(0);
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

  /// True when [bytes] is a GIF whose first frame decodes as a CimBar frame:
  /// a 608x608 logical screen and a valid frame header.
  static bool isCimbarGif(Uint8List bytes) {
    try {
      if (bytes.length < 10) return false;
      final w = bytes[6] | (bytes[7] << 8);
      final h = bytes[8] | (bytes[9] << 8);
      if (w != CimbarSpec.framePx || h != CimbarSpec.framePx) return false;
      final frame = parseFirstFrame(bytes);
      if (frame == null) return false;
      return FrameDecoder().decodeExact(RgbBuffer.fromImage(frame)).header != null;
    } catch (_) {
      return false;
    }
  }
}
