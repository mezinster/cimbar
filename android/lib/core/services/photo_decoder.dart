import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_assembler.dart';
import '../decode/frame_decoder.dart';
import '../decode/rgb_buffer.dart';
import '../format/file_container.dart';
import '../models/decode_result.dart';
import 'crypto_service.dart';

/// Result of a still-photo v2 decode attempt.
///
/// [errorCode] is a stable, l10n-mappable tag ('multi_frame',
/// 'passphrase_required', 'not_located', 'decode_failed'); [error] is the
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
    return const PhotoDecodeResult(error: 'Cannot decode image', errorCode: 'decode_failed');
  }
  final r = FrameDecoder().decode(RgbBuffer.fromImage(image));
  final diag = r.diag.toMap();
  if (r.status != DecodeStatus.ok) {
    final errorCode = r.status == DecodeStatus.notLocated ? 'not_located' : 'decode_failed';
    return PhotoDecodeResult(
      error: 'Barcode ${r.status.name}${r.diag.note.isEmpty ? '' : ': ${r.diag.note}'}',
      errorCode: errorCode,
      diag: diag,
    );
  }
  final h = r.header!;
  if (h.total > 1) {
    return PhotoDecodeResult(
      error: 'This file spans ${h.total} frames — use Live Scan',
      errorCode: 'multi_frame',
      diag: diag,
      total: h.total,
    );
  }
  final asm = FrameAssembler();
  final added = asm.add(r.data!, blocksFailed: r.diag.rsFailed);
  if (!added.accepted) {
    return PhotoDecodeResult(error: 'Frame rejected (${added.reason})', errorCode: 'decode_failed', diag: diag);
  }
  try {
    final payload = FileContainer.stripLengthPrefix(asm.framedData());
    Uint8List plain;
    if (FileContainer.isEncrypted(payload)) {
      if (passphrase.isEmpty) {
        return PhotoDecodeResult(
          error: 'This file is encrypted: a passphrase is required',
          errorCode: 'passphrase_required',
          diag: diag,
        );
      }
      plain = CryptoService.decrypt(payload, passphrase);
    } else {
      plain = payload;
    }
    final f = FileContainer.parsePayload(plain);
    return PhotoDecodeResult(result: DecodeResult(filename: f.fileName, data: f.fileBytes), diag: diag);
  } catch (e) {
    return PhotoDecodeResult(error: '$e', errorCode: 'decode_failed', diag: diag);
  }
}
