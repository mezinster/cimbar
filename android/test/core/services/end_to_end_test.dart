import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/models/decode_result.dart';
import 'package:cimbar_scanner/core/services/decode_pipeline.dart';

import '../../test_utils/cimbar_encoder.dart';

void main() {
  group('End-to-end GIF round-trip', () {
    test('single-frame small payload', () async {
      final fileData = Uint8List.fromList(utf8.encode('Hello, CimBar!'));
      const filename = 'hello.txt';
      const passphrase = 'test123';

      final gifBytes = CimbarEncoder.encodeToGif(
        fileData: fileData,
        filename: filename,
        passphrase: passphrase,
        frameSize: 256,
      );

      // Verify it's a valid GIF
      expect(gifBytes[0], equals(0x47)); // 'G'
      expect(gifBytes[1], equals(0x49)); // 'I'
      expect(gifBytes[2], equals(0x46)); // 'F'

      // Decode via full pipeline
      final pipeline = DecodePipeline();
      DecodeProgress? lastProgress;

      await for (final progress in pipeline.decodeGif(gifBytes, passphrase)) {
        lastProgress = progress;
      }

      expect(lastProgress?.state, equals(DecodeState.done));

      final result = pipeline.lastResult;
      expect(result, isNotNull);
      expect(result!.filename, equals(filename));
      expect(utf8.decode(result.data), equals('Hello, CimBar!'));
    });

    test('multi-frame payload', () async {
      // Generate a payload large enough for multiple frames at 256px
      // dataBytesPerFrame(256) ≈ 2784, so ~6000 bytes = 3 frames
      final fileData = Uint8List(6000);
      for (var i = 0; i < fileData.length; i++) {
        fileData[i] = (i * 7 + 31) & 0xFF;
      }
      const filename = 'multi_frame.bin';
      const passphrase = 'multipass';

      final gifBytes = CimbarEncoder.encodeToGif(
        fileData: fileData,
        filename: filename,
        passphrase: passphrase,
        frameSize: 256,
      );

      final pipeline = DecodePipeline();
      DecodeProgress? lastProgress;

      await for (final progress in pipeline.decodeGif(gifBytes, passphrase)) {
        lastProgress = progress;
      }

      expect(lastProgress?.state, equals(DecodeState.done));

      final result = pipeline.lastResult;
      expect(result, isNotNull);
      expect(result!.filename, equals(filename));
      expect(result.data.length, equals(6000));

      // Verify data integrity
      var mismatches = 0;
      for (var i = 0; i < fileData.length; i++) {
        if (result.data[i] != fileData[i]) mismatches++;
      }
      expect(mismatches, equals(0));
    });

    test('wrong passphrase fails', () async {
      final fileData = Uint8List.fromList(utf8.encode('Secret data'));
      const filename = 'secret.txt';

      final gifBytes = CimbarEncoder.encodeToGif(
        fileData: fileData,
        filename: filename,
        passphrase: 'correct-password',
        frameSize: 256,
      );

      final pipeline = DecodePipeline();
      DecodeProgress? lastProgress;

      await for (final progress
          in pipeline.decodeGif(gifBytes, 'wrong-password')) {
        lastProgress = progress;
      }

      expect(lastProgress?.state, equals(DecodeState.error));
      expect(pipeline.lastResult, isNull);
    });

    test('different frame sizes', () async {
      final fileData = Uint8List.fromList(utf8.encode('Frame size test'));
      const filename = 'sizes.txt';
      const passphrase = 'sizetest';

      // Test with 128px frame
      final gifBytes128 = CimbarEncoder.encodeToGif(
        fileData: fileData,
        filename: filename,
        passphrase: passphrase,
        frameSize: 128,
      );

      final pipeline128 = DecodePipeline();
      DecodeProgress? last128;
      await for (final p in pipeline128.decodeGif(gifBytes128, passphrase)) {
        last128 = p;
      }

      expect(last128?.state, equals(DecodeState.done));
      expect(pipeline128.lastResult?.filename, equals(filename));
      expect(utf8.decode(pipeline128.lastResult!.data), equals('Frame size test'));
    });
  });
}
