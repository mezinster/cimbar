import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'grid_model.dart';
import 'luma_plane.dart';
import 'rgb_buffer.dart';

/// One sampled 8x8 tile: luma[64] and rgb[192], row-major.
class CellPatch {
  final Float32List luma = Float32List(64);
  final Float32List rgb = Float32List(192);
}

/// Samples the 64 tile pixels of a cell through a GridModel, bilinear, at the
/// source resolution. dx/dy shift the sample position in source pixels.
/// When a [luma] plane is given, [sampleLuma] reads it (one channel, ~3x
/// cheaper than RGB) — the drift search's hot path.
class CellSampler {
  final RgbBuffer image;
  final GridModel grid;
  final LumaPlane? luma;
  final Float32List _tmp = Float32List(3);
  final Float64List _corners = Float64List(8); // x00,y00,x10,y10,x01,y01,x11,y11

  CellSampler(this.image, this.grid, {this.luma});

  /// Corners of the cell's tile region in source pixels, computed once per
  /// cell: (col,row), (col+t,row), (col,row+t), (col+t,row+t) where t is the
  /// tile extent in cell units (8/9). The 64 sample positions are then
  /// bilinearly interpolated between these four corners — exact for affine
  /// grid models, and the projective error over a 9 px cell is far below the
  /// 0.5 px bilinear sampling resolution.
  void _cellCorners(int col, int row) {
    const t = CimbarSpec.cellPx / CimbarSpec.pitchPx; // tile extent in cell units (8/9)
    final (x00, y00) = grid.toSource(col.toDouble(), row.toDouble());
    final (x10, y10) = grid.toSource(col + t, row.toDouble());
    final (x01, y01) = grid.toSource(col.toDouble(), row + t);
    final (x11, y11) = grid.toSource(col + t, row + t);
    _corners[0] = x00;
    _corners[1] = y00;
    _corners[2] = x10;
    _corners[3] = y10;
    _corners[4] = x01;
    _corners[5] = y01;
    _corners[6] = x11;
    _corners[7] = y11;
  }

  void sample(int col, int row, CellPatch out, {double dx = 0, double dy = 0}) {
    _cellCorners(col, row);
    for (var j = 0; j < 8; j++) {
      final v = (j + 0.5) / 8;
      for (var i = 0; i < 8; i++) {
        final u = (i + 0.5) / 8;
        final w00 = (1 - u) * (1 - v), w10 = u * (1 - v), w01 = (1 - u) * v, w11 = u * v;
        final sx = w00 * _corners[0] + w10 * _corners[2] + w01 * _corners[4] + w11 * _corners[6] + dx;
        final sy = w00 * _corners[1] + w10 * _corners[3] + w01 * _corners[5] + w11 * _corners[7] + dy;
        final p = j * 8 + i;
        image.bilinear(sx, sy, out.rgb, p * 3);
        out.luma[p] = 0.299 * out.rgb[p * 3] + 0.587 * out.rgb[p * 3 + 1] + 0.114 * out.rgb[p * 3 + 2];
      }
    }
  }

  /// Luma-only sample of the 64 tile pixels into out[0..63].
  void sampleLuma(int col, int row, Float32List out, {double dx = 0, double dy = 0}) {
    _cellCorners(col, row);
    final lp = luma;
    for (var j = 0; j < 8; j++) {
      final v = (j + 0.5) / 8;
      for (var i = 0; i < 8; i++) {
        final u = (i + 0.5) / 8;
        final w00 = (1 - u) * (1 - v), w10 = u * (1 - v), w01 = (1 - u) * v, w11 = u * v;
        final sx = w00 * _corners[0] + w10 * _corners[2] + w01 * _corners[4] + w11 * _corners[6] + dx;
        final sy = w00 * _corners[1] + w10 * _corners[3] + w01 * _corners[5] + w11 * _corners[7] + dy;
        final p = j * 8 + i;
        if (lp != null) {
          out[p] = lp.bilinear(sx, sy);
        } else {
          image.bilinear(sx, sy, _tmp, 0);
          out[p] = 0.299 * _tmp[0] + 0.587 * _tmp[1] + 0.114 * _tmp[2];
        }
      }
    }
  }
}
