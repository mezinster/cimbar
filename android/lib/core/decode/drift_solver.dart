import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'cell_classifier.dart';
import 'cell_sampler.dart';

/// Per-cell drift in source pixels, indexed row*64 + col.
///
/// [meanAbs]/[maxAbs] are the mean and max of `(|dx| + |dy|) / 2` per cell,
/// not vector magnitudes.
class DriftField {
  final Float32List dx = Float32List(CimbarSpec.gridCells * CimbarSpec.gridCells);
  final Float32List dy = Float32List(CimbarSpec.gridCells * CimbarSpec.gridCells);
  int widened = 0;
  double meanAbs = 0;
  double maxAbs = 0;
}

/// Flood-fill drift solver (spec §6.5): BFS from the cells adjacent to the four
/// finder corners; each cell starts from the mean drift of its visited
/// neighbours, tries the 3x3 offsets at ±1 px (luma-only sampling, symbol-only
/// Hamming), widens to the ±2 ring when the best Hamming exceeds
/// [wideThreshold], and clamps to ±[clampPx]. Seed cells (no decided
/// neighbours) always evaluate the ±2 ring as well, since they have no prior.
///
/// Seed cells (nn == 0) always search the ±2 ring but are not counted in
/// [DriftField.widened], which counts poor-match widenings only.
class DriftSolver {
  final CellSampler sampler;
  final CellClassifier classifier;
  final int wideThreshold;
  final double clampPx;

  DriftSolver(this.sampler, this.classifier, {this.wideThreshold = 20, this.clampPx = 6});

  static const List<(int, int)> _near = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
  static const List<(int, int)> _ring2 = [
    (-2, -2), (-1, -2), (0, -2), (1, -2), (2, -2),
    (-2, -1), (2, -1),
    (-2, 0), (2, 0),
    (-2, 1), (2, 1),
    (-2, 2), (-1, 2), (0, 2), (1, 2), (2, 2),
  ];
  static const List<(int, int)> _seeds = [(8, 0), (0, 8), (55, 0), (63, 8), (0, 55), (8, 63), (63, 55), (55, 63)];

  DriftField solve() {
    const n = CimbarSpec.gridCells;
    final field = DriftField();
    final visited = Uint8List(n * n);
    final queue = <int>[];
    var head = 0;
    for (final (c, r) in _seeds) {
      final k = r * n + c;
      if (visited[k] == 0) {
        visited[k] = 1;
        queue.add(k);
      }
    }
    final luma = Float32List(64);
    var sumAbs = 0.0;
    var count = 0;
    while (head < queue.length) {
      final k = queue[head++];
      final col = k % n, row = k ~/ n;
      // initial drift = mean of decided 4-neighbours
      var ix = 0.0, iy = 0.0, nn = 0;
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final c2 = col + dc, r2 = row + dr;
        if (c2 < 0 || c2 >= n || r2 < 0 || r2 >= n) continue;
        final k2 = r2 * n + c2;
        if (visited[k2] == 2) {
          ix += field.dx[k2];
          iy += field.dy[k2];
          nn++;
        }
      }
      if (nn > 0) {
        ix /= nn;
        iy /= nn;
      }
      // Hill-climb over the 3x3 neighbourhood: re-center on the best offset
      // until the center wins (bounded by the clamp), so a 2 px error is
      // reached in two steps rather than stalling one pixel short.
      var bestX = ix, bestY = iy;
      sampler.sampleLuma(col, row, luma, dx: bestX, dy: bestY);
      var bestH = classifier.bestSymbol(luma).$2;
      // max 3 steps; measured drift <= 2.1 px
      for (var iter = 0; iter < 3; iter++) {
        var moved = false;
        final cx = bestX, cy = bestY;
        for (final (ox, oy) in _near) {
          if (ox == 0 && oy == 0) continue;
          final tx = cx + ox, ty = cy + oy;
          if (tx.abs() > clampPx || ty.abs() > clampPx) continue;
          sampler.sampleLuma(col, row, luma, dx: tx, dy: ty);
          final h = classifier.bestSymbol(luma).$2;
          if (h < bestH) {
            bestH = h;
            bestX = tx;
            bestY = ty;
            moved = true;
          }
        }
        if (!moved) break;
      }
      final needWide = bestH > wideThreshold;
      if (needWide || nn == 0) {
        if (needWide) field.widened++;
        final cx = bestX, cy = bestY;
        for (final (ox, oy) in _ring2) {
          final tx = cx + ox, ty = cy + oy;
          if (tx.abs() > clampPx || ty.abs() > clampPx) continue;
          sampler.sampleLuma(col, row, luma, dx: tx, dy: ty);
          final h = classifier.bestSymbol(luma).$2;
          if (h < bestH) {
            bestH = h;
            bestX = tx;
            bestY = ty;
          }
        }
      }
      bestX = bestX.clamp(-clampPx, clampPx);
      bestY = bestY.clamp(-clampPx, clampPx);
      field.dx[k] = bestX;
      field.dy[k] = bestY;
      visited[k] = 2;
      final a = (bestX.abs() + bestY.abs()) / 2;
      sumAbs += a;
      if (a > field.maxAbs) field.maxAbs = a;
      count++;
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final c2 = col + dc, r2 = row + dr;
        if (c2 < 0 || c2 >= n || r2 < 0 || r2 >= n) continue;
        if (CimbarSpec.isReservedCell(c2, r2)) continue;
        final k2 = r2 * n + c2;
        if (visited[k2] == 0) {
          visited[k2] = 1;
          queue.add(k2);
        }
      }
    }
    field.meanAbs = count == 0 ? 0 : sumAbs / count;
    return field;
  }
}
