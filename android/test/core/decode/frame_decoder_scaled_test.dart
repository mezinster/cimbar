// Non-exact grid test (Plan 3 readiness): FrameDecoder.decodeWithGrid must
// work through any GridModel, not just ExactGridModel — this pins that the
// cell sampler's bilinear source lookup is resolution-independent, ahead of
// Plan 3's located (camera) grid model.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

String repoPath(String rel) => '../$rel';

/// Grid model for a uniformly-scaled and offset copy of the exact 608x608
/// frame: cell-unit (cx, cy) maps to the same point ExactGridModel would use,
/// then scaled and offset into the resampled buffer's coordinate space.
class AffineGridModel extends GridModel {
  final double scale;
  final double offsetX, offsetY;
  const AffineGridModel(this.scale, this.offsetX, this.offsetY);

  @override
  (double, double) toSource(double cx, double cy) => (
        offsetX + (CimbarSpec.quietPx + cx * CimbarSpec.pitchPx) * scale,
        offsetY + (CimbarSpec.quietPx + cy * CimbarSpec.pitchPx) * scale,
      );
}

/// Nearest-neighbour resample of [src] to a [newSize] x [newSize] square,
/// where destination pixel (x, y) reads source pixel (x/scale, y/scale)
/// (floor) — matching the coordinate mapping [AffineGridModel] assumes.
RgbBuffer resample(RgbBuffer src, double scale, int newSize) {
  final out = Uint8List(newSize * newSize * 3);
  for (var y = 0; y < newSize; y++) {
    var sy = (y / scale).floor();
    if (sy >= src.height) sy = src.height - 1;
    if (sy < 0) sy = 0;
    for (var x = 0; x < newSize; x++) {
      var sx = (x / scale).floor();
      if (sx >= src.width) sx = src.width - 1;
      if (sx < 0) sx = 0;
      final si = (sy * src.width + sx) * 3;
      final di = (y * newSize + x) * 3;
      out[di] = src.rgb[si];
      out[di + 1] = src.rgb[si + 1];
      out[di + 2] = src.rgb[si + 2];
    }
  }
  return RgbBuffer(newSize, newSize, out);
}

void main() {
  final jsonPath = repoPath('test-data/goldens/hello.json');
  final golden = GoldenSidecar.load(jsonPath);
  final frame0 = GifParser.parseFrames(File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync()).first;
  final src = RgbBuffer.fromImage(frame0);

  test('2x nearest-neighbour scaled frame decodes ok through AffineGridModel', () {
    final buf2x = resample(src, 2, 1216);
    final r = FrameDecoder().decodeWithGrid(buf2x, const AffineGridModel(2, 0, 0));
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.diag.hammingMax, 0);
    expect(r.cells, golden.frames[0].cells);
    expect(r.diag.rsOk, 12);
  });

  test('3x nearest-neighbour scaled frame decodes ok through AffineGridModel', () {
    final buf3x = resample(src, 3, 1824);
    final r = FrameDecoder().decodeWithGrid(buf3x, const AffineGridModel(3, 0, 0));
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.diag.hammingMax, 0);
    expect(r.cells, golden.frames[0].cells);
    expect(r.diag.rsOk, 12);
  });

  // Brief called for 0.75x (456px, 6 px/cell), but that is still >= the spec
  // §11 "≥5 camera px per cell" floor and decodes cleanly (verified: status
  // ok, hammingMax 22, rsOk 12) — so it does not exercise the documented
  // limit. 0.5x (304px, 4 px/cell) is unambiguously below the floor and
  // reliably fails (status rsFailed, rsOk 0/12 across repeated runs), so it
  // is used here instead. See final-fix-report.md for the measurements
  // across the intermediate scales (0.6–0.7x flip status non-monotonically,
  // underscoring that this is a soft, aliasing-dependent limit, not a hard
  // cliff at exactly 5 px/cell).
  test('0.5x downscaled frame is below the spec §11 px/cell floor and does not decode', () {
    final buf05 = resample(src, 0.5, 304);
    final r = FrameDecoder().decodeWithGrid(buf05, const AffineGridModel(0.5, 0, 0));
    expect(r.status, isNot(DecodeStatus.ok));
  });
}
