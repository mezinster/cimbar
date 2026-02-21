import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/file_service.dart';

/// Metadata about a stored decoded file.
class StoredFile {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modified;

  const StoredFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
  });
}

class FilesState {
  final List<StoredFile> files;
  final bool isLoading;

  const FilesState({
    this.files = const [],
    this.isLoading = false,
  });

  FilesState copyWith({
    List<StoredFile>? files,
    bool? isLoading,
  }) {
    return FilesState(
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final filesControllerProvider =
    StateNotifierProvider<FilesController, FilesState>((ref) {
  return FilesController();
});

class FilesController extends StateNotifier<FilesState> {
  FilesController() : super(const FilesState());

  Future<void> loadFiles() async {
    state = state.copyWith(isLoading: true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final entries = dir.listSync();
      final files = <StoredFile>[];

      for (final entry in entries) {
        if (entry is File) {
          final stat = entry.statSync();
          files.add(StoredFile(
            name: entry.uri.pathSegments.last,
            path: entry.path,
            sizeBytes: stat.size,
            modified: stat.modified,
          ));
        }
      }

      // Sort by modification date, newest first
      files.sort((a, b) => b.modified.compareTo(a.modified));

      state = state.copyWith(files: files, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await loadFiles();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> shareFile(String path) async {
    await FileService.shareFile(path);
  }
}
