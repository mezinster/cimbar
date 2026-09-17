import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/services/crypto_service.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';

/// [payload]/[framedOf] mirror file_container_test.dart's helpers: payload =
/// [u32 nameLen][name][fileBytes]; framedOf wraps it as
/// [u32 len][payload][zero padding] the way FrameAssembler.framedData() does.
Uint8List payload(String name, List<int> bytes) {
  final n = utf8.encode(name);
  final out = Uint8List(4 + n.length + bytes.length);
  out[3] = n.length;
  out.setRange(4, 4 + n.length, n);
  out.setRange(4 + n.length, out.length, bytes);
  return out;
}

Uint8List framedOf(Uint8List body, {int padding = 32}) {
  final framed = Uint8List(4 + body.length + padding);
  framed[3] = body.length;
  framed.setRange(4, 4 + body.length, body);
  return framed;
}

void main() {
  test('unencrypted payload round-trips', () {
    final body = payload('hello.txt', [1, 2, 3, 4]);
    final f = decodeFramedPayload(framedOf(body), '');
    expect(f.fileName, 'hello.txt');
    expect(f.fileBytes, Uint8List.fromList([1, 2, 3, 4]));
  });

  test('encrypted payload decodes with the right passphrase, and requires one when empty', () {
    final body = payload('secret.bin', [9, 9, 9]);
    final encrypted = CryptoService.encrypt(body, 'pw');
    final framed = framedOf(encrypted);

    final f = decodeFramedPayload(framed, 'pw');
    expect(f.fileName, 'secret.bin');
    expect(f.fileBytes, Uint8List.fromList([9, 9, 9]));

    expect(() => decodeFramedPayload(framed, ''), throwsA(isA<PassphraseRequiredException>()));
  });

  test('a wrong passphrase throws', () {
    final body = payload('secret.bin', [9, 9, 9]);
    final framed = framedOf(CryptoService.encrypt(body, 'pw'));
    expect(() => decodeFramedPayload(framed, 'nope'), throwsA(anything));
  });
}
