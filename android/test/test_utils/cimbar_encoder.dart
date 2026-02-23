import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/crypto_service.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';
import 'package:cimbar_scanner/core/utils/byte_utils.dart';

/// Test utility: encodes data into CimBar format (GIF or raw frames).
///
/// Extracts and extends the encode helpers from decode_pipeline_test.dart
/// so they can be shared across multiple test files.
class CimbarEncoder {
  static final _rs = ReedSolomon(CimbarConstants.eccBytes);

  /// Full pipeline: file → encrypt → RS encode → draw frames → GIF bytes.
  ///
  /// Returns a valid animated GIF that can be decoded by [DecodePipeline].
  static Uint8List encodeToGif({
    required Uint8List fileData,
    required String filename,
    required String passphrase,
    int frameSize = 256,
  }) {
    // 1. Build file header: [4-byte nameLen][nameBytes][fileData]
    final nameBytes = Uint8List.fromList(utf8.encode(filename));
    final header = writeUint32BE(nameBytes.length);
    final plaintext = concatBytes([header, nameBytes, fileData]);

    // 2. Encrypt
    final encrypted = CryptoService.encrypt(plaintext, passphrase);

    // 3. Prepend 4-byte length prefix
    final lengthPrefix = writeUint32BE(encrypted.length);
    final framedData = concatBytes([lengthPrefix, encrypted]);

    // 4. Split into frames and encode
    final dpf = CimbarConstants.dataBytesPerFrame(frameSize);
    final numFrames = (framedData.length + dpf - 1) ~/ dpf;

    final frames = <img.Image>[];
    for (var f = 0; f < numFrames; f++) {
      final start = f * dpf;
      final end = min((f + 1) * dpf, framedData.length);
      final chunk = framedData.sublist(start, end);

      final rsFrame = encodeRSFrame(chunk, frameSize);
      frames.add(encodeFrame(rsFrame, frameSize));
    }

    // 5. Encode as animated GIF
    return _encodeGif(frames);
  }

  /// Encode frames into an animated GIF using the image package.
  static Uint8List _encodeGif(List<img.Image> frames) {
    // Build an animation by adding frames to the first image
    final animation = img.Image(
      width: frames.first.width,
      height: frames.first.height,
    );

    // Copy first frame pixels into animation root
    for (final pixel in frames.first) {
      animation.setPixelRgba(
        pixel.x, pixel.y,
        pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), 255,
      );
    }
    animation.frameDuration = 400; // ms per frame

    // Add subsequent frames
    for (var i = 1; i < frames.length; i++) {
      final frame = img.Image(
        width: frames[i].width,
        height: frames[i].height,
      );
      for (final pixel in frames[i]) {
        frame.setPixelRgba(
          pixel.x, pixel.y,
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), 255,
        );
      }
      frame.frameDuration = 400;
      animation.addFrame(frame);
    }

    return Uint8List.fromList(img.encodeGif(animation));
  }

  /// Draw one symbol on an image (matches cimbar.js drawSymbol).
  static void drawSymbol(
    img.Image image,
    int symIdx,
    List<int> colorRGB,
    int ox,
    int oy,
    int size,
  ) {
    final cr = colorRGB[0], cg = colorRGB[1], cb = colorRGB[2];
    final q = max(1, (size * 0.28).floor());
    final h = max(1, (q * 0.75).floor());

    img.fillRect(image,
        x1: ox, y1: oy, x2: ox + size, y2: oy + size,
        color: img.ColorRgba8(cr, cg, cb, 255));

    void paintBlack(int bx, int by) {
      img.fillRect(image,
          x1: bx, y1: by, x2: bx + 2 * h, y2: by + 2 * h,
          color: img.ColorRgba8(0, 0, 0, 255));
    }

    if ((symIdx >> 3) & 1 == 0) paintBlack(ox + q - h, oy + q - h);
    if ((symIdx >> 2) & 1 == 0) paintBlack(ox + size - q - h, oy + q - h);
    if ((symIdx >> 1) & 1 == 0) paintBlack(ox + q - h, oy + size - q - h);
    if ((symIdx >> 0) & 1 == 0) paintBlack(ox + size - q - h, oy + size - q - h);
  }

  /// Draw finder pattern.
  static void drawFinder(img.Image image, int ox, int oy, int size) {
    final s = size * 3;
    img.fillRect(image,
        x1: ox, y1: oy, x2: ox + s, y2: oy + s,
        color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(image,
        x1: ox + size, y1: oy + size, x2: ox + 2 * size, y2: oy + 2 * size,
        color: img.ColorRgba8(51, 51, 51, 255));
    final inner = (size * 0.4).floor();
    final offset = ((size - inner) / 2).floor();
    img.fillRect(image,
        x1: ox + size + offset,
        y1: oy + size + offset,
        x2: ox + size + offset + inner,
        y2: oy + size + offset + inner,
        color: img.ColorRgba8(255, 255, 255, 255));
  }

  /// RS-encode a data chunk for one frame (matching encodeRSFrame in cimbar.js).
  /// Uses byte-stride interleaving: byte j of block i → position j * N + i.
  static Uint8List encodeRSFrame(Uint8List dataChunk, int frameSize) {
    final raw = CimbarConstants.rawBytesPerFrame(frameSize);

    // Phase 1: RS-encode each block into a temporary list
    final blocks = <Uint8List>[];
    var inOff = 0, totalOut = 0;
    while (totalOut < raw) {
      final spaceLeft = raw - totalOut;
      if (spaceLeft <= CimbarConstants.eccBytes) break;

      final blockTotal = min(CimbarConstants.blockTotal, spaceLeft);
      final blockData = blockTotal - CimbarConstants.eccBytes;
      final chunk = Uint8List(blockData);
      final take = min(blockData, dataChunk.length - inOff);
      if (take > 0) {
        chunk.setRange(0, take, dataChunk, inOff);
      }
      inOff += take;

      final encoded = _rs.encode(chunk);
      blocks.add(Uint8List.fromList(encoded.sublist(0, blockTotal)));
      totalOut += blockTotal;
    }

    // Phase 2: Interleave — byte j of block i → position j * N + i
    final output = Uint8List(raw);
    final n = blocks.length;
    var maxBlockLen = 0;
    for (final b in blocks) {
      if (b.length > maxBlockLen) maxBlockLen = b.length;
    }
    var pos = 0;
    for (var j = 0; j < maxBlockLen; j++) {
      for (var i = 0; i < n; i++) {
        if (j < blocks[i].length) {
          output[pos++] = blocks[i][j];
        }
      }
    }
    return output;
  }

  /// Encode a frame onto an image (matching encodeFrame in cimbar.js).
  static img.Image encodeFrame(Uint8List rsData, int frameSize) {
    const cs = CimbarConstants.cellSize;
    final cols = frameSize ~/ cs;
    final rows = frameSize ~/ cs;
    final image = img.Image(width: frameSize, height: frameSize);

    // Black background
    img.fill(image, color: img.ColorRgba8(17, 17, 17, 255));

    var cellIdx = 0;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final inTL = row < 3 && col < 3;
        final inBR = row >= rows - 3 && col >= cols - 3;
        if (inTL || inBR) continue;

        final globalBit = cellIdx * 7;
        final bytePos = globalBit ~/ 8;
        final bitShift = globalBit % 8;

        var bits = 0;
        for (var b = 0; b < 7; b++) {
          final absBit = bytePos * 8 + bitShift + b;
          final aB = absBit ~/ 8;
          final aBit = 7 - (absBit % 8);
          final dataBit = (aB < rsData.length) ? ((rsData[aB] >> aBit) & 1) : 0;
          bits = (bits << 1) | dataBit;
        }

        final colorIdx = (bits >> 4) & 0x7;
        final symIdx = bits & 0xF;

        final ox = col * cs;
        final oy = row * cs;
        drawSymbol(image, symIdx, CimbarConstants.colors[colorIdx], ox, oy, cs);

        cellIdx++;
      }
    }

    drawFinder(image, 0, 0, cs);
    drawFinder(image, (cols - 3) * cs, (rows - 3) * cs, cs);

    return image;
  }
}
