import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_assembler.dart';
import '../decode/frame_decoder.dart';
import '../decode/rgb_buffer.dart';
import '../format/file_container.dart';
import '../models/decode_result.dart';
import 'crypto_service.dart';
import 'gif_parser.dart';

/// GIF import: GIF -> frames -> FrameDecoder (exact) -> FrameAssembler ->
/// length prefix -> [decrypt] -> file. Mirrors web-app/index.html startDecode.
class DecodePipeline {
  final FrameDecoder _decoder = FrameDecoder();

  Stream<DecodeProgress> decodeGif(Uint8List gifBytes, String passphrase) async* {
    yield const DecodeProgress(state: DecodeState.parsingGif, message: 'Parsing GIF...');

    final List<img.Image> frames;
    try {
      frames = GifParser.parseFrames(gifBytes);
    } catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'Failed to parse GIF: $e');
      return;
    }

    yield const DecodeProgress(state: DecodeState.decodingFrames, message: 'Decoding frames...');

    final assembler = FrameAssembler();
    var rejected = 0;
    for (var i = 0; i < frames.length; i++) {
      final r = _decoder.decodeExact(RgbBuffer.fromImage(frames[i]));
      if (r.status == DecodeStatus.unsupportedGrid) {
        yield DecodeProgress(
          state: DecodeState.error,
          message: 'Not a CimBar v2 GIF: frames must be 608x608 px (${r.diag.note}). v1 GIFs must be re-encoded.',
        );
        return;
      }
      final data = r.data;
      if (data == null) {
        yield DecodeProgress(
          state: DecodeState.error,
          message: 'Frame ${i + 1}: ${r.status.name}${r.diag.note.isEmpty ? '' : ' (${r.diag.note})'}',
        );
        return;
      }
      final added = assembler.add(data, blocksFailed: r.diag.rsFailed);
      if (!added.accepted) rejected++;
      yield DecodeProgress(
        state: DecodeState.decodingFrames,
        progress: (i + 1) / frames.length,
        message: 'Frame ${i + 1}/${frames.length}: ${added.accepted ? 'ok' : 'rejected (${added.reason})'}',
      );
    }

    if (!assembler.isComplete) {
      if (assembler.total == 0) {
        yield DecodeProgress(
          state: DecodeState.error,
          message: 'No CimBar v2 frames decoded ($rejected rejected)',
        );
        return;
      }
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Incomplete: ${assembler.filled} of ${assembler.total} frames decoded ($rejected rejected)',
      );
      return;
    }

    final Uint8List payloadBytes;
    try {
      payloadBytes = FileContainer.stripLengthPrefix(assembler.framedData());
    } on FormatException catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'Header corrupt: ${e.message}');
      return;
    }

    final Uint8List plain;
    if (FileContainer.isEncrypted(payloadBytes)) {
      if (passphrase.isEmpty) {
        yield const DecodeProgress(state: DecodeState.error, message: 'This GIF is encrypted: a passphrase is required');
        return;
      }
      yield const DecodeProgress(state: DecodeState.decrypting, progress: 0.5, message: 'Decrypting...');
      try {
        plain = CryptoService.decrypt(payloadBytes, passphrase);
      } catch (e) {
        yield DecodeProgress(state: DecodeState.error, message: 'Decryption failed: $e');
        return;
      }
    } else {
      plain = payloadBytes;
    }

    final ParsedFile file;
    try {
      file = FileContainer.parsePayload(plain);
    } on FormatException catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'File header corrupt: ${e.message}');
      return;
    }

    // Store result BEFORE yield — async* generators suspend at yield.
    _lastResult = DecodeResult(filename: file.fileName, data: file.fileBytes);
    yield DecodeProgress(
      state: DecodeState.done,
      progress: 1.0,
      message: 'Decoded: ${file.fileName} (${file.fileBytes.length} bytes)',
    );
  }

  DecodeResult? _lastResult;
  DecodeResult? get lastResult => _lastResult;
}
