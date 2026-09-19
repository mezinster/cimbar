import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/bit_packing.dart';

void main() {
  test('cellValue/cellSymbol/cellColor', () {
    expect(BitPacking.cellValue(15, 3), 63);
    expect(BitPacking.cellValue(9, 2), (9 << 2) | 2);
    expect(BitPacking.cellSymbol(BitPacking.cellValue(9, 2)), 9);
    expect(BitPacking.cellColor(BitPacking.cellValue(9, 2)), 2);
  });

  test('packCells/unpackCells round trip, MSB-first', () {
    final raw = Uint8List(2880);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = (i * 37 + 11) & 0xFF;
    }
    final cells = BitPacking.packCells(raw);
    expect(cells.length, 3840);
    expect(cells[0], raw[0] >> 2);
    expect(cells[1], ((raw[0] & 3) << 4) | (raw[1] >> 4));
    for (final v in cells) {
      expect(v >= 0 && v < 64, isTrue);
    }
    final back = BitPacking.unpackCells(cells);
    expect(back, raw);
  });
}
