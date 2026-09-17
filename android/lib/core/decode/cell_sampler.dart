import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'grid_model.dart';
import 'rgb_buffer.dart';

/// One sampled 8x8 tile: luma[64] and rgb[192], row-major.
class CellPatch {
  final Float32List luma = Float32List(64);
  final Float32List rgb = Float32List(192);
}

/// Samples the 64 tile pixels of a cell through a GridModel, bilinear,
/// at the source resolution. dx/dy shift the sample position in source pixels.
class CellSampler {
  final RgbBuffer image;
  final GridModel grid;
  CellSampler(this.image, this.grid);

  void sample(int col, int row, CellPatch out, {double dx = 0, double dy = 0}) {
    const pitch = CimbarSpec.pitchPx;
    for (var j = 0; j < 8; j++) {
      for (var i = 0; i < 8; i++) {
        final (sx, sy) = grid.toSource(col + (i + 0.5) / pitch, row + (j + 0.5) / pitch);
        final p = j * 8 + i;
        image.bilinear(sx + dx, sy + dy, out.rgb, p * 3);
        out.luma[p] = 0.299 * out.rgb[p * 3] + 0.587 * out.rgb[p * 3 + 1] + 0.114 * out.rgb[p * 3 + 2];
      }
    }
  }
}
