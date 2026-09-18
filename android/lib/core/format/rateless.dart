import 'dart:typed_data';

import '../services/galois_field.dart';
import 'cimbar_spec.dart';

/// v2.1 coding layer (spec §5): repair-row coefficients derived from the frame
/// header alone, and GF(256) combination of source bodies. Port of
/// `codingCoefficients` in web-app/format.js and `combineBodies` in
/// web-app/rateless.js.
class Rateless {
  Rateless._();

  /// Coefficients of repair row `r` of file `fileId` over `n` source frames.
  ///
  /// A splitmix32-style generator: a linear state advance plus murmur3's fmix32
  /// output mix, so rows for different `r` are not confined to a small linear
  /// subspace (a plain xorshift/LFSR would be). Dart ints are 64-bit, so each
  /// product may exceed 2^63 and wrap; the low 32 bits survive, which is all
  /// `& 0xFFFFFFFF` keeps.
  static Uint8List coefficients(int fileId, int r, int n) {
    var state = ((((fileId & 0xFFFF) << 16) | (r & 0xFFFF))) & 0xFFFFFFFF;
    final out = Uint8List(n);
    for (var j = 0; j < n; j++) {
      state = (state + CimbarSpec.codingIncrement) & 0xFFFFFFFF;
      var z = state;
      z = ((z ^ (z >> 16)) * CimbarSpec.codingMixMul1) & 0xFFFFFFFF;
      z = ((z ^ (z >> 13)) * CimbarSpec.codingMixMul2) & 0xFFFFFFFF;
      z = (z ^ (z >> 16)) & 0xFFFFFFFF;
      out[j] = z & 0xFF;
    }
    return out;
  }

  /// out = sum over j of coef[j] * bodies[j] in GF(256). All bodies share one length.
  static Uint8List combine(List<Uint8List> bodies, Uint8List coef) {
    final len = bodies[0].length;
    final out = Uint8List(len);
    for (var j = 0; j < coef.length; j++) {
      final c = coef[j];
      if (c == 0) continue;
      final b = bodies[j];
      if (c == 1) {
        for (var i = 0; i < len; i++) {
          out[i] ^= b[i];
        }
        continue;
      }
      for (var i = 0; i < len; i++) {
        out[i] ^= GaloisField.gfMul(c, b[i]);
      }
    }
    return out;
  }
}
