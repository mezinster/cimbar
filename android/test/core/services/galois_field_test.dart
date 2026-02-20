import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/services/galois_field.dart';

void main() {
  group('GaloisField', () {
    test('gfExp table wraps at 255', () {
      for (var i = 0; i < 255; i++) {
        expect(GaloisField.gfExp[i + 255], equals(GaloisField.gfExp[i]),
            reason: 'gfExp[$i] != gfExp[${i + 255}]');
      }
    });

    test('gfExp[0] == 1 (alpha^0 = 1)', () {
      expect(GaloisField.gfExp[0], equals(1));
    });

    test('gfLog[1] == 0 (log(1) = 0)', () {
      expect(GaloisField.gfLog[1], equals(0));
    });

    test('gfMul identity and zero', () {
      expect(GaloisField.gfMul(0, 42), equals(0));
      expect(GaloisField.gfMul(42, 0), equals(0));
      expect(GaloisField.gfMul(1, 42), equals(42));
      expect(GaloisField.gfMul(42, 1), equals(42));
    });

    test('gfMul commutativity', () {
      for (var a = 1; a < 256; a += 17) {
        for (var b = 1; b < 256; b += 19) {
          expect(GaloisField.gfMul(a, b), equals(GaloisField.gfMul(b, a)),
              reason: 'gfMul($a,$b) != gfMul($b,$a)');
        }
      }
    });

    test('gfDiv is inverse of gfMul', () {
      for (var a = 1; a < 256; a += 13) {
        for (var b = 1; b < 256; b += 17) {
          final product = GaloisField.gfMul(a, b);
          expect(GaloisField.gfDiv(product, b), equals(a),
              reason: 'gfDiv(gfMul($a,$b), $b) != $a');
        }
      }
    });

    test('gfPow and gfInv consistency', () {
      for (var x = 1; x < 256; x += 11) {
        final inv = GaloisField.gfInv(x);
        expect(GaloisField.gfMul(x, inv), equals(1),
            reason: 'x * gfInv(x) != 1 for x=$x');
      }
    });

    test('polyEval of [1] returns 1 for any x', () {
      expect(GaloisField.polyEval(Uint8List.fromList([1]), 0), equals(1));
      expect(GaloisField.polyEval(Uint8List.fromList([1]), 42), equals(1));
    });

    test('polyMul [1,0] * [1,0] = [1,0,0]', () {
      final p = Uint8List.fromList([1, 0]);
      final result = GaloisField.polyMul(p, p);
      expect(result, equals(Uint8List.fromList([1, 0, 0])));
    });

    test('polyAdd cancellation', () {
      final p = Uint8List.fromList([3, 5, 7]);
      final result = GaloisField.polyAdd(p, p);
      expect(result, equals(Uint8List.fromList([0, 0, 0])));
    });
  });
}
