import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import '../models/barcode_rect.dart';
import '../models/decode_tuning_config.dart';
import 'cimbar_decoder.dart';
import 'frame_locator.dart';
import 'image_preprocessing.dart';
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

  /// Verbose multi-line diagnostics for ADB logcat (only when collectStats).
  final String? debugInfo;

  /// Short one-liner for AR overlay (only when collectStats).
  final String? overlayLine;

  /// Whether the metadata block indicates the payload is encrypted.
  final bool? isEncrypted;

  const IsolateFrameResult({
    this.dataBytes,
    this.frameSize,
    this.barcodeRect,
    required this.sourceImageWidth,
    required this.sourceImageHeight,
    this.rawFramePng,
    this.croppedFramePng,
    this.debugInfo,
    this.overlayLine,
    this.isEncrypted,
  });
}

/// Metadata block read result.
class MetadataBlockResult {
  final bool valid;
  final int? frameSize;
  final bool? isEncrypted;
  const MetadataBlockResult({required this.valid, this.frameSize, this.isEncrypted});
}

/// Read the center 3x3 metadata block from a frame image.
/// Verifies checkerboard corners (TL=dark, TR=bright, BL=bright, BR=dark).
MetadataBlockResult readMetadataBlock(img.Image image, int cols, int frameSize) {
  const cs = CimbarConstants.cellSize;
  final cx = cols ~/ 2 - 1;

  double sampleLuma(int col, int row) {
    final px = (col * cs + cs ~/ 2).clamp(0, image.width - 1);
    final py = (row * cs + cs ~/ 2).clamp(0, image.height - 1);
    final p = image.getPixel(px, py);
    return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
  }

  // Verify checkerboard corners
  final tlLuma = sampleLuma(cx, cx);
  final trLuma = sampleLuma(cx + 2, cx);
  final blLuma = sampleLuma(cx, cx + 2);
  final brLuma = sampleLuma(cx + 2, cx + 2);

  if (!(tlLuma < 128 && trLuma > 128 && blLuma > 128 && brLuma < 128)) {
    return const MetadataBlockResult(valid: false);
  }

  // Read data bits
  final d0 = sampleLuma(cx + 1, cx) > 128 ? 1 : 0;
  final d1 = sampleLuma(cx, cx + 1) > 128 ? 1 : 0;
  final d2 = sampleLuma(cx + 1, cx + 1) > 128 ? 1 : 0;

  final sizeBits = (d0 << 1) | d1;
  final detectedSize = CimbarConstants.bitsToFrameSize[sizeBits] ?? frameSize;

  return MetadataBlockResult(
    valid: true,
    frameSize: detectedSize,
    isEncrypted: d2 == 1,
  );
}

/// Internal decode result carrying the strategy that worked and stats.
class _DecodeOutcome {
  final Uint8List data;
  final int frameSize;
  final String warpStrategy; // '4pt', '2pt', 'crop', 'center-crop'
  final DecodeStats? stats;
  final bool labFallback;
  final bool? isEncrypted;

  _DecodeOutcome({
    required this.data,
    required this.frameSize,
    required this.warpStrategy,
    this.stats,
    this.labFallback = false,
    this.isEncrypted,
  });
}

/// Top-level function suitable for [Isolate.run]. Performs all heavy
/// computation: YUV→RGB conversion, barcode location, perspective warp,
/// and CimBar decode with RS error correction.
IsolateFrameResult decodeFrameInIsolate(IsolateFrameInput input) {
  final totalSw = Stopwatch()..start();
  final collect = input.collectStats;
  final log = collect ? <String>[] : null;

  // 1. YUV → RGB
  final yuvSw = Stopwatch()..start();
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
  final yuvMs = yuvSw.elapsedMilliseconds;

  // Optionally capture raw frame
  Uint8List? rawFramePng;
  if (input.captureFrame) {
    rawFramePng = Uint8List.fromList(img.encodePng(image));
  }

  final decoder = CimbarDecoder();
  final tuning = input.tuningConfig;

  _DecodeOutcome? outcome;
  BarcodeRect? barcodeRect;
  Uint8List? croppedFramePng;

  // Finder/locate diagnostics
  int findersFound = 0;
  int locateMs = 0;
  String? locateError;

  // Strategy 1: FrameLocator (bright-region detection)
  final locateSw = Stopwatch()..start();
  LocateResult? locateResult;
  try {
    locateResult = FrameLocator.locate(image);
    locateMs = locateSw.elapsedMilliseconds;
    barcodeRect = locateResult.boundingBox;

    // Count finders
    final finders = [
      locateResult.tlFinderCenter,
      locateResult.trFinderCenter,
      locateResult.blFinderCenter,
      locateResult.brFinderCenter,
    ];
    findersFound = finders.where((f) => f != null).length;

    final decodeSw = Stopwatch()..start();
    outcome = _tryDecodeImage(
      decoder, locateResult.cropped, tuning, input.lockedFrameSize,
      sourcePhoto: image, locateResult: locateResult,
      collectStats: collect, log: log,
    );
    final decodeMs = decodeSw.elapsedMilliseconds;

    if (outcome != null && input.captureFrame) {
      final cropped = _getDecodedImage(
        locateResult.cropped, outcome.frameSize,
        sourcePhoto: image, locateResult: locateResult,
      );
      if (cropped != null) {
        croppedFramePng = Uint8List.fromList(img.encodePng(cropped));
      }
    }

    // On capture + failure: save the first warp attempt so we can see it
    if (outcome == null && input.captureFrame && findersFound >= 2) {
      final captureImg = _getDecodedImage(
        locateResult.cropped, 256,
        sourcePhoto: image, locateResult: locateResult,
      );
      if (captureImg != null) {
        croppedFramePng = Uint8List.fromList(img.encodePng(captureImg));
      }
    }

    if (collect) {
      locateMs = locateSw.elapsedMilliseconds - decodeMs;
    }
  } catch (e) {
    locateMs = locateSw.elapsedMilliseconds;
    locateError = e.toString();
  }

  // Strategy 2: Center square crop
  int centerCropMs = 0;
  if (outcome == null) {
    final centerSw = Stopwatch()..start();
    final minDim = min(image.width, image.height);
    final cropX = (image.width - minDim) ~/ 2;
    final cropY = (image.height - minDim) ~/ 2;
    final center = img.copyCrop(image,
        x: cropX, y: cropY, width: minDim, height: minDim);
    outcome = _tryDecodeImage(
      decoder, center, tuning, input.lockedFrameSize,
      collectStats: collect, log: log,
      logPrefix: 'center',
    );
    centerCropMs = centerSw.elapsedMilliseconds;
    if (outcome != null) {
      outcome = _DecodeOutcome(
        data: outcome.data,
        frameSize: outcome.frameSize,
        warpStrategy: 'center-crop',
        stats: outcome.stats,
        labFallback: outcome.labFallback,
        isEncrypted: outcome.isEncrypted,
      );
      barcodeRect = BarcodeRect(
          x: cropX, y: cropY, width: minDim, height: minDim);
      if (input.captureFrame) {
        final resized = img.copyResize(center,
            width: outcome.frameSize, height: outcome.frameSize,
            interpolation: img.Interpolation.nearest);
        croppedFramePng = Uint8List.fromList(img.encodePng(resized));
      }
    }
  }

  final totalMs = totalSw.elapsedMilliseconds;

  // Build diagnostic strings
  String? debugInfo;
  String? overlayLine;
  if (collect) {
    final ok = outcome != null;
    final lines = <String>[];

    // Locate line
    lines.add(_fmtLocate(0, locateResult));

    // Per-attempt lines (warp, wb, decode) from log
    if (log != null) lines.addAll(log);

    // Gate line
    if (ok) {
      lines.add(_fmtGate(0, true, outcome.data.length, outcome.warpStrategy));
    } else {
      lines.add(_fmtGate(0, false, 0, 'none'));
    }

    debugInfo = lines.join('\n');

    // Short overlay line (unchanged format — for AR display)
    if (ok) {
      overlayLine = 'OK ${outcome.frameSize}px '
          '${outcome.warpStrategy} ${totalMs}ms '
          'f=$findersFound';
    } else {
      overlayLine = 'FAIL ${totalMs}ms f=$findersFound'
          '${locateError != null ? ' err' : ''}';
    }
  }

  return IsolateFrameResult(
    dataBytes: outcome?.data,
    frameSize: outcome?.frameSize,
    barcodeRect: barcodeRect,
    sourceImageWidth: image.width,
    sourceImageHeight: image.height,
    rawFramePng: rawFramePng,
    croppedFramePng: croppedFramePng,
    debugInfo: debugInfo,
    overlayLine: overlayLine,
    isEncrypted: outcome?.isEncrypted,
  );
}

/// Format structured locate diagnostic line.
String _fmtLocate(int frameNum, LocateResult? loc) {
  final sb = StringBuffer('frame=$frameNum stage=locate');
  sb.write(' candidates=${loc?.candidateCount ?? 0}');
  if (loc?.tlFinderCenter != null) {
    sb.write(' tl=${loc!.tlFinderCenter!.x.toInt()},${loc.tlFinderCenter!.y.toInt()}');
  }
  if (loc?.trFinderCenter != null) {
    sb.write(' tr=${loc!.trFinderCenter!.x.toInt()},${loc.trFinderCenter!.y.toInt()}');
  }
  if (loc?.blFinderCenter != null) {
    sb.write(' bl=${loc!.blFinderCenter!.x.toInt()},${loc.blFinderCenter!.y.toInt()}');
  }
  if (loc?.brFinderCenter != null) {
    sb.write(' br=${loc!.brFinderCenter!.x.toInt()},${loc.brFinderCenter!.y.toInt()}');
  }
  if (loc?.tlLuma != null) sb.write(' tlLuma=${loc!.tlLuma!.toStringAsFixed(0)}');
  if (loc?.gapOk != null) sb.write(' gapOk=${loc!.gapOk}');
  if (loc?.devNorm != null) sb.write(' devNorm=${loc!.devNorm!.toStringAsFixed(3)}');
  return sb.toString();
}

String _fmtWarp(int frameNum, String strategy, String srcPts, int dstSize) {
  return 'frame=$frameNum stage=warp strategy=$strategy srcPts="$srcPts" dstSize=$dstSize';
}

String _fmtWb(int frameNum, DecodeStats? stats, String src) {
  final sb = StringBuffer('frame=$frameNum stage=wb');
  if (stats?.wbWhitePoint != null) {
    final wp = stats!.wbWhitePoint!;
    sb.write(' wpR=${wp[0].toStringAsFixed(0)} wpG=${wp[1].toStringAsFixed(0)} wpB=${wp[2].toStringAsFixed(0)}');
  }
  sb.write(' src=$src');
  return sb.toString();
}

String _fmtDecode(int frameNum, DecodeStats? stats, bool useHashDetection) {
  final sb = StringBuffer('frame=$frameNum stage=decode');
  if (stats != null) {
    sb.write(' cells=${stats.cellCount}');
    sb.write(' rsBlocks=${stats.rsBlocks} rsOk=${stats.rsOk} rsFail=${stats.rsFail}');
    if (stats.rsBlocks > 0) {
      sb.write(' errRate=${(stats.rsFail / stats.rsBlocks).toStringAsFixed(3)}');
    }
    if (useHashDetection && stats.hammingSum > 0) {
      sb.write(' hashMean=${stats.hammingAvg.toStringAsFixed(1)} hashMax=${stats.hammingMax}');
      sb.write(' driftXFinal=${stats.driftXFinal} driftYFinal=${stats.driftYFinal}');
    }
  }
  return sb.toString();
}

String _fmtGate(int frameNum, bool pass, int bytes, String method) {
  return 'frame=$frameNum stage=gate pass=$pass bytes=$bytes method=$method';
}

/// Try all candidate frame sizes on a cropped image.
_DecodeOutcome? _tryDecodeImage(
  CimbarDecoder decoder,
  img.Image cropped,
  DecodeTuningConfig tuning,
  int? lockedFrameSize, {
  img.Image? sourcePhoto,
  LocateResult? locateResult,
  bool collectStats = false,
  List<String>? log,
  String logPrefix = 'loc',
}) {
  if (lockedFrameSize != null) {
    return _tryDecode(decoder, cropped, lockedFrameSize, tuning,
        sourcePhoto: sourcePhoto, locateResult: locateResult,
        collectStats: collectStats, log: log, logPrefix: logPrefix);
  }
  for (final size in CimbarConstants.frameSizes) {
    final outcome = _tryDecode(decoder, cropped, size, tuning,
        sourcePhoto: sourcePhoto, locateResult: locateResult,
        collectStats: collectStats, log: log, logPrefix: logPrefix);
    if (outcome != null) return outcome;
  }
  return null;
}

/// Try to decode at a specific frame size with perspective warp fallback.
_DecodeOutcome? _tryDecode(
  CimbarDecoder decoder,
  img.Image cropped,
  int frameSize,
  DecodeTuningConfig tuning, {
  img.Image? sourcePhoto,
  LocateResult? locateResult,
  bool collectStats = false,
  List<String>? log,
  String logPrefix = 'loc',
}) {
  // Track WB white point from warp strategies to share with crop fallback.
  // Warped images have finders at correct grid positions, so WB sampling works.
  // Crop images may have padding that shifts finders away from grid corners.
  List<double>? capturedWb;

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
        // Determine if source region is smaller than frameSize (→ upscaling)
        final tl = locateResult.tlFinderCenter!;
        final tr = locateResult.trFinderCenter!;
        final bl = locateResult.blFinderCenter!;
        final edgeTop = sqrt((tr.x - tl.x) * (tr.x - tl.x) +
            (tr.y - tl.y) * (tr.y - tl.y));
        final edgeLeft = sqrt((bl.x - tl.x) * (bl.x - tl.x) +
            (bl.y - tl.y) * (bl.y - tl.y));
        final needsSharpen = edgeTop < frameSize && edgeLeft < frameSize;

        final sw = Stopwatch()..start();
        final warped = PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
        // Capture WB from warped image (finders at correct grid positions)
        capturedWb ??= CimbarDecoder.sampleFinderWhite(warped, frameSize);
        log?.add(_fmtWarp(0, '4pt',
            '${tl.x.toInt()},${tl.y.toInt()} '
            '${tr.x.toInt()},${tr.y.toInt()} '
            '${bl.x.toInt()},${bl.y.toInt()} '
            '${locateResult.brFinderCenter!.x.toInt()},${locateResult.brFinderCenter!.y.toInt()}',
            frameSize));
        final result = _tryDecodeResized(decoder, warped, frameSize, tuning,
            collectStats: collectStats, log: log,
            needsSharpen: needsSharpen);
        if (result != null) {
          return _DecodeOutcome(
            data: result.data,
            frameSize: frameSize,
            warpStrategy: '4pt',
            stats: result.stats,
            labFallback: result.labFallback,
            isEncrypted: result.isEncrypted,
          );
        }
      } else {
        log?.add(_fmtWarp(0, '4pt', 'corners=null', frameSize));
      }
    }

    // Strategy B: 2-point warp
    if (locateResult.tlFinderCenter != null &&
        locateResult.brFinderCenter != null) {
      final corners = PerspectiveTransform.computeBarcodeCorners(
          locateResult.tlFinderCenter!, locateResult.brFinderCenter!, frameSize);
      if (corners != null) {
        // Estimate source size from TL-BR diagonal
        final tl = locateResult.tlFinderCenter!;
        final br = locateResult.brFinderCenter!;
        final diag = sqrt((br.x - tl.x) * (br.x - tl.x) +
            (br.y - tl.y) * (br.y - tl.y));
        // Diagonal of a square of side s = s*sqrt(2), so side ≈ diag/1.414
        final estSide = diag / 1.414;
        final needsSharpen = estSide < frameSize;

        final sw = Stopwatch()..start();
        final warped = PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
        // Capture WB from warped image if not already captured from 4pt
        capturedWb ??= CimbarDecoder.sampleFinderWhite(warped, frameSize);
        log?.add(_fmtWarp(0, '2pt',
            '${tl.x.toInt()},${tl.y.toInt()} '
            '${br.x.toInt()},${br.y.toInt()}',
            frameSize));
        final result = _tryDecodeResized(decoder, warped, frameSize, tuning,
            collectStats: collectStats, log: log,
            needsSharpen: needsSharpen);
        if (result != null) {
          return _DecodeOutcome(
            data: result.data,
            frameSize: frameSize,
            warpStrategy: '2pt',
            stats: result.stats,
            labFallback: result.labFallback,
            isEncrypted: result.isEncrypted,
          );
        }
      } else {
        log?.add(_fmtWarp(0, '2pt', 'corners=null', frameSize));
      }
    }
  }

  // Strategy C: crop+resize — pass WB from warp strategies if available
  final needsSharpen = cropped.width < frameSize || cropped.height < frameSize;
  final sw = Stopwatch()..start();
  log?.add(_fmtWarp(0, 'crop', 'resize', frameSize));
  final result = _tryDecodeResized(
      decoder,
      img.copyResize(cropped,
          width: frameSize, height: frameSize,
          interpolation: img.Interpolation.nearest),
      frameSize, tuning, collectStats: collectStats, log: log,
      needsSharpen: needsSharpen,
      whitePoint: capturedWb);
  if (result != null) {
    return _DecodeOutcome(
      data: result.data,
      frameSize: frameSize,
      warpStrategy: 'crop',
      stats: result.stats,
      labFallback: result.labFallback,
    );
  }
  return null;
}

/// Internal result from _tryDecodeResized (carries stats + LAB flag).
class _ResizedResult {
  final Uint8List data;
  final DecodeStats? stats;
  final bool labFallback;
  final bool? isEncrypted;
  _ResizedResult(this.data, {this.stats, this.labFallback = false, this.isEncrypted});
}

/// Decode a pre-sized image and apply quality gate + LAB failover.
_ResizedResult? _tryDecodeResized(
  CimbarDecoder decoder,
  img.Image resized,
  int frameSize,
  DecodeTuningConfig tuning, {
  bool collectStats = false,
  List<String>? log,
  bool needsSharpen = false,
  List<double>? whitePoint,
}) {
  try {
    // Metadata block shortcut: verify frame size before expensive decode
    final cols = frameSize ~/ CimbarConstants.cellSize;
    final meta = readMetadataBlock(resized, cols, frameSize);
    if (meta.valid && meta.frameSize != frameSize) {
      return null;
    }

    // Preprocess for symbol detection if adaptive threshold is enabled
    Uint8List? preprocessedGray;
    if (tuning.useAdaptiveThreshold && tuning.useHashDetection) {
      preprocessedGray = ImagePreprocessing.preprocessSymbolGrid(
          resized, needsSharpen: needsSharpen);
    }

    final stats = collectStats ? DecodeStats() : null;
    final rawBytes = decoder.decodeFramePixels(resized, frameSize,
        enableWhiteBalance: tuning.enableWhiteBalance,
        useRelativeColor: tuning.useRelativeColor,
        symbolThreshold: tuning.symbolThreshold,
        quadrantOffset: tuning.quadrantOffset,
        useHashDetection: tuning.useHashDetection,
        preprocessedGray: preprocessedGray,
        whitePoint: whitePoint,
        stats: stats);
    final dataBytes = decoder.decodeRSFrame(rawBytes, frameSize, stats: stats);

    // Determine WB source for structured logging
    final wbSrc = whitePoint != null ? 'warp' : (stats?.whiteBalanceApplied == true ? 'crop' : 'none');
    log?.add(_fmtWb(0, stats, wbSrc));
    log?.add(_fmtDecode(0, stats, tuning.useHashDetection));

    if (dataBytes.isEmpty) {
      return null;
    }

    // Quality gate: reject frames where first 64 bytes are all zero
    var nonZero = 0;
    final checkLen = min(64, dataBytes.length);
    for (var i = 0; i < checkLen; i++) {
      if (dataBytes[i] != 0) nonZero++;
    }
    if (nonZero == 0) {
      // Retry with LAB color space (reuse same preprocessed gray — symbols unchanged)
      final statsLab = collectStats ? DecodeStats() : null;
      final rawBytesLab = decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: tuning.enableWhiteBalance,
          useRelativeColor: false,
          symbolThreshold: tuning.symbolThreshold,
          quadrantOffset: tuning.quadrantOffset,
          useHashDetection: tuning.useHashDetection,
          useLabColor: true,
          preprocessedGray: preprocessedGray,
          whitePoint: whitePoint,
          stats: statsLab);
      final dataBytesLab = decoder.decodeRSFrame(rawBytesLab, frameSize, stats: statsLab);

      log?.add(_fmtWb(0, statsLab, '${wbSrc}+LAB'));
      log?.add(_fmtDecode(0, statsLab, tuning.useHashDetection));

      if (dataBytesLab.isEmpty) {
        return null;
      }

      var nonZeroLab = 0;
      final checkLenLab = min(64, dataBytesLab.length);
      for (var i = 0; i < checkLenLab; i++) {
        if (dataBytesLab[i] != 0) nonZeroLab++;
      }
      if (nonZeroLab == 0) {
        return null;
      }

      return _ResizedResult(dataBytesLab,
          stats: statsLab, labFallback: true,
          isEncrypted: meta.valid ? meta.isEncrypted : null);
    }

    return _ResizedResult(dataBytes, stats: stats,
        isEncrypted: meta.valid ? meta.isEncrypted : null);
  } catch (e) {
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
