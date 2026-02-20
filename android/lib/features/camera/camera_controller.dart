import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/decode_result.dart';
import '../../core/services/camera_decode_pipeline.dart';

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

  final _pipeline = CameraDecodePipeline();
  final _picker = ImagePicker();

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

    await for (final progress
        in _pipeline.decodePhoto(state.capturedPhotoBytes!, passphrase)) {
      state = state.copyWith(progress: progress);

      if (progress.state == DecodeState.done) {
        state = state.copyWith(
          isDecoding: false,
          result: _pipeline.lastResult,
        );
      } else if (progress.state == DecodeState.error) {
        state = state.copyWith(isDecoding: false);
      }
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

  void reset() {
    state = const CameraState();
  }
}
