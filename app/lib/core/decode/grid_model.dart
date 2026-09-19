import '../format/cimbar_spec.dart';

/// Maps cell-unit coordinates to source-image pixel coordinates.
/// One cell unit is one pitch (9 px); the grid origin is cell (0, 0)'s
/// top-left corner; finder centers are at (3.5, 3.5), (60.5, 3.5), ...
abstract class GridModel {
  const GridModel();
  (double, double) toSource(double cx, double cy);
}

/// Identity model for frames whose pixels are at exact spec positions (GIF path).
class ExactGridModel extends GridModel {
  const ExactGridModel();

  @override
  (double, double) toSource(double cx, double cy) => (
        CimbarSpec.quietPx + cx * CimbarSpec.pitchPx,
        CimbarSpec.quietPx + cy * CimbarSpec.pitchPx,
      );
}
