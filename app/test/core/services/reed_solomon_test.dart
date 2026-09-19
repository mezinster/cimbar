import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';

/// Deterministic pseudo-random byte sequence, matching test_rs.js.
Uint8List seqData(int n, int seed) {
  final d = Uint8List(n);
  var s = seed;
  for (var i = 0; i < n; i++) {
    s = ((s * 1664525) + 1013904223) & 0xFFFFFFFF;
    d[i] = s & 0xFF;
  }
  return d;
}

void main() {
  final rs = ReedSolomon(64); // ECC_BYTES = 64, correction capacity = 32

  group('ReedSolomon', () {
    test('encode/decode, no errors', () {
      final data = seqData(100, 42);
      final encoded = rs.encode(data);
      expect(encoded.length, equals(164)); // 100 + 64

      final decoded = rs.decode(encoded);
      expect(decoded, equals(data));
    });

    test('correct 32 random errors', () {
      final data = seqData(100, 99);
      final encoded = rs.encode(data);
      final received = Uint8List.fromList(encoded);

      // Inject 32 errors at fixed, spread-out positions
      for (var k = 0; k < 32; k++) {
        received[k * 5] ^= 0xA5;
      }

      final decoded = rs.decode(received);
      expect(decoded, equals(data));
    });

    test('33+ errors detected as uncorrectable', () {
      final data = seqData(100, 7);
      final encoded = rs.encode(data);
      final received = Uint8List.fromList(encoded);

      // Inject 40 errors to reliably exceed correction capacity
      for (var k = 0; k < 40; k++) {
        received[k * 4] ^= 0xFF;
      }

      var threw = false;
      var wrongDecode = false;
      try {
        final decoded = rs.decode(received);
        wrongDecode = !_arraysEqual(decoded, data);
      } catch (_) {
        threw = true;
      }

      expect(
        threw || wrongDecode,
        isTrue,
        reason:
            '40 injected errors were silently "corrected" to the original data',
      );
    });

    test('Forney / Omega correctness with 8 errors at known positions', () {
      final data = seqData(50, 13);
      final encoded = rs.encode(data);
      final received = Uint8List.fromList(encoded);

      // Inject 8 errors at specific byte positions
      const errorPositions = [0, 7, 14, 21, 28, 35, 42, 49];
      for (final pos in errorPositions) {
        received[pos] ^= 0xC3;
      }

      final decoded = rs.decode(received);
      expect(decoded, equals(data));
    });

    test('full-block (191 data bytes) round-trip', () {
      final data = seqData(191, 55);
      final encoded = rs.encode(data);
      expect(encoded.length, equals(255));

      final decoded = rs.decode(encoded);
      expect(decoded, equals(data));
    });

    test('full-block with max correctable errors', () {
      final data = seqData(191, 77);
      final encoded = rs.encode(data);
      final received = Uint8List.fromList(encoded);

      // Inject 32 errors (max correctable for RS(255,191))
      for (var k = 0; k < 32; k++) {
        received[k * 7] ^= 0xBB;
      }

      final decoded = rs.decode(received);
      expect(decoded, equals(data));
    });
  });
}

bool _arraysEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
