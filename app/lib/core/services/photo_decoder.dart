import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_decoder.dart';
import '../decode/rateless_assembler.dart';
import '../decode/rgb_buffer.dart';
import '../models/decode_result.dart';
import '../../features/photo/data/platform_jpeg_session.dart' show DecodedPixels;
import 'payload_decoder.dart';

/// Result of a still-photo v2 decode attempt.
///
/// [errorCode] is a stable, l10n-mappable tag ('multi_frame',
/// 'passphrase_required', 'not_located', 'unsupported_grid', 'unreadable_image', 'decode_failed'); [error] is the
/// English message the screen falls back to when it doesn't map the code.
class PhotoDecodeResult {
  final DecodeResult? result;
  final String? error;
  final String? errorCode;
  final Map<String, String> diag;
  final int? total;

  const PhotoDecodeResult({
    this.result,
    this.error,
    this.errorCode,
    this.diag = const {},
    this.total,
  });
}

/// Decode one still photo (PNG/JPEG bytes) containing a single-frame v2
/// barcode. Runs the full locate -> homography -> white-balance -> drift ->
/// RS -> [decrypt] chain on a background isolate so the UI thread stays
/// responsive.
Future<PhotoDecodeResult> decodePhotoBytes(Uint8List imageBytes, String passphrase) {
  return Isolate.run(() => decodePhotoSync(imageBytes, passphrase));
}

/// Synchronous core of [decodePhotoBytes]; exposed for tests that don't need
/// isolate hop overhead.
PhotoDecodeResult decodePhotoSync(Uint8List imageBytes, String passphrase) {
  final image = img.decodeImage(imageBytes);
  if (image == null) {
    return const PhotoDecodeResult(error: 'Cannot decode image', errorCode: 'unreadable_image');
  }
  return decodePhotoBuffer(RgbBuffer.fromImage(image), passphrase);
}

/// Decode already-decoded pixels (RGBA, e.g. from the native decoder) off the
/// UI isolate.
Future<PhotoDecodeResult> decodePhotoPixels(DecodedPixels px, String passphrase) {
  return Isolate.run(() {
    final n = px.width * px.height;
    final rgb = Uint8List(n * 3);
    final rgba = px.rgba;
    for (var i = 0, j = 0, k = 0; i < n; i++, j += 4, k += 3) {
      rgb[k] = rgba[j];
      rgb[k + 1] = rgba[j + 1];
      rgb[k + 2] = rgba[j + 2];
    }
    return decodePhotoBuffer(RgbBuffer(px.width, px.height, rgb), passphrase);
  });
}

/// Maps a failed [DecodeStatus] to a stable error code.
String photoErrorCode(DecodeStatus s) => switch (s) {
      DecodeStatus.notLocated => 'not_located',
      DecodeStatus.unsupportedGrid => 'unsupported_grid',
      _ => 'decode_failed',
    };

/// Locate, decode and (if needed) decrypt a single-frame barcode in [image].
PhotoDecodeResult decodePhotoBuffer(RgbBuffer image, String passphrase) {
  final r = FrameDecoder().decode(image);
  final diag = r.diag.toMap();
  if (r.status != DecodeStatus.ok) {
    return PhotoDecodeResult(
      error: 'Barcode ${r.status.name}${r.diag.note.isEmpty ? '' : ': ${r.diag.note}'}',
      errorCode: photoErrorCode(r.status),
      diag: diag,
    );
  }
  final h = r.header!;
  if (h.total > 1 || h.repair) {
    return PhotoDecodeResult(
      error: 'This file spans ${h.total} frames — use Live Scan',
      errorCode: 'multi_frame',
      diag: diag,
      total: h.total,
    );
  }
  final asm = RatelessAssembler();
  final added = asm.add(r.data!, blocksFailed: r.diag.rsFailed);
  if (!added.accepted) {
    return PhotoDecodeResult(error: 'Frame rejected (${added.reason})', errorCode: 'decode_failed', diag: diag);
  }
  try {
    final f = decodeFramedPayload(asm.framedData(), passphrase, compressed: asm.compressed);
    return PhotoDecodeResult(result: DecodeResult(filename: f.fileName, data: f.fileBytes), diag: diag);
  } on PassphraseRequiredException {
    return PhotoDecodeResult(
      error: 'This file is encrypted: a passphrase is required',
      errorCode: 'passphrase_required',
      diag: diag,
    );
  } catch (e) {
    return PhotoDecodeResult(error: '$e', errorCode: 'decode_failed', diag: diag);
  }
}
