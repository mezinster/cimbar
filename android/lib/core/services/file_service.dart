import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/decode_result.dart';

/// What happened when the system was asked to open a file.
enum OpenOutcome { opened, noApp, failed }

/// Centralized file operations: opening, sharing and exporting decoded files.
///
/// Every file handed to another app carries an explicit MIME type resolved
/// from its extension ([mimeTypeFor]). Without it Android's ContentResolver
/// reports `application/octet-stream`, the share sheet lists only the few
/// apps that accept anything, and strict targets such as Telegram refuse the
/// file outright. The same type drives the `ACTION_VIEW` chooser in [openFile].
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

  /// MIME type for [path] from its extension, `application/octet-stream`
  /// when the extension is unknown or missing.
  static String mimeTypeFor(String path) => lookupMimeType(path.toLowerCase()) ?? 'application/octet-stream';

  /// Share a [DecodeResult] via the system share sheet.
  static Future<void> shareResult(DecodeResult result) async {
    await shareFile(await _writeTemp(result));
  }

  /// Share an existing file by path.
  static Future<void> shareFile(String filePath) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(filePath, mimeType: mimeTypeFor(filePath))]));
  }

  /// Open a [DecodeResult] with whatever app handles its type.
  static Future<OpenOutcome> openResult(DecodeResult result) async {
    return openFile(await _writeTemp(result));
  }

  /// Open an existing file by path with the system `ACTION_VIEW` chooser.
  static Future<OpenOutcome> openFile(String filePath) async {
    try {
      final r = await OpenFilex.open(filePath, type: mimeTypeFor(filePath));
      return switch (r.type) {
        ResultType.done => OpenOutcome.opened,
        ResultType.noAppToOpen => OpenOutcome.noApp,
        _ => OpenOutcome.failed,
      };
    } catch (_) {
      return OpenOutcome.failed;
    }
  }

  /// Let the user save [bytes] somewhere they can reach from other apps
  /// (the system "save as" picker, Downloads by default). Returns false when
  /// the picker was dismissed.
  static Future<bool> exportBytes(String filename, Uint8List bytes) async {
    final name = safeBasename(filename);
    final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mimeTypeFor(name));
    return uri != null;
  }

  /// [exportBytes] for a file already on disk.
  static Future<bool> exportFile(String filePath) async {
    return exportBytes(filePath, await File(filePath).readAsBytes());
  }

  static Future<String> _writeTemp(DecodeResult result) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${safeBasename(result.filename)}');
    await file.writeAsBytes(result.data);
    return file.path;
  }
}
