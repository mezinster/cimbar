import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import '../models/barcode_rect.dart';
import '../models/decode_tuning_config.dart';
import 'cimbar_decoder.dart';
import 'frame_locator.dart';
import 'perspective_transform.dart';
import 'yuv_converter.dart';

/// Input data for [decodeFrameInIsolate]. All fields are primitive or
/// transferable types so they can cross isolate boundaries.
class IsolateFrameInput {
  final int width;
  final int height;
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final DecodeTuningConfig tuningConfig;
  final int? lockedFrameSize;
  final bool collectStats;
  final bool captureFrame;

  const IsolateFrameInput({
    required this.width,
    required this.height,
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.tuningConfig,
    this.lockedFrameSize,
    this.collectStats = false,
    this.captureFrame = false,
  });
}

/// Result from [decodeFrameInIsolate]. Null [dataBytes] means decode failed.
class IsolateFrameResult {
  final Uint8List? dataBytes;
  final int? frameSize;
  final BarcodeRect? barcodeRect;
  final int sourceImageWidth;
  final int sourceImageHeight;
  final Uint8List? rawFramePng;
  final Uint8List? croppedFramePng;

  const IsolateFrameResult({
    this.dataBytes,
    this.frameSize,
    this.barcodeRect,
    required this.sourceImageWidth,
    required this.sourceImageHeight,
    this.rawFramePng,
    this.croppedFramePng,
  });
}

/// Top-level function suitable for [Isolate.run]. Performs all heavy
/// computation: YUV→RGB conversion, barcode location, perspective warp,
/// and CimBar decode with RS error correction.
IsolateFrameResult decodeFrameInIsolate(IsolateFrameInput input) {
  // 1. YUV → RGB
  final image = YuvConverter.yuv420ToImage(
    width: input.width,
    height: input.height,
    yPlane: input.yPlane,
    uPlane: input.uPlane,
    vPlane: input.vPlane,
    yRowStride: input.yRowStride,
    uvRowStride: input.uvRowStride,
    uvPixelStride: input.uvPixelStride,
  );

  // Optionally capture raw frame
  Uint8List? rawFramePng;
  if (input.captureFrame) {
    rawFramePng = Uint8List.fromList(img.encodePng(image));
  }

  final decoder = CimbarDecoder();
  final tuning = input.tuningConfig;

  Uint8List? dataBytes;
  int? usedSize;
  BarcodeRect? barcodeRect;
  Uint8List? croppedFramePng;

  // Strategy 1: FrameLocator (bright-region detection)
  try {
    final locateResult = FrameLocator.locate(image);
    barcodeRect = locateResult.boundingBox;
    (dataBytes, usedSize) = _tryDecodeImage(
      decoder, locateResult.cropped, tuning, input.lockedFrameSize,
      sourcePhoto: image, locateResult: locateResult,
      collectStats: input.collectStats,
    );
    if (dataBytes != null && input.captureFrame) {
      // Capture the warped/cropped barcode image
      final cropped = _getDecodedImage(
        locateResult.cropped, usedSize!,
        sourcePhoto: image, locateResult: locateResult,
      );
      if (cropped != null) {
        croppedFramePng = Uint8List.fromList(img.encodePng(cropped));
      }
    }
  } catch (_) {
    // FrameLocator failed — try center crop
  }

  // Strategy 2: Center square crop
  if (dataBytes == null) {
    final minDim = min(image.width, image.height);
    final cropX = (image.width - minDim) ~/ 2;
    final cropY = (image.height - minDim) ~/ 2;
    final center = img.copyCrop(image,
        x: cropX, y: cropY, width: minDim, height: minDim);
    (dataBytes, usedSize) = _tryDecodeImage(
      decoder, center, tuning, input.lockedFrameSize,
      collectStats: input.collectStats,
    );
    if (dataBytes != null) {
      barcodeRect = BarcodeRect(
          x: cropX, y: cropY, width: minDim, height: minDim);
      if (input.captureFrame) {
        final resized = img.copyResize(center,
            width: usedSize!, height: usedSize,
            interpolation: img.Interpolation.nearest);
        croppedFramePng = Uint8List.fromList(img.encodePng(resized));
      }
    }
  }

  return IsolateFrameResult(
    dataBytes: dataBytes,
    frameSize: usedSize,
    barcodeRect: barcodeRect,
    sourceImageWidth: image.width,
    sourceImageHeight: image.height,
    rawFramePng: rawFramePng,
    croppedFramePng: croppedFramePng,
  );
}

/// Try all candidate frame sizes on a cropped image.
(Uint8List?, int?) _tryDecodeImage(
  CimbarDecoder decoder,
  img.Image cropped,
  DecodeTuningConfig tuning,
  int? lockedFrameSize, {
  img.Image? sourcePhoto,
  LocateResult? locateResult,
  bool collectStats = false,
}) {
  if (lockedFrameSize != null) {
    final data = _tryDecode(decoder, cropped, lockedFrameSize, tuning,
        sourcePhoto: sourcePhoto, locateResult: locateResult,
        collectStats: collectStats);
    if (data != null) return (data, lockedFrameSize);
    return (null, null);
  }
  for (final size in CimbarConstants.frameSizes) {
    final data = _tryDecode(decoder, cropped, size, tuning,
        sourcePhoto: sourcePhoto, locateResult: locateResult,
        collectStats: collectStats);
    if (data != null) return (data, size);
  }
  return (null, null);
}

/// Try to decode at a specific frame size with perspective warp fallback.
Uint8List? _tryDecode(
  CimbarDecoder decoder,
  img.Image cropped,
  int frameSize,
  DecodeTuningConfig tuning, {
  img.Image? sourcePhoto,
  LocateResult? locateResult,
  bool collectStats = false,
}) {
  if (sourcePhoto != null && locateResult != null) {
    // Strategy A: 4-point warp
    if (locateResult.tlFinderCenter != null &&
        locateResult.trFinderCenter != null &&
        locateResult.blFinderCenter != null &&
        locateResult.brFinderCenter != null) {
      final corners = PerspectiveTransform.computeBarcodeCornersFrom4(
          locateResult.tlFinderCenter!,
          locateResult.trFinderCenter!,
          locateResult.blFinderCenter!,
          locateResult.brFinderCenter!,
          frameSize);
      if (corners != null) {
        final warped = PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
        final result = _tryDecodeResized(decoder, warped, frameSize, tuning,
            collectStats: collectStats);
        if (result != null) return result;
      }
    }

    // Strategy B: 2-point warp
    if (locateResult.tlFinderCenter != null &&
        locateResult.brFinderCenter != null) {
      final corners = PerspectiveTransform.computeBarcodeCorners(
          locateResult.tlFinderCenter!, locateResult.brFinderCenter!, frameSize);
      if (corners != null) {
        final warped = PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
        final result = _tryDecodeResized(decoder, warped, frameSize, tuning,
            collectStats: collectStats);
        if (result != null) return result;
      }
    }
  }

  // Strategy C: crop+resize
  return _tryDecodeResized(
      decoder,
      img.copyResize(cropped,
          width: frameSize, height: frameSize,
          interpolation: img.Interpolation.nearest),
      frameSize, tuning, collectStats: collectStats);
}

/// Decode a pre-sized image and apply quality gate + LAB failover.
Uint8List? _tryDecodeResized(
  CimbarDecoder decoder,
  img.Image resized,
  int frameSize,
  DecodeTuningConfig tuning, {
  bool collectStats = false,
}) {
  try {
    final stats = collectStats ? DecodeStats() : null;
    final rawBytes = decoder.decodeFramePixels(resized, frameSize,
        enableWhiteBalance: tuning.enableWhiteBalance,
        useRelativeColor: tuning.useRelativeColor,
        symbolThreshold: tuning.symbolThreshold,
        quadrantOffset: tuning.quadrantOffset,
        useHashDetection: tuning.useHashDetection,
        stats: stats);
    final dataBytes = decoder.decodeRSFrame(rawBytes, frameSize);

    if (dataBytes.isEmpty) return null;

    // Quality gate: reject frames where first 64 bytes are all zero
    var nonZero = 0;
    final checkLen = min(64, dataBytes.length);
    for (var i = 0; i < checkLen; i++) {
      if (dataBytes[i] != 0) nonZero++;
    }
    if (nonZero == 0) {
      // Retry with LAB color space
      final statsLab = collectStats ? DecodeStats() : null;
      final rawBytesLab = decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: tuning.enableWhiteBalance,
          useRelativeColor: false,
          symbolThreshold: tuning.symbolThreshold,
          quadrantOffset: tuning.quadrantOffset,
          useHashDetection: tuning.useHashDetection,
          useLabColor: true,
          stats: statsLab);
      final dataBytesLab = decoder.decodeRSFrame(rawBytesLab, frameSize);

      if (dataBytesLab.isEmpty) return null;

      var nonZeroLab = 0;
      final checkLenLab = min(64, dataBytesLab.length);
      for (var i = 0; i < checkLenLab; i++) {
        if (dataBytesLab[i] != 0) nonZeroLab++;
      }
      if (nonZeroLab == 0) return null;

      return dataBytesLab;
    }

    return dataBytes;
  } catch (_) {
    return null;
  }
}

/// Get the final decoded image (warped or resized) for capture purposes.
img.Image? _getDecodedImage(
  img.Image cropped,
  int frameSize, {
  img.Image? sourcePhoto,
  LocateResult? locateResult,
}) {
  if (sourcePhoto != null && locateResult != null) {
    // Try 4-point warp
    if (locateResult.tlFinderCenter != null &&
        locateResult.trFinderCenter != null &&
        locateResult.blFinderCenter != null &&
        locateResult.brFinderCenter != null) {
      final corners = PerspectiveTransform.computeBarcodeCornersFrom4(
          locateResult.tlFinderCenter!,
          locateResult.trFinderCenter!,
          locateResult.blFinderCenter!,
          locateResult.brFinderCenter!,
          frameSize);
      if (corners != null) {
        return PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
      }
    }
    // Try 2-point warp
    if (locateResult.tlFinderCenter != null &&
        locateResult.brFinderCenter != null) {
      final corners = PerspectiveTransform.computeBarcodeCorners(
          locateResult.tlFinderCenter!, locateResult.brFinderCenter!, frameSize);
      if (corners != null) {
        return PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
      }
    }
  }
  return img.copyResize(cropped,
      width: frameSize, height: frameSize,
      interpolation: img.Interpolation.nearest);
}
