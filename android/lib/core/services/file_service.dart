import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/decode_result.dart';

/// Centralized file operations: sharing and listing decoded files.
class FileService {
  FileService._();

  /// The last path segment of a decoded file's name. The name comes out of
  /// the barcode payload, so it is untrusted: anything up to the last '/' or
  /// '\\' is dropped so a crafted name can never write outside the target
  /// directory. Falls back to 'decoded.bin' when nothing usable is left.
  static String safeBasename(String filename) {
    var name = filename;
    for (final sep in ['/', '\\']) {
      final i = name.lastIndexOf(sep);
      if (i >= 0) name = name.substring(i + 1);
    }
    name = name.trim();
    return (name.isEmpty || name == '.' || name == '..') ? 'decoded.bin' : name;
  }

  /// Share a [DecodeResult] via the system share sheet.
  static Future<void> shareResult(DecodeResult result) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${safeBasename(result.filename)}');
    await file.writeAsBytes(result.data);
    await Share.shareXFiles([XFile(file.path)]);
  }

  /// Share an existing file by path.
  static Future<void> shareFile(String filePath) async {
    await Share.shareXFiles([XFile(filePath)]);
  }
}
