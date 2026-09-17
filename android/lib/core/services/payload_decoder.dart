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
/// decrypt if needed, and parse the file container.
///
/// Throws [PassphraseRequiredException] when the payload is encrypted and
/// [passphrase] is empty. Otherwise propagates whatever
/// [FileContainer.stripLengthPrefix]/[FileContainer.parsePayload] throw on a
/// malformed container, or whatever [CryptoService.decrypt] throws on a
/// wrong passphrase or corrupted ciphertext.
ParsedFile decodeFramedPayload(Uint8List framed, String passphrase) {
  final payload = FileContainer.stripLengthPrefix(framed);
  Uint8List plain;
  if (FileContainer.isEncrypted(payload)) {
    if (passphrase.isEmpty) throw const PassphraseRequiredException();
    plain = CryptoService.decrypt(payload, passphrase);
  } else {
    plain = payload;
  }
  return FileContainer.parsePayload(plain);
}
