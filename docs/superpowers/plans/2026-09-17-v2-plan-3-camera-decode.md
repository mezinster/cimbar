# CimBar v2 — Plan 3: Camera Decode Stages (Locator, Homography Grid, White Point, Drift) and Synthetic Degradation Harness

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `FrameDecoder.decode(image)` decode a v2 barcode from an arbitrary RGB image: find the four finders, fit a homography grid model, white-balance from the finder cores, solve per-cell drift, and prove it on synthetic degradations (scale, rotation, perspective, blur, brightness, noise, lens barrel, real photo backgrounds) rendered from the golden GIFs.

**Architecture:** Everything is pure Dart under `lib/core/decode/`, behind the `FrameDecoder.decode(image, {grid})` seam Plan 2 left. New units: `LumaPlane` (8-bit luma, 2× downscale, bilinear), `FinderLocator` (1:1:3:1:1 run-length scanning on a locally-binarized downscaled luma plane, clustering, parallelogram selection, brightness-based TL classification), `Homography`/`HomographyGridModel` (DLT from four finder centers to spec cell coordinates), `WhitePoint` (90th-percentile RGB over the finder cores through the grid model), `DriftSolver` (BFS from the corners, luma-only 9/25-position Hamming search per cell, clamp ±6 px). `CellSampler` gains a luma-only path and `CellClassifier` a symbol-only path so the drift search is cheap. A test utility renders golden frames into synthetic scenes through a homography with optional barrel distortion, blur, brightness, noise and a real-photo background, and reports where the finder centers landed. No Flutter imports; the CLI's `--mode camera` becomes real.

**Tech Stack:** Dart 3, `image` ^4.2 for file decode only, existing `reed_solomon.dart`. Tests via `flutter test` wrapped by `android/tests/run_all.sh`.

**Spec:** `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` — §6.2 (locate), §6.3 (grid model, white point, grid-size derivation §3.2), §6.4 (sampling), §6.5 (drift), §6.8 (diagnostics), §9.4 rows "Synthetic degradations of goldens" and "Locator on goldens composited onto real photo backgrounds", §11 risks. Camera acquisition (§8) is Plan 4.

## Global Constraints

- All new code under `android/lib/core/decode/` and `android/test/test_utils/` imports only `dart:*`, `package:image` (file decode in tests only) and `lib/core/`. **No `package:flutter`**; `dart run tool/decode_image.dart` must keep working.
- Coordinates: `RgbBuffer`/`LumaPlane` use continuous coordinates where pixel `k` covers `[k, k+1)` and its center is `k + 0.5`. Grid models map cell units (one unit = one 9 px pitch, origin at cell (0,0)'s top-left) to source pixels; finder centers are at cell coords (3.5, 3.5), (60.5, 3.5), (3.5, 60.5), (60.5, 60.5), i.e. frame pixels (47.5, 47.5), (560.5, 47.5), (47.5, 560.5), (560.5, 560.5).
- Locator (spec §6.2): downscale 2× by area average; run pattern light:dark:light(3):dark:light, or its 7-run 1:1:1:1:1:1:1 form when the core dot splits the middle run, with every run within 50 % of the module estimate (total ÷ 7); vertical confirmation at the center column of each row hit; run-length modules corrected by cos of the grid rotation folded into ±45°; clustering within one module; four corners chosen by minimum parallelogram closure error `devNorm = |(P+Q) − (R+S)| / meanSide` ≤ 0.35 (v1 validated 30% linear; the spec's 0.09 was that value squared) with all four modules within 2× of each other; TL = brightest full-res 3×3 core center, exceeding every other by ≥ 40 luma; TR/BL by the sign of `(BR−TL) × (P−TL)` (negative → TR, positive → BL in image coordinates with y down).
- Grid size (§3.2): `estimate = round(meanCenterDistance / module) + 7`; accept only `|estimate − 64| ≤ 6`, else `unsupportedGrid`.
- White point (§6.3): per-channel 90th percentile over the four finder cores (the eight core cells around the dot cell, sampled at five points each), applied via `CellClassifier.classify(whitePoint:)`; if any channel < 30, no white balance.
- Drift (§6.5): BFS from the cells adjacent to the four corners; initial drift = mean of visited 4-neighbours; 9 positions (initial + 8 neighbours at ±1 px); widen to the ±2 ring (16 more positions) when the best Hamming > 20; clamp to ±6 px; luma-only sampling and symbol-only classification during the search; final classification samples RGB at the winning offset.
- Status rules unchanged from Plan 2 (`notLocated`, `unsupportedGrid`, `rsFailed`, `badHeader`, `ok`).
- Tests run from `android/`: `sh tests/run_all.sh` (never bare `flutter test`); single files with `flutter test <path>`. Goldens at `../test-data/goldens/`; v1 photos at `test/fixtures/camera_raw_1280x720_{a,b}.png`. `flutter analyze lib/core tool test/core test/test_utils` must add no issues (pre-existing issues live only in legacy v1/UI files). Lints: prefer_const_constructors, prefer_const_declarations, avoid_print, prefer_single_quotes.
- Commit after every task; message ends with the two lines:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi`

---

## File map

| Path (under `android/`) | Responsibility |
|---|---|
| `lib/core/decode/luma_plane.dart` | 8-bit luma from RGB, 2× area downscale, bilinear, 3×3 mean |
| `lib/core/decode/cell_sampler.dart` | + optional `LumaPlane`, `sampleLuma()` |
| `lib/core/decode/cell_classifier.dart` | + `bestSymbol(luma)` symbol-only path |
| `lib/core/decode/homography.dart` | `Homography.solve/map`, `HomographyGridModel.fromFinders` |
| `lib/core/decode/finder_locator.dart` | `FinderLocator.locate(LumaPlane) → LocateResult` |
| `lib/core/decode/white_point.dart` | `WhitePoint.fromFinders(image, grid)` |
| `lib/core/decode/drift_solver.dart` | `DriftSolver.solve() → DriftField` |
| `lib/core/decode/diagnostics.dart` | + locate/grid/wb/drift fields and keys |
| `lib/core/decode/decode_report.dart` | + `stage=locate/grid/wb/drift` lines |
| `lib/core/decode/frame_decoder.dart` | `decode()` camera path; `decodeWithGrid(..., useDrift, luma, diag)` |
| `tool/decode_image.dart` | `--mode camera` real; `--no-drift` |
| `test/test_utils/synthetic_scene.dart` | Golden frame → synthetic scene renderer with ground-truth finder centers |
| `test/core/decode/*_test.dart` | Per-unit tests + synthetic camera-path suites |
| `android/CLAUDE.md`, `CLAUDE.md`, `CHANGELOG.md` | Docs |

Dependency order: T1 and T2 are independent; T3 needs T2; T4 needs T1 and T3; T5 needs T4; T6 needs T5; T7 needs T6.

Helper used by tests (define in each test file that needs it): `String repoPath(String rel) => '../$rel';`

---

### Task 1: LumaPlane, luma-only sampling, symbol-only classification

**Files:**
- Create: `lib/core/decode/luma_plane.dart`
- Modify: `lib/core/decode/cell_sampler.dart` (replace file), `lib/core/decode/cell_classifier.dart` (replace file)
- Test: `test/core/decode/luma_plane_test.dart`

**Interfaces:**
- `LumaPlane(width, height, luma: Uint8List)`, `factory LumaPlane.fromRgb(RgbBuffer)`, `int at(x, y)`, `LumaPlane downscale2()`, `double bilinear(double x, double y)`, `double mean3x3(int cx, int cy)`.
- `CellSampler(RgbBuffer image, GridModel grid, {LumaPlane? luma})`; `sample(col, row, CellPatch out, {dx, dy})` unchanged; new `sampleLuma(col, row, Float32List out64, {dx, dy})` (uses the luma plane when given, else RGB).
- `CellClassifier.bestSymbol(Float32List luma) → (int symbol, int hamming)`; `classify` unchanged in behaviour.

- [ ] **Step 1: Write the failing test**

`test/core/decode/luma_plane_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/cell_classifier.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/tiles.dart';

void main() {
  test('fromRgb uses BT.601 integer weights', () {
    final buf = RgbBuffer(3, 1, Uint8List.fromList([255, 255, 255, 0, 0, 0, 0, 255, 0]));
    final l = LumaPlane.fromRgb(buf);
    expect(l.width, 3);
    expect(l.at(0, 0), 255);
    expect(l.at(1, 0), 0);
    expect(l.at(2, 0), (150 * 255) >> 8);
  });

  test('downscale2 averages 2x2 blocks and floors odd sizes', () {
    final l = LumaPlane(5, 2, Uint8List.fromList([0, 100, 200, 200, 9, 0, 100, 200, 200, 9]));
    final d = l.downscale2();
    expect(d.width, 2);
    expect(d.height, 1);
    expect(d.at(0, 0), 50);
    expect(d.at(1, 0), 200);
  });

  test('bilinear is exact at centers and clamps at edges', () {
    final l = LumaPlane(2, 1, Uint8List.fromList([0, 200]));
    expect(l.bilinear(1.5, 0.5), 200);
    expect(l.bilinear(1.0, 0.5), closeTo(100, 1e-6));
    expect(l.bilinear(-5, -5), 0);
    expect(l.bilinear(50, 50), 200);
  });

  test('mean3x3 clamps at the corner', () {
    final l = LumaPlane(2, 2, Uint8List.fromList([10, 20, 30, 40]));
    expect(l.mean3x3(0, 0), closeTo((10 * 4 + 20 * 2 + 30 * 2 + 40) / 9, 1e-6));
  });

  test('sampleLuma through a LumaPlane matches the RGB path and bestSymbol is exact', () {
    final im = img.Image(width: CimbarSpec.framePx, height: CimbarSpec.framePx);
    final t = Tiles.bits[11];
    final ox = CimbarSpec.cellOriginX(8), oy = CimbarSpec.cellOriginY(0);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (t[y * 8 + x] == 1) im.setPixelRgb(ox + x, oy + y, 0, 255, 255);
      }
    }
    final rgb = RgbBuffer.fromImage(im);
    final luma = LumaPlane.fromRgb(rgb);
    final viaLuma = CellSampler(rgb, const ExactGridModel(), luma: luma);
    final viaRgb = CellSampler(rgb, const ExactGridModel());
    final a = Float32List(64), b = Float32List(64);
    viaLuma.sampleLuma(8, 0, a);
    viaRgb.sampleLuma(8, 0, b);
    for (var p = 0; p < 64; p++) {
      expect((a[p] > 100), t[p] == 1, reason: 'luma path pixel $p');
      expect((a[p] - b[p]).abs() < 2, isTrue, reason: 'paths agree within rounding at $p');
    }
    final (sym, ham) = CellClassifier().bestSymbol(a);
    expect(sym, 11);
    expect(ham, 0);
    // shifting by one pixel must raise the distance (drift search relies on this)
    viaLuma.sampleLuma(8, 0, a, dx: 1);
    final (_, ham2) = CellClassifier().bestSymbol(a);
    expect(ham2 > 0, isTrue, reason: 'shifted hamming $ham2');
  });
}
```

- [ ] **Step 2: Run to verify failure** — `cd android && flutter test test/core/decode/luma_plane_test.dart 2>&1 | tail -3` → compile errors.

- [ ] **Step 3: Write luma_plane.dart**

```dart
import 'dart:typed_data';

import 'rgb_buffer.dart';

/// 8-bit luma plane. Same continuous-coordinate convention as RgbBuffer:
/// pixel k covers [k, k+1), center at k + 0.5.
class LumaPlane {
  final int width;
  final int height;
  final Uint8List luma;

  LumaPlane(this.width, this.height, this.luma) {
    if (luma.length != width * height) {
      throw ArgumentError('luma length ${luma.length} != $width*$height');
    }
  }

  /// BT.601 with integer weights (77, 150, 29) / 256.
  factory LumaPlane.fromRgb(RgbBuffer rgb) {
    final out = Uint8List(rgb.width * rgb.height);
    final s = rgb.rgb;
    var j = 0;
    for (var i = 0; i < out.length; i++) {
      out[i] = (77 * s[j] + 150 * s[j + 1] + 29 * s[j + 2]) >> 8;
      j += 3;
    }
    return LumaPlane(rgb.width, rgb.height, out);
  }

  int at(int x, int y) => luma[y * width + x];

  /// Area-average 2x downscale (odd trailing row/column dropped).
  LumaPlane downscale2() {
    final w = width ~/ 2, h = height ~/ 2;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final r0 = (2 * y) * width, r1 = r0 + width;
      for (var x = 0; x < w; x++) {
        final x0 = 2 * x;
        out[y * w + x] = (luma[r0 + x0] + luma[r0 + x0 + 1] + luma[r1 + x0] + luma[r1 + x0 + 1]) >> 2;
      }
    }
    return LumaPlane(w, h, out);
  }

  double bilinear(double x, double y) {
    final fx = x - 0.5, fy = y - 0.5;
    var x0 = fx.floor(), y0 = fy.floor();
    final tx = fx - x0, ty = fy - y0;
    var x1 = x0 + 1, y1 = y0 + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x0 >= width) x0 = width - 1;
    if (x1 >= width) x1 = width - 1;
    if (y0 >= height) y0 = height - 1;
    if (y1 >= height) y1 = height - 1;
    final a = luma[y0 * width + x0], b = luma[y0 * width + x1];
    final c = luma[y1 * width + x0], d = luma[y1 * width + x1];
    return a * (1 - tx) * (1 - ty) + b * tx * (1 - ty) + c * (1 - tx) * ty + d * tx * ty;
  }

  /// Mean of the 3x3 neighbourhood around integer pixel (cx, cy), clamped.
  double mean3x3(int cx, int cy) {
    var sum = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = (cx + dx).clamp(0, width - 1), y = (cy + dy).clamp(0, height - 1);
        sum += luma[y * width + x];
      }
    }
    return sum / 9;
  }
}
```

- [ ] **Step 4: Replace cell_sampler.dart**

```dart
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

  CellSampler(this.image, this.grid, {this.luma});

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

  /// Luma-only sample of the 64 tile pixels into out[0..63].
  void sampleLuma(int col, int row, Float32List out, {double dx = 0, double dy = 0}) {
    const pitch = CimbarSpec.pitchPx;
    final lp = luma;
    for (var j = 0; j < 8; j++) {
      for (var i = 0; i < 8; i++) {
        final (sx, sy) = grid.toSource(col + (i + 0.5) / pitch, row + (j + 0.5) / pitch);
        final p = j * 8 + i;
        if (lp != null) {
          out[p] = lp.bilinear(sx + dx, sy + dy);
        } else {
          image.bilinear(sx + dx, sy + dy, _tmp, 0);
          out[p] = 0.299 * _tmp[0] + 0.587 * _tmp[1] + 0.114 * _tmp[2];
        }
      }
    }
  }
}
```

- [ ] **Step 5: Replace cell_classifier.dart**

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/tiles.dart';
import 'cell_sampler.dart';

class CellClassification {
  final int symbol;
  final int hamming;
  final int color;
  final double colorMargin;
  const CellClassification(this.symbol, this.hamming, this.color, this.colorMargin);
}

/// Symbol by average hash + Hamming distance to the 16 tiles; color by
/// brightness-normalized chroma over the winning tile's lit pixels (spec §6.6–6.7).
/// Note: colorMargin is in normalized-chroma units (palette entries are ≥1.41
/// apart), not RGB units like the JS exact path's diagnostic.
class CellClassifier {
  late final List<List<double>> _paletteChroma;

  CellClassifier() {
    _paletteChroma = [
      for (final c in CimbarSpec.palette) _chroma(c[0].toDouble(), c[1].toDouble(), c[2].toDouble()),
    ];
  }

  static List<double> _chroma(double r, double g, double b) {
    final m = math.max(1.0, math.max(r, math.max(g, b)));
    return [(r - g) / m, (g - b) / m, (b - r) / m];
  }

  /// Symbol-only classification of a 64-entry luma patch: (symbol, hamming).
  (int, int) bestSymbol(Float32List luma) {
    var mean = 0.0;
    for (var i = 0; i < 64; i++) {
      mean += luma[i];
    }
    mean /= 64;
    var bestSym = 0, bestDist = 65;
    for (var s = 0; s < 16; s++) {
      final t = Tiles.bits[s];
      var d = 0;
      for (var i = 0; i < 64; i++) {
        d += ((luma[i] > mean) ? 1 : 0) ^ t[i];
      }
      if (d < bestDist) {
        bestDist = d;
        bestSym = s;
      }
    }
    return (bestSym, bestDist);
  }

  CellClassification classify(CellPatch p, {List<double>? whitePoint}) {
    final (bestSym, bestDist) = bestSymbol(p.luma);
    final t = Tiles.bits[bestSym];
    var r = 0.0, g = 0.0, b = 0.0, n = 0;
    for (var i = 0; i < 64; i++) {
      if (t[i] == 1) {
        r += p.rgb[i * 3];
        g += p.rgb[i * 3 + 1];
        b += p.rgb[i * 3 + 2];
        n++;
      }
    }
    if (n > 0) {
      r /= n;
      g /= n;
      b /= n;
    }
    if (whitePoint != null) {
      r = r * 255 / math.max(1.0, whitePoint[0]);
      g = g * 255 / math.max(1.0, whitePoint[1]);
      b = b * 255 / math.max(1.0, whitePoint[2]);
    }
    final ch = _chroma(r, g, b);
    var bestC = 0;
    var bestD = double.infinity, secondD = double.infinity;
    for (var c = 0; c < _paletteChroma.length; c++) {
      final pc = _paletteChroma[c];
      final dd = (ch[0] - pc[0]) * (ch[0] - pc[0]) + (ch[1] - pc[1]) * (ch[1] - pc[1]) + (ch[2] - pc[2]) * (ch[2] - pc[2]);
      if (dd < bestD) {
        secondD = bestD;
        bestD = dd;
        bestC = c;
      } else if (dd < secondD) {
        secondD = dd;
      }
    }
    return CellClassification(bestSym, bestDist, bestC, math.sqrt(secondD) - math.sqrt(bestD));
  }
}
```

- [ ] **Step 6: Run tests and analyzer**

Run: `cd android && flutter test test/core/decode/ 2>&1 | tail -3` → all pass (the existing decode tests must still pass; `luma_plane_test.dart` adds 5).
Run: `cd android && flutter analyze lib/core/decode test/core/decode 2>&1 | tail -2` → `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add android/lib/core/decode/luma_plane.dart android/lib/core/decode/cell_sampler.dart android/lib/core/decode/cell_classifier.dart android/test/core/decode/luma_plane_test.dart
git commit -m "Add LumaPlane, luma-only cell sampling and symbol-only classification

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 2: Homography and HomographyGridModel

**Files:**
- Create: `lib/core/decode/homography.dart`
- Test: `test/core/decode/homography_test.dart`

**Interfaces:**
- `class Homography { final Float64List h /*9, h[8]=1*/; (double, double) map(double x, double y); static Homography? solve(List<(double, double)> from, List<(double, double)> to) }` — DLT from exactly four correspondences, Gaussian elimination with partial pivoting; null when singular.
- `class HomographyGridModel extends GridModel { final Homography h; static HomographyGridModel? fromFinders({required (double,double) tl, tr, bl, br}) }` — cell coords (3.5,3.5)/(60.5,3.5)/(3.5,60.5)/(60.5,60.5) → the given source points.

- [ ] **Step 1: Write the failing test**

`test/core/decode/homography_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';

void main() {
  const square = [(0.0, 0.0), (10.0, 0.0), (0.0, 10.0), (10.0, 10.0)];

  test('identity', () {
    final h = Homography.solve(square, square)!;
    final (x, y) = h.map(3.0, 7.0);
    expect(x, closeTo(3.0, 1e-9));
    expect(y, closeTo(7.0, 1e-9));
  });

  test('scale and translate', () {
    const to = [(100.0, 50.0), (120.0, 50.0), (100.0, 70.0), (120.0, 70.0)];
    final h = Homography.solve(square, to)!;
    final (x, y) = h.map(5.0, 5.0);
    expect(x, closeTo(110.0, 1e-9));
    expect(y, closeTo(60.0, 1e-9));
  });

  test('perspective quad maps corners exactly and inverse round-trips', () {
    const to = [(10.0, 20.0), (200.0, 5.0), (30.0, 180.0), (220.0, 210.0)];
    final h = Homography.solve(square, to)!;
    for (var i = 0; i < 4; i++) {
      final (x, y) = h.map(square[i].$1, square[i].$2);
      expect(x, closeTo(to[i].$1, 1e-6));
      expect(y, closeTo(to[i].$2, 1e-6));
    }
    final inv = Homography.solve(to, square)!;
    final (mx, my) = h.map(2.5, 8.0);
    final (bx, by) = inv.map(mx, my);
    expect(bx, closeTo(2.5, 1e-6));
    expect(by, closeTo(8.0, 1e-6));
  });

  test('fromFinders with exact frame finder centers reproduces ExactGridModel', () {
    final gm = HomographyGridModel.fromFinders(
      tl: (47.5, 47.5), tr: (560.5, 47.5), bl: (47.5, 560.5), br: (560.5, 560.5),
    )!;
    const exact = ExactGridModel();
    for (final (cx, cy) in [(0.0, 0.0), (32.0, 32.0), (8.5, 0.5), (63.9, 63.9)]) {
      final (ax, ay) = gm.toSource(cx, cy);
      final (ex, ey) = exact.toSource(cx, cy);
      expect(ax, closeTo(ex, 1e-6));
      expect(ay, closeTo(ey, 1e-6));
    }
  });
}
```

- [ ] **Step 2: Run to verify failure** — compile error.

- [ ] **Step 3: Write homography.dart**

```dart
import 'dart:typed_data';

import 'grid_model.dart';

/// 3x3 projective transform, row-major, h[8] == 1.
/// map(x, y) = ((h0 x + h1 y + h2) / w, (h3 x + h4 y + h5) / w), w = h6 x + h7 y + 1.
class Homography {
  final Float64List h;
  const Homography(this.h);

  (double, double) map(double x, double y) {
    final w = h[6] * x + h[7] * y + h[8];
    final iw = w.abs() < 1e-12 ? 0.0 : 1.0 / w;
    return ((h[0] * x + h[1] * y + h[2]) * iw, (h[3] * x + h[4] * y + h[5]) * iw);
  }

  /// Direct linear transform from four point correspondences. Null if singular.
  static Homography? solve(List<(double, double)> from, List<(double, double)> to) {
    if (from.length != 4 || to.length != 4) throw ArgumentError('need exactly 4 correspondences');
    final a = Float64List(64);
    final b = Float64List(8);
    for (var i = 0; i < 4; i++) {
      final (sx, sy) = from[i];
      final (dx, dy) = to[i];
      final r0 = i * 2, r1 = r0 + 1;
      a[r0 * 8 + 0] = sx;
      a[r0 * 8 + 1] = sy;
      a[r0 * 8 + 2] = 1;
      a[r0 * 8 + 6] = -sx * dx;
      a[r0 * 8 + 7] = -sy * dx;
      b[r0] = dx;
      a[r1 * 8 + 3] = sx;
      a[r1 * 8 + 4] = sy;
      a[r1 * 8 + 5] = 1;
      a[r1 * 8 + 6] = -sx * dy;
      a[r1 * 8 + 7] = -sy * dy;
      b[r1] = dy;
    }
    final x = _solve8(a, b);
    if (x == null) return null;
    final out = Float64List(9);
    for (var i = 0; i < 8; i++) {
      out[i] = x[i];
    }
    out[8] = 1.0;
    return Homography(out);
  }

  static Float64List? _solve8(Float64List a, Float64List b) {
    const n = 8;
    final m = Float64List.fromList(a);
    final r = Float64List.fromList(b);
    for (var col = 0; col < n; col++) {
      var maxRow = col;
      var maxVal = m[col * n + col].abs();
      for (var row = col + 1; row < n; row++) {
        final v = m[row * n + col].abs();
        if (v > maxVal) {
          maxVal = v;
          maxRow = row;
        }
      }
      if (maxVal < 1e-10) return null;
      if (maxRow != col) {
        for (var j = 0; j < n; j++) {
          final t = m[col * n + j];
          m[col * n + j] = m[maxRow * n + j];
          m[maxRow * n + j] = t;
        }
        final t = r[col];
        r[col] = r[maxRow];
        r[maxRow] = t;
      }
      final pivot = m[col * n + col];
      for (var row = col + 1; row < n; row++) {
        final f = m[row * n + col] / pivot;
        if (f == 0) continue;
        for (var j = col; j < n; j++) {
          m[row * n + j] -= f * m[col * n + j];
        }
        r[row] -= f * r[col];
      }
    }
    final x = Float64List(n);
    for (var row = n - 1; row >= 0; row--) {
      var s = r[row];
      for (var j = row + 1; j < n; j++) {
        s -= m[row * n + j] * x[j];
      }
      x[row] = s / m[row * n + row];
    }
    return x;
  }
}

/// Grid model from four finder centers in source pixels (spec §6.3).
class HomographyGridModel extends GridModel {
  final Homography h;
  const HomographyGridModel(this.h);

  static const List<(double, double)> finderCells = [(3.5, 3.5), (60.5, 3.5), (3.5, 60.5), (60.5, 60.5)];

  static HomographyGridModel? fromFinders({
    required (double, double) tl,
    required (double, double) tr,
    required (double, double) bl,
    required (double, double) br,
  }) {
    final h = Homography.solve(finderCells, [tl, tr, bl, br]);
    return h == null ? null : HomographyGridModel(h);
  }

  @override
  (double, double) toSource(double cx, double cy) => h.map(cx, cy);
}
```

- [ ] **Step 4: Run tests and analyzer** — `flutter test test/core/decode/homography_test.dart` → 4 pass; analyzer clean.

- [ ] **Step 5: Commit**

```bash
git add android/lib/core/decode/homography.dart android/test/core/decode/homography_test.dart
git commit -m "Add Homography (DLT) and HomographyGridModel from finder centers

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 3: Synthetic scene renderer (test utility)

**Files:**
- Create: `test/test_utils/synthetic_scene.dart`
- Test: `test/core/decode/synthetic_scene_test.dart`

**Interfaces:**
- `RgbBuffer loadGoldenFrame(String name, int frameIndex)` — GIF frame from `../test-data/goldens/<name>.gif`.
- `RgbBuffer loadPhoto(String path)` — PNG/JPEG via `img.decodeImage`.
- `class SceneSpec { double scale = 1; double rotationDeg = 0; double keystone = 0; double centerX, centerY; double blurSigma = 0 /*dest px*/; double brightness = 1; double noiseSigma = 0; double barrelK = 0; int seed = 1; }`
- `class Scene { RgbBuffer image; List<(double, double)> finderCenters /*TL,TR,BL,BR dest px*/; Homography frameToScene; }`
- `Scene renderScene(RgbBuffer frame, int outW, int outH, SceneSpec spec, {RgbBuffer? background})`.
- `List<(double,double)> sceneQuad(SceneSpec spec)` — dest corners TL,TR,BL,BR of the 608 frame.

Rendering: inverse mapping per destination pixel center through `Homography.solve(quad, frameCorners)`; optional barrel distortion applied in scene space before mapping (`p' = c + (p − c)·(1 + k·r²)`, `r` = |p − c| / (304·scale)); bilinear from the frame when inside `[0,608)²`, else the background pixel (or black); then separable Gaussian blur (kernel radius `ceil(3σ)`), brightness multiply, Gaussian noise (Box–Muller, seeded), clamp 0–255.

- [ ] **Step 1: Write the failing test**

`test/core/decode/synthetic_scene_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));
  final frame = loadGoldenFrame('hello', 0);

  test('scale 1 unrotated: finder centers land at offset + 47.5', () {
    final spec = SceneSpec()..centerX = 400..centerY = 400;
    final scene = renderScene(frame, 800, 800, spec);
    expect(scene.image.width, 800);
    expect(scene.finderCenters[0].$1, closeTo(96 + 47.5, 1e-6));
    expect(scene.finderCenters[0].$2, closeTo(96 + 47.5, 1e-6));
    expect(scene.finderCenters[3].$1, closeTo(96 + 560.5, 1e-6));
    // pixel at the frame's TL finder outer ring is white, quiet zone black
    expect(scene.image.r(96 + 16, 96 + 16), 255);
    expect(scene.image.r(96 + 2, 96 + 2), 0);
    expect(scene.image.r(10, 10), 0);
  });

  FrameDecoder decoder() => FrameDecoder();

  test('decodes with a grid built from the known finder centers (scale 1)', () {
    final scene = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    final gm = HomographyGridModel.fromFinders(
      tl: scene.finderCenters[0], tr: scene.finderCenters[1], bl: scene.finderCenters[2], br: scene.finderCenters[3],
    )!;
    final r = decoder().decodeWithGrid(scene.image, gm);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.diag.hammingMax, 0);
    expect(r.data, golden.frames[0].data);
  });

  test('scale 2.3, rotation 33°, keystone 0.15 decodes from known finders', () {
    final spec = SceneSpec()
      ..scale = 2.3
      ..rotationDeg = 33
      ..keystone = 0.15
      ..centerX = 900
      ..centerY = 900;
    final scene = renderScene(frame, 1800, 1800, spec);
    final gm = HomographyGridModel.fromFinders(
      tl: scene.finderCenters[0], tr: scene.finderCenters[1], bl: scene.finderCenters[2], br: scene.finderCenters[3],
    )!;
    final r = decoder().decodeWithGrid(scene.image, gm);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, golden.frames[0].data);
  });

  test('blur 2.5 px + noise 8 + brightness 0.8 at scale 2.3 still decodes from known finders', () {
    final spec = SceneSpec()
      ..scale = 2.3
      ..blurSigma = 2.5
      ..noiseSigma = 8
      ..brightness = 0.8
      ..centerX = 800
      ..centerY = 800;
    final scene = renderScene(frame, 1600, 1600, spec);
    final gm = HomographyGridModel.fromFinders(
      tl: scene.finderCenters[0], tr: scene.finderCenters[1], bl: scene.finderCenters[2], br: scene.finderCenters[3],
    )!;
    final r = decoder().decodeWithGrid(scene.image, gm);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, golden.frames[0].data);
    expect(r.diag.hammingMax > 0, isTrue, reason: 'degradation should be visible in hamming');
  });

  test('background composite keeps the photo outside the quad', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_a.png');
    final scene = renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360, background: photo);
    expect(scene.image.r(5, 5), photo.r(5, 5));
    expect(scene.image.g(5, 5), photo.g(5, 5));
  });
}
```

- [ ] **Step 2: Run to verify failure** — compile error (utility missing).

- [ ] **Step 3: Write synthetic_scene.dart**

`test/test_utils/synthetic_scene.dart`:

```dart
// Renders golden GIF frames into synthetic camera-like scenes with known
// geometry so locator/decoder tests have exact ground truth.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

RgbBuffer loadGoldenFrame(String name, int frameIndex) {
  final gif = File(GoldenSidecar.gifPathFor('../test-data/goldens/$name.json')).readAsBytesSync();
  return RgbBuffer.fromImage(GifParser.parseFrames(gif)[frameIndex]);
}

RgbBuffer loadPhoto(String path) => RgbBuffer.fromImage(img.decodeImage(File(path).readAsBytesSync())!);

class SceneSpec {
  double scale = 1;
  double rotationDeg = 0;
  /// Keystone: top edge shrunk by (1-k), bottom edge widened by (1+k) before rotation.
  double keystone = 0;
  double centerX = 0;
  double centerY = 0;
  double blurSigma = 0; // destination pixels
  double brightness = 1;
  double noiseSigma = 0;
  /// Barrel distortion applied in scene space: p' = c + (p - c) * (1 + k r^2), r = |p-c| / (304*scale).
  double barrelK = 0;
  int seed = 1;
}

class Scene {
  final RgbBuffer image;
  final List<(double, double)> finderCenters; // TL, TR, BL, BR in scene px
  final Homography frameToScene;
  const Scene(this.image, this.finderCenters, this.frameToScene);
}

const List<(double, double)> frameCorners = [(0.0, 0.0), (608.0, 0.0), (0.0, 608.0), (608.0, 608.0)];

/// Destination corners (TL, TR, BL, BR) of the 608x608 frame under [spec].
List<(double, double)> sceneQuad(SceneSpec spec) {
  final half = CimbarSpec.framePx / 2 * spec.scale;
  final k = spec.keystone;
  final local = [(-half * (1 - k), -half), (half * (1 - k), -half), (-half * (1 + k), half), (half * (1 + k), half)];
  final th = spec.rotationDeg * math.pi / 180;
  final c = math.cos(th), s = math.sin(th);
  return [
    for (final (x, y) in local) (spec.centerX + x * c - y * s, spec.centerY + x * s + y * c),
  ];
}

Scene renderScene(RgbBuffer frame, int outW, int outH, SceneSpec spec, {RgbBuffer? background}) {
  final quad = sceneQuad(spec);
  final frameToScene = Homography.solve(frameCorners, quad)!;
  final sceneToFrame = Homography.solve(quad, frameCorners)!;
  final out = Uint8List(outW * outH * 3);
  final tmp = Float32List(3);
  final radius = CimbarSpec.framePx / 2 * spec.scale;
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      var px = x + 0.5, py = y + 0.5;
      if (spec.barrelK != 0) {
        final dx = px - spec.centerX, dy = py - spec.centerY;
        final r2 = (dx * dx + dy * dy) / (radius * radius);
        final f = 1 + spec.barrelK * r2;
        px = spec.centerX + dx * f;
        py = spec.centerY + dy * f;
      }
      final (u, v) = sceneToFrame.map(px, py);
      final o = (y * outW + x) * 3;
      if (u >= 0 && u < CimbarSpec.framePx && v >= 0 && v < CimbarSpec.framePx) {
        frame.bilinear(u, v, tmp, 0);
        out[o] = tmp[0].round().clamp(0, 255);
        out[o + 1] = tmp[1].round().clamp(0, 255);
        out[o + 2] = tmp[2].round().clamp(0, 255);
      } else if (background != null) {
        final bx = x.clamp(0, background.width - 1), by = y.clamp(0, background.height - 1);
        out[o] = background.r(bx, by);
        out[o + 1] = background.g(bx, by);
        out[o + 2] = background.b(bx, by);
      }
    }
  }
  var image = RgbBuffer(outW, outH, out);
  if (spec.blurSigma > 0) image = gaussianBlur(image, spec.blurSigma);
  if (spec.brightness != 1 || spec.noiseSigma > 0) image = brightnessNoise(image, spec.brightness, spec.noiseSigma, spec.seed);
  final centers = [
    for (final (fx, fy) in [(47.5, 47.5), (560.5, 47.5), (47.5, 560.5), (560.5, 560.5)]) frameToScene.map(fx, fy),
  ];
  return Scene(image, centers, frameToScene);
}

RgbBuffer gaussianBlur(RgbBuffer src, double sigma) {
  final radius = (3 * sigma).ceil();
  final kernel = Float64List(2 * radius + 1);
  var sum = 0.0;
  for (var i = -radius; i <= radius; i++) {
    kernel[i + radius] = math.exp(-(i * i) / (2 * sigma * sigma));
    sum += kernel[i + radius];
  }
  for (var i = 0; i < kernel.length; i++) {
    kernel[i] /= sum;
  }
  final w = src.width, h = src.height;
  final tmp = Float32List(w * h * 3);
  final s = src.rgb;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var acc = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final xx = (x + i).clamp(0, w - 1);
          acc += s[(y * w + xx) * 3 + c] * kernel[i + radius];
        }
        tmp[(y * w + x) * 3 + c] = acc;
      }
    }
  }
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var acc = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final yy = (y + i).clamp(0, h - 1);
          acc += tmp[(yy * w + x) * 3 + c] * kernel[i + radius];
        }
        out[(y * w + x) * 3 + c] = acc.round().clamp(0, 255);
      }
    }
  }
  return RgbBuffer(w, h, out);
}

RgbBuffer brightnessNoise(RgbBuffer src, double brightness, double noiseSigma, int seed) {
  final rnd = math.Random(seed);
  final out = Uint8List(src.rgb.length);
  for (var i = 0; i < out.length; i++) {
    var v = src.rgb[i] * brightness;
    if (noiseSigma > 0) {
      final u1 = math.max(1e-12, rnd.nextDouble()), u2 = rnd.nextDouble();
      v += noiseSigma * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    }
    out[i] = v.round().clamp(0, 255);
  }
  return RgbBuffer(src.width, src.height, out);
}
```

- [ ] **Step 4: Run tests and analyzer**

Run: `cd android && flutter test test/core/decode/synthetic_scene_test.dart 2>&1 | tail -3` → 5 pass. If the blur/noise case fails RS, first check `hammingMax`/`hammingMean` in the reason string; report the numbers rather than relaxing the parameters (the controller decides).
Run: `cd android && flutter analyze test/test_utils test/core/decode 2>&1 | tail -2` → clean.

- [ ] **Step 5: Commit**

```bash
git add android/test/test_utils/synthetic_scene.dart android/test/core/decode/synthetic_scene_test.dart
git commit -m "Add synthetic scene renderer for golden frames with known finder geometry

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 4: FinderLocator

**Files:**
- Create: `lib/core/decode/finder_locator.dart`
- Test: `test/core/decode/finder_locator_test.dart`

**Interfaces:**
- `class Finder { final double x, y, module; }` (full-resolution continuous px; module = px per pitch).
- `class LocateResult { Finder? tl, tr, bl, br; int candidates; int clusters; double devNorm /*-1 if none*/; double tlLuma, secondLuma; String failReason; bool get ok; double get module }`.
- `class FinderLocator { const FinderLocator({int downscale = 2, double maxDevNorm = 0.35, double tlMargin = 40, int maxClusters = 12}); LocateResult locate(LumaPlane full); }`.

- [ ] **Step 1: Write the failing test**

`test/core/decode/finder_locator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/finder_locator.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

import '../../test_utils/synthetic_scene.dart';

void main() {
  final frame = loadGoldenFrame('lorem_12k', 2);
  const locator = FinderLocator();

  void expectCorners(LocateResult r, Scene scene, double tol) {
    expect(r.ok, isTrue, reason: 'locate failed: ${r.failReason} (candidates ${r.candidates}, clusters ${r.clusters})');
    final got = [r.tl!, r.tr!, r.bl!, r.br!];
    for (var i = 0; i < 4; i++) {
      expect(got[i].x, closeTo(scene.finderCenters[i].$1, tol), reason: 'corner $i x');
      expect(got[i].y, closeTo(scene.finderCenters[i].$2, tol), reason: 'corner $i y');
    }
  }

  test('exact placement at scale 1 on black', () {
    final scene = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    final r = locator.locate(LumaPlane.fromRgb(scene.image));
    expectCorners(r, scene, 1.5);
    expect(r.module, closeTo(9, 1.0));
    expect(r.devNorm, lessThan(0.02));
    expect(r.tlLuma - r.secondLuma, greaterThan(100));
  });

  test('scale 1.8 rotated 90, 180, 271 and 37 degrees keeps TL/TR/BL/BR assignment', () {
    for (final rot in [90.0, 180.0, 271.0, 37.0]) {
      final scene = renderScene(frame, 1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = rot..centerX = 850..centerY = 850);
      final r = locator.locate(LumaPlane.fromRgb(scene.image));
      expectCorners(r, scene, 2.0);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('keystone 0.12 at scale 1.6', () {
    final scene = renderScene(frame, 1200, 1200, SceneSpec()..scale = 1.6..keystone = 0.12..rotationDeg = 12..centerX = 600..centerY = 600);
    final r = locator.locate(LumaPlane.fromRgb(scene.image));
    expectCorners(r, scene, 2.0);
  });

  test('composited on a real photo background, scale 1.0 and 0.9 rotated 15', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_a.png');
    final a = renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360, background: photo);
    expectCorners(locator.locate(LumaPlane.fromRgb(a.image)), a, 2.0);
    final b = renderScene(frame, 1280, 720, SceneSpec()..scale = 0.9..rotationDeg = 15..centerX = 700..centerY = 360, background: photo);
    expectCorners(locator.locate(LumaPlane.fromRgb(b.image)), b, 2.0);
  });

  test('blurred (sigma 2.5 px) and noisy (sigma 8) at scale 1.5', () {
    final scene = renderScene(frame, 1100, 1100, SceneSpec()..scale = 1.5..blurSigma = 2.5..noiseSigma = 8..centerX = 550..centerY = 550);
    expectCorners(locator.locate(LumaPlane.fromRgb(scene.image)), scene, 2.5);
  });

  test('photo without a v2 barcode fails to locate', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_b.png');
    final r = locator.locate(LumaPlane.fromRgb(photo));
    expect(r.ok, isFalse);
    expect(r.failReason, isNotEmpty);
  });

  test('a v1 barcode photo (a) fails to locate as v2', () {
    final r = locator.locate(LumaPlane.fromRgb(loadPhoto('test/fixtures/camera_raw_1280x720_a.png')));
    expect(r.ok, isFalse);
  });

  test('blank image', () {
    final r = locator.locate(LumaPlane.fromRgb(RgbBuffer(64, 64, Uint8List(64 * 64 * 3))));
    expect(r.ok, isFalse);
  });
}
```

Add `import 'dart:typed_data';` at the top of this file (for `Uint8List`).

- [ ] **Step 2: Run to verify failure** — compile error.

- [ ] **Step 3: Write finder_locator.dart**

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'luma_plane.dart';

/// A located finder pattern center in full-resolution continuous pixels.
class Finder {
  final double x;
  final double y;
  final double module; // px per pitch (one finder ring width)
  const Finder(this.x, this.y, this.module);
}

class LocateResult {
  final Finder? tl, tr, bl, br;
  final int candidates;
  final int clusters;
  final double devNorm;
  final double tlLuma;
  final double secondLuma;
  final String failReason;

  const LocateResult({
    this.tl,
    this.tr,
    this.bl,
    this.br,
    this.candidates = 0,
    this.clusters = 0,
    this.devNorm = -1,
    this.tlLuma = 0,
    this.secondLuma = 0,
    this.failReason = '',
  });

  bool get ok => tl != null && tr != null && bl != null && br != null;
  double get module => ok ? (tl!.module + tr!.module + bl!.module + br!.module) / 4 : 0;
}

class _Cluster {
  double sx = 0, sy = 0, sm = 0;
  int hits = 0;
  double get x => sx / hits;
  double get y => sy / hits;
  double get m => sm / hits;
}

class _Refined {
  final double x, y, m;
  final int hits;
  const _Refined(this.x, this.y, this.m, this.hits);
}

class _Run {
  final int start;
  final int length;
  final bool dark;
  const _Run(this.start, this.length, this.dark);
  int get end => start + length;
}

/// Finds the four QR-style 7x7-cell finders (spec §6.2).
///
/// 1. Downscale 2x, binarize with a local mean.
/// 2. Row scan: sliding 1:1:3:1:1 windows (strict) give candidate x positions.
/// 3. For each hit, the finder's full 7-module extent along the column through
///    it is matched *anchored* at the run containing the hit row — one of four
///    interpretations (solid core, or the tr/bl/br core dot left of / at /
///    right of the anchor run), best fit wins. This is dot-tolerant and, being
///    a chord through the center, rotation-invariant.
/// 4. Cluster hits within one module; refine each strong cluster by
///    alternating row/column extents through its center (3 iterations).
/// 5. Choose four by parallelogram closure, classify TL by core brightness,
///    orient TR/BL by cross product, correct the module for rotation.
class FinderLocator {
  final int downscale;
  final double maxDevNorm;
  final double tlMargin;
  final int maxClusters;

  const FinderLocator({this.downscale = 2, this.maxDevNorm = 0.35, this.tlMargin = 40, this.maxClusters = 12});

  static const List<double> _p5 = [1, 1, 3, 1, 1];
  static const List<double> _p7 = [1, 1, 1, 1, 1, 1, 1];
  static const double _p7Tol = 0.25;

  /// Minimum downscaled module. Below ~3 px a ring is 2 px wide and, after
  /// binarization, integer quantization makes a +-25% tolerance accept any
  /// exact-2 px run, so ordinary photo texture matches the pattern. It also
  /// bounds the barcode at >=57*2*3 = 342 full-res px across, under which the
  /// 64-cell grid is not sampleable anyway.
  static const double _minModule = 3.0;

  LocateResult locate(LumaPlane full) {
    final ds = downscale == 2 ? full.downscale2() : full;
    if (ds.width < 16 || ds.height < 16) return const LocateResult(failReason: 'image too small');
    final bin = _binarize(ds);
    final w = ds.width, h = ds.height;

    // Phases 2–4: row scan, anchored column extent, clustering.
    final clusters = <_Cluster>[];
    var candidates = 0;
    for (var y = 0; y < h; y++) {
      final runs = _rowRuns(bin, w, y);
      for (var i = 1; i < runs.length; i++) {
        if (runs[i].dark) continue;
        final match = _slidingMatch(runs, i);
        if (match == null) continue;
        final (total, m) = match;
        if (m < _minModule) continue;
        final cx = runs[i].start + total / 2;
        final col = _colRuns(bin, w, cx.floor().clamp(0, w - 1), 0, h);
        final ey = _anchoredExtent(col, y, m);
        if (ey == null) continue;
        final cy = (ey.$1 + ey.$2) / 2;
        final mv = (ey.$2 - ey.$1) / 7;
        candidates++;
        final mod = (m + mv) / 2;
        _Cluster? best;
        var bestD = double.infinity;
        for (final c in clusters) {
          final d = math.sqrt((c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy));
          if (d <= math.max(2.0, c.m) && d < bestD) {
            best = c;
            bestD = d;
          }
        }
        if (best == null) {
          best = _Cluster();
          clusters.add(best);
        }
        best.sx += cx;
        best.sy += cy;
        best.sm += mod;
        best.hits++;
      }
    }

    final strong = clusters.where((c) => c.hits >= 2).toList()..sort((a, b) => b.hits.compareTo(a.hits));
    final refined = <_Refined>[];
    for (final c in strong.take(maxClusters)) {
      final r = _refine(bin, w, h, c.x, c.y, c.m);
      if (r != null) refined.add(_Refined(r.$1, r.$2, r.$3, c.hits));
    }
    if (refined.length < 4) {
      return LocateResult(candidates: candidates, clusters: strong.length, failReason: 'fewer than 4 finder candidates (${refined.length} after refinement, ${strong.length} clusters)');
    }

    // Phase 5: parallelogram selection over diagonal pairs.
    var bestDev = double.infinity;
    List<_Refined>? bestQuad; // [P, R, Q, S] cyclic; diagonals PQ and RS
    final n = refined.length;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        for (var k = 0; k < n; k++) {
          if (k == i || k == j) continue;
          for (var l = k + 1; l < n; l++) {
            if (l == i || l == j) continue;
            final p = refined[i], q = refined[j], r = refined[k], s = refined[l];
            final mods = [p.m, q.m, r.m, s.m];
            final mMax = mods.reduce(math.max), mMin = mods.reduce(math.min);
            if (mMax > 2 * mMin) continue;
            final side = (_dist(p, r) + _dist(r, q) + _dist(q, s) + _dist(s, p)) / 4;
            if (side <= 0) continue;
            final ex = (p.x + q.x) - (r.x + s.x), ey = (p.y + q.y) - (r.y + s.y);
            final dev = math.sqrt(ex * ex + ey * ey) / side;
            final ratio = side / ((mMax + mMin) / 2);
            if (ratio < 40 || ratio > 75) continue; // finder centers are 57 modules apart
            if (dev < bestDev) {
              bestDev = dev;
              bestQuad = [p, r, q, s];
            }
          }
        }
      }
    }
    if (bestQuad == null || bestDev > maxDevNorm) {
      return LocateResult(candidates: candidates, clusters: strong.length, devNorm: bestQuad == null ? -1 : bestDev, failReason: 'no parallelogram of finders (devNorm ${bestDev.isFinite ? bestDev.toStringAsFixed(3) : '-'})');
    }

    // Phase 6: classify TL by full-res core brightness; BR is TL's diagonal partner.
    final scale = downscale.toDouble();
    final pts = [for (final c in bestQuad) Finder(c.x * scale, c.y * scale, c.m * scale)];
    final lum = [for (final f in pts) full.mean3x3(f.x.floor(), f.y.floor())];
    var tlIdx = 0;
    for (var i = 1; i < 4; i++) {
      if (lum[i] > lum[tlIdx]) tlIdx = i;
    }
    var second = -1.0;
    for (var i = 0; i < 4; i++) {
      if (i != tlIdx && lum[i] > second) second = lum[i];
    }
    if (lum[tlIdx] - second < tlMargin) {
      return LocateResult(candidates: candidates, clusters: strong.length, devNorm: bestDev, tlLuma: lum[tlIdx], secondLuma: second, failReason: 'TL core not distinct (${lum[tlIdx].toStringAsFixed(0)} vs ${second.toStringAsFixed(0)})');
    }
    final brIdx = (tlIdx + 2) % 4;
    final tl = pts[tlIdx], br = pts[brIdx];
    Finder? tr, bl;
    for (final i in [(tlIdx + 1) % 4, (tlIdx + 3) % 4]) {
      final p = pts[i];
      final cross = (br.x - tl.x) * (p.y - tl.y) - (br.y - tl.y) * (p.x - tl.x);
      if (cross < 0) {
        tr = p;
      } else {
        bl = p;
      }
    }
    if (tr == null || bl == null) {
      return LocateResult(candidates: candidates, clusters: strong.length, devNorm: bestDev, tlLuma: lum[tlIdx], secondLuma: second, failReason: 'TR/BL orientation ambiguous');
    }
    // Axis-aligned chords through a finder rotated by θ are 1/cos θ longer than
    // the true module: correct with the grid rotation folded into ±45°.
    var folded = math.atan2(tr.y - tl.y, tr.x - tl.x) % (math.pi / 2);
    if (folded > math.pi / 4) folded -= math.pi / 2;
    final cosF = math.cos(folded);
    Finder fix(Finder f) => Finder(f.x, f.y, f.module * cosF);
    return LocateResult(tl: fix(tl), tr: fix(tr), bl: fix(bl), br: fix(br), candidates: candidates, clusters: strong.length, devNorm: bestDev, tlLuma: lum[tlIdx], secondLuma: second);
  }

  static double _dist(_Refined a, _Refined b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  /// Local-mean binarization (integral image). dark = v < mean - 8 || v < 24.
  static Uint8List _binarize(LumaPlane p) {
    final w = p.width, h = p.height;
    final win = math.max(15, math.min(w, h) ~/ 10);
    final half = win ~/ 2;
    final integral = Int32List((w + 1) * (h + 1));
    for (var y = 1; y <= h; y++) {
      var rowSum = 0;
      for (var x = 1; x <= w; x++) {
        rowSum += p.luma[(y - 1) * w + (x - 1)];
        integral[y * (w + 1) + x] = integral[(y - 1) * (w + 1) + x] + rowSum;
      }
    }
    final out = Uint8List(w * h); // 1 = dark
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - half), y1 = math.min(h, y + half + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - half), x1 = math.min(w, x + half + 1);
        final sum = integral[y1 * (w + 1) + x1] - integral[y0 * (w + 1) + x1] - integral[y1 * (w + 1) + x0] + integral[y0 * (w + 1) + x0];
        final mean = sum / ((y1 - y0) * (x1 - x0));
        final v = p.luma[y * w + x];
        out[y * w + x] = (v < mean - 8 || v < 24) ? 1 : 0;
      }
    }
    return out;
  }

  static List<_Run> _rowRuns(Uint8List bin, int w, int y) {
    final runs = <_Run>[];
    var start = 0;
    var dark = bin[y * w] == 1;
    for (var x = 1; x <= w; x++) {
      final d = x < w ? bin[y * w + x] == 1 : !dark;
      if (d != dark) {
        runs.add(_Run(start, x - start, dark));
        start = x;
        dark = d;
      }
    }
    return runs;
  }

  static List<_Run> _colRuns(Uint8List bin, int w, int x, int y0, int y1) {
    final runs = <_Run>[];
    var start = y0;
    var dark = bin[y0 * w + x] == 1;
    for (var y = y0 + 1; y <= y1; y++) {
      final d = y < y1 ? bin[y * w + x] == 1 : !dark;
      if (d != dark) {
        runs.add(_Run(start, y - start, dark));
        start = y;
        dark = d;
      }
    }
    return runs;
  }

  /// Sliding match starting at light run [i], bounded by dark runs on both
  /// sides. Tries the solid core (1:1:3:1:1, 50% per-run tolerance) and then
  /// the dotted core (1:1:1:1:1:1:1) at a much tighter tolerance.
  ///
  /// The dotted pattern is needed because an axis-aligned chord through an
  /// obliquely rotated finder cannot avoid the core dot: the core's
  /// clean-chord band is half-width (3m/2)|sin t - cos t| while the dot's
  /// shadow is (m/2)(sin t + cos t), and for t near 37 deg the shadow is 2.4x
  /// the band. Its tolerance is [_p7Tol], not 0.5, because a uniform 7-run
  /// pattern at 50% also admits windows shifted by one run where a merged
  /// ~2-module run stands in for a 1-module one.
  static (int, double)? _slidingMatch(List<_Run> runs, int i) {
    final five = _fitAt(runs, i, _p5, 0.5);
    if (five != null) return five;
    return _fitAt(runs, i, _p7, _p7Tol);
  }

  static (int, double)? _fitAt(List<_Run> runs, int i, List<double> pat, double tol) {
    final n = pat.length;
    if (i + n >= runs.length) return null; // dark run required on both sides
    var total = 0;
    for (var k = 0; k < n; k++) {
      total += runs[i + k].length;
    }
    final m = total / 7;
    for (var k = 0; k < n; k++) {
      final e = pat[k] * m;
      if ((runs[i + k].length - e).abs() > tol * e) return null;
    }
    return (total, m);
  }

  /// Relative fit error of pattern [pat] over runs[start..start+n) with module
  /// total/7; null when colors do not alternate light-first or bounds fail.
  static double? _fit(List<_Run> runs, int start, List<double> pat) {
    final n = pat.length;
    if (start < 1 || start + n >= runs.length) return null;
    if (runs[start].dark) return null;
    var total = 0;
    for (var k = 0; k < n; k++) {
      total += runs[start + k].length;
    }
    final m = total / 7;
    var worst = 0.0;
    for (var k = 0; k < n; k++) {
      final e = pat[k] * m;
      final err = (runs[start + k].length - e).abs() / e;
      if (err > worst) worst = err;
    }
    return worst;
  }

  /// Finder extent [start, end) along a run list, anchored at the run that
  /// contains position [p]. Tries: solid core (5 runs starting two runs before
  /// the anchor), and the dotted core with the anchor being the left core
  /// half, the dot, or the right core half (7 runs). Best fit ≤ 0.5 wins; the
  /// module must be within 0.5–2x of [m].
  static (int, int)? _anchoredExtent(List<_Run> runs, int p, double m) {
    var j = -1;
    for (var i = 0; i < runs.length; i++) {
      if (p >= runs[i].start && p < runs[i].end) {
        j = i;
        break;
      }
    }
    if (j < 0) return null;
    const tries = [(-2, _p5), (-2, _p7), (-3, _p7), (-4, _p7)];
    double bestErr = 0.5;
    (int, int)? best;
    for (final (off, pat) in tries) {
      final start = j + off;
      final err = _fit(runs, start, pat);
      if (err == null || err > bestErr) continue;
      final end = runs[start + pat.length - 1].end;
      final mm = (end - runs[start].start) / 7;
      if (mm < 0.5 * m || mm > 2 * m) continue;
      bestErr = err;
      best = (runs[start].start, end);
    }
    return best;
  }

  /// Alternate row/column extents through the current center (3 iterations).
  static (double, double, double)? _refine(Uint8List bin, int w, int h, double cx, double cy, double m) {
    var x = cx, y = cy, mod = m;
    for (var iter = 0; iter < 3; iter++) {
      final yi = y.floor().clamp(0, h - 1), xi = x.floor().clamp(0, w - 1);
      final ex = _anchoredExtent(_rowRuns(bin, w, yi), xi, mod);
      if (ex == null) return null;
      final ey = _anchoredExtent(_colRuns(bin, w, xi, 0, h), yi, mod);
      if (ey == null) return null;
      x = (ex.$1 + ex.$2) / 2;
      y = (ey.$1 + ey.$2) / 2;
      mod = ((ex.$2 - ex.$1) + (ey.$2 - ey.$1)) / 14;
    }
    return (x, y, mod);
  }
}
```

- [ ] **Step 4: Run tests and analyzer**

Run: `cd android && flutter test test/core/decode/finder_locator_test.dart 2>&1 | tail -15` → 8 pass. (History: this file went through four rounds during execution — off-center columns, a permissive 7-run sliding pattern, two-column AND — before the anchored-extent design above passed all cases; the row scan accepts the dotted 7-run pattern only at 25 % per-run tolerance and the module floor is 3.0 downscaled px because false clusters on real photos measure ≤ 2.6.)
Run: `cd android && flutter analyze lib/core/decode test/core/decode 2>&1 | tail -2` → clean.

- [ ] **Step 5: Commit**

```bash
git add android/lib/core/decode/finder_locator.dart android/test/core/decode/finder_locator_test.dart
git commit -m "Add FinderLocator: run-length finder detection with parallelogram selection and TL classification

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 5: WhitePoint, extended diagnostics/report, and the camera path in FrameDecoder

**Files:**
- Create: `lib/core/decode/white_point.dart`
- Replace: `lib/core/decode/diagnostics.dart`, `lib/core/decode/frame_decoder.dart`
- Modify: `lib/core/decode/decode_report.dart` (`lines()` gains stages)
- Test: `test/core/decode/white_point_test.dart`, `test/core/decode/camera_path_test.dart`; extend `test/core/decode/decode_report_test.dart`

**Interfaces:**
- `WhitePoint.fromFinders(RgbBuffer image, GridModel grid) → List<double>?` (null when any channel < 30).
- `Diagnostics` new fields: `bool locateRan; int locateMs; int candidates; int clusters; Float64List? corners /*tlx,tly,trx,try,blx,bly,brx,bry*/; double module; double tlLuma, secondLuma; double devNorm; String locateFail; int gridEstimate; List<double>? whitePoint; bool driftUsed; int driftMs; double driftMeanAbs, driftMaxAbs; int driftWidened;` — `toMap()` adds `locateMs, candidates, clusters, module, corners (as "x,y;x,y;x,y;x,y"), tlLuma, secondLuma, devNorm, locateFail (when set), gridEstimate, wb (as "r,g,b" or "-"), driftUsed, driftMs, driftMeanAbs, driftMaxAbs, driftWidened` only when `locateRan` or `driftUsed`.
- `FrameDecoder.decode(RgbBuffer image, {GridModel? grid, bool useDrift = true})`; `decodeWithGrid(image, grid, {List<double>? whitePoint, bool useDrift = false, LumaPlane? luma, Diagnostics? diag})`. In this task `useDrift` is accepted and recorded as `driftUsed = false` (Task 6 implements it).
- `DecodeReport.lines` emits, when `locateRan`: `stage=locate ok=… candidates=… clusters=… module=… corners=… tlLuma=… secondLuma=… devNorm=… locateMs=… [fail=…]`, `stage=grid estimate=…`, `stage=wb rgb=…`; when `driftUsed`: `stage=drift meanAbs=… maxAbs=… widened=… driftMs=…`.

- [ ] **Step 1: Write the failing tests**

`test/core/decode/white_point_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/white_point.dart';

import '../../test_utils/synthetic_scene.dart';

void main() {
  final frame = loadGoldenFrame('hello', 0);

  test('exact frame: white point is pure white', () {
    final wp = WhitePoint.fromFinders(frame, const ExactGridModel())!;
    expect(wp[0], closeTo(255, 1));
    expect(wp[1], closeTo(255, 1));
    expect(wp[2], closeTo(255, 1));
  });

  test('a color cast shows in the white point', () {
    final scene = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    // tint the whole scene: blue x 0.5
    for (var i = 2; i < scene.image.rgb.length; i += 3) {
      scene.image.rgb[i] = (scene.image.rgb[i] * 0.5).round();
    }
    final wp = WhitePoint.fromFinders(scene.image, const ExactGridModelOffset(96, 96))!;
    expect(wp[0], closeTo(255, 2));
    expect(wp[2], closeTo(128, 3));
  });

  test('too dark returns null', () {
    final dark = renderScene(frame, 800, 800, SceneSpec()..centerX = 400..centerY = 400..brightness = 0.05);
    expect(WhitePoint.fromFinders(dark.image, const ExactGridModelOffset(96, 96)), isNull);
  });
}

/// Exact grid shifted by a pixel offset (the frame drawn at (ox, oy) in a larger canvas).
class ExactGridModelOffset extends GridModel {
  final double ox, oy;
  const ExactGridModelOffset(this.ox, this.oy);
  @override
  (double, double) toSource(double cx, double cy) {
    final (x, y) = const ExactGridModel().toSource(cx, cy);
    return (x + ox, y + oy);
  }
}
```

`test/core/decode/camera_path_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json'));
  final frame = loadGoldenFrame('lorem_12k', 2);
  final truth = golden.frames[2].data;

  void expectDecodes(Scene scene, String label) {
    final r = FrameDecoder().decode(scene.image, useDrift: false);
    expect(r.status, DecodeStatus.ok, reason: '$label: ${r.diag.toMap()}');
    expect(r.data, truth, reason: '$label data');
    expect(r.header!.seq, 2);
  }

  test('scale 1.5, 2.0, 2.5 unrotated', () {
    for (final s in [1.5, 2.0, 2.5]) {
      final size = (608 * s + 200).ceil();
      expectDecodes(renderScene(frame, size, size, SceneSpec()..scale = s..centerX = size / 2..centerY = size / 2), 'scale $s');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rotations 37, 90, 180, 271 at scale 1.8', () {
    for (final rot in [37.0, 90.0, 180.0, 271.0]) {
      // 1094 px side rotated 37° needs a 1548 px bounding box: use 1700.
      expectDecodes(renderScene(frame, 1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = rot..centerX = 850..centerY = 850), 'rot $rot');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('keystone 0.12 (about 20 degrees of tilt) at scale 1.8', () {
    expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 1.8..keystone = 0.12..rotationDeg = 8..centerX = 750..centerY = 750), 'keystone');
  });

  test('blur sigma 1.5 source px (3 px at scale 2)', () {
    expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 2..blurSigma = 3..centerX = 750..centerY = 750), 'blur');
  });

  test('brightness 0.7 and 1.3', () {
    for (final b in [0.7, 1.3]) {
      expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 2..brightness = b..centerX = 750..centerY = 750), 'brightness $b');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('noise sigma 8', () {
    expectDecodes(renderScene(frame, 1500, 1500, SceneSpec()..scale = 2..noiseSigma = 8..centerX = 750..centerY = 750), 'noise');
  });

  test('combined mild degradation', () {
    final spec = SceneSpec()
      ..scale = 1.7
      ..rotationDeg = 12
      ..keystone = 0.1
      ..blurSigma = 1.4
      ..brightness = 0.85
      ..noiseSigma = 5
      ..centerX = 700
      ..centerY = 700;
    expectDecodes(renderScene(frame, 1400, 1400, spec), 'combined');
  });

  test('composited on a real photo at scale 1.0', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_a.png');
    expectDecodes(renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360, background: photo), 'photo background');
  });

  test('photo without barcode is notLocated with locate diagnostics', () {
    final r = FrameDecoder().decode(loadPhoto('test/fixtures/camera_raw_1280x720_b.png'));
    expect(r.status, DecodeStatus.notLocated);
    expect(r.diag.locateRan, isTrue);
    expect(r.diag.locateFail, isNotEmpty);
    expect(r.diag.toMap().containsKey('locateMs'), isTrue);
  });
}
```

Append to `test/core/decode/decode_report_test.dart` (inside `main`, after the existing tests):

```dart
  test('camera-path lines include locate/grid/wb stages', () {
    final scene = renderScene(RgbBuffer.fromImage(frame), 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    final r = FrameDecoder().decode(scene.image, useDrift: false);
    final lines = DecodeReport.lines(r, frameIndex: 0);
    expect(lines.any((l) => l.startsWith('frame=0 stage=locate ok=true') && l.contains('corners=')), isTrue, reason: lines.join('\n'));
    expect(lines.any((l) => l.startsWith('frame=0 stage=grid estimate=64')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=wb rgb=')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=result status=ok')), isTrue);
  });
```
and add `import '../../test_utils/synthetic_scene.dart';` to that file.

- [ ] **Step 2: Run to verify failure** — compile errors.

- [ ] **Step 3: Write white_point.dart**

```dart
import '../format/cimbar_spec.dart';
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
```
Replace the first import line `import '../format/cimbar_spec.dart';` with `import 'dart:typed_data';` (the file uses `Float32List` and nothing from `CimbarSpec`).

- [ ] **Step 4: Replace diagnostics.dart**

```dart
import 'dart:typed_data';

import '../format/frame_header.dart';

enum DecodeStatus { ok, notLocated, unsupportedGrid, rsFailed, badHeader }

/// Per-frame decode diagnostics, printed as `key=value` pairs by DecodeReport.
class Diagnostics {
  // cells
  int hammingMax = 0;
  double hammingMean = 0;
  double colorMarginMin = double.infinity;
  final List<int> hammingHist = [0, 0, 0, 0]; // <8, <16, <24, >=24
  int sampleMs = 0;
  // rs / header
  int rsBlocks = 0;
  int rsOk = 0;
  int rsFailed = 0;
  int rsMs = 0;
  String headerReason = '';
  String note = '';
  // locate (camera path)
  bool locateRan = false;
  int locateMs = 0;
  int candidates = 0;
  int clusters = 0;
  Float64List? corners; // tlx,tly,trx,try,blx,bly,brx,bry
  double module = 0;
  double tlLuma = 0;
  double secondLuma = 0;
  double devNorm = -1;
  String locateFail = '';
  int gridEstimate = 0;
  List<double>? whitePoint;
  // drift
  bool driftUsed = false;
  int driftMs = 0;
  double driftMeanAbs = 0;
  double driftMaxAbs = 0;
  int driftWidened = 0;

  void addHamming(int h) {
    if (h > hammingMax) hammingMax = h;
    hammingHist[h < 8 ? 0 : (h < 16 ? 1 : (h < 24 ? 2 : 3))]++;
  }

  static String _f(double v, [int d = 2]) => v.toStringAsFixed(d);

  Map<String, String> toMap() => {
        'hammingMax': '$hammingMax',
        'hammingMean': _f(hammingMean),
        'hammingHist': hammingHist.join('/'),
        'colorMarginMin': colorMarginMin == double.infinity ? '-' : _f(colorMarginMin, 3),
        'rsBlocks': '$rsBlocks',
        'rsOk': '$rsOk',
        'rsFailed': '$rsFailed',
        if (headerReason.isNotEmpty) 'headerReason': headerReason,
        if (note.isNotEmpty) 'note': note,
        'sampleMs': '$sampleMs',
        'rsMs': '$rsMs',
        if (locateRan) ...{
          'locateMs': '$locateMs',
          'candidates': '$candidates',
          'clusters': '$clusters',
          'module': _f(module),
          'corners': corners == null ? '-' : [for (var i = 0; i < 8; i += 2) '${_f(corners![i], 1)},${_f(corners![i + 1], 1)}'].join(';'),
          'tlLuma': _f(tlLuma, 0),
          'secondLuma': _f(secondLuma, 0),
          'devNorm': _f(devNorm, 3),
          if (locateFail.isNotEmpty) 'locateFail': locateFail,
          'gridEstimate': '$gridEstimate',
          'wb': whitePoint == null ? '-' : whitePoint!.map((v) => _f(v, 0)).join(','),
        },
        if (driftUsed) ...{
          'driftMs': '$driftMs',
          'driftMeanAbs': _f(driftMeanAbs),
          'driftMaxAbs': _f(driftMaxAbs),
          'driftWidened': '$driftWidened',
        },
      };
}

class FrameResult {
  final DecodeStatus status;
  final Uint8List? cells;
  final Uint8List? raw;
  final Uint8List? data;
  final FrameHeader? header;
  final Diagnostics diag;

  const FrameResult({
    required this.status,
    required this.diag,
    this.cells,
    this.raw,
    this.data,
    this.header,
  });

  bool get isOk => status == DecodeStatus.ok;
}
```

- [ ] **Step 5: Replace frame_decoder.dart**

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import '../format/rs_framing.dart';
import '../services/reed_solomon.dart';
import 'cell_classifier.dart';
import 'cell_sampler.dart';
import 'diagnostics.dart';
import 'finder_locator.dart';
import 'grid_model.dart';
import 'homography.dart';
import 'luma_plane.dart';
import 'rgb_buffer.dart';
import 'white_point.dart';

/// The single v2 frame decoder (spec §6.1). GIF paths call [decodeExact];
/// camera paths call [decode], which locates the finders, fits a homography
/// grid, white-balances from the finder cores and decodes the cells.
class FrameDecoder {
  final ReedSolomon _rs = ReedSolomon(CimbarSpec.rsEccBytes);
  final CellClassifier _classifier = CellClassifier();
  final FinderLocator locator;

  static const int gridTolerance = 6;

  FrameDecoder({this.locator = const FinderLocator()});

  FrameResult decode(RgbBuffer image, {GridModel? grid, bool useDrift = true}) {
    if (grid != null) return decodeWithGrid(image, grid, useDrift: useDrift);
    final diag = Diagnostics()..locateRan = true;
    final sw = Stopwatch()..start();
    final luma = LumaPlane.fromRgb(image);
    final loc = locator.locate(luma);
    diag.locateMs = sw.elapsedMilliseconds;
    diag.candidates = loc.candidates;
    diag.clusters = loc.clusters;
    diag.devNorm = loc.devNorm;
    diag.tlLuma = loc.tlLuma;
    diag.secondLuma = loc.secondLuma;
    if (!loc.ok) {
      diag.locateFail = loc.failReason;
      return FrameResult(status: DecodeStatus.notLocated, diag: diag..note = loc.failReason);
    }
    final tl = loc.tl!, tr = loc.tr!, bl = loc.bl!, br = loc.br!;
    diag.corners = Float64List.fromList([tl.x, tl.y, tr.x, tr.y, bl.x, bl.y, br.x, br.y]);
    diag.module = loc.module;

    final gm = HomographyGridModel.fromFinders(tl: (tl.x, tl.y), tr: (tr.x, tr.y), bl: (bl.x, bl.y), br: (br.x, br.y));
    if (gm == null) {
      diag.locateFail = 'homography singular';
      return FrameResult(status: DecodeStatus.notLocated, diag: diag..note = diag.locateFail);
    }
    final side = (_dist(tl, tr) + _dist(tl, bl)) / 2;
    final estimate = (side / loc.module).round() + CimbarSpec.finderCells;
    diag.gridEstimate = estimate;
    if ((estimate - CimbarSpec.gridCells).abs() > gridTolerance) {
      return FrameResult(status: DecodeStatus.unsupportedGrid, diag: diag..note = 'grid estimate $estimate cells (supported: ${CimbarSpec.gridCells})');
    }
    final wp = WhitePoint.fromFinders(image, gm);
    diag.whitePoint = wp;
    return decodeWithGrid(image, gm, whitePoint: wp, useDrift: useDrift, luma: luma, diag: diag);
  }

  static double _dist(Finder a, Finder b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  FrameResult decodeExact(RgbBuffer image) {
    const size = CimbarSpec.framePx;
    if (image.width != size || image.height != size) {
      return FrameResult(
        status: DecodeStatus.unsupportedGrid,
        diag: Diagnostics()
          ..note = 'expected ${size}x$size, got ${image.width}x${image.height} (v1 GIF?)',
      );
    }
    return decodeWithGrid(image, const ExactGridModel());
  }

  FrameResult decodeWithGrid(
    RgbBuffer image,
    GridModel grid, {
    List<double>? whitePoint,
    bool useDrift = false,
    LumaPlane? luma,
    Diagnostics? diag,
  }) {
    final d = diag ?? Diagnostics();
    final sw = Stopwatch()..start();
    final sampler = CellSampler(image, grid, luma: luma);
    final patch = CellPatch();
    final positions = CimbarSpec.usableCellPositions;
    final cells = Uint8List(positions.length);
    var hammingSum = 0;
    d.driftUsed = false; // Task 6 wires the drift solver here
    for (var k = 0; k < positions.length; k++) {
      final pos = positions[k];
      sampler.sample(pos.col, pos.row, patch);
      final c = _classifier.classify(patch, whitePoint: whitePoint);
      cells[k] = BitPacking.cellValue(c.symbol, c.color);
      hammingSum += c.hamming;
      d.addHamming(c.hamming);
      if (c.colorMargin < d.colorMarginMin) d.colorMarginMin = c.colorMargin;
    }
    d.hammingMean = hammingSum / positions.length;
    d.sampleMs = sw.elapsedMilliseconds;

    sw.reset();
    final raw = BitPacking.unpackCells(cells);
    final rs = RsFraming.decodeFrame(raw, _rs);
    d.rsMs = sw.elapsedMilliseconds;
    d.rsBlocks = rs.blocksOk + rs.blocksFailed;
    d.rsOk = rs.blocksOk;
    d.rsFailed = rs.blocksFailed;
    if (rs.blocksFailed > 0) {
      return FrameResult(status: DecodeStatus.rsFailed, diag: d, cells: cells, raw: raw, data: rs.data);
    }
    final hd = FrameHeader.decode(rs.data);
    if (!hd.valid) {
      d.headerReason = hd.reason;
      return FrameResult(status: DecodeStatus.badHeader, diag: d, cells: cells, raw: raw, data: rs.data, header: hd.header);
    }
    return FrameResult(status: DecodeStatus.ok, diag: d, cells: cells, raw: raw, data: rs.data, header: hd.header);
  }
}
```

- [ ] **Step 6: Extend decode_report.dart lines()**

Insert at the start of `lines()`'s body, right after `final p = 'frame=$frameIndex';`:

```dart
    if (r.diag.locateRan) {
      out.add('$p stage=locate ${_kv({
            'ok': '${r.diag.locateFail.isEmpty}',
            'candidates': d['candidates']!,
            'clusters': d['clusters']!,
            'module': d['module']!,
            'corners': d['corners']!,
            'tlLuma': d['tlLuma']!,
            'secondLuma': d['secondLuma']!,
            'devNorm': d['devNorm']!,
            'locateMs': d['locateMs']!,
            if (r.diag.locateFail.isNotEmpty) 'fail': r.diag.locateFail,
          })}');
      if (r.diag.locateFail.isEmpty) {
        out.add('$p stage=grid estimate=${d['gridEstimate']}');
        out.add('$p stage=wb rgb=${d['wb']}');
      }
    }
    if (r.diag.driftUsed) {
      out.add('$p stage=drift ${_kv({
            'meanAbs': d['driftMeanAbs']!,
            'maxAbs': d['driftMaxAbs']!,
            'widened': d['driftWidened']!,
            'driftMs': d['driftMs']!,
          })}');
    }
```

- [ ] **Step 7: Run tests and analyzer**

Run: `cd android && flutter test test/core/decode/ 2>&1 | tail -20` → all pass (white_point 3, camera_path 9, report +1, plus everything earlier). Investigate any synthetic failure with the diagnostics in the reason string; report numbers before changing thresholds.
Run: `cd android && flutter analyze lib/core test/core test/test_utils tool 2>&1 | tail -2` → no new issues.
Run the CLI on a rendered scene is Task 7; here just confirm `dart run tool/decode_image.dart ../test-data/goldens/hello.gif` still exits 0.

- [ ] **Step 8: Commit**

```bash
git add android/lib/core/decode/white_point.dart android/lib/core/decode/diagnostics.dart android/lib/core/decode/frame_decoder.dart android/lib/core/decode/decode_report.dart android/test/core/decode/white_point_test.dart android/test/core/decode/camera_path_test.dart android/test/core/decode/decode_report_test.dart
git commit -m "Add camera decode path: locate, homography grid, grid-size check, white point, diagnostics

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 6: DriftSolver

**Files:**
- Create: `lib/core/decode/drift_solver.dart`
- Modify: `lib/core/decode/frame_decoder.dart` (`decodeWithGrid` uses the solver when `useDrift`)
- Test: `test/core/decode/drift_solver_test.dart`

**Interfaces:**
- `class DriftField { final Float32List dx, dy /*4096, indexed row*64+col*/; int widened; double meanAbs; double maxAbs; }`
- `class DriftSolver { DriftSolver(CellSampler sampler, CellClassifier classifier, {int wideThreshold = 20, double clampPx = 6}); DriftField solve(); }`
- `FrameDecoder.decodeWithGrid(..., useDrift: true)` runs the solver first (requires `luma` for speed but works without), then samples RGB at each cell's drift and classifies; fills `diag.driftUsed/driftMs/driftMeanAbs/driftMaxAbs/driftWidened`.

- [ ] **Step 1: Write the failing test**

`test/core/decode/drift_solver_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/cell_classifier.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/drift_solver.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

/// Exact grid shifted by a constant source-pixel offset: every cell should
/// resolve to drift == (−ox, −oy) relative to the model.
class ShiftedExactGrid extends GridModel {
  final double ox, oy;
  const ShiftedExactGrid(this.ox, this.oy);
  @override
  (double, double) toSource(double cx, double cy) {
    final (x, y) = const ExactGridModel().toSource(cx, cy);
    return (x + ox, y + oy);
  }
}

void main() {
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json'));
  final frame = loadGoldenFrame('lorem_12k', 1);
  final truth = golden.frames[1].data;

  test('exact frame: drift stays at zero', () {
    final luma = LumaPlane.fromRgb(frame);
    final f = DriftSolver(CellSampler(frame, const ExactGridModel(), luma: luma), CellClassifier()).solve();
    expect(f.maxAbs, lessThanOrEqualTo(0.0));
    expect(f.widened, 0);
  });

  test('a grid model that is off by (2, -1) px is corrected by the solver', () {
    final luma = LumaPlane.fromRgb(frame);
    final f = DriftSolver(CellSampler(frame, const ShiftedExactGrid(2, -1), luma: luma), CellClassifier()).solve();
    expect(f.meanAbs, closeTo(1.5, 0.3)); // mean of |dx|=2 and |dy|=1
    final k = 32 * 64 + 32;
    expect(f.dx[k], closeTo(-2, 0.01));
    expect(f.dy[k], closeTo(1, 0.01));
    final r = FrameDecoder().decodeWithGrid(frame, const ShiftedExactGrid(2, -1), useDrift: true, luma: luma);
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, truth);
    expect(r.diag.driftUsed, isTrue);
  });

  test('barrel distortion the homography cannot model: drift recovers the frame', () {
    final spec = SceneSpec()
      ..scale = 1.8
      ..barrelK = 0.02
      ..centerX = 750
      ..centerY = 750;
    final scene = renderScene(frame, 1500, 1500, spec);
    final off = FrameDecoder().decode(scene.image, useDrift: false);
    final on = FrameDecoder().decode(scene.image, useDrift: true);
    expect(on.status, DecodeStatus.ok, reason: 'with drift: ${on.diag.toMap()}');
    expect(on.data, truth);
    expect(on.diag.driftMeanAbs, greaterThan(0.3), reason: 'drift should be non-trivial here');
    // Document the effect: without drift the frame should be worse (more hamming), whatever its status.
    expect(off.diag.hammingMean, greaterThan(on.diag.hammingMean));
  });

  test('camera path with drift on all Task 5 geometries still decodes', () {
    for (final spec in [
      SceneSpec()..scale = 1.5,
      SceneSpec()..scale = 2.2..rotationDeg = 200,
      SceneSpec()..scale = 1.8..keystone = 0.12..rotationDeg = 8,
    ]) {
      final size = (608 * spec.scale * 1.5).ceil(); // room for any rotation
      spec
        ..centerX = size / 2
        ..centerY = size / 2;
      final scene = renderScene(frame, size, size, spec);
      final r = FrameDecoder().decode(scene.image);
      expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
      expect(r.data, truth);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('timing report (not asserted)', () {
    final scene = renderScene(frame, 1500, 1500, SceneSpec()..scale = 1.8..centerX = 750..centerY = 750);
    final r = FrameDecoder().decode(scene.image);
    // Visible with --verbose in the JSON reporter; kept as a data point for Plan 4.
    expect(r.diag.toMap()['driftMs'], isNotNull);
    expect(Uint8List(0), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure** — compile error.

- [ ] **Step 3: Write drift_solver.dart**

```dart
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'cell_classifier.dart';
import 'cell_sampler.dart';

/// Per-cell drift in source pixels, indexed row*64 + col.
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
/// [wideThreshold], and clamps to ±[clampPx].
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
      for (var iter = 0; iter < 8; iter++) {
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
      if (bestH > wideThreshold) {
        field.widened++;
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
```

Note on the (2, −1) test: the solver measures drift as the offset to ADD to the model's position, so a model shifted by (+2, −1) resolves to drift (−2, +1); `meanAbs` uses the average of |dx| and |dy| = (2 + 1) / 2 = 1.5. The hill-climb reaches (−2, +1) from (0, 0) in two steps because each 1 px step toward the true position lowers the Hamming distance of the block-structured tiles.

- [ ] **Step 4: Wire the solver into decodeWithGrid**

In `frame_decoder.dart`, add `import 'drift_solver.dart';` and replace the block from `d.driftUsed = false; // Task 6 wires the drift solver here` through the end of the per-cell loop with:

```dart
    DriftField? drift;
    if (useDrift) {
      final lp = luma ?? LumaPlane.fromRgb(image);
      final dsw = Stopwatch()..start();
      drift = DriftSolver(CellSampler(image, grid, luma: lp), _classifier).solve();
      d.driftUsed = true;
      d.driftMs = dsw.elapsedMilliseconds;
      d.driftMeanAbs = drift.meanAbs;
      d.driftMaxAbs = drift.maxAbs;
      d.driftWidened = drift.widened;
    } else {
      d.driftUsed = false;
    }
    for (var k = 0; k < positions.length; k++) {
      final pos = positions[k];
      if (drift != null) {
        final idx = pos.row * CimbarSpec.gridCells + pos.col;
        sampler.sample(pos.col, pos.row, patch, dx: drift.dx[idx], dy: drift.dy[idx]);
      } else {
        sampler.sample(pos.col, pos.row, patch);
      }
      final c = _classifier.classify(patch, whitePoint: whitePoint);
      cells[k] = BitPacking.cellValue(c.symbol, c.color);
      hammingSum += c.hamming;
      d.addHamming(c.hamming);
      if (c.colorMargin < d.colorMarginMin) d.colorMarginMin = c.colorMargin;
    }
```

- [ ] **Step 5: Run tests and analyzer**

Run: `cd android && flutter test test/core/decode/drift_solver_test.dart 2>&1 | tail -8` → 5 pass. If the barrel case fails with drift on, report `driftMeanAbs/driftMaxAbs/widened/hammingMean` for both runs; the knobs are `barrelK` in the test (must stay large enough that `off` is measurably worse) and `clampPx` (must stay 6 per spec).
Run: `cd android && flutter test test/core/decode/ 2>&1 | tail -3` → all pass.
Run: `cd android && flutter analyze lib/core test/core 2>&1 | tail -2` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/decode/drift_solver.dart android/lib/core/decode/frame_decoder.dart android/test/core/decode/drift_solver_test.dart
git commit -m "Add DriftSolver: BFS per-cell drift search wired into the camera decode path

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 7: CLI camera mode, corpus expectations, docs

**Files:**
- Modify: `tool/decode_image.dart` (`--no-drift`; usage text; camera mode is now real)
- Modify: `test/fixtures/corpus/README.md` (what the columns mean now that locate runs), `android/CLAUDE.md`, `CLAUDE.md`, `CHANGELOG.md`
- Test: run the CLI on a rendered scene PNG produced by a small Dart script (no new test file needed beyond a smoke check in `decode_report_test.dart`, already added in Task 5)

- [ ] **Step 1: CLI**

In `tool/decode_image.dart`: add `var useDrift = true;` next to `mode`; add a `case '--no-drift': useDrift = false;` to the argument switch; update the usage string to `… [--mode exact|camera] [--no-drift]`; replace `final result = mode == 'exact' ? decoder.decodeExact(buffer) : decoder.decode(buffer);` with `final result = mode == 'exact' ? decoder.decodeExact(buffer) : decoder.decode(buffer, useDrift: useDrift);`. The report lines already include the new stages.

Smoke run: render a scene PNG with a temporary test file (not committed), `test/tmp_render_scene_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'test_utils/synthetic_scene.dart';

void main() {
  test('render /tmp/scene.png', () {
    final frame = loadGoldenFrame('lorem_12k', 2);
    final s = renderScene(frame, 1700, 1700, SceneSpec()..scale = 1.8..rotationDeg = 20..keystone = 0.1..blurSigma = 1.5..noiseSigma = 5..centerX = 850..centerY = 850);
    final im = img.Image(width: 1700, height: 1700);
    for (var y = 0; y < 1700; y++) {
      for (var x = 0; x < 1700; x++) {
        im.setPixelRgb(x, y, s.image.r(x, y), s.image.g(x, y), s.image.b(x, y));
      }
    }
    File('/tmp/scene.png').writeAsBytesSync(img.encodePng(im));
  });
}
```
Run `cd android && flutter test test/tmp_render_scene_test.dart`, then delete the file (`rm test/tmp_render_scene_test.dart`) before committing.

Run: `cd android && dart run tool/decode_image.dart /tmp/scene.png --golden ../test-data/goldens/lorem_12k.json --frame 2; echo exit=$?`
Expected: `stage=locate ok=true …`, `stage=grid estimate=64`, `stage=wb rgb=…`, `stage=drift …`, `stage=result status=ok`, `stage=truth cellAcc=1.000 …`, `exit=0`. Then `--no-drift` → still `status=ok`. Then `dart run tool/decode_image.dart test/fixtures/camera_raw_1280x720_a.png; echo exit=$?` → `stage=locate ok=false … fail=…`, `stage=result status=notLocated`, `exit=1`. Paste all three outputs into your report.

- [ ] **Step 2: Corpus README and docs**

`test/fixtures/corpus/README.md`: add a paragraph: "Since Plan 3 the camera path is real: a case's status comes from the locator → homography → white point → drift → RS chain, and the table's `hammingMean` and `symbolAcc` are meaningful. Real captures are still to be added (spec §9.3 checklist)."

`android/CLAUDE.md`: in "v2 Format and Decode Layer" add one line each for `luma_plane.dart`, `homography.dart`, `finder_locator.dart`, `white_point.dart`, `drift_solver.dart`; replace the `frame_decoder.dart` line with: "`FrameDecoder`: `decode(image, {grid, useDrift = true})` runs the camera path (LumaPlane → FinderLocator → HomographyGridModel → grid-size check (64 ± 6) → WhitePoint → DriftSolver → cells → RS → header); `decodeExact(image)` is the GIF path; `decodeWithGrid(image, grid, {whitePoint, useDrift, luma, diag})` is the shared core"; update the CLI section (`--no-drift`, `--mode camera` now decodes; example locate/grid/wb/drift lines from your smoke run); in "Decoding Pipelines" change the sentence to "Camera photo and live scan UI still call the v1 decoder until Plan 4 rewires them to `FrameDecoder.decode`"; add a "Synthetic scenes" paragraph pointing at `test/test_utils/synthetic_scene.dart` (what it renders, `SceneSpec` fields) and listing the degradation suites (`camera_path_test.dart`, `finder_locator_test.dart`, `drift_solver_test.dart`); add rows for the new test files to the Tests table.

Root `CLAUDE.md` Interoperability: "The Android app decodes v2 GIFs via file import; the v2 camera decoder (`FrameDecoder.decode`) is implemented and proven on synthetic degradations, but the camera screens still run v1 until Plan 4."

`CHANGELOG.md` Unreleased → Added: "- v2 camera decode stages in Dart: finder locator, homography grid model, finder-core white balance, per-cell drift solver; synthetic degradation test harness (scale, rotation, perspective, blur, brightness, noise, barrel distortion, photo backgrounds)."

- [ ] **Step 3: Full suite, analyzer, commit**

Run: `cd android && sh tests/run_all.sh` → all pass, corpus table printed (the two v1 rows must still be `notLocated` or `unsupportedGrid`). Run: `cd android && flutter analyze lib/core tool test/core test/test_utils 2>&1 | tail -2` → no new issues.

```bash
git add android/tool/decode_image.dart android/test/fixtures/corpus/README.md android/CLAUDE.md CLAUDE.md CHANGELOG.md
git commit -m "Make the CLI camera mode real (--no-drift) and document the v2 camera decode stages

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

## Self-review notes

- Spec coverage: §6.2 (Task 4), §6.3 grid + grid-size + white point (Tasks 2, 5), §6.4 already in Plan 2, §6.5 (Task 6), §6.8 additions (Task 5), §9.4 "synthetic degradations" (Tasks 3, 5, 6) and "locator on composited backgrounds, finder centers within 2 px" (Task 4). §8 and the 150 ms target are Plan 4; the timing test in Task 6 records the data point.
- Deviations recorded: grid-size tolerance ±6 (spec says "other than 64 → unsupportedGrid"; the run-length module estimate is too noisy for exact equality); the locator adds a side/module ratio gate (40–75) beyond the spec's list; white point excludes the core center cell for all four corners (spec says "the finder whites"; the TL center is white but skipping it keeps the sampler uniform).
- Names used across tasks: `LumaPlane.{fromRgb,downscale2,bilinear,mean3x3,at}`, `CellSampler(image, grid, {luma}).sampleLuma`, `CellClassifier.bestSymbol → (int,int)`, `Homography.solve/map`, `HomographyGridModel.fromFinders`, `FinderLocator.locate → LocateResult{tl,tr,bl,br,candidates,clusters,devNorm,tlLuma,secondLuma,failReason,ok,module}`, `Finder{x,y,module}`, `WhitePoint.fromFinders`, `DriftSolver(sampler, classifier).solve → DriftField{dx,dy,widened,meanAbs,maxAbs}`, `FrameDecoder.decode(image, {grid, useDrift})`, `decodeWithGrid(image, grid, {whitePoint, useDrift, luma, diag})`, `Diagnostics.{locateRan, locateMs, candidates, clusters, corners, module, tlLuma, secondLuma, devNorm, locateFail, gridEstimate, whitePoint, driftUsed, driftMs, driftMeanAbs, driftMaxAbs, driftWidened}`, `renderScene/SceneSpec/Scene/loadGoldenFrame/loadPhoto/sceneQuad` — spelled identically in every task.
- Known risk: the locator's binarization constants and the synthetic thresholds were derived analytically, not measured; Tasks 4–6 tell the implementer to report numbers before tuning, and the controller rules on changes.
