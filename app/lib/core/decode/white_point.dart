import 'dart:typed_data';
import 'grid_model.dart';
import 'rgb_buffer.dart';

/// White reference from the four finder cores (spec §6.3): per-channel 90th
/// percentile over the eight core cells around each core's center cell,
/// five samples per cell, through the grid model. Null when too dark.
class WhitePoint {
  WhitePoint._();

  static const double minChannel = 30;

  static List<double>? fromFinders(RgbBuffer image, GridModel grid) {
    const corners = [(0, 0), (56, 0), (0, 56), (56, 56)];
    const offsets = [(0.5, 0.5), (0.25, 0.5), (0.75, 0.5), (0.5, 0.25), (0.5, 0.75)];
    final r = <double>[], g = <double>[], b = <double>[];
    final tmp = Float32List(3);
    for (final (ox, oy) in corners) {
      for (var cy = 2; cy <= 4; cy++) {
        for (var cx = 2; cx <= 4; cx++) {
          if (cx == 3 && cy == 3) continue; // dot cell on tr/bl/br
          for (final (fx, fy) in offsets) {
            final (sx, sy) = grid.toSource(ox + cx + fx, oy + cy + fy);
            image.bilinear(sx, sy, tmp, 0);
            r.add(tmp[0]);
            g.add(tmp[1]);
            b.add(tmp[2]);
          }
        }
      }
    }
    final wp = [_p90(r), _p90(g), _p90(b)];
    if (wp.any((v) => v < minChannel)) return null;
    return wp;
  }

  static double _p90(List<double> v) {
    v.sort();
    return v[((v.length - 1) * 0.9).round()];
  }
}
