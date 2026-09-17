import 'dart:typed_data';

import 'cimbar_spec.dart';

/// The 16 symbol tiles as 64-entry 0/1 arrays (row-major, index = row*8 + col).
class Tiles {
  Tiles._();

  static final List<Uint8List> bits =
      List.unmodifiable(CimbarSpec.tiles.map(hexToTile));

  static Uint8List hexToTile(String hex) {
    if (hex.length != 16) throw ArgumentError('tile hex must be 16 chars');
    final t = Uint8List(64);
    for (var i = 0; i < 16; i++) {
      final nib = int.parse(hex[i], radix: 16);
      for (var b = 0; b < 4; b++) {
        t[i * 4 + b] = (nib >> (3 - b)) & 1;
      }
    }
    return t;
  }

  static String tileToHex(Uint8List t) {
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      var nib = 0;
      for (var b = 0; b < 4; b++) {
        nib = (nib << 1) | t[i * 4 + b];
      }
      sb.write(nib.toRadixString(16));
    }
    return sb.toString();
  }

  static int popcount(Uint8List t) {
    var n = 0;
    for (var i = 0; i < 64; i++) {
      n += t[i];
    }
    return n;
  }

  static int hamming(Uint8List a, Uint8List b) {
    var n = 0;
    for (var i = 0; i < 64; i++) {
      n += a[i] ^ b[i];
    }
    return n;
  }
}
