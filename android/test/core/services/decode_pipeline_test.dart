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
