import 'dart:typed_data';

/// GF(256) arithmetic with primitive polynomial x^8+x^4+x^3+x^2+1 (0x11D).
/// Port of web-app/rs.js:13-73.
class GaloisField {
  GaloisField._();

  static const int _gfPrim = 0x11D;

  /// Exponential lookup table (512 entries for wraparound).
  static final Uint8List gfExp = _buildExp();

  /// Logarithm lookup table (256 entries).
  static final Uint8List gfLog = _buildLog();

  static Uint8List _buildExp() {
    final exp = Uint8List(512);
    final log = Uint8List(256);
    var x = 1;
    for (var i = 0; i < 255; i++) {
      exp[i] = x;
      log[x] = i;
      x <<= 1;
      if (x & 0x100 != 0) x ^= _gfPrim;
    }
    for (var i = 255; i < 512; i++) {
      exp[i] = exp[i - 255];
    }
    return exp;
  }

  static Uint8List _buildLog() {
    final log = Uint8List(256);
    var x = 1;
    for (var i = 0; i < 255; i++) {
      log[x] = i;
      x <<= 1;
      if (x & 0x100 != 0) x ^= _gfPrim;
    }
    return log;
  }

  static int gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return gfExp[gfLog[a] + gfLog[b]];
  }

  static int gfDiv(int a, int b) {
    if (b == 0) throw ArgumentError('GF division by zero');
    if (a == 0) return 0;
    return gfExp[(gfLog[a] - gfLog[b] + 255) % 255];
  }

  static int gfPow(int x, int power) {
    return gfExp[(gfLog[x] * power) % 255];
  }

  static int gfInv(int x) {
    return gfExp[255 - gfLog[x]];
  }

  // ── Polynomial operations (index 0 = highest degree) ──

  static Uint8List polyScale(Uint8List p, int x) {
    final result = Uint8List(p.length);
    for (var i = 0; i < p.length; i++) {
      result[i] = gfMul(p[i], x);
    }
    return result;
  }

  static Uint8List polyAdd(Uint8List p, Uint8List q) {
    final len = p.length > q.length ? p.length : q.length;
    final result = Uint8List(len);
    for (var i = 0; i < p.length; i++) {
      result[i + len - p.length] ^= p[i];
    }
    for (var i = 0; i < q.length; i++) {
      result[i + len - q.length] ^= q[i];
    }
    return result;
  }

  static Uint8List polyMul(Uint8List p, Uint8List q) {
    final result = Uint8List(p.length + q.length - 1);
    for (var i = 0; i < p.length; i++) {
      for (var j = 0; j < q.length; j++) {
        result[i + j] ^= gfMul(p[i], q[j]);
      }
    }
    return result;
  }

  static int polyEval(Uint8List p, int x) {
    var y = p[0];
    for (var i = 1; i < p.length; i++) {
      y = gfMul(y, x) ^ p[i];
    }
    return y;
  }
}
