import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/file_container.dart';
import 'crypto_service.dart';

/// Raised inside the chunked inflate when the output passes the cap; turned
/// into a [FormatException] by [decodeFramedPayload].
class _InflateTooLarge implements Exception {
  const _InflateTooLarge(this.maxBytes);
  final int maxBytes;
}

/// Collects inflate output, refusing to buffer more than [maxBytes]: a few KB
/// of crafted zlib can otherwise expand to gigabytes (spec §4, §12).
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.maxBytes);
  final int maxBytes;
  final BytesBuilder _out = BytesBuilder(copy: false);
  int _count = 0;

  @override
  void add(List<int> chunk) {
    _count += chunk.length;
    if (_count > maxBytes) throw _InflateTooLarge(maxBytes);
    _out.add(chunk);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _out.takeBytes();
}

/// Inflate [bytes] chunk by chunk, stopping as soon as the output passes
/// [maxBytes] instead of materialising the whole expansion first.
Uint8List _inflateCapped(Uint8List bytes, int maxBytes) {
  final sink = _CappedSink(maxBytes);
  final input = ZLibDecoder().startChunkedConversion(sink);
  input.add(bytes);
  input.close();
  return sink.takeBytes();
}

/// Thrown by [decodeFramedPayload] when the framed payload is encrypted and
/// no passphrase was supplied.
class PassphraseRequiredException implements Exception {
  const PassphraseRequiredException();
  @override
  String toString() => 'passphrase required';
}

/// The shared tail of every v2 decode path once frame(s) have been fully
/// assembled: strip the u32 length prefix, detect encryption (`CB 42` magic),
/// decrypt if needed, inflate if the frame headers said the payload is
/// compressed (v2.1, spec §4 — deflate runs before encryption on the encode
/// side, so inflate runs after decryption here), and parse the file container.
///
/// [compressed] comes from the assembled frames' header flag, not from the
/// bytes: an unflagged deflate stream is not inflated.
///
/// Inflation is capped at [maxInflatedBytes] (default
/// [CimbarSpec.maxInflatedBytes], 128 MB); past it a [FormatException] is
/// thrown rather than the expansion being buffered. The parameter exists so
/// tests can lower the cap.
///
/// [passphrase] is trimmed first, as the web app trims its passphrase field on
/// both encode and decode: every app decode path (GIF import, photo, live
/// scan and its passphrase prompt) ends here, so " pw " opens a GIF encrypted
/// with "pw", and a whitespace-only passphrase counts as none.
///
/// Throws [PassphraseRequiredException] when the payload is encrypted and
/// [passphrase] is empty after trimming, and [FormatException] when inflation fails or the
/// inflated size exceeds the cap.
/// Otherwise propagates whatever
/// [FileContainer.stripLengthPrefix]/[FileContainer.parsePayload] throw on a
/// malformed container, or whatever [CryptoService.decrypt] throws on a
/// wrong passphrase or corrupted ciphertext.
ParsedFile decodeFramedPayload(
  Uint8List framed,
  String passphrase, {
  bool compressed = false,
  int maxInflatedBytes = CimbarSpec.maxInflatedBytes,
}) {
  final payload = FileContainer.stripLengthPrefix(framed);
  final pass = passphrase.trim();
  Uint8List plain;
  if (FileContainer.isEncrypted(payload)) {
    if (pass.isEmpty) throw const PassphraseRequiredException();
    plain = CryptoService.decrypt(payload, pass);
  } else {
    plain = payload;
  }
  if (compressed) {
    try {
      plain = _inflateCapped(plain, maxInflatedBytes);
    } on _InflateTooLarge catch (e) {
      throw FormatException('inflated size exceeds ${e.maxBytes} bytes');
    } catch (e) {
      throw FormatException('inflate failed: $e');
    }
  }
  return FileContainer.parsePayload(plain);
}
