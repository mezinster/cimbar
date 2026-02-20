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
  final rs = ReedSolomon(32); // ECC_BYTES = 32, correction capacity = 16

  group('ReedSolomon', () {
    test('encode/decode, no errors', () {
      final data = seqData(100, 42);
      final encoded = rs.encode(data);
      expect(encoded.length, equals(132)); // 100 + 32

      final decoded = rs.decode(encoded);
      expect(decoded, equals(data));
    });

    test('correct 16 random errors', () {
      final data = seqData(100, 99);
      final encoded = rs.encode(data);
      final received = Uint8List.fromList(encoded);

      // Inject 16 errors at fixed, spread-out positions
      for (var k = 0; k < 16; k++) {
        received[k * 8] ^= 0xA5;
      }

      final decoded = rs.decode(received);
      expect(decoded, equals(data));
    });

    test('17+ errors detected as uncorrectable', () {
      final data = seqData(100, 7);
      final encoded = rs.encode(data);
      final received = Uint8List.fromList(encoded);

      // Inject 20 errors
      for (var k = 0; k < 20; k++) {
        received[k * 6] ^= 0xFF;
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
            '20 injected errors were silently "corrected" to the original data',
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

    test('full-block (223 data bytes) round-trip', () {
      final data = seqData(223, 55);
      final encoded = rs.encode(data);
      expect(encoded.length, equals(255));

      final decoded = rs.decode(encoded);
      expect(decoded, equals(data));
    });

    test('full-block with max correctable errors', () {
      final data = seqData(223, 77);
      final encoded = rs.encode(data);
      final received = Uint8List.fromList(encoded);

      for (var k = 0; k < 16; k++) {
        received[k * 15] ^= 0xBB;
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
