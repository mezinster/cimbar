import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../constants/cimbar_constants.dart';

/// AES-256-GCM encryption/decryption matching web-app/crypto.js wire format.
///
/// Wire format: [0xCB 0x42 0x01 0x00][16 salt][12 IV][ciphertext + 16 auth tag]
class CryptoService {
  /// Derive a 32-byte AES key from passphrase + salt using PBKDF2-HMAC-SHA256.
  static Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(
        salt,
        CimbarConstants.pbkdf2Iterations,
        32, // 256-bit key
      ));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Decrypt a wire-format payload.
  /// Throws on bad magic, wrong passphrase, or tampered data.
  static Uint8List decrypt(Uint8List data, String passphrase) {
    if (data.length < 32 + 16) {
      // minimum: 32-byte header + at least 16-byte auth tag
      throw ArgumentError('Data too short to be a valid CimBar encrypted file');
    }

    // Verify magic
    if (data[0] != CimbarConstants.magic[0] ||
        data[1] != CimbarConstants.magic[1]) {
      throw ArgumentError('Invalid file: missing CimBar magic header');
    }
    if (data[2] != 0x01) {
      throw ArgumentError('Unsupported format version: ${data[2]}');
    }

    final salt = data.sublist(4, 20);
    final iv = data.sublist(20, 32);
    final ciphertextWithTag = data.sublist(32);

    final key = _deriveKey(passphrase, salt);

    // PointyCastle GCM: ciphertext+tag concatenated, same as Web Crypto
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(key),
          128, // tag length in bits
          iv,
          Uint8List(0), // no additional data
        ),
      );

    try {
      final plaintext = Uint8List(ciphertextWithTag.length - 16); // minus tag
      var offset = 0;
      offset += cipher.processBytes(
        ciphertextWithTag,
        0,
        ciphertextWithTag.length,
        plaintext,
        0,
      );
      cipher.doFinal(plaintext, offset);
      return plaintext;
    } catch (e) {
      throw StateError(
        'Decryption failed — wrong passphrase or corrupted data',
      );
    }
  }

  /// Encrypt arbitrary bytes with a passphrase.
  /// Returns Uint8List containing the full wire format.
  static Uint8List encrypt(Uint8List data, String passphrase) {
    final random = FortunaRandom();
    random.seed(KeyParameter(
      Uint8List.fromList(
        List.generate(32, (i) => DateTime.now().microsecondsSinceEpoch + i),
      ),
    ));

    final salt = random.nextBytes(16);
    final iv = random.nextBytes(12);
    final key = _deriveKey(passphrase, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final ciphertextWithTag = Uint8List(data.length + 16); // plus tag
    var offset = 0;
    offset += cipher.processBytes(data, 0, data.length, ciphertextWithTag, 0);
    cipher.doFinal(ciphertextWithTag, offset);

    // Build wire format
    final result = Uint8List(4 + 16 + 12 + ciphertextWithTag.length);
    result.setRange(0, 4, CimbarConstants.magic);
    result.setRange(4, 20, salt);
    result.setRange(20, 32, iv);
    result.setRange(32, result.length, ciphertextWithTag);
    return result;
  }

  /// Score passphrase strength, returns 0-100.
  static int passphraseStrength(String pass) {
    var score = 0;
    if (pass.length >= 8) score += 20;
    if (pass.length >= 14) score += 20;
    if (pass.length >= 20) score += 10;
    if (RegExp(r'[A-Z]').hasMatch(pass)) score += 15;
    if (RegExp(r'[a-z]').hasMatch(pass)) score += 10;
    if (RegExp(r'[0-9]').hasMatch(pass)) score += 10;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pass)) score += 15;
    return score > 100 ? 100 : score;
  }
}
