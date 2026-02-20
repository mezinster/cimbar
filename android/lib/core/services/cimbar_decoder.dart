import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import 'reed_solomon.dart';

/// Decode CimBar frames from pixel data.
/// Port of decode-side functions from web-app/cimbar.js.
class CimbarDecoder {
  final ReedSolomon _rs;

  CimbarDecoder([ReedSolomon? rs]) : _rs = rs ?? ReedSolomon(CimbarConstants.eccBytes);

  /// Decode raw bytes from a frame image.
  /// [frame] must be a square image of [frameSize] pixels.
  Uint8List decodeFramePixels(img.Image frame, int frameSize) {
    final cs = CimbarConstants.cellSize;
    final cols = frameSize ~/ cs;
    final rows = frameSize ~/ cs;
    final totalBits = CimbarConstants.usableCells(frameSize) * 7;
    final totalBytes = (totalBits + 7) ~/ 8; // ceil
    final outBytes = Uint8List(totalBytes);

    var bitBuf = 0;
    var bitCount = 0;
    var byteIdx = 0;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        // Skip finder pattern cells
        final inTL = row < 3 && col < 3;
        final inBR = row >= rows - 3 && col >= cols - 3;
        if (inTL || inBR) continue;

        final ox = col * cs;
        final oy = row * cs;

        // Color detection: sample center pixel
        final cx = ox + cs ~/ 2;
        final cy = oy + cs ~/ 2;
        final pixel = frame.getPixel(cx, cy);
        final colorIdx = _nearestColorIdx(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());

        // Symbol detection: sample 4 quadrant points
        final symIdx = _detectSymbol(frame, ox, oy, cs);

        final bits = ((colorIdx & 0x7) << 4) | (symIdx & 0xF);

        bitBuf = (bitBuf << 7) | bits;
        bitCount += 7;

        while (bitCount >= 8 && byteIdx < totalBytes) {
          bitCount -= 8;
          outBytes[byteIdx++] = (bitBuf >> bitCount) & 0xFF;
        }
      }
    }

    return outBytes;
  }

  /// RS-decode one frame's raw bytes back to data bytes.
  Uint8List decodeRSFrame(Uint8List rawBytes, int frameSize) {
    final raw = CimbarConstants.rawBytesPerFrame(frameSize);
    final result = <int>[];
    var off = 0;

    while (off < raw) {
      final spaceLeft = raw - off;
      if (spaceLeft <= CimbarConstants.eccBytes) break;

      final blockTotal = min(CimbarConstants.blockTotal, spaceLeft);
      final blockData = blockTotal - CimbarConstants.eccBytes;
      final block = rawBytes.sublist(off, min(off + blockTotal, rawBytes.length));
      off += blockTotal;

      // Pad block if needed (rawBytes might be shorter)
      final paddedBlock = Uint8List(blockTotal);
      paddedBlock.setRange(0, min(block.length, blockTotal), block);

      try {
        final decoded = _rs.decode(paddedBlock);
        result.addAll(decoded);
      } catch (_) {
        // If RS decode fails, push zeros
        for (var i = 0; i < blockData; i++) {
          result.add(0);
        }
      }
    }

    return Uint8List.fromList(result);
  }

  /// Find nearest color index using weighted distance.
  static int _nearestColorIdx(int r, int g, int b) {
    var best = 0;
    var bestDist = 0x7FFFFFFF; // max int
    for (var i = 0; i < CimbarConstants.colors.length; i++) {
      final c = CimbarConstants.colors[i];
      final dr = r - c[0];
      final dg = g - c[1];
      final db = b - c[2];
      final d = dr * dr * 2 + dg * dg * 4 + db * db;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// Detect 4-bit symbol from quadrant luma sampling.
  static int _detectSymbol(img.Image image, int ox, int oy, int cs) {
    final q = max(1, (cs * 0.28).floor());

    double luma(int px, int py) {
      final x = min(px, image.width - 1);
      final y = min(py, image.height - 1);
      final p = image.getPixel(x, y);
      return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }

    final c = luma(ox + cs ~/ 2, oy + cs ~/ 2);
    final tl = luma(ox + q, oy + q);
    final tr = luma(ox + cs - q, oy + q);
    final bl = luma(ox + q, oy + cs - q);
    final br = luma(ox + cs - q, oy + cs - q);

    final thresh = c * 0.5 + 20;

    return ((tl > thresh ? 1 : 0) << 3) |
        ((tr > thresh ? 1 : 0) << 2) |
        ((bl > thresh ? 1 : 0) << 1) |
        (br > thresh ? 1 : 0);
  }
}
