import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'cell_grid.dart';
import 'frame_builder.dart';
import 'frame_raster.dart';
import 'payload_encoder.dart';

/// Port of web-app/gif-encoder.js. Frames arrive as palette indices
/// (FrameRaster), so nothing is quantized and the output is byte-identical to
/// the web encoder's for the same frames.
class GifWriter {
  GifWriter._();

  static Uint8List palette() {
    final pal = Uint8List(256 * 3);
    var idx = 0;
    final fixed = [...CimbarSpec.palette, const [0, 0, 0], const [255, 255, 255]];
    for (final c in fixed) {
      pal[idx * 3] = c[0]; pal[idx * 3 + 1] = c[1]; pal[idx * 3 + 2] = c[2];
      idx++;
    }
    for (var v = 0; v <= 255 && idx < 256; v += 8) {
      pal[idx * 3] = v; pal[idx * 3 + 1] = v; pal[idx * 3 + 2] = v;
      idx++;
    }
    for (var r = 0; r < 6 && idx < 256; r++) {
      for (var g = 0; g < 6 && idx < 256; g++) {
        for (var b = 0; b < 6 && idx < 256; b++) {
          pal[idx * 3] = r * 51; pal[idx * 3 + 1] = g * 51; pal[idx * 3 + 2] = b * 51;
          idx++;
        }
      }
    }
    return pal;
  }

  static Uint8List encode(List<Uint8List> indexFrames,
          {required int delayCs, int width = CimbarSpec.framePx, int height = CimbarSpec.framePx}) =>
      encodeStream(indexFrames, delayCs: delayCs, width: width, height: height);

  /// Same bytes as [encode], but pulls [indexFrames] one at a time and
  /// LZW-compresses each before asking for the next, so a lazy iterable
  /// (see [buildGif]) keeps one frame raster alive instead of all of them —
  /// 625 rasters at the 500-frame Share GIF cap would be ~231 MB.
  static Uint8List encodeStream(Iterable<Uint8List> indexFrames,
      {required int delayCs, int width = CimbarSpec.framePx, int height = CimbarSpec.framePx}) {
    final out = BytesBuilder(copy: false);
    void word(int n) => out.add([n & 0xFF, (n >> 8) & 0xFF]);
    out.add('GIF89a'.codeUnits);
    word(width);
    word(height);
    out.add([0xF7, 0, 0]);
    out.add(palette());
    out.add([0x21, 0xFF, 0x0B]);
    out.add('NETSCAPE2.0'.codeUnits);
    out.add([0x03, 0x01, 0x00, 0x00, 0x00]);
    for (final indices in indexFrames) {
      out.add([0x21, 0xF9, 0x04, 0x04]);
      word(delayCs);
      out.add([0x00, 0x00]);
      out.add([0x2C]);
      word(0); word(0); word(width); word(height);
      out.add([0x00]);
      const lzwMin = 8;
      out.add([lzwMin]);
      out.add(_lzw(indices, lzwMin));
    }
    out.add([0x3B]);
    return out.takeBytes();
  }

  static Uint8List _lzw(Uint8List indices, int minCodeSize) {
    final clearCode = 1 << minCodeSize;
    final eofCode = clearCode + 1;
    var codeSize = minCodeSize + 1;
    var nextCode = eofCode + 1;
    final out = BytesBuilder(copy: false);
    var bitBuf = 0, bitCount = 0;
    final sub = Uint8List(256);
    var subLen = 0;

    void emit(int code, int n) {
      bitBuf |= code << bitCount;
      bitCount += n;
      while (bitCount >= 8) {
        sub[subLen++] = bitBuf & 0xFF;
        bitBuf >>= 8;
        bitCount -= 8;
        if (subLen == 255) {
          out.addByte(255);
          out.add(Uint8List.fromList(sub.sublist(0, 255)));
          subLen = 0;
        }
      }
    }

    final table = <int, int>{};
    void reset() {
      table.clear();
      emit(clearCode, codeSize);
      codeSize = minCodeSize + 1;
      nextCode = eofCode + 1;
    }

    reset();
    var prefix = indices[0];
    for (var i = 1; i < indices.length; i++) {
      final suffix = indices[i];
      final key = (prefix << 8) | suffix;
      final hit = table[key];
      if (hit != null) {
        prefix = hit;
      } else {
        emit(prefix, codeSize);
        if (nextCode <= 4095) {
          table[key] = nextCode++;
          if (nextCode > (1 << codeSize) && codeSize < 12) codeSize++;
        } else {
          reset();
        }
        prefix = suffix;
      }
    }
    emit(prefix, codeSize);
    emit(eofCode, codeSize);
    if (bitCount > 0) {
      sub[subLen++] = bitBuf & 0xFF;
      bitBuf = 0;
      bitCount = 0;
    }
    if (subLen > 0) {
      out.addByte(subLen);
      out.add(Uint8List.fromList(sub.sublist(0, subLen)));
    }
    out.addByte(0);
    return out.takeBytes();
  }
}

/// The downloadable GIF for [p]: N source + gifRepairCount(N) repair frames.
/// Each frame is built and rendered only when the writer asks for it, so peak
/// memory is one raster plus the GIF being written. Top-level so it can run in
/// Isolate.run.
Uint8List buildGif(EncodedPayload p, int delayMs) => GifWriter.encodeStream(
      FrameBuilder.gifFrameStream(p).map((f) => FrameRaster.render(CellGrid.cells(f))),
      delayCs: delayMs ~/ 10,
    );
