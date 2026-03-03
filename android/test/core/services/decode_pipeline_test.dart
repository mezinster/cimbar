import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/cimbar_decoder.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';
import 'package:cimbar_scanner/core/utils/byte_utils.dart';

import '../../test_utils/cimbar_encoder.dart';

/// Port of web-app/tests/test_pipeline_node.js encode-side logic.
///
/// Since GIF encode/decode round-trip requires the web-app's GifEncoder
/// (which we don't port to Dart), this test exercises the RS frame layer:
/// encodeRSFrame -> drawFrame -> readFrame -> decodeRSFrame round-trip.

const _frameSize = 256;

final _rs = ReedSolomon(CimbarConstants.eccBytes);
final _dpf = CimbarConstants.dataBytesPerFrame(_frameSize);
final _decoder = CimbarDecoder(_rs);

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

        final rsFrame = CimbarEncoder.encodeRSFrame(chunk, _frameSize);
        final frameImage = CimbarEncoder.encodeFrame(rsFrame, _frameSize);

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
        final rsFrame = CimbarEncoder.encodeRSFrame(chunk, _frameSize);
        final frameImage = CimbarEncoder.encodeFrame(rsFrame, _frameSize);

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

    test('length prefix round-trip (unencrypted small payload)', () {
      // Simulate an unencrypted payload: [nameLen][name][data]
      // nameLen=5, name="a.txt", data=10 bytes -> total = 4+5+10 = 19 bytes
      const fakeEncLen = 19;
      final fakeEnc = Uint8List(fakeEncLen);
      // Set first 4 bytes to nameLen=5
      fakeEnc[0] = 0; fakeEnc[1] = 0; fakeEnc[2] = 0; fakeEnc[3] = 5;
      // "a.txt" in ASCII
      fakeEnc[4] = 0x61; fakeEnc[5] = 0x2E; fakeEnc[6] = 0x74;
      fakeEnc[7] = 0x78; fakeEnc[8] = 0x74;
      // 10 bytes of data
      for (var i = 9; i < fakeEncLen; i++) {
        fakeEnc[i] = (i * 11 + 3) & 0xFF;
      }

      final lengthPrefix = writeUint32BE(fakeEnc.length);
      final framedData = concatBytes([lengthPrefix, fakeEnc]);

      final chunk = Uint8List(_dpf);
      chunk.setRange(0, framedData.length, framedData);

      final rsFrame = CimbarEncoder.encodeRSFrame(chunk, _frameSize);
      final frameImage = CimbarEncoder.encodeFrame(rsFrame, _frameSize,
          isEncrypted: false);

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

      // Verify it does NOT start with magic bytes (unencrypted)
      expect(recovered[0] != 0xCB || recovered[1] != 0x42, isTrue);
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

      final rsFrame = CimbarEncoder.encodeRSFrame(chunk, _frameSize);
      final frameImage = CimbarEncoder.encodeFrame(rsFrame, _frameSize);

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
