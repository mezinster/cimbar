import 'dart:io';
import 'dart:typed_data';

import '../../core/services/gif_parser.dart';
import '../../core/services/incoming_share.dart';
import '../../core/services/photo_decoder.dart';
import '../../core/services/share_detection.dart';
import '../../features/photo/presentation/photo_optimiser_provider.dart';

/// Where a shared item goes (design spec, "Routing a share").
sealed class ShareRoute {
  const ShareRoute();
}

/// Send tab, Text mode, with [text] filled in.
class ToSendText extends ShareRoute {
  final String text;
  const ToSendText(this.text);
}

/// Send tab, File mode, with the file staged.
class ToSendFile extends ShareRoute {
  final String name;
  final Uint8List bytes;
  const ToSendFile(this.name, this.bytes);
}

/// Import tab: a CimBar GIF.
class ToImport extends ShareRoute {
  final String name;
  final Uint8List bytes;
  const ToImport(this.name, this.bytes);
}

/// The photo optimiser: an ordinary photo to send.
class ToOptimiser extends ShareRoute {
  final PendingPhoto photo;
  const ToOptimiser(this.photo);
}

/// Camera tab showing what detection made of a barcode photo.
class ToCamera extends ShareRoute {
  final Uint8List bytes;
  final String path;
  final PhotoDecodeResult result;
  const ToCamera(this.bytes, this.path, this.result);
}

/// The item is above the Send cap; [length] is null when the size is unknown.
class ShowTooLarge extends ShareRoute {
  final int? length;
  const ShowTooLarge(this.length);
}

/// Nothing usable could be read.
class ShowUnreadable extends ShareRoute {
  const ShowUnreadable();
}

/// Decides where [item] goes. A GIF goes to Import only when its first frame
/// is a CimBar frame; a photo (by magic bytes) is copied by [stage] and run
/// through barcode detection — a barcode outcome opens the Camera tab with
/// that result, anything else (including any detection failure) the
/// optimiser; everything else is sent as a file. [onDetecting] fires just
/// before a photo is staged and detected, so the caller can show progress.
Future<ShareRoute> routeShare(
  ShareItem item, {
  required PixelDecoder decodePixels,
  required Future<String> Function(SharedFileItem) stage,
  void Function()? onDetecting,
}) async {
  switch (item) {
    case SharedText(:final text):
      return ToSendText(text);
    case ShareTooLarge(:final length):
      return ShowTooLarge(length);
    case ShareUnreadable():
      return const ShowUnreadable();
    case SharedFileItem():
      try {
        return await _routeFile(item, decodePixels, stage, onDetecting);
      } on FileSystemException {
        // Gone or unreadable between readShare and here.
        return const ShowUnreadable();
      }
  }
}

Future<ShareRoute> _routeFile(
  SharedFileItem item,
  PixelDecoder decodePixels,
  Future<String> Function(SharedFileItem) stage,
  void Function()? onDetecting,
) async {
  switch (sniffKind(await _readHead(item.path))) {
    case ShareKind.gif:
      final bytes = await File(item.path).readAsBytes();
      return GifParser.isCimbarGif(bytes) ? ToImport(item.name, bytes) : ToSendFile(item.name, bytes);
    case ShareKind.image:
      onDetecting?.call();
      final staged = await stage(item);
      final toOptimiser = ToOptimiser(PendingPhoto(path: staged, name: item.name));
      final PhotoDecodeResult r;
      try {
        r = await detectSharedPhoto(staged, decodePixels);
      } catch (_) {
        // detectSharedPhoto maps the platform's decode/memory errors itself;
        // anything else (another PlatformException code, a missing plugin)
        // is equally "not a barcode we can read".
        return toOptimiser;
      }
      if (!isBarcodeOutcome(r)) return toOptimiser;
      return ToCamera(await File(staged).readAsBytes(), staged, r);
    case ShareKind.other:
      return ToSendFile(item.name, await File(item.path).readAsBytes());
  }
}

/// The first bytes of [path], enough for [sniffKind].
Future<Uint8List> _readHead(String path) async {
  final raf = await File(path).open();
  try {
    return await raf.read(16);
  } finally {
    await raf.close();
  }
}
