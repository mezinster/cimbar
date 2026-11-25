import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/core/encode/frame_budget.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';

Uint8List _random(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

void main() {
  test('framedBytes', () {
    expect(framedBytes(nameBytes: 5, dataBytes: 100, encrypted: false), 113);
    expect(framedBytes(nameBytes: 5, dataBytes: 100, encrypted: true), 161);
  });

  test('framesForFramed', () {
    expect(framesForFramed(0), 1);
    expect(framesForFramed(2104), 1);
    expect(framesForFramed(2105), 2);
  });

  test('photoByteBudget', () {
    expect(photoByteBudget(1, 'a.jpg'), 2104 - 8 - 5 - 48);
  });

  test('photoByteBudget uses UTF-8 name length', () {
    const name = 'фото😀.jpg';
    expect(utf8.encode(name).length, 16);
    expect(photoByteBudget(3, name), 3 * 2104 - 8 - 16 - 48);
  });

  test('encryption reserve holds through the real encoder', () {
    for (final n in [1, 7, 50]) {
      const name = 'IMG_1.jpg';
      final budget = photoByteBudget(n, name);
      final b = _random(budget, n);
      expect(PayloadEncoder.encode(name: name, bytes: b, passphrase: 'pw').total, n);
      final more = _random(budget + 1, n);
      expect(PayloadEncoder.encode(name: name, bytes: more, passphrase: 'pw').total, n + 1);
      expect(PayloadEncoder.encode(name: name, bytes: b).total <= n, isTrue);
    }
  });

  test('framesForFile agrees with the encoder', () {
    const name = 'IMG_1.jpg';
    for (final len in [0, 1, 2000, 2104, 5000, 20000]) {
      final b = _random(len, len);
      for (final enc in [false, true]) {
        final total = PayloadEncoder.encode(name: name, bytes: b, passphrase: enc ? 'pw' : '').total;
        expect(framesForFile(name, len, encrypted: enc), total, reason: 'len=$len enc=$enc');
      }
    }
  });
}
