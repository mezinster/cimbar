import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../core/models/barcode_rect.dart';
import '../../core/models/decode_result.dart';
import '../../core/models/decode_tuning_config.dart';
import '../../core/services/crypto_service.dart';
import '../../core/services/frame_decode_isolate.dart';
import '../../core/services/live_scanner.dart';
import '../../core/utils/byte_utils.dart';

/// Top-level function to run isolate decode — must be top-level so the
/// closure doesn't capture LiveScanController's `this` (which holds
/// Riverpod's SynchronousFuture, an unsendable object).
/// See: https://github.com/dart-lang/sdk/issues/52661
Future<IsolateFrameResult> _runIsolate(IsolateFrameInput input) {
  return Isolate.run(() => decodeFrameInIsolate(input));
}

final liveScanControllerProvider =
    StateNotifierProvider<LiveScanController, LiveScanState>((ref) {
  return LiveScanController();
});

class LiveScanState {
  final bool isScanning;
  final int framesAnalyzed;
  final int uniqueFrames;
  final int totalFrames;
  final int? detectedFrameSize;
  final bool isDecrypting;
  final DecodeResult? result;
  final String? errorMessage;
  final BarcodeRect? barcodeRect;
  final int? sourceImageWidth;
  final int? sourceImageHeight;
  final bool debugEnabled;
  final List<String> debugLog;
  final String? captureStatus;

  const LiveScanState({
    this.isScanning = false,
    this.framesAnalyzed = 0,
    this.uniqueFrames = 0,
    this.totalFrames = 0,
    this.detectedFrameSize,
    this.isDecrypting = false,
    this.result,
    this.errorMessage,
    this.barcodeRect,
    this.sourceImageWidth,
    this.sourceImageHeight,
    this.debugEnabled = false,
    this.debugLog = const [],
    this.captureStatus,
  });

  LiveScanState copyWith({
    bool? isScanning,
    int? framesAnalyzed,
    int? uniqueFrames,
    int? totalFrames,
    int? detectedFrameSize,
    bool? isDecrypting,
    DecodeResult? result,
    String? errorMessage,
    BarcodeRect? barcodeRect,
    int? sourceImageWidth,
    int? sourceImageHeight,
    bool? debugEnabled,
    List<String>? debugLog,
    String? captureStatus,
    bool clearResult = false,
    bool clearError = false,
    bool clearBarcodeRect = false,
    bool clearCaptureStatus = false,
  }) {
    return LiveScanState(
      isScanning: isScanning ?? this.isScanning,
      framesAnalyzed: framesAnalyzed ?? this.framesAnalyzed,
      uniqueFrames: uniqueFrames ?? this.uniqueFrames,
      totalFrames: totalFrames ?? this.totalFrames,
      detectedFrameSize: detectedFrameSize ?? this.detectedFrameSize,
      isDecrypting: isDecrypting ?? this.isDecrypting,
      result: clearResult ? null : (result ?? this.result),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      barcodeRect: clearBarcodeRect ? null : (barcodeRect ?? this.barcodeRect),
      sourceImageWidth: sourceImageWidth ?? this.sourceImageWidth,
      sourceImageHeight: sourceImageHeight ?? this.sourceImageHeight,
      debugEnabled: debugEnabled ?? this.debugEnabled,
      debugLog: debugLog ?? this.debugLog,
      captureStatus: clearCaptureStatus
          ? null
          : (captureStatus ?? this.captureStatus),
    );
  }

  bool get isComplete =>
      totalFrames > 0 && uniqueFrames >= totalFrames && !isDecrypting;
}

class LiveScanController extends StateNotifier<LiveScanState> {
  LiveScanController() : super(const LiveScanState());

  final LiveScanner _scanner = LiveScanner();

  /// Minimum interval between frame processing (throttle to ~4fps).
  static const _throttleMs = 250;
  int _lastProcessedMs = 0;
  bool _processing = false;

  static const _maxDebugEntries = 50;
  bool _debugMode = false;

  DecodeTuningConfig _tuningConfig = const DecodeTuningConfig();

  void updateTuningConfig(DecodeTuningConfig config) {
    _tuningConfig = config;
    _scanner.tuningConfig = config;
  }

  void updateDebugMode(bool enabled) {
    _debugMode = enabled;
    _scanner.onDebug = _debugMode ? _onDebug : null;
    _scanner.collectStats = _debugMode;
  }

  void startScan() {
    _scanner.reset();
    _scanner.onDebug = _debugMode ? _onDebug : null;
    _lastProcessedMs = 0;
    _processing = false;
    state = LiveScanState(isScanning: true, debugEnabled: state.debugEnabled);
  }

  void _onDebug(ScanDebugInfo info) {
    _logAdb(info.toString());
    _logOverlay(info.toString());
  }

  /// Verbose logging for ADB logcat — always prints when debug mode is on.
  /// Multi-line messages are split into separate debugPrint calls.
  void _logAdb(String msg) {
    if (!_debugMode) return;
    for (final line in msg.split('\n')) {
      if (line.isNotEmpty) debugPrint('[cimbar_scan] $line');
    }
  }

  /// Short one-liner for the AR debug overlay.
  void _logOverlay(String msg) {
    if (!_debugMode) return;
    Future.microtask(() {
      final log = [...state.debugLog, msg];
      if (log.length > _maxDebugEntries) {
        log.removeRange(0, log.length - _maxDebugEntries);
      }
      state = state.copyWith(debugLog: log);
    });
  }

  void toggleDebug() {
    // Only allow overlay toggle when master debug mode is enabled in Settings
    if (!_debugMode) return;
    state = state.copyWith(debugEnabled: !state.debugEnabled);
  }

  void clearCaptureStatus() {
    state = state.copyWith(clearCaptureStatus: true);
  }

  void stopScan() {
    state = state.copyWith(isScanning: false);
  }

  bool _captureNextFrame = false;

  /// Request debug frame capture on the next processed frame.
  void captureDebugFrame() {
    _captureNextFrame = true;
    _logAdb('capture requested (waiting for next frame)');
    _logOverlay('capture requested');
  }

  /// Process a camera frame. Called from the image stream callback.
  ///
  /// Accepts raw YUV plane data to decouple from CameraImage.
  /// Heavy computation (YUV→RGB, locate, warp, decode) runs in a background
  /// isolate. Stateful frame tracking (adjacency, dedup) stays on main isolate.
  void onCameraFrame({
    required int width,
    required int height,
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    if (!state.isScanning || _processing) return;

    // Throttle: skip if too soon since last frame
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProcessedMs < _throttleMs) return;
    _lastProcessedMs = now;
    _processing = true;

    final capture = _captureNextFrame;
    _captureNextFrame = false;

    _processFrameAsync(
      width: width,
      height: height,
      yPlane: yPlane,
      uPlane: uPlane,
      vPlane: vPlane,
      yRowStride: yRowStride,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
      captureFrame: capture,
    );
  }

  Future<void> _processFrameAsync({
    required int width,
    required int height,
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required bool captureFrame,
  }) async {
    final frameNum = _scanner.framesAnalyzed + 1;
    try {
      final input = IsolateFrameInput(
        width: width,
        height: height,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: yRowStride,
        uvRowStride: uvRowStride,
        uvPixelStride: uvPixelStride,
        tuningConfig: _tuningConfig,
        lockedFrameSize: _scanner.detectedFrameSize,
        collectStats: _debugMode,
        captureFrame: captureFrame,
      );

      final result = await _runIsolate(input);

      // Verbose ADB log from isolate diagnostics
      if (result.debugInfo != null) {
        _logAdb('--- frame #$frameNum ---\n${result.debugInfo}');
      }
      // Short overlay line
      if (result.overlayLine != null) {
        _logOverlay('#$frameNum ${result.overlayLine}');
      }

      // Process stateful tracking on main isolate
      if (result.dataBytes != null && result.frameSize != null) {
        final progress = _scanner.processDecodedData(
            result.dataBytes!, result.frameSize!);

        if (_debugMode) {
          _logAdb('  tracking: unique=${progress.uniqueFrames}/${progress.totalFrames} '
              'locked=${progress.detectedFrameSize}');
        }

        Future.microtask(() {
          state = state.copyWith(
            framesAnalyzed: _scanner.framesAnalyzed + 1,
            uniqueFrames: progress.uniqueFrames,
            totalFrames: progress.totalFrames,
            detectedFrameSize: progress.detectedFrameSize,
            barcodeRect: result.barcodeRect,
            sourceImageWidth: result.sourceImageWidth,
            sourceImageHeight: result.sourceImageHeight,
            clearBarcodeRect: result.barcodeRect == null,
          );
          _processing = false;
        });
      } else {
        // Decode failed — still update UI with barcode rect if available
        _scanner.incrementFramesAnalyzed();
        Future.microtask(() {
          state = state.copyWith(
            framesAnalyzed: _scanner.framesAnalyzed,
            barcodeRect: result.barcodeRect,
            sourceImageWidth: result.sourceImageWidth,
            sourceImageHeight: result.sourceImageHeight,
            clearBarcodeRect: result.barcodeRect == null,
          );
          _processing = false;
        });
      }

      // Save debug captures if present
      if (result.rawFramePng != null || result.croppedFramePng != null) {
        _saveDebugCaptures(result.rawFramePng, result.croppedFramePng);
      } else if (captureFrame) {
        _logAdb('capture flag was set but isolate returned no PNGs');
        state = state.copyWith(captureStatus: 'failed');
      }
    } catch (e) {
      _logAdb('frame #$frameNum isolate error: $e');
      _logOverlay('#$frameNum ERR ${e.runtimeType}');
      _scanner.incrementFramesAnalyzed();
      _processing = false;
      if (captureFrame) {
        state = state.copyWith(captureStatus: 'failed');
      }
    }
  }

  Future<void> _saveDebugCaptures(
      Uint8List? rawPng, Uint8List? croppedPng) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      var saved = 0;
      if (rawPng != null) {
        await File('${dir.path}/cimbar_debug_raw_$ts.png')
            .writeAsBytes(rawPng);
        saved++;
      }
      if (croppedPng != null) {
        await File('${dir.path}/cimbar_debug_crop_$ts.png')
            .writeAsBytes(croppedPng);
        saved++;
      }
      if (saved > 0) {
        _logAdb('captured $saved debug image(s) to ${dir.path}');
        _logOverlay('captured $saved image(s)');
        state = state.copyWith(captureStatus: 'saved');
      }
    } catch (e) {
      _logAdb('capture save failed: $e');
      _logOverlay('capture FAILED');
      state = state.copyWith(captureStatus: 'failed');
    }
  }

  /// Check if scanning is complete (called by UI via ref.listen).
  bool get scanComplete => _scanner.uniqueFrameCount > 0 &&
      _scanner.totalFrames > 0 &&
      _scanner.uniqueFrameCount >= _scanner.totalFrames;

  /// Assemble frames and decrypt.
  Future<void> decrypt(String passphrase) async {
    state = state.copyWith(
      isScanning: false,
      isDecrypting: true,
      clearError: true,
    );

    try {
      final scanResult = _scanner.assemble();
      if (scanResult == null) {
        state = state.copyWith(
          isDecrypting: false,
          errorMessage: 'Could not assemble frames — incomplete adjacency chain',
        );
        return;
      }

      // Extract encrypted payload using 4-byte length prefix
      final payloadLength = readUint32BE(scanResult.data);
      if (payloadLength + 4 > scanResult.data.length) {
        state = state.copyWith(
          isDecrypting: false,
          errorMessage: 'Invalid payload length in assembled data',
        );
        return;
      }
      final encryptedPayload = scanResult.data.sublist(4, 4 + payloadLength);

      // Decrypt
      final Uint8List plaintext;
      try {
        plaintext = CryptoService.decrypt(encryptedPayload, passphrase);
      } catch (e) {
        state = state.copyWith(
          isDecrypting: false,
          errorMessage: 'Decryption failed: $e',
        );
        return;
      }

      // Parse file header: [4-byte nameLen][nameBytes][fileData]
      if (plaintext.length < 4) {
        state = state.copyWith(
          isDecrypting: false,
          errorMessage: 'Decrypted data too short',
        );
        return;
      }

      final nameLen = readUint32BE(plaintext);
      if (nameLen > plaintext.length - 4) {
        state = state.copyWith(
          isDecrypting: false,
          errorMessage: 'Invalid filename length',
        );
        return;
      }

      final filename = utf8.decode(plaintext.sublist(4, 4 + nameLen));
      final fileData = plaintext.sublist(4 + nameLen);

      final result = DecodeResult(filename: filename, data: fileData);
      state = state.copyWith(
        isDecrypting: false,
        result: result,
      );
      // Auto-save to app documents so file appears in Files tab
      await _autoSave(result);
    } catch (e) {
      state = state.copyWith(
        isDecrypting: false,
        errorMessage: 'Error: $e',
      );
    }
  }

  Future<String?> _autoSave(DecodeResult result) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${result.filename}');
      await file.writeAsBytes(result.data);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> saveResult() async {
    final result = state.result;
    if (result == null) return null;
    return _autoSave(result);
  }
}
