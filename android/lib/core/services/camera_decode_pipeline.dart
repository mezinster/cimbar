import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import '../models/decode_result.dart';
import '../utils/byte_utils.dart';
import 'cimbar_decoder.dart';
import 'crypto_service.dart';
import 'frame_locator.dart';

/// Single-frame decode pipeline for camera-captured photos.
///
/// Pipeline: Photo → locate barcode → crop → try all frame sizes →
///           RS decode → validate length prefix → decrypt → parse file header.
class CameraDecodePipeline {
  final CimbarDecoder _decoder = CimbarDecoder();

  DecodeResult? _lastResult;
  DecodeResult? get lastResult => _lastResult;

  /// Decode a single CimBar frame from a camera photo.
  Stream<DecodeProgress> decodePhoto(
    Uint8List imageBytes,
    String passphrase,
  ) async* {
    // 1. Decode image
    final photo = img.decodeImage(imageBytes);
    if (photo == null) {
      yield const DecodeProgress(
        state: DecodeState.error,
        message: 'Failed to decode image',
      );
      return;
    }

    // 2. Locate barcode region
    yield const DecodeProgress(
      state: DecodeState.locatingBarcode,
      progress: 0.1,
      message: 'Locating barcode...',
    );

    final img.Image cropped;
    try {
      final locateResult = FrameLocator.locate(photo);
      cropped = locateResult.cropped;
    } catch (e) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Barcode not found: $e',
      );
      return;
    }

    // 3. Try all frame sizes to find valid decode
    yield const DecodeProgress(
      state: DecodeState.detectingFrameSize,
      progress: 0.2,
      message: 'Detecting frame size...',
    );

    final sizeResult = _tryAllFrameSizes(cropped);
    if (sizeResult == null) {
      yield const DecodeProgress(
        state: DecodeState.error,
        message: 'No valid frame size found — could not decode barcode',
      );
      return;
    }

    final (frameSize, dataBytes) = sizeResult;

    yield DecodeProgress(
      state: DecodeState.detectingFrameSize,
      progress: 0.4,
      message: 'Detected frame size: ${frameSize}px',
    );

    // 4. Extract encrypted payload using 4-byte length prefix
    final payloadLength = readUint32BE(dataBytes);
    final encryptedPayload = dataBytes.sublist(4, 4 + payloadLength);

    // 5. Decrypt
    yield const DecodeProgress(
      state: DecodeState.decrypting,
      progress: 0.6,
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

    // 6. Parse file header: [4-byte nameLen][nameBytes][fileData]
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

  /// Try decoding the cropped image at each supported frame size.
  /// Returns (frameSize, dataBytes) for the first size that produces a
  /// plausible 4-byte length prefix, or null if none work.
  (int, Uint8List)? _tryAllFrameSizes(img.Image cropped) {
    for (final frameSize in CimbarConstants.frameSizes) {
      try {
        // Resize cropped barcode to candidate frame size
        final resized = img.copyResize(cropped,
            width: frameSize,
            height: frameSize,
            interpolation: img.Interpolation.linear);

        // Decode pixels -> raw bytes -> RS decode
        final rawBytes = _decoder.decodeFramePixels(resized, frameSize,
            enableWhiteBalance: true, useRelativeColor: true);
        final dataBytes = _decoder.decodeRSFrame(rawBytes, frameSize);

        // Validate: need at least 4 bytes for length prefix
        if (dataBytes.length < 4) continue;

        final payloadLength = readUint32BE(dataBytes);

        // Plausibility check: payload must be >= 32 bytes (minimum for
        // AES-GCM: 4 magic + 16 salt + 12 IV + tag) and fit in data
        if (payloadLength >= 32 && payloadLength <= dataBytes.length - 4) {
          return (frameSize, dataBytes);
        }
      } catch (_) {
        // RS decode or other failure at this size — try next
        continue;
      }
    }
    return null;
  }
}
