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
import 'frame_decode_isolate.dart' show readMetadataBlock;
import 'frame_locator.dart';
import 'image_preprocessing.dart';
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

    // 4. Extract payload using 4-byte length prefix
    final payloadLength = readUint32BE(dataBytes);
    final payloadBytes = dataBytes.sublist(4, 4 + payloadLength);

    // 5. Auto-detect encryption via magic bytes
    final Uint8List fileHeaderBytes;
    final isEncrypted = payloadBytes.length >= 2 &&
        payloadBytes[0] == CimbarConstants.magic[0] &&
        payloadBytes[1] == CimbarConstants.magic[1];

    if (isEncrypted) {
      yield const DecodeProgress(
        state: DecodeState.decrypting,
        progress: 0.6,
        message: 'Decrypting...',
      );

      try {
        fileHeaderBytes = CryptoService.decrypt(payloadBytes, passphrase);
      } catch (e) {
        yield DecodeProgress(
          state: DecodeState.error,
          message: 'Decryption failed: $e',
        );
        return;
      }
    } else {
      fileHeaderBytes = payloadBytes;
    }

    // 6. Parse file header: [4-byte nameLen][nameBytes][fileData]
    if (fileHeaderBytes.length < 4) {
      yield const DecodeProgress(
        state: DecodeState.error,
        message: 'Data too short for file header',
      );
      return;
    }

    final nameLen = readUint32BE(fileHeaderBytes);
    if (nameLen > fileHeaderBytes.length - 4) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Invalid filename length: $nameLen',
      );
      return;
    }

    final filename = utf8.decode(fileHeaderBytes.sublist(4, 4 + nameLen));
    final fileData = fileHeaderBytes.sublist(4 + nameLen);

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
          // Determine if source region is smaller than frameSize (→ upscaling)
          final tl = locateResult.tlFinderCenter!;
          final tr = locateResult.trFinderCenter!;
          final bl = locateResult.blFinderCenter!;
          final edgeTop = sqrt((tr.x - tl.x) * (tr.x - tl.x) +
              (tr.y - tl.y) * (tr.y - tl.y));
          final edgeLeft = sqrt((bl.x - tl.x) * (bl.x - tl.x) +
              (bl.y - tl.y) * (bl.y - tl.y));
          final needsSharpen4pt = edgeTop < frameSize && edgeLeft < frameSize;

          final result = _tryDecodeAtSize(sourcePhoto, frameSize, config,
              usePerspective: true, use4Point: true,
              locateResult: locateResult, needsSharpen: needsSharpen4pt);
          if (result != null) return (frameSize, result);
        }

        // Strategy B: 2-point perspective warp (TL+BR only)
        if (locateResult.tlFinderCenter != null &&
            locateResult.brFinderCenter != null) {
          // Estimate source size from TL-BR diagonal
          final tl = locateResult.tlFinderCenter!;
          final br = locateResult.brFinderCenter!;
          final diag = sqrt((br.x - tl.x) * (br.x - tl.x) +
              (br.y - tl.y) * (br.y - tl.y));
          final estSide = diag / 1.414;
          final needsSharpen2pt = estSide < frameSize;

          final result = _tryDecodeAtSize(sourcePhoto, frameSize, config,
              usePerspective: true, locateResult: locateResult,
              needsSharpen: needsSharpen2pt);
          if (result != null) return (frameSize, result);
        }
      }

      // Strategy C: existing crop+resize
      final needsSharpenCrop =
          cropped.width < frameSize || cropped.height < frameSize;
      final result = _tryDecodeAtSize(cropped, frameSize, config,
          needsSharpen: needsSharpenCrop);
      if (result != null) return (frameSize, result);
    }
    return null;
  }

  /// Try to decode an image at a specific frame size.
  ///
  /// If [usePerspective] is true, applies a perspective warp using finder
  /// centers from [locateResult]. When [use4Point] is true, uses all 4 finder
  /// centers for the warp; otherwise uses only TL+BR (2-point method).
  ///
  /// Matches the decode logic in `_tryDecodeResized()` from
  /// `frame_decode_isolate.dart`: metadata block shortcut, adaptive threshold
  /// preprocessing, quality gate, and LAB failover.
  Uint8List? _tryDecodeAtSize(
    img.Image source,
    int frameSize,
    DecodeTuningConfig config, {
    bool usePerspective = false,
    bool use4Point = false,
    LocateResult? locateResult,
    bool needsSharpen = false,
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

      // Metadata block shortcut: verify frame size before expensive decode
      final cols = frameSize ~/ CimbarConstants.cellSize;
      final meta = readMetadataBlock(resized, cols, frameSize);
      if (meta.valid && meta.frameSize != frameSize) {
        return null;
      }

      // Preprocess for symbol detection if adaptive threshold is enabled
      Uint8List? preprocessedGray;
      if (config.useAdaptiveThreshold && config.useHashDetection) {
        preprocessedGray = ImagePreprocessing.preprocessSymbolGrid(
            resized, needsSharpen: needsSharpen);
      }

      // Decode pixels -> raw bytes -> RS decode
      final rawBytes = _decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: config.enableWhiteBalance,
          useRelativeColor: config.useRelativeColor,
          symbolThreshold: config.symbolThreshold,
          quadrantOffset: config.quadrantOffset,
          useHashDetection: config.useHashDetection,
          preprocessedGray: preprocessedGray);
      final dataBytes = _decoder.decodeRSFrame(rawBytes, frameSize);

      if (dataBytes.isEmpty) return null;

      // Quality gate: reject frames where first 64 bytes are all zero
      var nonZero = 0;
      final checkLen = min(64, dataBytes.length);
      for (var i = 0; i < checkLen; i++) {
        if (dataBytes[i] != 0) nonZero++;
      }

      if (nonZero == 0) {
        // Retry with LAB color space (reuse preprocessedGray — symbols unchanged)
        final rawBytesLab = _decoder.decodeFramePixels(resized, frameSize,
            enableWhiteBalance: config.enableWhiteBalance,
            useRelativeColor: false,
            symbolThreshold: config.symbolThreshold,
            quadrantOffset: config.quadrantOffset,
            useHashDetection: config.useHashDetection,
            useLabColor: true,
            preprocessedGray: preprocessedGray);
        final dataBytesLab = _decoder.decodeRSFrame(rawBytesLab, frameSize);

        if (dataBytesLab.isEmpty) return null;

        var nonZeroLab = 0;
        final checkLenLab = min(64, dataBytesLab.length);
        for (var i = 0; i < checkLenLab; i++) {
          if (dataBytesLab[i] != 0) nonZeroLab++;
        }
        if (nonZeroLab == 0) return null;

        // Validate length prefix plausibility
        if (dataBytesLab.length < 4) return null;
        final payloadLengthLab = readUint32BE(dataBytesLab);
        if (payloadLengthLab >= 5 &&
            payloadLengthLab <= dataBytesLab.length - 4) {
          return dataBytesLab;
        }
        return null;
      }

      // Validate: need at least 4 bytes for length prefix
      if (dataBytes.length < 4) return null;

      final payloadLength = readUint32BE(dataBytes);

      // Plausibility check: payload must be >= 5 bytes (minimum for
      // unencrypted: 4 nameLen + 1 name char) and fit in data
      if (payloadLength >= 5 && payloadLength <= dataBytes.length - 4) {
        return dataBytes;
      }
    } catch (_) {
      // RS decode or other failure
    }
    return null;
  }
}
