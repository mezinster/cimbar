import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../core/models/decode_result.dart';
import '../../core/services/crypto_service.dart';
import '../../core/services/live_scanner.dart';
import '../../core/services/yuv_converter.dart';
import '../../core/utils/byte_utils.dart';

final liveScanControllerProvider =
    StateNotifierProvider<LiveScanController, LiveScanState>((ref) {
  return LiveScanController();
});

class LiveScanState {
  final bool isScanning;
  final int uniqueFrames;
  final int totalFrames;
  final int? detectedFrameSize;
  final bool isDecrypting;
  final DecodeResult? result;
  final String? errorMessage;

  const LiveScanState({
    this.isScanning = false,
    this.uniqueFrames = 0,
    this.totalFrames = 0,
    this.detectedFrameSize,
    this.isDecrypting = false,
    this.result,
    this.errorMessage,
  });

  LiveScanState copyWith({
    bool? isScanning,
    int? uniqueFrames,
    int? totalFrames,
    int? detectedFrameSize,
    bool? isDecrypting,
    DecodeResult? result,
    String? errorMessage,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return LiveScanState(
      isScanning: isScanning ?? this.isScanning,
      uniqueFrames: uniqueFrames ?? this.uniqueFrames,
      totalFrames: totalFrames ?? this.totalFrames,
      detectedFrameSize: detectedFrameSize ?? this.detectedFrameSize,
      isDecrypting: isDecrypting ?? this.isDecrypting,
      result: clearResult ? null : (result ?? this.result),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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

  void startScan() {
    _scanner.reset();
    _lastProcessedMs = 0;
    _processing = false;
    state = const LiveScanState(isScanning: true);
  }

  void stopScan() {
    state = state.copyWith(isScanning: false);
  }

  /// Process a camera frame. Called from the image stream callback.
  ///
  /// Accepts raw YUV plane data to decouple from CameraImage.
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

    try {
      // Convert YUV to RGB
      final image = YuvConverter.yuv420ToImage(
        width: width,
        height: height,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: yRowStride,
        uvRowStride: uvRowStride,
        uvPixelStride: uvPixelStride,
      );

      // Process through scanner
      final progress = _scanner.processFrame(image);
      if (progress != null) {
        state = state.copyWith(
          uniqueFrames: progress.uniqueFrames,
          totalFrames: progress.totalFrames,
          detectedFrameSize: progress.detectedFrameSize,
        );
      }
    } finally {
      _processing = false;
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

      state = state.copyWith(
        isDecrypting: false,
        result: DecodeResult(filename: filename, data: fileData),
      );
    } catch (e) {
      state = state.copyWith(
        isDecrypting: false,
        errorMessage: 'Error: $e',
      );
    }
  }

  Future<String?> saveResult() async {
    final result = state.result;
    if (result == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${result.filename}');
    await file.writeAsBytes(result.data);
    return file.path;
  }
}
