import 'dart:typed_data';

import 'galois_field.dart';

/// Reed-Solomon RS(255, 255-eccLen) over GF(256).
/// Port of web-app/rs.js:76-235, preserving all four documented bug fixes.
class ReedSolomon {
  final int eccLen;
  final Uint8List _gen;

  ReedSolomon([this.eccLen = 32]) : _gen = _generatorPoly(eccLen);

  static Uint8List _generatorPoly(int eccLen) {
    var g = Uint8List.fromList([1]);
    for (var i = 0; i < eccLen; i++) {
      g = GaloisField.polyMul(
        g,
        Uint8List.fromList([1, GaloisField.gfPow(2, i)]),
      );
    }
    return g;
  }

  /// Encode data bytes. Returns Uint8List of length data.length + eccLen.
  Uint8List encode(Uint8List data) {
    final msg = Uint8List(data.length + eccLen);
    msg.setRange(0, data.length, data);

    // Polynomial long division
    for (var i = 0; i < data.length; i++) {
      final coef = msg[i];
      if (coef != 0) {
        for (var j = 1; j < _gen.length; j++) {
          msg[i + j] ^= GaloisField.gfMul(_gen[j], coef);
        }
      }
    }

    // Restore data, append ECC
    final result = Uint8List(data.length + eccLen);
    result.setRange(0, data.length, data);
    result.setRange(data.length, result.length, msg, data.length);
    return result;
  }

  /// Decode received codeword. Returns original data Uint8List.
  /// Throws if uncorrectable.
  Uint8List decode(Uint8List received) {
    final msg = Uint8List.fromList(received);

    // 1. Compute syndromes
    final syndromes = Uint8List(eccLen);
    var hasError = false;
    for (var i = 0; i < eccLen; i++) {
      syndromes[i] = GaloisField.polyEval(msg, GaloisField.gfPow(2, i));
      if (syndromes[i] != 0) hasError = true;
    }

    if (!hasError) return msg.sublist(0, msg.length - eccLen);

    // 2. Berlekamp-Massey to find error locator polynomial
    var C = Uint8List.fromList([1]);
    var B = Uint8List.fromList([1]);
    var L = 0, m = 1, b = 1;

    for (var n = 0; n < eccLen; n++) {
      var d = syndromes[n];
      for (var i = 1; i <= L; i++) {
        if (i < C.length) {
          d ^= GaloisField.gfMul(C[C.length - 1 - i], syndromes[n - i]);
        }
      }

      if (d == 0) {
        m++;
      } else if (2 * L <= n) {
        final T = Uint8List.fromList(C);
        final shift = Uint8List(m + B.length);
        shift.setRange(0, B.length, B);
        final scaled =
            GaloisField.polyScale(shift, GaloisField.gfMul(d, GaloisField.gfInv(b)));
        final cPad = Uint8List(C.length > scaled.length ? C.length : scaled.length);
        cPad.setRange(cPad.length - C.length, cPad.length, C);
        C = GaloisField.polyAdd(cPad, scaled);
        L = n + 1 - L;
        B = T;
        b = d;
        m = 1;
      } else {
        final shift = Uint8List(m + B.length);
        shift.setRange(0, B.length, B);
        final scaled =
            GaloisField.polyScale(shift, GaloisField.gfMul(d, GaloisField.gfInv(b)));
        final cPad = Uint8List(C.length > scaled.length ? C.length : scaled.length);
        cPad.setRange(cPad.length - C.length, cPad.length, C);
        C = GaloisField.polyAdd(cPad, scaled);
        m++;
      }
    }

    if (L == 0) return msg.sublist(0, msg.length - eccLen);

    // 3. Chien search — BUG FIX #1: must search all 255 GF elements, not msg.length
    final errPos = <int>[];
    for (var i = 0; i < 255; i++) {
      if (GaloisField.polyEval(C, GaloisField.gfPow(2, i)) == 0) {
        // BUG FIX #2: pos = (255 - i) % 255, not msg.length - 1 - i
        final pos = (255 - i) % 255;
        if (pos < msg.length) errPos.add(pos);
      }
    }

    if (errPos.length != L) {
      throw StateError(
        'RS: uncorrectable errors (found ${errPos.length}, expected $L)',
      );
    }

    // 4. Forney algorithm
    final E = Uint8List(msg.length);

    // BUG FIX #3: syndromesAsc = reversed syndromes [S_{t-1},...,S_0]
    final syndromesAsc = Uint8List(eccLen);
    for (var i = 0; i < eccLen; i++) {
      syndromesAsc[i] = syndromes[eccLen - 1 - i];
    }
    final product = GaloisField.polyMul(syndromesAsc, C);
    // mod x^t: keep lowest-degree terms = slice from end
    final omega = product.sublist(product.length - eccLen);

    for (final pos in errPos) {
      final xi = GaloisField.gfPow(2, pos);
      final xiInv = GaloisField.gfInv(xi);

      // Formal derivative of C (only odd-indexed terms survive in GF(2^m))
      var denom = 0;
      for (var i = 1; i < C.length; i += 2) {
        denom ^= GaloisField.gfMul(
          C[C.length - 1 - i],
          GaloisField.gfPow(xiInv, i - 1),
        );
      }

      final num = GaloisField.polyEval(
        omega.isNotEmpty ? omega : Uint8List.fromList([0]),
        xiInv,
      );

      // BUG FIX #4: e_k = X_k * Omega(X_k^-1) / Lambda'(X_k^-1)
      E[msg.length - 1 - pos] = GaloisField.gfMul(xi, GaloisField.gfDiv(num, denom));
    }

    // 5. Correct
    final corrected = Uint8List(msg.length);
    for (var i = 0; i < msg.length; i++) {
      corrected[i] = msg[i] ^ E[i];
    }

    // 6. Verify
    for (var i = 0; i < eccLen; i++) {
      if (GaloisField.polyEval(corrected, GaloisField.gfPow(2, i)) != 0) {
        throw StateError('RS: correction failed verification');
      }
    }

    return corrected.sublist(0, corrected.length - eccLen);
  }
}
