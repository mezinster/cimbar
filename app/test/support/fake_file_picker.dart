import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A picked file backed by a real file on disk.
final class FakePickedFile extends PlatformFile {
  FakePickedFile(this.file, {String? name})
    : name = name ?? file.uri.pathSegments.last;

  final File file;

  @override
  final String name;

  @override
  Uri get uri => file.uri;

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => null;

  @override
  Future<int?> length() => file.length();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}

/// Answers every pick with [next] and records the requested [FileType]s.
class FakeFilePicker extends FilePickerPlatform {
  List<PlatformFile> next = const [];
  final List<FileType> types = [];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    types.add(type);
    return next;
  }
}

/// Installs a [FakeFilePicker] for the rest of the test.
FakeFilePicker installFakeFilePicker() {
  final previous = FilePickerPlatform.instance;
  final fake = FakeFilePicker();
  FilePickerPlatform.instance = fake;
  addTearDown(() => FilePickerPlatform.instance = previous);
  return fake;
}
