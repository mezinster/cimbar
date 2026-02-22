import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/decode_result.dart';
import '../../core/models/decode_tuning_config.dart';
import '../../core/services/camera_decode_pipeline.dart';
import '../../core/services/decode_pipeline.dart';

final cameraControllerProvider =
    StateNotifierProvider<CameraController, CameraState>((ref) {
  return CameraController();
});

class CameraState {
  final Uint8List? capturedPhotoBytes;
  final String? capturedPhotoPath;
  final DecodeProgress? progress;
  final DecodeResult? result;
  final bool isDecoding;

  const CameraState({
    this.capturedPhotoBytes,
    this.capturedPhotoPath,
    this.progress,
    this.result,
    this.isDecoding = false,
  });

  CameraState copyWith({
    Uint8List? capturedPhotoBytes,
    String? capturedPhotoPath,
    DecodeProgress? progress,
    DecodeResult? result,
    bool? isDecoding,
    bool clearResult = false,
    bool clearProgress = false,
  }) {
    return CameraState(
      capturedPhotoBytes: capturedPhotoBytes ?? this.capturedPhotoBytes,
      capturedPhotoPath: capturedPhotoPath ?? this.capturedPhotoPath,
      progress: clearProgress ? null : (progress ?? this.progress),
      result: clearResult ? null : (result ?? this.result),
      isDecoding: isDecoding ?? this.isDecoding,
    );
  }
}

class CameraController extends StateNotifier<CameraState> {
  CameraController() : super(const CameraState());

  final _cameraPipeline = CameraDecodePipeline();
  final _gifPipeline = DecodePipeline();
  final _picker = ImagePicker();

  DecodeTuningConfig? tuningConfig;

  /// Check if bytes start with GIF magic (GIF87a or GIF89a).
  static bool _isGif(Uint8List bytes) {
    return bytes.length >= 6 &&
        bytes[0] == 0x47 && // G
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x38 && // 8
        (bytes[4] == 0x39 || bytes[4] == 0x37) && // 9 or 7
        bytes[5] == 0x61; // a
  }

  Future<void> capturePhoto() async {
    final xFile = await _picker.pickImage(source: ImageSource.camera);
    if (xFile == null) return;

    final bytes = await File(xFile.path).readAsBytes();
    state = CameraState(
      capturedPhotoBytes: bytes,
      capturedPhotoPath: xFile.path,
    );
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
    );

    final bytes = state.capturedPhotoBytes!;

    // Route GIF files through the full multi-frame pipeline
    if (_isGif(bytes)) {
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
      await for (final progress
          in _cameraPipeline.decodePhoto(bytes, passphrase,
              tuningConfig: tuningConfig)) {
        state = state.copyWith(progress: progress);

        if (progress.state == DecodeState.done) {
          final result = _cameraPipeline.lastResult;
          state = state.copyWith(isDecoding: false, result: result);
          if (result != null) await _autoSave(result);
        } else if (progress.state == DecodeState.error) {
          state = state.copyWith(isDecoding: false);
        }
      }
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

  void reset() {
    state = const CameraState();
  }
}
