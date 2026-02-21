import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/decode_result.dart';
import '../utils/byte_utils.dart';
import 'cimbar_decoder.dart';
import 'crypto_service.dart';
import 'gif_parser.dart';

/// Full decode pipeline: GIF -> frames -> RS decode -> decrypt -> file.
/// Port of web-app/index.html:1003-1086.
class DecodePipeline {
  final CimbarDecoder _decoder = CimbarDecoder();

  /// Decode a GIF file with a passphrase.
  /// Yields progress updates; the final event has state == DecodeState.done
  /// and contains the result.
  Stream<DecodeProgress> decodeGif(Uint8List gifBytes, String passphrase) async* {
    // 1. Parse GIF
    yield const DecodeProgress(
      state: DecodeState.parsingGif,
      message: 'Parsing GIF...',
    );

    final List<img.Image> frames;
    final int frameSize;
    try {
      frames = GifParser.parseFrames(gifBytes);
      if (frames.isEmpty) throw ArgumentError('GIF contains no frames');
      frameSize = frames.first.width;
    } catch (e) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Failed to parse GIF: $e',
      );
      return;
    }

    // 2. Decode frames -> raw bytes -> RS decode
    yield const DecodeProgress(
      state: DecodeState.decodingFrames,
      progress: 0.0,
      message: 'Decoding frames...',
    );

    final allData = <int>[];
    for (var i = 0; i < frames.length; i++) {
      final rawBytes = _decoder.decodeFramePixels(frames[i], frameSize);
      final dataBytes = _decoder.decodeRSFrame(rawBytes, frameSize);
      allData.addAll(dataBytes);

      yield DecodeProgress(
        state: DecodeState.decodingFrames,
        progress: (i + 1) / frames.length,
        message: 'Decoded frame ${i + 1}/${frames.length}',
      );
    }

    final allBytes = Uint8List.fromList(allData);

    // 3. Read 4-byte big-endian length prefix -> extract encrypted payload
    if (allBytes.length < 4) {
      yield const DecodeProgress(
        state: DecodeState.error,
        message: 'Decoded data too short',
      );
      return;
    }

    final payloadLength = readUint32BE(allBytes);
    if (payloadLength < 32 || payloadLength > allBytes.length - 4) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Invalid payload length: $payloadLength',
      );
      return;
    }

    final encryptedPayload = allBytes.sublist(4, 4 + payloadLength);

    // 4. AES-GCM decrypt
    yield const DecodeProgress(
      state: DecodeState.decrypting,
      progress: 0.5,
      message: 'Decrypting...',
    );

    final Uint8List plaintext;
    try {
      plaintext = CryptoService.decrypt(encryptedPayload, passphrase);
    } catch (e) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Decryption failed: $e',
      );
      return;
    }

    // 5. Parse file header: [4-byte nameLen][nameBytes][fileData]
    if (plaintext.length < 4) {
      yield const DecodeProgress(
        state: DecodeState.error,
        message: 'Decrypted data too short for file header',
      );
      return;
    }

    final nameLen = readUint32BE(plaintext);
    if (nameLen > plaintext.length - 4) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Invalid filename length: $nameLen',
      );
      return;
    }

    final filename = utf8.decode(plaintext.sublist(4, 4 + nameLen));
    final fileData = plaintext.sublist(4 + nameLen);

    // Store result BEFORE yield — async* generators suspend at yield, so
    // the listener reads lastResult before the line after yield executes.
    _lastResult = DecodeResult(filename: filename, data: fileData);

    yield DecodeProgress(
      state: DecodeState.done,
      progress: 1.0,
      message: 'Decoded: $filename (${fileData.length} bytes)',
    );
  }

  /// Decode a raw binary file (from C++ scanner) with a passphrase.
  Stream<DecodeProgress> decodeBinary(
    Uint8List binaryData,
    String passphrase,
  ) async* {
    yield const DecodeProgress(
      state: DecodeState.decrypting,
      progress: 0.5,
      message: 'Decrypting binary...',
    );

    final Uint8List plaintext;
    try {
      plaintext = CryptoService.decrypt(binaryData, passphrase);
    } catch (e) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Decryption failed: $e',
      );
      return;
    }

    if (plaintext.length < 4) {
      yield const DecodeProgress(
        state: DecodeState.error,
        message: 'Decrypted data too short for file header',
      );
      return;
    }

    final nameLen = readUint32BE(plaintext);
    if (nameLen > plaintext.length - 4) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Invalid filename length: $nameLen',
      );
      return;
    }

    final filename = utf8.decode(plaintext.sublist(4, 4 + nameLen));
    final fileData = plaintext.sublist(4 + nameLen);

    _lastResult = DecodeResult(filename: filename, data: fileData);

    yield DecodeProgress(
      state: DecodeState.done,
      progress: 1.0,
      message: 'Decoded: $filename (${fileData.length} bytes)',
    );
  }

  DecodeResult? _lastResult;
  DecodeResult? get lastResult => _lastResult;
}
