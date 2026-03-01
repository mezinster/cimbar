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

  /// Verbose multi-line diagnostics for ADB logcat (only when collectStats).
  final String? debugInfo;

  /// Short one-liner for AR overlay (only when collectStats).
  final String? overlayLine;

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
  });
}

/// Internal decode result carrying the strategy that worked and stats.
class _DecodeOutcome {
  final Uint8List data;
  final int frameSize;
  final String warpStrategy; // '4pt', '2pt', 'crop', 'center-crop'
  final DecodeStats? stats;
  final bool labFallback;

  _DecodeOutcome({
    required this.data,
    required this.frameSize,
    required this.warpStrategy,
    this.stats,
    this.labFallback = false,
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
  String? finderCoords;
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
    if (collect && findersFound > 0) {
      final coords = <String>[];
      if (locateResult.tlFinderCenter != null) {
        coords.add('TL(${locateResult.tlFinderCenter!.x.toInt()},${locateResult.tlFinderCenter!.y.toInt()})');
      }
      if (locateResult.trFinderCenter != null) {
        coords.add('TR(${locateResult.trFinderCenter!.x.toInt()},${locateResult.trFinderCenter!.y.toInt()})');
      }
      if (locateResult.blFinderCenter != null) {
        coords.add('BL(${locateResult.blFinderCenter!.x.toInt()},${locateResult.blFinderCenter!.y.toInt()})');
      }
      if (locateResult.brFinderCenter != null) {
        coords.add('BR(${locateResult.brFinderCenter!.x.toInt()},${locateResult.brFinderCenter!.y.toInt()})');
      }
      finderCoords = coords.join(' ');
    }

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
    final sb = StringBuffer();

    // Line 1: summary
    sb.writeln('${ok ? "OK" : "FAIL"} ${image.width}x${image.height} '
        'total=${totalMs}ms yuv=${yuvMs}ms locate=${locateMs}ms');

    // Line 2: finders
    sb.write('  finders=$findersFound');
    if (finderCoords != null) sb.write(' $finderCoords');
    if (locateError != null) sb.write(' locate_err=$locateError');
    sb.writeln();

    // Line 3: rect + crop size
    if (barcodeRect != null) {
      sb.writeln('  rect=(${barcodeRect.x},${barcodeRect.y} '
          '${barcodeRect.width}x${barcodeRect.height})');
    }
    if (locateResult != null) {
      sb.writeln('  crop=${locateResult.cropped.width}x${locateResult.cropped.height}');
    }

    if (ok) {
      // Decode result
      sb.writeln('  decoded=${outcome!.frameSize}px '
          'warp=${outcome.warpStrategy}'
          '${outcome.labFallback ? ' LAB-fallback' : ''}');

      // Decode stats
      if (outcome.stats != null) {
        _writeStats(sb, outcome.stats!);
      }
    }

    // Per-attempt log (both success and failure)
    if (log != null && log.isNotEmpty) {
      for (final line in log) {
        sb.writeln('  $line');
      }
    }

    if (!ok && centerCropMs > 0) {
      sb.write('  center-crop=${centerCropMs}ms');
    }

    debugInfo = sb.toString();

    // Short overlay line
    if (ok) {
      overlayLine = 'OK ${outcome!.frameSize}px '
          '${outcome.warpStrategy} ${totalMs}ms '
          'f=${findersFound}';
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
  );
}

void _writeStats(StringBuffer sb, DecodeStats s) {
  sb.writeln('  cells=${s.cellCount} wb=${s.whiteBalanceApplied} '
      'sym15=${s.sym15Count}(${s.sym15Pct.toStringAsFixed(0)}%)');
  if (s.hammingSum > 0) {
    sb.writeln('  hamming=avg${s.hammingAvg.toStringAsFixed(1)}'
        '/min${s.hammingMin}/max${s.hammingMax} '
        'drift=(${s.driftXFinal},${s.driftYFinal}) '
        'driftCells=${s.driftNonZeroCount} '
        'driftAvg=${s.driftAbsAvg.toStringAsFixed(1)}');
  }
  sb.writeln('  color=${s.colorHist}');
  sb.writeln('  sym=${s.symHist}');
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
        final sw = Stopwatch()..start();
        final warped = PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
        final result = _tryDecodeResized(decoder, warped, frameSize, tuning,
            collectStats: collectStats, log: log,
            label: '$logPrefix/4pt/${frameSize}px');
        log?.add('$logPrefix/4pt/${frameSize}px: '
            '${result != null ? "OK" : "FAIL"} ${sw.elapsedMilliseconds}ms');
        if (result != null) {
          return _DecodeOutcome(
            data: result.data,
            frameSize: frameSize,
            warpStrategy: '4pt',
            stats: result.stats,
            labFallback: result.labFallback,
          );
        }
      } else {
        log?.add('$logPrefix/4pt/${frameSize}px: corners=null');
      }
    }

    // Strategy B: 2-point warp
    if (locateResult.tlFinderCenter != null &&
        locateResult.brFinderCenter != null) {
      final corners = PerspectiveTransform.computeBarcodeCorners(
          locateResult.tlFinderCenter!, locateResult.brFinderCenter!, frameSize);
      if (corners != null) {
        final sw = Stopwatch()..start();
        final warped = PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
        final result = _tryDecodeResized(decoder, warped, frameSize, tuning,
            collectStats: collectStats, log: log,
            label: '$logPrefix/2pt/${frameSize}px');
        log?.add('$logPrefix/2pt/${frameSize}px: '
            '${result != null ? "OK" : "FAIL"} ${sw.elapsedMilliseconds}ms');
        if (result != null) {
          return _DecodeOutcome(
            data: result.data,
            frameSize: frameSize,
            warpStrategy: '2pt',
            stats: result.stats,
            labFallback: result.labFallback,
          );
        }
      } else {
        log?.add('$logPrefix/2pt/${frameSize}px: corners=null');
      }
    }
  }

  // Strategy C: crop+resize
  final sw = Stopwatch()..start();
  final result = _tryDecodeResized(
      decoder,
      img.copyResize(cropped,
          width: frameSize, height: frameSize,
          interpolation: img.Interpolation.nearest),
      frameSize, tuning, collectStats: collectStats, log: log,
      label: '$logPrefix/crop/${frameSize}px');
  log?.add('$logPrefix/crop/${frameSize}px: '
      '${result != null ? "OK" : "FAIL"} ${sw.elapsedMilliseconds}ms');
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
  _ResizedResult(this.data, {this.stats, this.labFallback = false});
}

/// Decode a pre-sized image and apply quality gate + LAB failover.
_ResizedResult? _tryDecodeResized(
  CimbarDecoder decoder,
  img.Image resized,
  int frameSize,
  DecodeTuningConfig tuning, {
  bool collectStats = false,
  List<String>? log,
  String label = '',
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

    if (dataBytes.isEmpty) {
      if (stats != null) {
        log?.add('  $label RS=empty ${_statsShort(stats)}');
      }
      return null;
    }

    // Quality gate: reject frames where first 64 bytes are all zero
    var nonZero = 0;
    final checkLen = min(64, dataBytes.length);
    for (var i = 0; i < checkLen; i++) {
      if (dataBytes[i] != 0) nonZero++;
    }
    if (nonZero == 0) {
      if (stats != null) {
        log?.add('  $label RS=ok qgate=ZERO ${_statsShort(stats)}');
      }
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

      if (dataBytesLab.isEmpty) {
        log?.add('  $label LAB RS=empty');
        return null;
      }

      var nonZeroLab = 0;
      final checkLenLab = min(64, dataBytesLab.length);
      for (var i = 0; i < checkLenLab; i++) {
        if (dataBytesLab[i] != 0) nonZeroLab++;
      }
      if (nonZeroLab == 0) {
        log?.add('  $label LAB qgate=ZERO');
        return null;
      }

      log?.add('  $label LAB OK nz=$nonZeroLab/64');
      return _ResizedResult(dataBytesLab,
          stats: statsLab, labFallback: true);
    }

    if (stats != null) {
      log?.add('  $label RS=ok nz=$nonZero/64 ${_statsShort(stats)}');
    }
    return _ResizedResult(dataBytes, stats: stats);
  } catch (e) {
    log?.add('  $label exception: $e');
    return null;
  }
}

/// Short stats summary for per-attempt log lines.
String _statsShort(DecodeStats s) {
  final buf = StringBuffer('c=${s.cellCount}');
  buf.write(' s15=${s.sym15Pct.toStringAsFixed(0)}%');
  if (s.hammingSum > 0) {
    buf.write(' h=${s.hammingAvg.toStringAsFixed(1)}');
    buf.write(' d=(${s.driftXFinal},${s.driftYFinal})');
  }
  buf.write(' wb=${s.whiteBalanceApplied}');
  return buf.toString();
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
