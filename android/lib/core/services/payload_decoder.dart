import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import '../format/file_container.dart';
import 'crypto_service.dart';

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
/// Throws [PassphraseRequiredException] when the payload is encrypted and
/// [passphrase] is empty, and [FormatException] when inflation fails.
/// Otherwise propagates whatever
/// [FileContainer.stripLengthPrefix]/[FileContainer.parsePayload] throw on a
/// malformed container, or whatever [CryptoService.decrypt] throws on a
/// wrong passphrase or corrupted ciphertext.
ParsedFile decodeFramedPayload(Uint8List framed, String passphrase, {bool compressed = false}) {
  final payload = FileContainer.stripLengthPrefix(framed);
  Uint8List plain;
  if (FileContainer.isEncrypted(payload)) {
    if (passphrase.isEmpty) throw const PassphraseRequiredException();
    plain = CryptoService.decrypt(payload, passphrase);
  } else {
    plain = payload;
  }
  if (compressed) {
    try {
      plain = Uint8List.fromList(ZLibCodec().decode(plain));
    } catch (e) {
      throw FormatException('inflate failed: $e');
    }
  }
  return FileContainer.parsePayload(plain);
}
