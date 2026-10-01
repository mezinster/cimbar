import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/tiles.dart';

/// Cells → 608×608 palette indices, pixel-identical to renderFrame in
/// web-app/cimbar.js: black background (quiet zone and gaps included), tile
/// "on" pixels in the cell's palette color, then the four finders on top.
/// Index 0–3 = CimbarSpec.palette, 4 = black, 5 = white — the slot order of
/// gif-encoder.js's palette, so indices go into the GIF unchanged.
class FrameRaster {
  FrameRaster._();

  static const int black = 4;
  static const int white = 5;
  static const int _size = CimbarSpec.framePx;

  static void _fill(Uint8List px, int x, int y, int w, int h, int v) {
    for (var yy = y; yy < y + h; yy++) {
      px.fillRange(yy * _size + x, yy * _size + x + w, v);
    }
  }

  static Uint8List render(Uint8List cells) {
    final px = Uint8List(_size * _size)..fillRange(0, _size * _size, black);
    final pos = CimbarSpec.usableCellPositions;
    for (var k = 0; k < pos.length; k++) {
      final ox = CimbarSpec.cellOriginX(pos[k].col);
      final oy = CimbarSpec.cellOriginY(pos[k].row);
      final t = Tiles.bits[BitPacking.cellSymbol(cells[k])];
      final c = BitPacking.cellColor(cells[k]);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          if (t[y * 8 + x] != 0) px[(oy + y) * _size + ox + x] = c;
        }
      }
    }
    for (final corner in const ['tl', 'tr', 'bl', 'br']) {
      final c = CimbarSpec.finderCenters[corner]!;
      // Math.round in JS; the values are exact integers for this spec
      // (16 + 3.5·9 − 31.5 = 16, 16 + 60.5·9 − 31.5 = 529), floor(x + 0.5) matches either way.
      final ox = (CimbarSpec.quietPx + c[0] * CimbarSpec.pitchPx - CimbarSpec.finderOuterPx / 2 + 0.5).floor();
      final oy = (CimbarSpec.quietPx + c[1] * CimbarSpec.pitchPx - CimbarSpec.finderOuterPx / 2 + 0.5).floor();
      const o = CimbarSpec.finderOuterPx, ri = CimbarSpec.finderRingInsetPx;
      _fill(px, ox, oy, o, o, white);
      _fill(px, ox + ri, oy + ri, o - 2 * ri, o - 2 * ri, black);
      _fill(px, ox + CimbarSpec.finderCoreInsetPx, oy + CimbarSpec.finderCoreInsetPx,
          CimbarSpec.finderCorePx, CimbarSpec.finderCorePx, white);
      if (CimbarSpec.finderDotOn.contains(corner)) {
        _fill(px, ox + CimbarSpec.finderDotInsetPx, oy + CimbarSpec.finderDotInsetPx,
            CimbarSpec.finderDotPx, CimbarSpec.finderDotPx, black);
      }
    }
    return px;
  }

  static List<int> _rgbOf(int i) => i < 4
      ? CimbarSpec.palette[i]
      : (i == white ? const [255, 255, 255] : const [0, 0, 0]);

  static Uint8List toRgb(Uint8List indices) {
    final out = Uint8List(indices.length * 3);
    for (var i = 0; i < indices.length; i++) {
      final c = _rgbOf(indices[i]);
      out[i * 3] = c[0]; out[i * 3 + 1] = c[1]; out[i * 3 + 2] = c[2];
    }
    return out;
  }

  static Uint8List toRgba(Uint8List indices) {
    final out = Uint8List(indices.length * 4);
    for (var i = 0; i < indices.length; i++) {
      final c = _rgbOf(indices[i]);
      out[i * 4] = c[0]; out[i * 4 + 1] = c[1]; out[i * 4 + 2] = c[2]; out[i * 4 + 3] = 255;
    }
    return out;
  }
}
