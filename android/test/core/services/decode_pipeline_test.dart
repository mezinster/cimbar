import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/cimbar_decoder.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';
import 'package:cimbar_scanner/core/utils/byte_utils.dart';

/// Port of web-app/tests/test_pipeline_node.js encode-side logic.
///
/// Since GIF encode/decode round-trip requires the web-app's GifEncoder
/// (which we don't port to Dart), this test exercises the RS frame layer:
/// encodeRSFrame -> drawFrame -> readFrame -> decodeRSFrame round-trip.

const _frameSize = 256;

final _rs = ReedSolomon(CimbarConstants.eccBytes);
final _dpf = CimbarConstants.dataBytesPerFrame(_frameSize);
final _decoder = CimbarDecoder(_rs);

/// Draw one symbol on an image (matches cimbar.js drawSymbol).
void _drawSymbol(
    img.Image image, int symIdx, List<int> colorRGB, int ox, int oy, int size) {
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
void _drawFinder(img.Image image, int ox, int oy, int size) {
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
Uint8List _encodeRSFrame(Uint8List dataChunk, int frameSize) {
  final raw = CimbarConstants.rawBytesPerFrame(frameSize);
  final output = Uint8List(raw);
  var inOff = 0, outOff = 0;

  while (outOff < raw) {
    final spaceLeft = raw - outOff;
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
    output.setRange(outOff, outOff + blockTotal, encoded);
    outOff += blockTotal;
  }
  return output;
}

/// Encode a frame onto an image (matching encodeFrame in cimbar.js).
img.Image _encodeFrame(Uint8List rsData, int frameSize) {
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
      _drawSymbol(image, symIdx, CimbarConstants.colors[colorIdx], ox, oy, cs);

      cellIdx++;
    }
  }

  _drawFinder(image, 0, 0, cs);
  _drawFinder(image, (cols - 3) * cs, (rows - 3) * cs, cs);

  return image;
}

void main() {
  group('Decode pipeline (RS frame round-trip)', () {
    test('length prefix round-trip (non-dpf-aligned payload)', () {
      const fakeEncLen = 37345;
      final fakeEnc = Uint8List(fakeEncLen);
      for (var i = 0; i < fakeEncLen; i++) {
        fakeEnc[i] = (i * 7 + 13) & 0xFF;
      }

      final lengthPrefix = writeUint32BE(fakeEnc.length);
      final framedData = concatBytes([lengthPrefix, fakeEnc]);
      final numFrames = (framedData.length + _dpf - 1) ~/ _dpf;

      // Encode frames -> decode frames
      final allData = <int>[];
      for (var f = 0; f < numFrames; f++) {
        final start = f * _dpf;
        final end = min((f + 1) * _dpf, framedData.length);
        final chunk = framedData.sublist(start, end);

        final rsFrame = _encodeRSFrame(chunk, _frameSize);
        final frameImage = _encodeFrame(rsFrame, _frameSize);

        final rawBytes = _decoder.decodeFramePixels(frameImage, _frameSize);
        final dataBytes = _decoder.decodeRSFrame(rawBytes, _frameSize);
        allData.addAll(dataBytes);
      }

      final allBytes = Uint8List.fromList(allData);
      final payloadLength = readUint32BE(allBytes);
      expect(payloadLength, equals(fakeEncLen));

      final recovered = allBytes.sublist(4, 4 + payloadLength);
      expect(recovered.length, equals(fakeEncLen));

      var mismatches = 0;
      for (var i = 0; i < fakeEncLen; i++) {
        if (recovered[i] != fakeEnc[i]) mismatches++;
      }
      expect(mismatches, equals(0));
    });

    test('length prefix round-trip (exact dpf-aligned payload)', () {
      final fakeEncLen = 3 * _dpf - 4;
      final fakeEnc = Uint8List(fakeEncLen);
      for (var i = 0; i < fakeEncLen; i++) {
        fakeEnc[i] = (i * 3 + 77) & 0xFF;
      }

      final lengthPrefix = writeUint32BE(fakeEnc.length);
      final framedData = concatBytes([lengthPrefix, fakeEnc]);
      expect(framedData.length, equals(3 * _dpf));

      final numFrames = framedData.length ~/ _dpf;
      final allData = <int>[];

      for (var f = 0; f < numFrames; f++) {
        final chunk = framedData.sublist(f * _dpf, (f + 1) * _dpf);
        final rsFrame = _encodeRSFrame(chunk, _frameSize);
        final frameImage = _encodeFrame(rsFrame, _frameSize);

        final rawBytes = _decoder.decodeFramePixels(frameImage, _frameSize);
        final dataBytes = _decoder.decodeRSFrame(rawBytes, _frameSize);
        allData.addAll(dataBytes);
      }

      final allBytes = Uint8List.fromList(allData);
      final payloadLength = readUint32BE(allBytes);
      expect(payloadLength, equals(fakeEncLen));

      final recovered = allBytes.sublist(4, 4 + payloadLength);
      var mismatches = 0;
      for (var i = 0; i < fakeEncLen; i++) {
        if (recovered[i] != fakeEnc[i]) mismatches++;
      }
      expect(mismatches, equals(0));
    });

    test('length prefix round-trip (tiny payload, single frame)', () {
      const fakeEncLen = 100;
      final fakeEnc = Uint8List(fakeEncLen);
      for (var i = 0; i < fakeEncLen; i++) {
        fakeEnc[i] = (i * 11 + 3) & 0xFF;
      }

      final lengthPrefix = writeUint32BE(fakeEnc.length);
      final framedData = concatBytes([lengthPrefix, fakeEnc]);

      final chunk = Uint8List(_dpf);
      chunk.setRange(0, framedData.length, framedData);

      final rsFrame = _encodeRSFrame(chunk, _frameSize);
      final frameImage = _encodeFrame(rsFrame, _frameSize);

      final rawBytes = _decoder.decodeFramePixels(frameImage, _frameSize);
      final dataBytes = _decoder.decodeRSFrame(rawBytes, _frameSize);

      final allBytes = Uint8List.fromList(dataBytes);
      final payloadLength = readUint32BE(allBytes);
      expect(payloadLength, equals(fakeEncLen));

      final recovered = allBytes.sublist(4, 4 + payloadLength);
      var mismatches = 0;
      for (var i = 0; i < fakeEncLen; i++) {
        if (recovered[i] != fakeEnc[i]) mismatches++;
      }
      expect(mismatches, equals(0));
    });
  });
}
