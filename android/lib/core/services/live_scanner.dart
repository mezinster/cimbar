import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants/cimbar_constants.dart';
import '../utils/byte_utils.dart';
import 'cimbar_decoder.dart';
import 'frame_locator.dart';

/// Result of processing a single camera frame.
class ScanProgress {
  final int uniqueFrames;
  final int totalFrames;
  final bool isComplete;
  final int? detectedFrameSize;

  const ScanProgress({
    required this.uniqueFrames,
    required this.totalFrames,
    required this.isComplete,
    this.detectedFrameSize,
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

/// Live scanning engine for multi-frame CimBar barcodes.
///
/// Tracks unique frames via content hashing, uses adjacency-chain ordering
/// to reconstruct the correct frame sequence, and detects frame 0 via
/// its 4-byte big-endian length prefix.
class LiveScanner {
  final CimbarDecoder _decoder = CimbarDecoder();

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

    // Strategy 1: FrameLocator (bright-region detection)
    try {
      final cropped = FrameLocator.locate(photo);
      // Only use if crop is meaningfully smaller than the original image.
      // If the crop covers >80% of the area, FrameLocator found "everything"
      // (e.g. well-lit room) and the crop is useless.
      final cropArea = cropped.width * cropped.height;
      final totalArea = photo.width * photo.height;
      if (cropArea < totalArea * 0.8) {
        (dataBytes, usedSize) = _tryDecodeImage(cropped);
      }
    } catch (_) {
      // No bright region found — try center crop below
    }

    // Strategy 2: Center square crop (user points camera directly at barcode)
    if (dataBytes == null) {
      final minDim = min(photo.width, photo.height);
      final cropX = (photo.width - minDim) ~/ 2;
      final cropY = (photo.height - minDim) ~/ 2;
      final center = img.copyCrop(photo,
          x: cropX, y: cropY, width: minDim, height: minDim);
      (dataBytes, usedSize) = _tryDecodeImage(center);
    }

    if (dataBytes == null || usedSize == null) return null;

    return processDecodedData(dataBytes, usedSize);
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

  /// Try all candidate frame sizes on a cropped image.
  /// Returns (dataBytes, frameSize) or (null, null).
  (Uint8List?, int?) _tryDecodeImage(img.Image cropped) {
    if (_frameSize != null) {
      final data = _tryDecode(cropped, _frameSize!);
      if (data != null) return (data, _frameSize!);
      return (null, null);
    }
    for (final size in CimbarConstants.frameSizes) {
      final data = _tryDecode(cropped, size);
      if (data != null) {
        _frameSize = size;
        return (data, size);
      }
    }
    return (null, null);
  }

  /// Try to decode a cropped image at a specific frame size.
  Uint8List? _tryDecode(img.Image cropped, int frameSize) {
    try {
      final resized = img.copyResize(cropped,
          width: frameSize,
          height: frameSize,
          interpolation: img.Interpolation.linear);

      final rawBytes = _decoder.decodeFramePixels(resized, frameSize);
      final dataBytes = _decoder.decodeRSFrame(rawBytes, frameSize);

      if (dataBytes.isEmpty) return null;

      // Quality check: if the first 64 bytes are all zero, every RS block
      // failed and the decoded data is garbage — reject this frame.
      var nonZero = 0;
      final checkLen = min(64, dataBytes.length);
      for (var i = 0; i < checkLen; i++) {
        if (dataBytes[i] != 0) nonZero++;
      }
      if (nonZero == 0) return null;

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
