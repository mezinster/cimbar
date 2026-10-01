import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/rs_framing.dart';
import '../services/reed_solomon.dart';

/// Frame data -> RS-encoded interleaved raw bytes -> 3840 cell values.
class CellGrid {
  CellGrid._();

  static final ReedSolomon _rs = ReedSolomon(CimbarSpec.rsEccBytes);

  static Uint8List raw(Uint8List frameData) => RsFraming.encodeFrame(frameData, _rs);

  static Uint8List cells(Uint8List frameData) => BitPacking.packCells(raw(frameData));
}
