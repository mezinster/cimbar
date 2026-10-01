import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/services/crypto_service.dart';

void main() {
  final data = Uint8List.fromList(List.generate(100, (i) => i));

  test('encrypt round-trips through decrypt', () {
    final enc = CryptoService.encrypt(data, 'pw');
    expect(CryptoService.decrypt(enc, 'pw'), data);
  });

  test('salt and IV are fresh per call (no 256-seed space)', () {
    final seen = <String>{};
    for (var i = 0; i < 300; i++) {
      final enc = CryptoService.encrypt(data, 'pw');
      seen.add(enc.sublist(4, 32).toString()); // salt || iv
    }
    // The old FortunaRandom seed kept only the low byte of the clock: at most
    // 256 distinct (salt, iv) pairs, so 300 calls (> 256) always collided.
    expect(seen.length, 300);
  });

  test('injected salt/iv are used verbatim (golden reproduction only)', () {
    final salt = Uint8List.fromList(List.generate(16, (i) => 0xA0 + i));
    final iv = Uint8List.fromList(List.generate(12, (i) => 0xB0 + i));
    final enc = CryptoService.encrypt(data, 'pw', salt: salt, iv: iv);
    expect(enc.sublist(4, 20), salt);
    expect(enc.sublist(20, 32), iv);
  });
}
