import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/decode_result.dart';
import '../../core/services/decode_pipeline.dart';

final importControllerProvider =
    StateNotifierProvider<ImportController, ImportState>((ref) {
  return ImportController();
});

class ImportState {
  final String? selectedFileName;
  final Uint8List? selectedFileBytes;
  final DecodeProgress? progress;
  final DecodeResult? result;
  final bool isDecoding;

  const ImportState({
    this.selectedFileName,
    this.selectedFileBytes,
    this.progress,
    this.result,
    this.isDecoding = false,
  });

  ImportState copyWith({
    String? selectedFileName,
    Uint8List? selectedFileBytes,
    DecodeProgress? progress,
    DecodeResult? result,
    bool? isDecoding,
    bool clearResult = false,
    bool clearProgress = false,
  }) {
    return ImportState(
      selectedFileName: selectedFileName ?? this.selectedFileName,
      selectedFileBytes: selectedFileBytes ?? this.selectedFileBytes,
      progress: clearProgress ? null : (progress ?? this.progress),
      result: clearResult ? null : (result ?? this.result),
      isDecoding: isDecoding ?? this.isDecoding,
    );
  }
}

class ImportController extends StateNotifier<ImportState> {
  ImportController() : super(const ImportState());

  final _pipeline = DecodePipeline();

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      state = ImportState(
        selectedFileName: file.name,
        selectedFileBytes: bytes,
      );
    }
  }

  Future<void> decode(String passphrase) async {
    if (state.selectedFileBytes == null) return;

    state = state.copyWith(
      isDecoding: true,
      clearResult: true,
      clearProgress: true,
    );

    await for (final progress
        in _pipeline.decodeGif(state.selectedFileBytes!, passphrase)) {
      state = state.copyWith(progress: progress);

      if (progress.state == DecodeState.done) {
        final result = _pipeline.lastResult;
        state = state.copyWith(
          isDecoding: false,
          result: result,
        );
        // Auto-save to app documents so file appears in Files tab
        if (result != null) await _autoSave(result);
      } else if (progress.state == DecodeState.error) {
        state = state.copyWith(isDecoding: false);
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
    state = const ImportState();
  }
}
