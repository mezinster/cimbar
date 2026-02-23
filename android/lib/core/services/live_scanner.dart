import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import '../models/barcode_rect.dart';
import '../models/decode_tuning_config.dart';
import '../utils/byte_utils.dart';
import 'cimbar_decoder.dart';
import 'frame_locator.dart';
import 'perspective_transform.dart';

/// Result of processing a single camera frame.
class ScanProgress {
  final int uniqueFrames;
  final int totalFrames;
  final bool isComplete;
  final int? detectedFrameSize;
  final BarcodeRect? barcodeRect;
  final int? sourceImageWidth;
  final int? sourceImageHeight;

  const ScanProgress({
    required this.uniqueFrames,
    required this.totalFrames,
    required this.isComplete,
    this.detectedFrameSize,
    this.barcodeRect,
    this.sourceImageWidth,
    this.sourceImageHeight,
  });
}

/// Assembled multi-frame scan result (raw data before decryption).
class ScanResult {
  final Uint8List data;
  final int frameSize;
  final int frameCount;

  const ScanResult({
    required this.data,
    required this.frameSize,
    required this.frameCount,
  });
}

/// Diagnostic info emitted via [LiveScanner.onDebug].
class ScanDebugInfo {
  final int framesAnalyzed;
  final int uniqueFrames;
  final int totalFrames;
  final int? detectedFrameSize;
  final String event; // e.g. 'frame_decoded', 'frame_rejected', 'crop_ratio'
  final String detail;

  const ScanDebugInfo({
    required this.framesAnalyzed,
    required this.uniqueFrames,
    required this.totalFrames,
    this.detectedFrameSize,
    required this.event,
    required this.detail,
  });

  @override
  String toString() =>
      '[$event] frames=$framesAnalyzed unique=$uniqueFrames/$totalFrames '
      'size=$detectedFrameSize $detail';
}

/// Live scanning engine for multi-frame CimBar barcodes.
///
/// Tracks unique frames via content hashing, uses adjacency-chain ordering
/// to reconstruct the correct frame sequence, and detects frame 0 via
/// its 4-byte big-endian length prefix.
class LiveScanner {
  final CimbarDecoder _decoder = CimbarDecoder();

  /// Optional debug callback for diagnostic logging.
  void Function(ScanDebugInfo)? onDebug;

  /// Runtime tuning configuration. Updated from settings UI.
  DecodeTuningConfig tuningConfig = const DecodeTuningConfig();

  /// Locked after first successful decode to avoid try-all-sizes overhead.
  int? _frameSize;

  /// Hash → decoded data bytes for each unique frame.
  final Map<String, Uint8List> _uniqueFrames = {};

  /// Hash of the most recently processed frame (for adjacency tracking).
  String? _lastHash;

  /// Adjacency map: hash → next hash (frame transitions).
  final Map<String, String> _adjacency = {};

  /// Hash of frame 0 (identified by length prefix).
  String? _frame0Hash;

  /// Total number of frames expected (derived from frame 0's length prefix).
  int _totalFrames = 0;

  /// Number of camera frames analyzed (including failures).
  int _framesAnalyzed = 0;

  int get uniqueFrameCount => _uniqueFrames.length;
  int get totalFrames => _totalFrames;
  int? get detectedFrameSize => _frameSize;
  int get framesAnalyzed => _framesAnalyzed;

  /// Process a single camera frame image.
  ///
  /// Returns [ScanProgress] with current state, or null if the frame
  /// could not be decoded (dark image, no barcode, etc.).
  ScanProgress? processFrame(img.Image photo) {
    _framesAnalyzed++;

    // Try multiple crop strategies to find the barcode
    Uint8List? dataBytes;
    int? usedSize;
    BarcodeRect? barcodeRect;

    // Strategy 1: FrameLocator (bright-region detection)
    try {
      final locateResult = FrameLocator.locate(photo);
      _emitDebug('crop_ratio',
          'crop=${locateResult.cropped.width}x${locateResult.cropped.height}');
      // Always use locator result — even when the barcode fills most of the
      // frame (normal scanning distance). Fall back to center-crop only if
      // FrameLocator throws or decode fails.
      barcodeRect = locateResult.boundingBox;
      (dataBytes, usedSize) = _tryDecodeImage(locateResult.cropped,
          sourcePhoto: photo, locateResult: locateResult);
      if (dataBytes != null) {
        _emitDebug('frame_decoded', 'strategy=locator size=$usedSize');
      } else {
        _emitDebug('frame_rejected', 'strategy=locator decode_failed');
      }
    } catch (_) {
      _emitDebug('frame_rejected', 'strategy=locator no_bright_region');
    }

    // Strategy 2: Center square crop (user points camera directly at barcode)
    if (dataBytes == null) {
      final minDim = min(photo.width, photo.height);
      final cropX = (photo.width - minDim) ~/ 2;
      final cropY = (photo.height - minDim) ~/ 2;
      final center = img.copyCrop(photo,
          x: cropX, y: cropY, width: minDim, height: minDim);
      (dataBytes, usedSize) = _tryDecodeImage(center);
      if (dataBytes != null) {
        barcodeRect = BarcodeRect(
            x: cropX, y: cropY, width: minDim, height: minDim);
        _emitDebug('frame_decoded', 'strategy=center size=$usedSize');
      } else {
        _emitDebug('frame_rejected', 'strategy=center decode_failed');
      }
    }

    if (dataBytes == null || usedSize == null) {
      // Even if decode failed, return progress with barcodeRect so the AR
      // overlay can highlight the detected region.
      if (barcodeRect != null) {
        return ScanProgress(
          uniqueFrames: _uniqueFrames.length,
          totalFrames: _totalFrames,
          isComplete: _isComplete(),
          detectedFrameSize: _frameSize,
          barcodeRect: barcodeRect,
          sourceImageWidth: photo.width,
          sourceImageHeight: photo.height,
        );
      }
      return null;
    }

    final progress = processDecodedData(dataBytes, usedSize);
    return ScanProgress(
      uniqueFrames: progress.uniqueFrames,
      totalFrames: progress.totalFrames,
      isComplete: progress.isComplete,
      detectedFrameSize: progress.detectedFrameSize,
      barcodeRect: barcodeRect,
      sourceImageWidth: photo.width,
      sourceImageHeight: photo.height,
    );
  }

  /// Process already-decoded frame data bytes.
  ///
  /// Handles deduplication, adjacency tracking, and frame 0 detection.
  /// [frameSize] is used for frame 0 length-prefix validation.
  ScanProgress processDecodedData(Uint8List dataBytes, int frameSize) {
    _frameSize ??= frameSize;

    // 1. Hash for deduplication
    final hash = _fnv1a(dataBytes);

    // 2. Track adjacency (if we have a previous frame and it's different)
    if (_lastHash != null && _lastHash != hash) {
      _adjacency[_lastHash!] = hash;
    }
    _lastHash = hash;

    // 3. Deduplicate
    if (_uniqueFrames.containsKey(hash)) {
      return ScanProgress(
        uniqueFrames: _uniqueFrames.length,
        totalFrames: _totalFrames,
        isComplete: _isComplete(),
        detectedFrameSize: _frameSize,
      );
    }

    // 4. Store new unique frame
    _uniqueFrames[hash] = dataBytes;
    _emitDebug('new_frame', 'hash=$hash unique=${_uniqueFrames.length} '
        'chain=${_adjacency.length} links');

    // 5. Check if this is frame 0 (has valid length prefix)
    if (_frame0Hash == null && dataBytes.length >= 4) {
      final payloadLength = readUint32BE(dataBytes);
      final dpf = CimbarConstants.dataBytesPerFrame(frameSize);
      // Payload must be >= 32 (min AES-GCM) and total frames 1..255
      if (payloadLength >= 32) {
        final framedLength = payloadLength + 4; // include the 4-byte prefix
        final numFrames = (framedLength + dpf - 1) ~/ dpf;
        if (numFrames >= 1 && numFrames <= 255) {
          _frame0Hash = hash;
          _totalFrames = numFrames;
        }
      }
    }

    return ScanProgress(
      uniqueFrames: _uniqueFrames.length,
      totalFrames: _totalFrames,
      isComplete: _isComplete(),
      detectedFrameSize: _frameSize,
    );
  }

  /// Assemble all captured frames in correct order.
  ///
  /// Follows the adjacency chain from frame 0 to reconstruct the sequence.
  /// Returns null if frame 0 is unknown or chain is incomplete.
  ScanResult? assemble() {
    if (_frame0Hash == null || _frameSize == null) return null;
    if (!_isComplete()) return null;

    final ordered = <Uint8List>[];
    var current = _frame0Hash!;
    final visited = <String>{};

    for (var i = 0; i < _totalFrames; i++) {
      if (visited.contains(current)) return null; // cycle detected
      visited.add(current);

      final data = _uniqueFrames[current];
      if (data == null) return null; // missing frame

      ordered.add(data);

      // Follow adjacency chain (except for last frame)
      if (i < _totalFrames - 1) {
        final next = _adjacency[current];
        if (next == null) return null; // broken chain
        current = next;
      }
    }

    // Concatenate all frame data
    final allData = concatBytes(ordered);

    return ScanResult(
      data: allData,
      frameSize: _frameSize!,
      frameCount: _totalFrames,
    );
  }

  /// Reset all state for a new scan.
  void reset() {
    _frameSize = null;
    _uniqueFrames.clear();
    _lastHash = null;
    _adjacency.clear();
    _frame0Hash = null;
    _totalFrames = 0;
    _framesAnalyzed = 0;
  }

  void _emitDebug(String event, String detail) {
    onDebug?.call(ScanDebugInfo(
      framesAnalyzed: _framesAnalyzed,
      uniqueFrames: _uniqueFrames.length,
      totalFrames: _totalFrames,
      detectedFrameSize: _frameSize,
      event: event,
      detail: detail,
    ));
  }

  /// Try all candidate frame sizes on a cropped image.
  /// Returns (dataBytes, frameSize) or (null, null).
  (Uint8List?, int?) _tryDecodeImage(img.Image cropped, {
    img.Image? sourcePhoto,
    LocateResult? locateResult,
  }) {
    if (_frameSize != null) {
      final data = _tryDecode(cropped, _frameSize!,
          sourcePhoto: sourcePhoto, locateResult: locateResult);
      if (data != null) return (data, _frameSize!);
      return (null, null);
    }
    for (final size in CimbarConstants.frameSizes) {
      final data = _tryDecode(cropped, size,
          sourcePhoto: sourcePhoto, locateResult: locateResult);
      if (data != null) {
        _frameSize = size;
        return (data, size);
      }
    }
    return (null, null);
  }

  /// Try to decode a cropped image at a specific frame size.
  ///
  /// When [sourcePhoto] and [locateResult] with finder centers are available,
  /// tries perspective warp first. Falls back to crop+resize if warp fails.
  Uint8List? _tryDecode(img.Image cropped, int frameSize, {
    img.Image? sourcePhoto,
    LocateResult? locateResult,
  }) {
    // Strategy A: perspective warp (when finder centers available)
    if (sourcePhoto != null &&
        locateResult?.tlFinderCenter != null &&
        locateResult?.brFinderCenter != null) {
      final corners = PerspectiveTransform.computeBarcodeCorners(
          locateResult!.tlFinderCenter!, locateResult.brFinderCenter!, frameSize);
      if (corners != null) {
        final warped = PerspectiveTransform.warpPerspective(
            sourcePhoto, corners, frameSize);
        final result = _tryDecodeResized(warped, frameSize);
        if (result != null) return result;
        _emitDebug('perspective_fallback',
            'warp failed RS for size=$frameSize, trying crop+resize');
      }
    }

    // Strategy B: existing crop+resize fallback
    return _tryDecodeResized(
        img.copyResize(cropped,
            width: frameSize,
            height: frameSize,
            interpolation: img.Interpolation.nearest),
        frameSize);
  }

  /// Decode a pre-sized image and apply quality gate.
  Uint8List? _tryDecodeResized(img.Image resized, int frameSize) {
    try {
      final stats = DecodeStats();
      final rawBytes = _decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: tuningConfig.enableWhiteBalance,
          useRelativeColor: tuningConfig.useRelativeColor,
          symbolThreshold: tuningConfig.symbolThreshold,
          quadrantOffset: tuningConfig.quadrantOffset,
          useHashDetection: tuningConfig.useHashDetection,
          stats: stats);
      final dataBytes = _decoder.decodeRSFrame(rawBytes, frameSize);

      _emitDebug('decode_stats', 'size=$frameSize $stats');

      if (dataBytes.isEmpty) return null;

      // Quality check: if the first 64 bytes are all zero, every RS block
      // failed and the decoded data is garbage — reject this frame.
      var nonZero = 0;
      final checkLen = min(64, dataBytes.length);
      for (var i = 0; i < checkLen; i++) {
        if (dataBytes[i] != 0) nonZero++;
      }
      if (nonZero == 0) {
        _emitDebug('quality_gate', 'REJECTED size=$frameSize nonZero=0/$checkLen, retrying LAB');
        // Retry with LAB color space
        final statsLab = DecodeStats();
        final rawBytesLab = _decoder.decodeFramePixels(resized, frameSize,
            enableWhiteBalance: tuningConfig.enableWhiteBalance,
            useRelativeColor: false, // LAB replaces relative color
            symbolThreshold: tuningConfig.symbolThreshold,
            quadrantOffset: tuningConfig.quadrantOffset,
            useHashDetection: tuningConfig.useHashDetection,
            useLabColor: true,
            stats: statsLab);
        final dataBytesLab = _decoder.decodeRSFrame(rawBytesLab, frameSize);

        _emitDebug('decode_stats_lab', 'size=$frameSize $statsLab');

        if (dataBytesLab.isEmpty) return null;

        var nonZeroLab = 0;
        final checkLenLab = min(64, dataBytesLab.length);
        for (var i = 0; i < checkLenLab; i++) {
          if (dataBytesLab[i] != 0) nonZeroLab++;
        }
        if (nonZeroLab == 0) {
          _emitDebug('quality_gate', 'REJECTED LAB size=$frameSize nonZero=0/$checkLenLab');
          return null;
        }

        _emitDebug('quality_gate', 'PASSED LAB size=$frameSize nonZero=$nonZeroLab/$checkLenLab');
        return dataBytesLab;
      }

      _emitDebug('quality_gate', 'PASSED size=$frameSize nonZero=$nonZero/$checkLen');
      return dataBytes;
    } catch (_) {
      return null;
    }
  }

  /// Check if scanning is complete.
  bool _isComplete() {
    if (_frame0Hash == null || _totalFrames == 0) return false;
    if (_uniqueFrames.length < _totalFrames) return false;

    // For single-frame barcodes, no adjacency chain needed
    if (_totalFrames == 1) return true;

    // Verify adjacency chain is complete from frame 0
    var current = _frame0Hash!;
    for (var i = 0; i < _totalFrames - 1; i++) {
      final next = _adjacency[current];
      if (next == null || !_uniqueFrames.containsKey(next)) return false;
      current = next;
    }
    return true;
  }

  /// FNV-1a hash of byte data, returned as hex string.
  static String _fnv1a(Uint8List data) {
    var hash = 0x811c9dc5; // FNV offset basis (32-bit)
    for (var i = 0; i < min(64, data.length); i++) {
      hash ^= data[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF; // FNV prime, masked to 32 bits
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
