import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

/// A file another app shared to CimBar ("Share → CimBar Scanner").
class SharedFile {
  final String name;
  final Uint8List bytes;
  const SharedFile(this.name, this.bytes);
}

/// Where shared media comes from: the share_handler plugin in the app (the
/// Android SEND intent, the iOS Share Extension), a fake in tests.
abstract class ShareSource {
  Future<SharedMedia?> initialMedia();
  Stream<SharedMedia> get mediaStream;
  Future<void> resetInitialMedia();
}

class PluginShareSource implements ShareSource {
  @override
  Future<SharedMedia?> initialMedia() => ShareHandler.instance.getInitialSharedMedia();

  @override
  Stream<SharedMedia> get mediaStream => ShareHandler.instance.sharedMediaStream;

  @override
  Future<void> resetInitialMedia() => ShareHandler.instance.resetInitialSharedMedia();
}

final shareSourceProvider = Provider<ShareSource>((ref) => PluginShareSource());

/// A filename from a filesystem path that can't throw — no `Uri`/`File`
/// round trip, which can raise on a path `Uri.parse`/`toFilePath` or
/// `File.uri.pathSegments` doesn't expect (empty path, an authority
/// component, ...).
String _basename(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i == -1 ? path : path.substring(i + 1);
}

/// The first readable attachment of [media]. [unreadable] is true when it had
/// attachments but none could be read — on Android a document-provider URI can
/// resolve to a shared-storage path the app holds no permission for; a
/// malformed `file://` URI (an authority component `toFilePath()` rejects) or
/// an empty path are also treated as unreadable rather than thrown.
Future<({SharedFile? file, bool unreadable})> firstSharedFile(SharedMedia media) async {
  final attachments = (media.attachments ?? const <SharedAttachment?>[]).whereType<SharedAttachment>().toList();
  for (final a in attachments) {
    try {
      final path = a.path.startsWith('file://') ? Uri.parse(a.path).toFilePath() : a.path;
      final file = File(path);
      final bytes = await file.readAsBytes();
      return (file: SharedFile(_basename(path), bytes), unreadable: false);
    } catch (_) {
      continue;
    }
  }
  return (file: null, unreadable: attachments.isNotEmpty);
}
