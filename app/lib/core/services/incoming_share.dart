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

/// The first readable attachment of [media]. [unreadable] is true when it had
/// attachments but none could be read — on Android a document-provider URI can
/// resolve to a shared-storage path the app holds no permission for.
Future<({SharedFile? file, bool unreadable})> firstSharedFile(SharedMedia media) async {
  final attachments = (media.attachments ?? const <SharedAttachment?>[]).whereType<SharedAttachment>().toList();
  for (final a in attachments) {
    final path = a.path.startsWith('file://') ? Uri.parse(a.path).toFilePath() : a.path;
    try {
      final file = File(path);
      return (file: SharedFile(file.uri.pathSegments.last, await file.readAsBytes()), unreadable: false);
    } on FileSystemException {
      continue;
    }
  }
  return (file: null, unreadable: attachments.isNotEmpty);
}
