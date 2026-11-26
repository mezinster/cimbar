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

/// The real filesystem path of attachment path [raw] (`file://` URIs
/// resolved), or null for the plugin's too-large marker, an empty path or a
/// URI that names no local file.
String? _resolvedPath(String raw) {
  if (raw.isEmpty || raw.startsWith(_tooLargePrefix)) return null;
  try {
    return raw.startsWith('file://') ? Uri.parse(raw).toFilePath() : raw;
  } catch (_) {
    return null;
  }
}

/// The first usable item of [media], how many attachments it carried, and
/// the real path of every attachment ([paths], markers excluded) so the caller
/// can delete the plugin's copies of the ones it doesn't use. Returns paths,
/// never file bytes. An attachment that is too large (the plugin's marker, or
/// a file above [cap]) or unreadable (a path the app holds no permission for,
/// a malformed `file://` URI, an empty path) is skipped for a later usable
/// one; only when none is usable is the share [ShareTooLarge] (if any item
/// was) or else [ShareUnreadable]. With no attachments, non-empty `content`
/// (text, or a URL-only share) is [SharedText]; otherwise `item` is null.
Future<({ShareItem? item, int count, List<String> paths})> readShare(
  SharedMedia media, {
  int cap = CimbarSpec.maxInflatedBytes,
}) async {
  final attachments = (media.attachments ?? const <SharedAttachment?>[]).whereType<SharedAttachment>().toList();
  final paths = [for (final a in attachments) _resolvedPath(a.path)].whereType<String>().toList();
  ShareTooLarge? tooLarge;
  for (final a in attachments) {
    if (a.path.startsWith(_tooLargePrefix)) {
      tooLarge ??= ShareTooLarge(length: _parseSize(a.path.substring(_tooLargePrefix.length)));
      continue;
    }
    final path = _resolvedPath(a.path);
    if (path == null) continue;
    try {
      final length = await File(path).length();
      if (length > cap) {
        tooLarge ??= ShareTooLarge(length: length);
        continue;
      }
      return (
        item: SharedFileItem(name: _basename(path), path: path, length: length),
        count: attachments.length,
        paths: paths,
      );
    } catch (_) {
      continue;
    }
  }
  if (attachments.isNotEmpty) {
    return (item: tooLarge ?? const ShareUnreadable(), count: attachments.length, paths: paths);
  }
  final content = media.content;
  if (content != null && content.isNotEmpty) return (item: SharedText(content), count: 0, paths: paths);
  return (item: null, count: 0, paths: paths);
}

/// Copies [f] into `<tempBase>/share_in/<timestamp>/<safe name>` and returns the
/// new path, then deletes the original if it was only the plugin's copy
/// ([deletePluginCopy]; [ios] as there).
Future<String> stageSharedFile(
  SharedFileItem f, {
  required Directory tempBase,
  required String cacheDir,
  bool? ios,
}) async {
  final dir = Directory('${tempBase.path}/share_in/${DateTime.now().microsecondsSinceEpoch}');
  await dir.create(recursive: true);
  final dest = '${dir.path}/${FileService.safeBasename(f.name)}';
  final copy = await File(f.path).copy(dest);
  // iOS keeps the source's modified time on a copy; stamp it now so launch
  // cleanup (clearPhotoTemp, files older than launch) never takes it for a leftover.
  await copy.setLastModified(DateTime.now());
  await deletePluginCopy(f.path, cacheDir: cacheDir, ios: ios);
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

/// Deletes [path] if, and only if, it is the share plugin's own copy: a
/// direct child of [cacheDir] (where the patched Android plugin writes, see
/// `safeCacheFile`) or, on iOS ([ios], default: the running platform), a file
/// in the App Group container. Anything else — including a crafted
/// `file://` share naming one of CimBar's own files nested deeper in the cache,
/// like a staged photo in `share_in/` — is left alone. Never throws.
Future<void> deletePluginCopy(String path, {required String cacheDir, bool? ios}) async {
  try {
    final p = _normalise(path);
    final i = p.lastIndexOf(Platform.pathSeparator);
    final directChild = i > 0 && p.substring(0, i) == _normalise(cacheDir);
    final appGroup = (ios ?? Platform.isIOS) && p.contains('/Shared/AppGroup/');
    if (directChild || appGroup) await File(p).delete();
  } catch (_) {}
}
