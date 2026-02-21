import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/decode_result.dart';

/// Centralized file operations: sharing and listing decoded files.
class FileService {
  FileService._();

  /// Share a [DecodeResult] via the system share sheet.
  static Future<void> shareResult(DecodeResult result) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${result.filename}');
    await file.writeAsBytes(result.data);
    await Share.shareXFiles([XFile(file.path)]);
  }

  /// Share an existing file by path.
  static Future<void> shareFile(String filePath) async {
    await Share.shareXFiles([XFile(filePath)]);
  }
}
