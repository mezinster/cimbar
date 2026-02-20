import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/services/crypto_service.dart';
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';

void main() {
  group('CryptoService', () {
    test('encrypt then decrypt round-trip', () {
      final original = Uint8List.fromList(
        List.generate(100, (i) => (i * 7 + 13) & 0xFF),
      );
      const passphrase = 'test-passphrase-123!';

      final encrypted = CryptoService.encrypt(original, passphrase);

      // Verify wire format header
      expect(encrypted[0], equals(CimbarConstants.magic[0]));
      expect(encrypted[1], equals(CimbarConstants.magic[1]));
      expect(encrypted[2], equals(0x01));
      expect(encrypted[3], equals(0x00));
      expect(encrypted.length, greaterThan(32 + 16)); // header + tag

      final decrypted = CryptoService.decrypt(encrypted, passphrase);
      expect(decrypted, equals(original));
    });

    test('wrong passphrase throws', () {
      final original = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encrypted = CryptoService.encrypt(original, 'correct-password');

      expect(
        () => CryptoService.decrypt(encrypted, 'wrong-password'),
        throwsA(isA<StateError>()),
      );
    });

    test('bad magic throws', () {
      final badData = Uint8List(100);
      badData[0] = 0xFF; // wrong magic

      expect(
        () => CryptoService.decrypt(badData, 'password'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('data too short throws', () {
      final shortData = Uint8List(10);

      expect(
        () => CryptoService.decrypt(shortData, 'password'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('passphraseStrength scoring', () {
      expect(CryptoService.passphraseStrength(''), equals(0));
      expect(CryptoService.passphraseStrength('abcdefgh'), equals(30)); // len>=8 + lowercase
      expect(CryptoService.passphraseStrength('Abcdefgh1!'), greaterThanOrEqualTo(65));
      expect(
        CryptoService.passphraseStrength('MyVeryLongP@ssw0rd!!'),
        greaterThanOrEqualTo(90),
      );
    });
  });
}
