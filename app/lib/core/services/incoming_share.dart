import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

import '../format/cimbar_spec.dart';
import 'file_service.dart';

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

/// Prefix the patched share_handler_android puts in an attachment's `path`
/// for an item above its size budget (`cimbar-too-large:<size or -1>`).
const _tooLargePrefix = 'cimbar-too-large:';

/// One thing another app shared to CimBar.
sealed class ShareItem {
  const ShareItem();
}

class SharedText extends ShareItem {
  final String text;
  const SharedText(this.text);
}

class SharedFileItem extends ShareItem {
  final String name;
  final String path;
  final int length;
  const SharedFileItem({required this.name, required this.path, required this.length});
}

class ShareTooLarge extends ShareItem {
  final int? length;
  const ShareTooLarge({this.length});
}

class ShareUnreadable extends ShareItem {
  const ShareUnreadable();
}

int? _parseSize(String s) {
  final n = int.tryParse(s);
  return (n == null || n < 0) ? null : n;
}

/// A filename from a filesystem path that can't throw.
String _basename(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i == -1 ? path : path.substring(i + 1);
}

/// The first usable item of [media] and how many attachments it carried.
/// Returns paths, never file bytes. An oversized attachment (the plugin's
/// marker, or a file above [cap]) is [ShareTooLarge]; attachments that all
/// fail (a path the app holds no permission for, a malformed `file://` URI,
/// an empty path) are [ShareUnreadable]. With no attachments, non-empty
/// `content` (text, or a URL-only share) is [SharedText]; otherwise `item` is null.
Future<({ShareItem? item, int count})> readShare(SharedMedia media, {int cap = CimbarSpec.maxInflatedBytes}) async {
  final attachments = (media.attachments ?? const <SharedAttachment?>[]).whereType<SharedAttachment>().toList();
  for (final a in attachments) {
    try {
      if (a.path.startsWith(_tooLargePrefix)) {
        return (
          item: ShareTooLarge(length: _parseSize(a.path.substring(_tooLargePrefix.length))),
          count: attachments.length,
        );
      }
      final path = a.path.startsWith('file://') ? Uri.parse(a.path).toFilePath() : a.path;
      final length = await File(path).length();
      if (length > cap) return (item: ShareTooLarge(length: length), count: attachments.length);
      return (item: SharedFileItem(name: _basename(path), path: path, length: length), count: attachments.length);
    } catch (_) {
      continue;
    }
  }
  if (attachments.isNotEmpty) return (item: const ShareUnreadable(), count: attachments.length);
  final content = media.content;
  if (content != null && content.isNotEmpty) return (item: SharedText(content), count: 0);
  return (item: null, count: 0);
}

/// Copies [f] into `<tempBase>/share_in/<timestamp>/<safe name>` and returns the
/// new path, then deletes the original if it was only the plugin's copy
/// ([deletePluginCopy]).
Future<String> stageSharedFile(SharedFileItem f, {required Directory tempBase, required String cacheDir}) async {
  final dir = Directory('${tempBase.path}/share_in/${DateTime.now().microsecondsSinceEpoch}');
  await dir.create(recursive: true);
  final dest = '${dir.path}/${FileService.safeBasename(f.name)}';
  await File(f.path).copy(dest);
  await deletePluginCopy(f.path, cacheDir: cacheDir);
  return dest;
}

/// [path] with `.`/`..` segments resolved and no trailing separator.
String _normalise(String path) {
  var p = Uri.file(path).normalizePath().toFilePath();
  final sep = Platform.pathSeparator;
  while (p.length > 1 && p.endsWith(sep)) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// True when [path] is [dir] or inside it, after normalising both — so
/// `<cache>_other/x` and `<cache>/../x` are not inside `<cache>`.
bool isWithinDir(String path, String dir) {
  final p = _normalise(path);
  final d = _normalise(dir);
  final sep = Platform.pathSeparator;
  return p == d || p.startsWith(d.endsWith(sep) ? d : '$d$sep');
}

/// Deletes [path] if, and only if, it is the share plugin's own copy: inside
/// [cacheDir] (Android) or an iOS App Group container. Anything else is a
/// file the app doesn't own and is left alone. Never throws.
Future<void> deletePluginCopy(String path, {required String cacheDir}) async {
  try {
    if (isWithinDir(path, cacheDir) || _normalise(path).contains('/Shared/AppGroup/')) {
      await File(path).delete();
    }
  } catch (_) {}
}
