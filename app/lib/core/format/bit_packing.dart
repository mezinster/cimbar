import 'dart:typed_data';

import 'cimbar_spec.dart';

/// 6-bit cell values <-> the frame's raw byte stream (MSB-first).
/// Cell value = (symbol << 2) | color.
class BitPacking {
  BitPacking._();

  static int cellValue(int sym, int color) =>
      ((sym & 0xF) << CimbarSpec.colorBits) | (color & 0x3);
  static int cellSymbol(int v) => (v >> CimbarSpec.colorBits) & 0xF;
  static int cellColor(int v) => v & 0x3;

  /// raw: up to 2880 bytes (missing bytes read as 0). Returns 3840 cell values.
  static Uint8List packCells(Uint8List raw) {
    const n = CimbarSpec.usableCells;
    final out = Uint8List(n);
    var bitPos = 0;
    for (var k = 0; k < n; k++) {
      var v = 0;
      for (var b = 0; b < CimbarSpec.bitsPerCell; b++) {
        final byte = bitPos >> 3;
        final bit = 7 - (bitPos & 7);
        final d = byte < raw.length ? (raw[byte] >> bit) & 1 : 0;
        v = (v << 1) | d;
        bitPos++;
      }
      out[k] = v;
    }
    return out;
  }

  /// cells: 3840 values 0..63. Returns 2880 raw bytes.
  static Uint8List unpackCells(Uint8List cells) {
    final raw = Uint8List(CimbarSpec.rawBytesPerFrame);
    var bitPos = 0;
    for (var k = 0; k < cells.length; k++) {
      for (var b = CimbarSpec.bitsPerCell - 1; b >= 0; b--) {
        if ((cells[k] >> b) & 1 == 1) {
          raw[bitPos >> 3] |= 1 << (7 - (bitPos & 7));
        }
        bitPos++;
      }
    }
    return raw;
  }
}
