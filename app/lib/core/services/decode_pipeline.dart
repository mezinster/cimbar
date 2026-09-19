import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_decoder.dart';
import '../decode/rateless_assembler.dart';
import '../decode/rgb_buffer.dart';
import '../format/file_container.dart';
import '../models/decode_result.dart';
import 'gif_parser.dart';
import 'payload_decoder.dart';

/// GIF import: GIF -> frames -> FrameDecoder (exact) -> RatelessAssembler ->
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

    final assembler = RatelessAssembler();
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
      final String frameMsg;
      if (added.accepted) {
        frameMsg = 'ok';
      } else if (added.reason == 'dependent') {
        frameMsg = 'no new information';
      } else {
        rejected++;
        frameMsg = 'rejected (${added.reason})';
      }
      yield DecodeProgress(
        state: DecodeState.decodingFrames,
        progress: (i + 1) / frames.length,
        message: 'Frame ${i + 1}/${frames.length}: $frameMsg',
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
        message: 'Incomplete: rank ${assembler.rank} of ${assembler.total} ($rejected rejected)',
      );
      return;
    }

    final ParsedFile file;
    try {
      file = decodeFramedPayload(assembler.framedData(), passphrase, compressed: assembler.compressed);
    } on PassphraseRequiredException {
      yield const DecodeProgress(state: DecodeState.error, message: 'This GIF is encrypted: a passphrase is required');
      return;
    } on FormatException catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'File header corrupt: ${e.message}');
      return;
    } on StateError catch (e) {
      // CryptoService.decrypt throws StateError on a wrong passphrase or a
      // corrupt auth tag; anything else here is not a decryption problem.
      yield DecodeProgress(state: DecodeState.error, message: 'Decryption failed: $e');
      return;
    } catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'Decode failed: $e');
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
