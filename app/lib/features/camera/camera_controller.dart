import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/byte_utils.dart';
import '../../core/models/decode_result.dart';
import '../../core/services/decode_pipeline.dart';
import '../../core/services/file_service.dart';
import '../../core/services/photo_decoder.dart';
import '../../core/services/share_detection.dart';
import '../photo/data/platform_jpeg_session.dart' as platform;

final cameraControllerProvider =
    StateNotifierProvider<CameraController, CameraState>((ref) {
  return CameraController(decodePixels: ref.read(pixelDecoderProvider));
});

/// [errorCode] is the stable tag [PhotoDecodeResult] produced ('multi_frame',
/// 'passphrase_required', 'not_located', 'decode_failed'); the screen maps it
/// to a localized string and only falls back to the English
/// `progress.message` when it is null. [errorTotal] carries the frame count
/// 'multi_frame' needs. [fromShare] is true while the photo is one another
/// app shared (adopted through [CameraController.adoptDetected]).
class CameraState {
  final Uint8List? capturedPhotoBytes;
  final String? capturedPhotoPath;
  final DecodeProgress? progress;
  final DecodeResult? result;
  final bool isDecoding;
  final String? errorCode;
  final int? errorTotal;
  final bool fromShare;

  const CameraState({
    this.capturedPhotoBytes,
    this.capturedPhotoPath,
    this.progress,
    this.result,
    this.isDecoding = false,
    this.errorCode,
    this.errorTotal,
    this.fromShare = false,
  });

  CameraState copyWith({
    Uint8List? capturedPhotoBytes,
    String? capturedPhotoPath,
    DecodeProgress? progress,
    DecodeResult? result,
    bool? isDecoding,
    String? errorCode,
    int? errorTotal,
    bool clearResult = false,
    bool clearProgress = false,
    bool clearError = false,
  }) {
    return CameraState(
      capturedPhotoBytes: capturedPhotoBytes ?? this.capturedPhotoBytes,
      capturedPhotoPath: capturedPhotoPath ?? this.capturedPhotoPath,
      progress: clearProgress ? null : (progress ?? this.progress),
      result: clearResult ? null : (result ?? this.result),
      isDecoding: isDecoding ?? this.isDecoding,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorTotal: clearError ? null : (errorTotal ?? this.errorTotal),
      fromShare: fromShare,
    );
  }
}

class CameraController extends StateNotifier<CameraState> {
  /// [decodePixels] reads a shared photo natively (HEIC included) when it is
  /// decoded again, e.g. with a passphrase.
  CameraController({PixelDecoder? decodePixels})
      : _decodePixels = decodePixels ?? platform.decodePixels,
        super(const CameraState());

  final PixelDecoder _decodePixels;

  final _gifPipeline = DecodePipeline();
  final _picker = ImagePicker();

  /// Adopt bytes captured by [PhotoCaptureScreen] (no on-disk path available).
  void setPhoto(Uint8List bytes, {String? path}) {
    state = CameraState(
      capturedPhotoBytes: bytes,
      capturedPhotoPath: path,
    );
  }

  /// Adopts a shared photo whose barcode detection already ran, so it isn't
  /// decoded twice: the state ends exactly as [decode] leaves it after a
  /// photo decode with result [r] (including the auto-save on success), plus
  /// [CameraState.fromShare].
  Future<void> adoptDetected(Uint8List bytes, String path, PhotoDecodeResult r) async {
    state = CameraState(capturedPhotoBytes: bytes, capturedPhotoPath: path, fromShare: true);
    await _applyPhotoResult(r);
  }

  Future<void> pickFromGallery() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;

    final bytes = await File(xFile.path).readAsBytes();
    state = CameraState(
      capturedPhotoBytes: bytes,
      capturedPhotoPath: xFile.path,
    );
  }

  Future<void> decode(String passphrase) async {
    if (state.capturedPhotoBytes == null) return;

    state = state.copyWith(
      isDecoding: true,
      clearResult: true,
      clearProgress: true,
      clearError: true,
    );

    final bytes = state.capturedPhotoBytes!;

    // Route GIF files through the full multi-frame pipeline
    if (isGif(bytes)) {
      await for (final progress in _gifPipeline.decodeGif(bytes, passphrase)) {
        state = state.copyWith(progress: progress);

        if (progress.state == DecodeState.done) {
          final result = _gifPipeline.lastResult;
          state = state.copyWith(isDecoding: false, result: result);
          if (result != null) await _autoSave(result);
        } else if (progress.state == DecodeState.error) {
          state = state.copyWith(isDecoding: false);
        }
      }
    } else {
      final path = state.capturedPhotoPath;
      // A shared photo may be HEIC, which the image package behind
      // decodePhotoBytes can't read: decode it natively, like detection did.
      await _applyPhotoResult(state.fromShare && path != null
          ? await _decodeShared(path, passphrase)
          : await decodePhotoBytes(bytes, passphrase));
    }
  }

  Future<PhotoDecodeResult> _decodeShared(String path, String passphrase) async {
    try {
      return await detectSharedPhoto(path, _decodePixels, passphrase: passphrase);
    } catch (_) {
      return const PhotoDecodeResult(error: 'Cannot decode image', errorCode: 'unreadable_image');
    }
  }

  /// The state a finished photo decode leaves, shared by [decode] and
  /// [adoptDetected] so the two can't drift apart.
  Future<void> _applyPhotoResult(PhotoDecodeResult r) async {
    state = state.copyWith(
      isDecoding: false,
      result: r.result,
      errorCode: r.errorCode,
      errorTotal: r.total,
      progress: DecodeProgress(
        state: r.error == null ? DecodeState.done : DecodeState.error,
        progress: 1,
        message: r.error ?? 'Decoded: ${r.result!.filename}',
      ),
    );
    if (r.result != null) await _autoSave(r.result!);
  }

  Future<String?> _autoSave(DecodeResult result) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${FileService.safeBasename(result.filename)}');
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

  void reset() {
    state = const CameraState();
  }
}
