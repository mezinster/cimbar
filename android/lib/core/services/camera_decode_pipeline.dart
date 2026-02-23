import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import '../models/decode_result.dart';
import '../models/decode_tuning_config.dart';
import '../utils/byte_utils.dart';
import 'cimbar_decoder.dart';
import 'crypto_service.dart';
import 'frame_locator.dart';
import 'perspective_transform.dart';

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
    String passphrase, {
    DecodeTuningConfig? tuningConfig,
  }) async* {
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
    final LocateResult locateResult;
    try {
      locateResult = FrameLocator.locate(photo);
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

    final sizeResult = _tryAllFrameSizes(cropped,
        tuningConfig: tuningConfig,
        sourcePhoto: photo,
        locateResult: locateResult);
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
  ///
  /// When [sourcePhoto] and [locateResult] with finder centers are available,
  /// tries perspective warp first per frame size, falling back to crop+resize.
  (int, Uint8List)? _tryAllFrameSizes(img.Image cropped, {
    DecodeTuningConfig? tuningConfig,
    img.Image? sourcePhoto,
    LocateResult? locateResult,
  }) {
    final config = tuningConfig ?? const DecodeTuningConfig();
    for (final frameSize in CimbarConstants.frameSizes) {
      if (sourcePhoto != null && locateResult != null) {
        // Strategy A: 4-point perspective warp (all 4 finders present)
        if (locateResult.tlFinderCenter != null &&
            locateResult.trFinderCenter != null &&
            locateResult.blFinderCenter != null &&
            locateResult.brFinderCenter != null) {
          final result = _tryDecodeAtSize(sourcePhoto, frameSize, config,
              usePerspective: true, use4Point: true, locateResult: locateResult);
          if (result != null) return (frameSize, result);
        }

        // Strategy B: 2-point perspective warp (TL+BR only)
        if (locateResult.tlFinderCenter != null &&
            locateResult.brFinderCenter != null) {
          final result = _tryDecodeAtSize(sourcePhoto, frameSize, config,
              usePerspective: true, locateResult: locateResult);
          if (result != null) return (frameSize, result);
        }
      }

      // Strategy C: existing crop+resize
      final result = _tryDecodeAtSize(cropped, frameSize, config);
      if (result != null) return (frameSize, result);
    }
    return null;
  }

  /// Try to decode an image at a specific frame size.
  ///
  /// If [usePerspective] is true, applies a perspective warp using finder
  /// centers from [locateResult]. When [use4Point] is true, uses all 4 finder
  /// centers for the warp; otherwise uses only TL+BR (2-point method).
  Uint8List? _tryDecodeAtSize(
    img.Image source,
    int frameSize,
    DecodeTuningConfig config, {
    bool usePerspective = false,
    bool use4Point = false,
    LocateResult? locateResult,
  }) {
    try {
      final img.Image resized;
      if (usePerspective && locateResult != null) {
        List<Point<double>>? corners;
        if (use4Point) {
          corners = PerspectiveTransform.computeBarcodeCornersFrom4(
              locateResult.tlFinderCenter!,
              locateResult.trFinderCenter!,
              locateResult.blFinderCenter!,
              locateResult.brFinderCenter!,
              frameSize);
        } else {
          corners = PerspectiveTransform.computeBarcodeCorners(
              locateResult.tlFinderCenter!, locateResult.brFinderCenter!,
              frameSize);
        }
        if (corners == null) return null;
        resized = PerspectiveTransform.warpPerspective(
            source, corners, frameSize);
      } else {
        resized = img.copyResize(source,
            width: frameSize,
            height: frameSize,
            interpolation: img.Interpolation.nearest);
      }

      // Decode pixels -> raw bytes -> RS decode
      final rawBytes = _decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: config.enableWhiteBalance,
          useRelativeColor: config.useRelativeColor,
          symbolThreshold: config.symbolThreshold,
          quadrantOffset: config.quadrantOffset,
          useHashDetection: config.useHashDetection);
      final dataBytes = _decoder.decodeRSFrame(rawBytes, frameSize);

      // Validate: need at least 4 bytes for length prefix
      if (dataBytes.length < 4) return null;

      final payloadLength = readUint32BE(dataBytes);

      // Plausibility check: payload must be >= 32 bytes (minimum for
      // AES-GCM: 4 magic + 16 salt + 12 IV + tag) and fit in data
      if (payloadLength >= 32 && payloadLength <= dataBytes.length - 4) {
        return dataBytes;
      }

      // Failover: retry with LAB color space
      final rawBytesLab = _decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: config.enableWhiteBalance,
          useRelativeColor: false, // LAB replaces relative color
          symbolThreshold: config.symbolThreshold,
          quadrantOffset: config.quadrantOffset,
          useHashDetection: config.useHashDetection,
          useLabColor: true);
      final dataBytesLab = _decoder.decodeRSFrame(rawBytesLab, frameSize);
      if (dataBytesLab.length < 4) return null;

      final payloadLengthLab = readUint32BE(dataBytesLab);
      if (payloadLengthLab >= 32 &&
          payloadLengthLab <= dataBytesLab.length - 4) {
        return dataBytesLab;
      }
    } catch (_) {
      // RS decode or other failure
    }
    return null;
  }
}
