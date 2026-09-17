# CimBar v2 — Plan 4: Decoder Performance, YUV/ROI Input, Decode Isolate, Camera Screens on v2, v1 Removal, CI and Docs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Android live scan and photo screens decode v2 barcodes through `FrameDecoder`, fast enough to keep up with a 200 ms GIF frame delay, with focus/exposure locking, an aiming guide and user hints; then delete every v1 decoder file, move CI to the real test runners, and bring the docs to the shipped state.

**Architecture:** Pure-Dart performance work first (cell sampling by corner interpolation, bounded locator scans, capped drift climb), then two additive input seams (`LumaPlane.fromYPlane`, `RgbBuffer.fromYuv420` with an ROI origin so grid coordinates stay absolute) behind `FrameDecoder.decodeYuv420`. A long-lived `DecodeIsolate` owns one `FrameDecoder` and processes `FrameJob`s; the main isolate keeps the `FrameAssembler` and a pure `CapturePolicy` state machine (lock focus/exposure after the first located frame, unlock after 2 s without one, hints from module size and corner motion). `LiveScanController`/`LiveScanScreen` and the photo path are rewritten on those pieces. v1 files, the tuning config and its Settings UI are deleted; the encryption magic moves into `crypto_service.dart`. CI runs `sh tests/run_all.sh` for Flutter (with the corpus table) and the web suite.

**Tech Stack:** Dart 3, Flutter 3.24+, `camera` ^0.11 (CameraX), Riverpod StateNotifier pattern, `image` ^4.2, existing crypto/RS services.

**Spec:** `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` — §8 (camera acquisition), §6.9 (removed v1 behaviour), §7.2 (deletions), §9.3 (corpus capture), §9.5 (CI), §10 steps 6 and 8, §11. Plan 3's final review (ledger of `2026-09-17-v2-plan-3-camera-decode`) supplies the performance priorities and real-capture risks this plan implements.

## Global Constraints

- Everything under `android/lib/core/decode/`, `android/lib/core/format/` and `android/tool/` stays free of `package:flutter` and `package:camera`. The isolate wrapper (`lib/core/services/decode_isolate.dart`) uses `dart:isolate` only. Screens/controllers are the only Flutter code.
- Coordinates stay absolute: an ROI `RgbBuffer` carries `originX/originY` and `bilinear(x, y)` accepts absolute source coordinates; grid models, finders and diagnostics are always in full-frame pixels.
- Spec §8 behaviour: 1080p (`ResolutionPreset.veryHigh`) YUV stream; locate on the Y plane; RGB conversion only for the finder bounding box plus one module; one long-lived isolate, frames dropped before any copy while a job is in flight; focus and exposure locked after the first frame with four finders (`ok` or `rsFailed`), unlocked after 2 s without a located frame; `BoxFit.contain` preview with a static aiming square; hints: module < 6 px → move closer, module > 40 px → move back, corner motion > 10 px between consecutive located frames → hold still, located but `rsFailed` → adjust angle or lighting; progress `filled / total`; single photo via the camera plugin's `takePicture()` at `ResolutionPreset.max`.
- Hint thresholds match the locator: the locator's module floor is 3 downscaled px = 6 full-res px per cell, so "move closer" fires below 6 px (not the spec's 5).
- Performance target (spec §8): `FrameDecoder.decodeYuv420` ≤ 150 ms for a 1080p frame on a mid-range 2022 phone. This cannot be asserted on desktop; the benchmark test asserts a loose desktop bound and prints the stage timings; the on-device number is recorded by the user (§10 step 7).
- Delete list (spec §7.2): `camera_decode_pipeline.dart`, `frame_locator.dart`, `symbol_hash_detector.dart`, `image_preprocessing.dart`, `perspective_transform.dart`, `frame_decode_isolate.dart`, `live_scanner.dart`, `cimbar_decoder.dart`, `yuv_converter.dart` (replaced by `RgbBuffer.fromYuv420`), `cimbar_constants.dart` (magic and PBKDF2 iterations move to `crypto_service.dart`), `decode_tuning_config.dart`, `decode_tuning_provider.dart`, the tuning UI in `settings_screen.dart`, `test/test_utils/cimbar_encoder.dart`, `test/test_utils/generate_test_gif.dart`, and the v1 tests `cimbar_decoder_test.dart`, `frame_locator_test.dart`, `live_scanner_test.dart`, `perspective_transform_test.dart`, `image_preprocessing_test.dart`, `camera_decode_integration_test.dart`, `yuv_converter_test.dart`. `crypto_service_test.dart`, `galois_field_test.dart`, `reed_solomon_test.dart` stay. `BarcodeRect` and `barcode_overlay_painter.dart` stay.
- Tests run from `android/`: `sh tests/run_all.sh` (never bare `flutter test`). `flutter analyze` must be clean over `lib/`, `tool/`, `test/` after Task 7 (the only pre-existing issues are in files this plan deletes or the UI files it rewrites).
- Commit after every task; message ends with the two lines:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi`

---

## File map

| Path (under `android/`) | Responsibility |
|---|---|
| `lib/core/decode/rgb_buffer.dart` | + `originX/originY`, `fromYuv420(...)` ROI conversion |
| `lib/core/decode/luma_plane.dart` | + `originX/originY`, `fromYPlane`, `crop` |
| `lib/core/decode/cell_sampler.dart` | corner-interpolated sampling (4 grid evaluations per cell) |
| `lib/core/decode/finder_locator.dart` | row stride 2, bounded column scans, origin-aware output |
| `lib/core/decode/drift_solver.dart` | hill-climb capped at 3 steps |
| `lib/core/decode/frame_decoder.dart` | `decodeYuv420(YuvFrame, {useDrift, hint})`, shared `_decodeLocated` |
| `lib/core/decode/yuv_frame.dart` | `YuvFrame`, `RoiHint` value types |
| `lib/core/services/decode_isolate.dart` | `DecodeIsolate`, `FrameJob`, `FrameOutcome` |
| `lib/core/services/capture_policy.dart` | `CapturePolicy`, `ScanHint`, `LockAction` |
| `lib/core/services/crypto_service.dart` | owns `magic` and `pbkdf2Iterations` |
| `lib/core/providers/debug_mode_provider.dart` | replaces the tuning provider (debug toggle only) |
| `lib/features/camera/live_scan_controller.dart`, `live_scan_screen.dart` | rewritten on v2 |
| `lib/features/camera/photo_capture_screen.dart` | in-app still capture via `takePicture()` |
| `lib/features/camera/camera_controller.dart`, `camera_screen.dart` | photo path on v2 |
| `lib/features/settings/settings_screen.dart` | tuning section → debug toggle |
| `lib/l10n/app_*.arb` | hint/aim strings (English in all five files; translations may repeat English) |
| `test/test_utils/synthetic_scene.dart` | + `rgbToYuv420(RgbBuffer, {semiPlanar})` |
| `test/core/decode/{benchmark,yuv_decode}_test.dart`, `test/core/services/{decode_isolate,capture_policy}_test.dart` | new tests |
| `.github/workflows/ci.yml` | Flutter runner + web job |
| `android/CLAUDE.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, spec status | docs |

Dependency order: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8. (T5 and T6 touch disjoint files but T6's controller imports T4's types; run them sequentially unless a worktree per task is used.)

Helper for tests: `String repoPath(String rel) => '../$rel';`

---

### Task 1: ROI-aware buffers and corner-interpolated cell sampling

**Files:**
- Modify: `lib/core/decode/rgb_buffer.dart`, `lib/core/decode/luma_plane.dart`, `lib/core/decode/cell_sampler.dart`
- Create: `lib/core/decode/yuv_frame.dart`
- Modify: `test/test_utils/synthetic_scene.dart` (+ `rgbToYuv420`)
- Test: `test/core/decode/roi_buffers_test.dart`; existing decode tests must stay green (sampling change must be exact on golden frames).

**Interfaces:**
- `class YuvFrame { final Uint8List yPlane, uPlane, vPlane; final int width, height, yRowStride, uvRowStride, uvPixelStride; const YuvFrame({...}); }`
- `class RoiHint { final int x, y, w, h; const RoiHint(this.x, this.y, this.w, this.h); }`
- `RgbBuffer(width, height, rgb, {int originX = 0, int originY = 0})`; `bilinear(x, y, out, off)` takes absolute coordinates (subtracts the origin, then clamps to the buffer); `r/g/b(x, y)` stay buffer-local; `factory RgbBuffer.fromYuv420(YuvFrame f, {int x0 = 0, int y0 = 0, int? w, int? h})` converts the clamped ROI with integer BT.601 and sets the origin.
- `LumaPlane(width, height, luma, {originX = 0, originY = 0})`; `factory LumaPlane.fromYPlane(Uint8List y, {required int width, required int height, required int rowStride})`; `LumaPlane crop(int x0, int y0, int w, int h)` (clamped; origin = absolute offset); `bilinear` and `mean3x3` take absolute coordinates for a cropped/offset plane? — **No**: to keep the locator simple, `LumaPlane` stays buffer-local for `at/mean3x3/downscale2`, but `bilinear(x, y)` is absolute (subtracts origin) because the cell sampler reads it through the grid model. Document this on both methods.
- `CellSampler.sample/sampleLuma`: per cell compute the four tile-region corners `toSource(col, row)`, `toSource(col + 8/9, row)`, `toSource(col, row + 8/9)`, `toSource(col + 8/9, row + 8/9)` once, then bilinearly interpolate the 64 sample positions with `u = (i + 0.5)/8`, `v = (j + 0.5)/8`. Exact for affine models; the projective error over 9 px is far below the 0.5 px bilinear resolution.
- Test util: `YuvFrame rgbToYuv420(RgbBuffer src, {bool semiPlanar = false, int yPad = 0})` — BT.601 forward conversion, chroma by 2×2 average; `semiPlanar` produces interleaved U/V with `uvPixelStride = 2` (NV21-style planes as the camera plugin exposes them: `uPlane` starts at U, `vPlane` starts at V, both with stride 2); `yPad` adds row padding to exercise `yRowStride > width`.

- [ ] **Step 1: Write the failing test**

`test/core/decode/roi_buffers_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/luma_plane.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/decode/yuv_frame.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final frame = loadGoldenFrame('hello', 0);
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));

  test('rgbToYuv420 round-trips within ±3 through fromYuv420 (planar and semi-planar, padded)', () {
    for (final semi in [false, true]) {
      final yuv = rgbToYuv420(frame, semiPlanar: semi, yPad: 16);
      expect(yuv.yRowStride, frame.width + 16);
      final back = RgbBuffer.fromYuv420(yuv);
      expect(back.width, frame.width);
      var maxErr = 0;
      for (var i = 0; i < back.rgb.length; i++) {
        final e = (back.rgb[i] - frame.rgb[i]).abs();
        if (e > maxErr) maxErr = e;
      }
      expect(maxErr, lessThanOrEqualTo(3), reason: 'semiPlanar=$semi maxErr=$maxErr');
    }
  });

  test('ROI conversion carries an origin and bilinear reads absolute coordinates', () {
    final yuv = rgbToYuv420(frame);
    final roi = RgbBuffer.fromYuv420(yuv, x0: 100, y0: 50, w: 200, h: 120);
    expect(roi.width, 200);
    expect(roi.originX, 100);
    expect(roi.originY, 50);
    final out = Float32List(3);
    roi.bilinear(100 + 10.5, 50 + 20.5, out, 0);
    expect(out[0], closeTo(frame.r(110, 70), 3));
    expect(out[1], closeTo(frame.g(110, 70), 3));
    // ROI clamps at the frame edge
    final edge = RgbBuffer.fromYuv420(yuv, x0: 600, y0: 600, w: 100, h: 100);
    expect(edge.width, 8);
    expect(edge.height, 8);
  });

  test('LumaPlane.fromYPlane honours rowStride; crop keeps an origin; bilinear is absolute', () {
    final yuv = rgbToYuv420(frame, yPad: 8);
    final l = LumaPlane.fromYPlane(yuv.yPlane, width: yuv.width, height: yuv.height, rowStride: yuv.yRowStride);
    expect(l.width, frame.width);
    expect(l.at(16, 16), greaterThan(240)); // TL finder outer ring
    final c = l.crop(10, 20, 100, 50);
    expect(c.originX, 10);
    expect(c.at(6, 0), l.at(16, 20));
    expect(c.bilinear(16.5, 20.5), closeTo(l.bilinear(16.5, 20.5), 1e-6));
  });

  test('corner-interpolated sampling stays exact on a golden frame (RGB and luma)', () {
    final r = FrameDecoder().decodeExact(frame);
    expect(r.status, DecodeStatus.ok);
    expect(r.diag.hammingMax, 0);
    expect(r.cells, golden.frames[0].cells);
    final luma = LumaPlane.fromRgb(frame);
    final s = CellSampler(frame, const ExactGridModel(), luma: luma);
    final a = Float32List(64);
    s.sampleLuma(8, 0, a);
    final p = CellPatch();
    s.sample(8, 0, p);
    for (var i = 0; i < 64; i++) {
      expect((a[i] - p.luma[i]).abs(), lessThan(2));
    }
  });

  test('decoding through an ROI buffer equals decoding the full buffer', () {
    final scene = renderScene(frame, 900, 900, SceneSpec()..centerX = 450..centerY = 450..scale = 1.2);
    final yuv = rgbToYuv420(scene.image);
    final full = FrameDecoder().decode(RgbBuffer.fromYuv420(yuv), useDrift: false);
    expect(full.status, DecodeStatus.ok, reason: '${full.diag.toMap()}');
    // ROI = finder bbox ± 20 px, decoded with the same grid model the full decode found
    final c = full.diag.corners!;
    final xs = [c[0], c[2], c[4], c[6]], ys = [c[1], c[3], c[5], c[7]];
    final x0 = xs.reduce((a, b) => a < b ? a : b).floor() - 20, y0 = ys.reduce((a, b) => a < b ? a : b).floor() - 20;
    final x1 = xs.reduce((a, b) => a > b ? a : b).ceil() + 20, y1 = ys.reduce((a, b) => a > b ? a : b).ceil() + 20;
    final roi = RgbBuffer.fromYuv420(yuv, x0: x0, y0: y0, w: x1 - x0, h: y1 - y0);
    final gm = HomographyGridModelFromDiag.build(c)!;
    final viaRoi = FrameDecoder().decodeWithGrid(roi, gm, useDrift: false, luma: LumaPlane.fromYPlane(yuv.yPlane, width: yuv.width, height: yuv.height, rowStride: yuv.yRowStride));
    expect(viaRoi.status, DecodeStatus.ok, reason: '${viaRoi.diag.toMap()}');
    expect(viaRoi.data, full.data);
  });
}
```

Add at the bottom of the test file:

```dart
/// Test helper: rebuild the grid model from the corners a decode reported.
class HomographyGridModelFromDiag {
  static GridModel? build(Float64List c) => HomographyGridModel.fromFinders(
        tl: (c[0], c[1]), tr: (c[2], c[3]), bl: (c[4], c[5]), br: (c[6], c[7]),
      );
}
```
with `import 'package:cimbar_scanner/core/decode/homography.dart';` at the top.

- [ ] **Step 2: Run to verify failure** — `cd android && flutter test test/core/decode/roi_buffers_test.dart 2>&1 | tail -5` → compile errors (`yuv_frame.dart`, `rgbToYuv420`, `originX`).

- [ ] **Step 3: yuv_frame.dart**

```dart
import 'dart:typed_data';

/// A camera frame in Android YUV_420_888 layout, as the camera plugin exposes it:
/// Y plane with [yRowStride]; U and V planes with [uvRowStride] and
/// [uvPixelStride] (1 = planar, 2 = interleaved/semi-planar).
class YuvFrame {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;

  const YuvFrame({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });
}

/// A region (absolute pixels) where the barcode was last seen.
class RoiHint {
  final int x;
  final int y;
  final int w;
  final int h;
  const RoiHint(this.x, this.y, this.w, this.h);
}
```

- [ ] **Step 4: rgb_buffer.dart changes**

Replace the class header, constructor and `bilinear`, and add `fromYuv420`:

```dart
/// Flat 8-bit RGB buffer with bilinear sampling. May cover only a region of a
/// larger source frame: [originX]/[originY] are the buffer's absolute position,
/// and [bilinear] takes ABSOLUTE source coordinates (pixel k covers [k, k+1),
/// center at k + 0.5). [r]/[g]/[b] index the buffer itself (local coordinates).
class RgbBuffer {
  final int width;
  final int height;
  final Uint8List rgb; // width * height * 3
  final int originX;
  final int originY;

  RgbBuffer(this.width, this.height, this.rgb, {this.originX = 0, this.originY = 0}) {
    if (rgb.length != width * height * 3) {
      throw ArgumentError('rgb length ${rgb.length} != $width*$height*3');
    }
  }

  /// Convert a region of a YUV_420_888 frame (BT.601, integer math). The
  /// region is clamped to the frame; the result records its origin.
  factory RgbBuffer.fromYuv420(YuvFrame f, {int x0 = 0, int y0 = 0, int? w, int? h}) {
    final rx0 = x0.clamp(0, f.width - 1), ry0 = y0.clamp(0, f.height - 1);
    final rx1 = (x0 + (w ?? f.width)).clamp(rx0 + 1, f.width);
    final ry1 = (y0 + (h ?? f.height)).clamp(ry0 + 1, f.height);
    final rw = rx1 - rx0, rh = ry1 - ry0;
    final out = Uint8List(rw * rh * 3);
    var o = 0;
    for (var y = ry0; y < ry1; y++) {
      final yRow = y * f.yRowStride;
      final uvRow = (y >> 1) * f.uvRowStride;
      for (var x = rx0; x < rx1; x++) {
        final yv = f.yPlane[yRow + x];
        final uvIdx = uvRow + (x >> 1) * f.uvPixelStride;
        final u = f.uPlane[uvIdx] - 128, v = f.vPlane[uvIdx] - 128;
        final r = yv + ((359 * v) >> 8);
        final g = yv - ((88 * u + 183 * v) >> 8);
        final b = yv + ((454 * u) >> 8);
        out[o++] = r < 0 ? 0 : (r > 255 ? 255 : r);
        out[o++] = g < 0 ? 0 : (g > 255 ? 255 : g);
        out[o++] = b < 0 ? 0 : (b > 255 ? 255 : b);
      }
    }
    return RgbBuffer(rw, rh, out, originX: rx0, originY: ry0);
  }
```
Add `import 'yuv_frame.dart';`. In `bilinear`, change the first line to `final fx = x - originX - 0.5, fy = y - originY - 0.5;` (rest unchanged). `fromImage` is unchanged (origin 0).

- [ ] **Step 5: luma_plane.dart changes**

Add fields `final int originX; final int originY;` with constructor `LumaPlane(this.width, this.height, this.luma, {this.originX = 0, this.originY = 0})`, and:

```dart
  /// Copy a Y plane whose rows may be padded ([rowStride] >= [width]).
  factory LumaPlane.fromYPlane(Uint8List y, {required int width, required int height, required int rowStride}) {
    if (rowStride == width) return LumaPlane(width, height, Uint8List.sublistView(y, 0, width * height));
    final out = Uint8List(width * height);
    for (var r = 0; r < height; r++) {
      out.setRange(r * width, (r + 1) * width, y, r * rowStride);
    }
    return LumaPlane(width, height, out);
  }

  /// Sub-plane (clamped) whose origin is the absolute offset of its (0,0).
  LumaPlane crop(int x0, int y0, int w, int h) {
    final cx0 = x0.clamp(0, width - 1), cy0 = y0.clamp(0, height - 1);
    final cx1 = (x0 + w).clamp(cx0 + 1, width), cy1 = (y0 + h).clamp(cy0 + 1, height);
    final cw = cx1 - cx0, ch = cy1 - cy0;
    final out = Uint8List(cw * ch);
    for (var r = 0; r < ch; r++) {
      out.setRange(r * cw, (r + 1) * cw, luma, (cy0 + r) * width + cx0);
    }
    return LumaPlane(cw, ch, out, originX: originX + cx0, originY: originY + cy0);
  }
```
In `bilinear`, use `final fx = x - originX - 0.5, fy = y - originY - 0.5;`. Note `Uint8List.sublistView` shares the caller's bytes: `fromYPlane` documents that the Y plane must outlive the plane (true for our copies). `at`, `mean3x3`, `downscale2` stay local; `downscale2` propagates `originX ~/ 2`? — **No**: the locator only ever downscales an origin-0 or cropped plane it then treats locally, and Task 3 adds the crop offset back itself. Keep `downscale2` origin 0 and say so in its doc comment.

- [ ] **Step 6: cell_sampler.dart — corner interpolation**

Replace both loops with a shared corner computation:

```dart
  final Float64List _corners = Float64List(8); // x00,y00,x10,y10,x01,y01,x11,y11

  void _cellCorners(int col, int row) {
    const t = CimbarSpec.cellPx / CimbarSpec.pitchPx; // tile extent in cell units (8/9)
    final (x00, y00) = grid.toSource(col.toDouble(), row.toDouble());
    final (x10, y10) = grid.toSource(col + t, row.toDouble());
    final (x01, y01) = grid.toSource(col.toDouble(), row + t);
    final (x11, y11) = grid.toSource(col + t, row + t);
    _corners[0] = x00; _corners[1] = y00; _corners[2] = x10; _corners[3] = y10;
    _corners[4] = x01; _corners[5] = y01; _corners[6] = x11; _corners[7] = y11;
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
```
(Check: tile pixel `i` center was at cell coordinate `col + (i + 0.5)/9`; with corners at `col` and `col + 8/9`, fraction `u = (i + 0.5)/8` gives `col + (8/9)·(i + 0.5)/8 = col + (i + 0.5)/9`. Identical for affine grids.)

- [ ] **Step 7: rgbToYuv420 in synthetic_scene.dart**

```dart
/// Forward BT.601 conversion to YUV_420_888 planes (chroma = 2x2 average).
/// [semiPlanar] interleaves U/V (uvPixelStride 2) as CameraX exposes NV21-like
/// buffers; [yPad] adds row padding so yRowStride > width.
YuvFrame rgbToYuv420(RgbBuffer src, {bool semiPlanar = false, int yPad = 0}) {
  final w = src.width, h = src.height, stride = w + yPad;
  final y = Uint8List(stride * h);
  final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2;
  final uvStride = semiPlanar ? cw * 2 : cw;
  final u = Uint8List(uvStride * ch), v = Uint8List(uvStride * ch);
  for (var yy = 0; yy < h; yy++) {
    for (var x = 0; x < w; x++) {
      final i = (yy * w + x) * 3;
      final r = src.rgb[i], g = src.rgb[i + 1], b = src.rgb[i + 2];
      y[yy * stride + x] = ((77 * r + 150 * g + 29 * b) >> 8).clamp(0, 255);
    }
  }
  for (var cy = 0; cy < ch; cy++) {
    for (var cx = 0; cx < cw; cx++) {
      var rs = 0, gs = 0, bs = 0, n = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final px = cx * 2 + dx, py = cy * 2 + dy;
          if (px >= w || py >= h) continue;
          final i = (py * w + px) * 3;
          rs += src.rgb[i]; gs += src.rgb[i + 1]; bs += src.rgb[i + 2]; n++;
        }
      }
      final r = rs / n, g = gs / n, b = bs / n;
      final uu = (128 - 0.168736 * r - 0.331264 * g + 0.5 * b).round().clamp(0, 255);
      final vv = (128 + 0.5 * r - 0.418688 * g - 0.081312 * b).round().clamp(0, 255);
      final idx = cy * uvStride + cx * (semiPlanar ? 2 : 1);
      u[idx] = uu;
      v[idx] = vv;
    }
  }
  return YuvFrame(yPlane: y, uPlane: u, vPlane: v, width: w, height: h, yRowStride: stride, uvRowStride: uvStride, uvPixelStride: semiPlanar ? 2 : 1);
}
```
Add `import 'package:cimbar_scanner/core/decode/yuv_frame.dart';`.

- [ ] **Step 8: Run tests**

Run: `cd android && flutter test test/core/decode/ 2>&1 | tail -5` → all pass (the golden/scaled/camera-path suites prove the sampler change is exact; `roi_buffers_test` adds 5). Run: `flutter analyze lib/core test/core test/test_utils` → no new issues.

- [ ] **Step 9: Commit**

```bash
git add android/lib/core/decode/yuv_frame.dart android/lib/core/decode/rgb_buffer.dart android/lib/core/decode/luma_plane.dart android/lib/core/decode/cell_sampler.dart android/test/test_utils/synthetic_scene.dart android/test/core/decode/roi_buffers_test.dart
git commit -m "Add YUV/ROI input buffers and corner-interpolated cell sampling

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 2: Locator and drift performance, benchmark test

**Files:**
- Modify: `lib/core/decode/finder_locator.dart`, `lib/core/decode/drift_solver.dart`
- Test: `test/core/decode/benchmark_test.dart`

**Changes:**
- Locator: scan every second row (`y += 2`) — the core band is ≥ 3 modules ≥ 9 downscaled px tall, so ≥ 2 hits per finder remain; bound the initial column-extent scan to `[y − 7m, y + 7m]` instead of the full height; return finder coordinates offset by the plane's `originX/originY` (`Finder(c.x * scale + full.originX, c.y * scale + full.originY, …)`); use `full.mean3x3` in local coordinates as before (compute the local center before adding the origin).
- Drift: cap the hill-climb at 3 iterations (`iter < 3`), measured `driftMaxAbs` ≤ 2.1 on real geometry.

- [ ] **Step 1: Benchmark test**

`test/core/decode/benchmark_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  test('1080p-class scene: stage timings printed, loose desktop bound', () {
    final frame = loadGoldenFrame('lorem_12k', 3);
    final truth = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json')).frames[3].data;
    // 1280x960 scene, barcode ~850 px wide (scale 1.4), 15° rotation, mild keystone
    final scene = renderScene(frame, 1280, 960, SceneSpec()..scale = 1.4..rotationDeg = 15..keystone = 0.05..centerX = 640..centerY = 480);
    final yuv = rgbToYuv420(scene.image, semiPlanar: true);
    final decoder = FrameDecoder();
    // warm-up
    decoder.decode(RgbBuffer.fromYuv420(yuv));
    final sw = Stopwatch()..start();
    final r = decoder.decode(RgbBuffer.fromYuv420(yuv));
    final total = sw.elapsedMilliseconds;
    expect(r.status, DecodeStatus.ok, reason: '${r.diag.toMap()}');
    expect(r.data, truth);
    final d = r.diag.toMap();
    final line = 'benchmark totalMs=$total locateMs=${d['locateMs']} sampleMs=${d['sampleMs']} driftMs=${d['driftMs']} rsMs=${d['rsMs']}';
    stdout.writeln(line);
    Directory('build').createSync(recursive: true);
    File('build/benchmark.txt').writeAsStringSync('$line\n');
    // Loose desktop JIT bound: catches order-of-magnitude regressions only.
    expect(total, lessThan(1500), reason: line);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
```

- [ ] **Step 2: Run before changes** — `cd android && flutter test test/core/decode/benchmark_test.dart 2>&1 | grep -E 'benchmark|passed|failed'`; record the line in your report (this is the "before").

- [ ] **Step 3: Locator edits**

In `locate()`: change `for (var y = 0; y < h; y++)` to `for (var y = 0; y < h; y += 2)`; change the per-hit column scan `final col = _colRuns(bin, w, cx.floor().clamp(0, w - 1), 0, h);` to
```dart
        final cy0 = math.max(0, (y - 7 * m).floor()), cy1 = math.min(h, (y + 7 * m).ceil());
        final col = _colRuns(bin, w, cx.floor().clamp(0, w - 1), cy0, cy1);
```
(`_anchoredExtent` positions are absolute plane rows because `_colRuns` records absolute `start`s.) In `_refine`, bound the column scan the same way around `yi` with `7 * mod`. At the end of `locate()`, apply the plane origin: build `pts` as `Finder(c.x * scale, c.y * scale, c.m * scale)` for the luma lookup, and in the final `fix` closure return `Finder(f.x + full.originX, f.y + full.originY, f.module * cosF)`.

- [ ] **Step 4: Drift edit** — `for (var iter = 0; iter < 3; iter++)` with the comment updated ("max 3 steps; measured drift ≤ 2.1 px").

- [ ] **Step 5: Run everything**

Run: `cd android && flutter test test/core/decode/ 2>&1 | tail -5` → all pass; note the benchmark line after the changes in your report (before/after). Run `flutter analyze lib/core test/core` → clean.

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/decode/finder_locator.dart android/lib/core/decode/drift_solver.dart android/test/core/decode/benchmark_test.dart
git commit -m "Locator row stride and bounded column scans, capped drift climb, benchmark test

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 3: `FrameDecoder.decodeYuv420` with ROI conversion and a search hint

**Files:**
- Modify: `lib/core/decode/frame_decoder.dart`, `lib/core/decode/diagnostics.dart` (+ `roiMs`, `roi` key)
- Test: `test/core/decode/yuv_decode_test.dart`

**Interfaces:**
- `FrameResult decodeYuv420(YuvFrame f, {bool useDrift = true, RoiHint? hint})` — Y plane → `LumaPlane.fromYPlane`; if `hint` is given, locate first on `luma.crop` of the hint expanded by 25 % per side, falling back to the full plane; then the shared located path: grid model, grid check, ROI = finder bbox ± 1.5 module (clamped) converted with `RgbBuffer.fromYuv420`, white point on the ROI, `decodeWithGrid(roi, gm, whitePoint, useDrift, luma: fullLuma, diag)`.
- `decode(RgbBuffer)` keeps its behaviour by calling the same shared `_decodeLocated(image-or-roi provider)`.
- `Diagnostics`: `int roiMs`, `List<int>? roi` (x,y,w,h) → keys `roiMs`, `roi` ("x,y,w,h") when `locateRan`.

- [ ] **Step 1: Test**

`test/core/decode/yuv_decode_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/yuv_frame.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final frame = loadGoldenFrame('lorem_12k', 1);
  final truth = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json')).frames[1].data;
  final scene = renderScene(frame, 1280, 720, SceneSpec()..scale = 1.0..rotationDeg = 8..centerX = 700..centerY = 360);

  test('decodeYuv420: planar and semi-planar frames decode with an ROI', () {
    for (final semi in [false, true]) {
      final r = FrameDecoder().decodeYuv420(rgbToYuv420(scene.image, semiPlanar: semi, yPad: 32));
      expect(r.status, DecodeStatus.ok, reason: 'semi=$semi ${r.diag.toMap()}');
      expect(r.data, truth);
      final roi = r.diag.roi!;
      expect(roi[2], lessThan(1280), reason: 'ROI narrower than the frame');
      expect(roi[2], greaterThan(600));
      expect(r.diag.toMap()['roi'], isNotNull);
    }
  });

  test('a correct hint decodes; a wrong hint falls back to the full frame', () {
    final yuv = rgbToYuv420(scene.image);
    final base = FrameDecoder().decodeYuv420(yuv);
    final c = base.diag.corners!;
    final good = RoiHint((c[0] - 30).floor(), (c[1] - 30).floor(), 700, 700);
    final withGood = FrameDecoder().decodeYuv420(yuv, hint: good);
    expect(withGood.status, DecodeStatus.ok, reason: '${withGood.diag.toMap()}');
    expect(withGood.data, truth);
    expect(withGood.diag.corners![0], closeTo(c[0], 2.0));
    final bad = const RoiHint(0, 0, 200, 200);
    final withBad = FrameDecoder().decodeYuv420(yuv, hint: bad);
    expect(withBad.status, DecodeStatus.ok, reason: '${withBad.diag.toMap()}');
    expect(withBad.data, truth);
  });

  test('a frame without a barcode is notLocated', () {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_b.png');
    final r = FrameDecoder().decodeYuv420(rgbToYuv420(photo));
    expect(r.status, DecodeStatus.notLocated);
  });
}
```

- [ ] **Step 2: Run to verify failure** — compile error (`decodeYuv420`, `diag.roi`).

- [ ] **Step 3: Diagnostics** — add `int roiMs = 0; List<int>? roi;` and, inside the `if (locateRan)` map block, `'roiMs': '$roiMs', 'roi': roi == null ? '-' : roi!.join(','),`.

- [ ] **Step 4: FrameDecoder refactor**

Add imports `yuv_frame.dart`. Restructure:

```dart
  FrameResult decode(RgbBuffer image, {GridModel? grid, bool? useDrift}) {
    final drift = useDrift ?? (grid == null);
    if (grid != null) return decodeWithGrid(image, grid, useDrift: drift);
    final diag = Diagnostics()..locateRan = true;
    final luma = LumaPlane.fromRgb(image);
    final loc = _locate(luma, null, diag);
    if (loc == null) return FrameResult(status: DecodeStatus.notLocated, diag: diag..note = diag.locateFail);
    return _decodeLocated(loc, luma, diag, drift, (_) => image);
  }

  FrameResult decodeYuv420(YuvFrame f, {bool useDrift = true, RoiHint? hint}) {
    final diag = Diagnostics()..locateRan = true;
    final luma = LumaPlane.fromYPlane(f.yPlane, width: f.width, height: f.height, rowStride: f.yRowStride);
    final loc = _locate(luma, hint, diag);
    if (loc == null) return FrameResult(status: DecodeStatus.notLocated, diag: diag..note = diag.locateFail);
    return _decodeLocated(loc, luma, diag, useDrift, (roi) {
      final sw = Stopwatch()..start();
      final buf = RgbBuffer.fromYuv420(f, x0: roi[0], y0: roi[1], w: roi[2], h: roi[3]);
      diag.roiMs = sw.elapsedMilliseconds;
      return buf;
    });
  }

  /// Locate on [luma]; with a [hint], try the expanded hint region first.
  LocateResult? _locate(LumaPlane luma, RoiHint? hint, Diagnostics diag) {
    final sw = Stopwatch()..start();
    LocateResult loc;
    if (hint != null) {
      final ex = (hint.w * 0.25).round(), ey = (hint.h * 0.25).round();
      final sub = luma.crop(hint.x - ex, hint.y - ey, hint.w + 2 * ex, hint.h + 2 * ey);
      loc = locator.locate(sub);
      if (!loc.ok) loc = locator.locate(luma);
    } else {
      loc = locator.locate(luma);
    }
    diag.locateMs = sw.elapsedMilliseconds;
    diag.candidates = loc.candidates;
    diag.clusters = loc.clusters;
    diag.devNorm = loc.devNorm;
    diag.tlLuma = loc.tlLuma;
    diag.secondLuma = loc.secondLuma;
    if (!loc.ok) {
      diag.locateFail = loc.failReason;
      return null;
    }
    return loc;
  }

  FrameResult _decodeLocated(LocateResult loc, LumaPlane luma, Diagnostics diag, bool useDrift, RgbBuffer Function(List<int> roi) rgbFor) {
    final tl = loc.tl!, tr = loc.tr!, bl = loc.bl!, br = loc.br!;
    diag.corners = Float64List.fromList([tl.x, tl.y, tr.x, tr.y, bl.x, bl.y, br.x, br.y]);
    diag.module = loc.module;
    final gm = HomographyGridModel.fromFinders(tl: (tl.x, tl.y), tr: (tr.x, tr.y), bl: (bl.x, bl.y), br: (br.x, br.y));
    if (gm == null) {
      diag.locateFail = 'homography singular';
      return FrameResult(status: DecodeStatus.notLocated, diag: diag..note = diag.locateFail);
    }
    final side = (_dist(tl, tr) + _dist(bl, br) + _dist(tl, bl) + _dist(tr, br)) / 4;
    final estimate = (side / loc.module).round() + CimbarSpec.finderCells;
    diag.gridEstimate = estimate;
    if ((estimate - CimbarSpec.gridCells).abs() > gridTolerance) {
      return FrameResult(status: DecodeStatus.unsupportedGrid, diag: diag..note = 'grid estimate $estimate cells (supported: ${CimbarSpec.gridCells} ± $gridTolerance)');
    }
    // ROI: finder bbox ± 1.5 modules — the finders sit 3.5 cells inside the grid edge,
    // so 1.5 modules of margin does not reach the outermost cells; use 4.5 modules
    // (3.5 cells to the grid edge + 1 for safety).
    final margin = (loc.module * 4.5).ceil();
    final xs = [tl.x, tr.x, bl.x, br.x], ys = [tl.y, tr.y, bl.y, br.y];
    final x0 = xs.reduce(math.min).floor() - margin, y0 = ys.reduce(math.min).floor() - margin;
    final x1 = xs.reduce(math.max).ceil() + margin, y1 = ys.reduce(math.max).ceil() + margin;
    final roi = [math.max(0, x0), math.max(0, y0), math.min(luma.width, x1) - math.max(0, x0), math.min(luma.height, y1) - math.max(0, y0)];
    diag.roi = roi;
    final image = rgbFor(roi);
    final wp = WhitePoint.fromFinders(image, gm);
    diag.whitePoint = wp;
    return decodeWithGrid(image, gm, whitePoint: wp, useDrift: useDrift, luma: luma, diag: diag);
  }
```
Keep `decodeExact` and `decodeWithGrid` as they are. Delete the old `decode` body. (The margin comment corrects spec §8's "plus one module": the finder *centers* are 3.5 cells from the grid edge, so the ROI must extend ≥ 3.5 modules beyond the outermost finder centers to include all cells; 4.5 gives one module of safety.)

- [ ] **Step 5: Run** — `flutter test test/core/decode/` all pass; `flutter analyze lib/core test/core` clean. Update the CLI (`tool/decode_image.dart`) camera branch to `decoder.decode(buffer, useDrift: useDrift)` unchanged (signature now `bool?`, still fine).

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/decode/frame_decoder.dart android/lib/core/decode/diagnostics.dart android/test/core/decode/yuv_decode_test.dart
git commit -m "Add FrameDecoder.decodeYuv420 with ROI conversion and locate hint

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 4: DecodeIsolate and CapturePolicy

**Files:**
- Create: `lib/core/services/decode_isolate.dart`, `lib/core/services/capture_policy.dart`
- Test: `test/core/services/decode_isolate_test.dart`, `test/core/services/capture_policy_test.dart`

**Interfaces:**

```dart
// decode_isolate.dart
class FrameJob { final YuvFrame frame; final bool useDrift; final RoiHint? hint; final bool capture; }
class FrameOutcome {
  final DecodeStatus status; final Uint8List? data; final int blocksFailed;
  final int? fileId, seq, total; final bool? encrypted;
  final Float64List? corners; final double module; final List<int>? roi;
  final Map<String, String> diag; final int totalMs; final int width, height;
  final Uint8List? capturePng; // full-frame RGB PNG when job.capture
}
class DecodeIsolate {
  static Future<DecodeIsolate> spawn();
  bool get busy;
  Future<FrameOutcome> decode(FrameJob job); // throws StateError if busy
  void dispose();
}

// capture_policy.dart
enum ScanHint { none, moveCloser, moveBack, holdStill, adjustAngle }
enum LockAction { none, lock, unlock }
class CapturePolicy {
  CapturePolicy({double minModulePx = 6, double maxModulePx = 40, double motionPx = 10, int unlockAfterMs = 2000});
  bool get locked;
  (ScanHint, LockAction) update(FrameOutcome o, int nowMs);
  void reset();
}
```

- [ ] **Step 1: Tests**

`test/core/services/capture_policy_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/services/capture_policy.dart';
import 'package:cimbar_scanner/core/services/decode_isolate.dart';

FrameOutcome outcome(DecodeStatus s, {double module = 12, double ox = 0}) => FrameOutcome(
      status: s,
      data: null,
      blocksFailed: s == DecodeStatus.rsFailed ? 3 : 0,
      corners: s == DecodeStatus.notLocated ? null : Float64List.fromList([100 + ox, 100, 700 + ox, 100, 100 + ox, 700, 700 + ox, 700]),
      module: module,
      roi: null,
      diag: const {},
      totalMs: 10,
      width: 1280,
      height: 720,
    );

void main() {
  test('locks after the first located frame, unlocks 2 s after losing it', () {
    final p = CapturePolicy();
    expect(p.update(outcome(DecodeStatus.notLocated), 0).$2, LockAction.none);
    expect(p.update(outcome(DecodeStatus.rsFailed), 100).$2, LockAction.lock);
    expect(p.locked, isTrue);
    expect(p.update(outcome(DecodeStatus.ok), 300).$2, LockAction.none);
    expect(p.update(outcome(DecodeStatus.notLocated), 1000).$2, LockAction.none);
    expect(p.update(outcome(DecodeStatus.notLocated), 2400).$2, LockAction.unlock);
    expect(p.locked, isFalse);
  });

  test('hints from module size, motion and rsFailed', () {
    final p = CapturePolicy();
    expect(p.update(outcome(DecodeStatus.ok, module: 4), 0).$1, ScanHint.moveCloser);
    expect(p.update(outcome(DecodeStatus.ok, module: 50), 100).$1, ScanHint.moveBack);
    expect(p.update(outcome(DecodeStatus.ok, module: 12), 200).$1, ScanHint.none);
    expect(p.update(outcome(DecodeStatus.ok, module: 12, ox: 25), 300).$1, ScanHint.holdStill);
    expect(p.update(outcome(DecodeStatus.rsFailed, module: 12, ox: 25), 400).$1, ScanHint.adjustAngle);
    expect(p.update(outcome(DecodeStatus.notLocated), 500).$1, ScanHint.none);
  });
}
```

`test/core/services/decode_isolate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/services/decode_isolate.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  test('spawn, decode two frames sequentially, busy flag, dispose', () async {
    final frame = loadGoldenFrame('hello', 0);
    final truth = GoldenSidecar.load(repoPath('test-data/goldens/hello.json')).frames[0].data;
    final scene = renderScene(frame, 1280, 720, SceneSpec()..centerX = 640..centerY = 360);
    final yuv = rgbToYuv420(scene.image, semiPlanar: true);
    final iso = await DecodeIsolate.spawn();
    expect(iso.busy, isFalse);
    final f = iso.decode(FrameJob(frame: yuv, useDrift: true, capture: true));
    expect(iso.busy, isTrue);
    expect(() => iso.decode(FrameJob(frame: yuv, useDrift: true)), throwsStateError);
    final o = await f;
    expect(iso.busy, isFalse);
    expect(o.status, DecodeStatus.ok, reason: '${o.diag}');
    expect(o.data, truth);
    expect(o.seq, 0);
    expect(o.total, 1);
    expect(o.corners!.length, 8);
    expect(o.capturePng, isNotNull);
    expect(o.capturePng![0], 0x89); // PNG magic
    final o2 = await iso.decode(FrameJob(frame: yuv, useDrift: false, hint: RoiHint(o.roi![0], o.roi![1], o.roi![2], o.roi![3])));
    expect(o2.status, DecodeStatus.ok);
    iso.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
```

- [ ] **Step 2: Run to verify failure** — compile errors.

- [ ] **Step 3: capture_policy.dart**

```dart
import 'dart:typed_data';

import '../decode/diagnostics.dart';
import 'decode_isolate.dart';

enum ScanHint { none, moveCloser, moveBack, holdStill, adjustAngle }

enum LockAction { none, lock, unlock }

/// Camera acquisition policy (spec §8): lock focus/exposure once a barcode is
/// located, unlock after [unlockAfterMs] without one; derive a user hint from
/// the finder module size, corner motion and the decode status.
class CapturePolicy {
  final double minModulePx;
  final double maxModulePx;
  final double motionPx;
  final int unlockAfterMs;

  bool _locked = false;
  int? _lastLocatedMs;
  Float64List? _lastCorners;

  CapturePolicy({this.minModulePx = 6, this.maxModulePx = 40, this.motionPx = 10, this.unlockAfterMs = 2000});

  bool get locked => _locked;

  void reset() {
    _locked = false;
    _lastLocatedMs = null;
    _lastCorners = null;
  }

  (ScanHint, LockAction) update(FrameOutcome o, int nowMs) {
    final located = o.corners != null && (o.status == DecodeStatus.ok || o.status == DecodeStatus.rsFailed || o.status == DecodeStatus.badHeader || o.status == DecodeStatus.unsupportedGrid);
    var action = LockAction.none;
    var hint = ScanHint.none;
    if (located) {
      _lastLocatedMs = nowMs;
      if (!_locked) {
        _locked = true;
        action = LockAction.lock;
      }
      if (o.module < minModulePx) {
        hint = ScanHint.moveCloser;
      } else if (o.module > maxModulePx) {
        hint = ScanHint.moveBack;
      } else if (_lastCorners != null && _motion(_lastCorners!, o.corners!) > motionPx) {
        hint = ScanHint.holdStill;
      } else if (o.status == DecodeStatus.rsFailed) {
        hint = ScanHint.adjustAngle;
      }
      _lastCorners = o.corners;
    } else {
      _lastCorners = null;
      if (_locked && _lastLocatedMs != null && nowMs - _lastLocatedMs! >= unlockAfterMs) {
        _locked = false;
        action = LockAction.unlock;
      }
    }
    return (hint, action);
  }

  static double _motion(Float64List a, Float64List b) {
    var worst = 0.0;
    for (var i = 0; i < 8; i += 2) {
      final dx = a[i] - b[i], dy = a[i + 1] - b[i + 1];
      final d = dx * dx + dy * dy;
      if (d > worst) worst = d;
    }
    return worst == 0 ? 0 : math.sqrt(worst);
  }
}
```
Add `import 'dart:math' as math;`. Note the order: `holdStill` is checked before `adjustAngle` — in the test the 4th call moves corners by 25 px with status ok (holdStill), and the 5th call has the same corners as the 4th (no motion) with rsFailed → adjustAngle.

- [ ] **Step 4: decode_isolate.dart**

```dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_decoder.dart';
import '../decode/rgb_buffer.dart';
import '../decode/yuv_frame.dart';

/// One camera frame to decode.
class FrameJob {
  final YuvFrame frame;
  final bool useDrift;
  final RoiHint? hint;
  final bool capture;
  const FrameJob({required this.frame, this.useDrift = true, this.hint, this.capture = false});
}

/// Everything the UI and assembler need from one decoded frame.
class FrameOutcome {
  final DecodeStatus status;
  final Uint8List? data;
  final int blocksFailed;
  final int? fileId;
  final int? seq;
  final int? total;
  final bool? encrypted;
  final Float64List? corners;
  final double module;
  final List<int>? roi;
  final Map<String, String> diag;
  final int totalMs;
  final int width;
  final int height;
  final Uint8List? capturePng;

  const FrameOutcome({
    required this.status,
    required this.data,
    required this.blocksFailed,
    this.fileId,
    this.seq,
    this.total,
    this.encrypted,
    required this.corners,
    required this.module,
    required this.roi,
    required this.diag,
    required this.totalMs,
    required this.width,
    required this.height,
    this.capturePng,
  });

  bool get located => corners != null;
}

/// Runs [FrameDecoder.decodeYuv420] in one long-lived background isolate.
/// One job at a time: callers drop frames while [busy].
class DecodeIsolate {
  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  Completer<FrameOutcome>? _pending;

  DecodeIsolate._(this._isolate, this._toWorker, this._fromWorker) {
    _fromWorker.listen((msg) {
      final p = _pending;
      _pending = null;
      if (p == null) return;
      if (msg is FrameOutcome) {
        p.complete(msg);
      } else {
        p.completeError(StateError('decode isolate error: $msg'));
      }
    });
  }

  static Future<DecodeIsolate> spawn() async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(_worker, handshake.sendPort);
    final toWorker = await handshake.first as SendPort;
    handshake.close();
    final fromWorker = ReceivePort();
    toWorker.send(fromWorker.sendPort);
    return DecodeIsolate._(isolate, toWorker, fromWorker);
  }

  bool get busy => _pending != null;

  Future<FrameOutcome> decode(FrameJob job) {
    if (_pending != null) throw StateError('DecodeIsolate is busy');
    final c = Completer<FrameOutcome>();
    _pending = c;
    _toWorker.send(job);
    return c.future;
  }

  void dispose() {
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _worker(SendPort handshake) {
    final inbox = ReceivePort();
    handshake.send(inbox.sendPort);
    SendPort? out;
    final decoder = FrameDecoder();
    inbox.listen((msg) {
      if (msg is SendPort) {
        out = msg;
        return;
      }
      if (msg is FrameJob) {
        try {
          out!.send(runJob(decoder, msg));
        } catch (e) {
          out!.send('$e');
        }
      }
    });
  }

  /// Decode one job (also used directly by tests and the photo path).
  static FrameOutcome runJob(FrameDecoder decoder, FrameJob job) {
    final sw = Stopwatch()..start();
    final r = decoder.decodeYuv420(job.frame, useDrift: job.useDrift, hint: job.hint);
    Uint8List? png;
    if (job.capture) {
      final rgb = RgbBuffer.fromYuv420(job.frame);
      final im = img.Image(width: rgb.width, height: rgb.height);
      var i = 0;
      for (var y = 0; y < rgb.height; y++) {
        for (var x = 0; x < rgb.width; x++) {
          im.setPixelRgb(x, y, rgb.rgb[i], rgb.rgb[i + 1], rgb.rgb[i + 2]);
          i += 3;
        }
      }
      png = img.encodePng(im);
    }
    final h = r.header;
    return FrameOutcome(
      status: r.status,
      data: r.data,
      blocksFailed: r.diag.rsFailed,
      fileId: h?.fileId,
      seq: h?.seq,
      total: h?.total,
      encrypted: h?.encrypted,
      corners: r.diag.corners,
      module: r.diag.module,
      roi: r.diag.roi,
      diag: r.diag.toMap(),
      totalMs: sw.elapsedMilliseconds,
      width: job.frame.width,
      height: job.frame.height,
      capturePng: png,
    );
  }
}
```

- [ ] **Step 5: Run** — both new test files pass; `flutter test test/core/` all pass; `flutter analyze lib/core test/core` clean (note `decode_isolate.dart` is under `lib/core/services/` and may import `package:image`; it must not import Flutter).

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/services/decode_isolate.dart android/lib/core/services/capture_policy.dart android/test/core/services/decode_isolate_test.dart android/test/core/services/capture_policy_test.dart
git commit -m "Add long-lived DecodeIsolate and CapturePolicy (lock/unlock, hints)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 5: Live scan on v2 (controller and screen)

**Files:**
- Rewrite: `lib/features/camera/live_scan_controller.dart`, `lib/features/camera/live_scan_screen.dart`
- Modify: `lib/l10n/app_en.arb` (+ keys below) and the other four ARB files (same keys; English text is acceptable), then `flutter gen-l10n`
- Modify: `lib/core/providers/` — create `debug_mode_provider.dart`; screens stop reading `decodeTuningProvider` (deleted in Task 7)

New l10n keys: `liveScanAim` "Fit the barcode inside the square", `hintMoveCloser` "Move closer", `hintMoveBack` "Move back", `hintHoldStill` "Hold still", `hintAdjustAngle` "Adjust angle or lighting", `liveScanIncomplete` "Missing frames: {missing}" (placeholder `missing` String), `errorMultiFrameNeedsLive` "This file spans {total} frames — use Live Scan" (placeholder `total` int).

**Controller design:**

```dart
class LiveScanState {
  final bool isScanning; final int framesAnalyzed; final int filled; final int total;
  final ScanHint hint; final Float64List? corners; final int? imageWidth, imageHeight;
  final LockAction pendingLock; // consumed by the screen: lock/unlock the camera
  final bool isDecrypting; final DecodeResult? result; final String? errorMessage;
  final bool debugEnabled; final List<String> debugLog; final String? captureStatus;
  bool get isComplete;
}
class LiveScanController extends StateNotifier<LiveScanState> {
  final FrameAssembler _assembler = FrameAssembler();
  final CapturePolicy _policy = CapturePolicy();
  DecodeIsolate? _isolate; RoiHint? _hint; bool _debugMode; bool _captureNext;
  Future<void> startScan();                 // spawns the isolate once, resets
  void stopScan(); void disposeIsolate();
  void onCameraFrame(YuvFrame f);          // returns immediately if busy or not scanning
  void consumeLockAction();                // screen acknowledges the pending lock/unlock
  Future<void> finish(String passphrase);  // assemble → strip → decrypt → parse → result
  void toggleDebug(); void captureDebugFrame(); void clearCaptureStatus(); Future<String?> saveResult();
}
```
Frame handling: `onCameraFrame` → if `!isScanning || _isolate == null || _isolate.busy` return (no copy happened yet — the screen copies planes only after asking `controller.wantsFrame`); else build `FrameJob(frame, hint: _hint, capture: _captureNext)` and await the outcome; on outcome: `_policy.update(o, now)` → hint + lock action into state; `_hint` = `RoiHint` from `o.roi` when located, else null; if `o.status == ok` → `_assembler.add(o.data!, blocksFailed: o.blocksFailed)`; state.filled/total from the assembler; when `isComplete` the screen calls `finish(passphrase)`. Debug: `debugPrint('[cimbar_scan] frame=N ' + diag lines)` when enabled; capture PNG saved to the documents dir as `capture_<ts>.png` plus `capture_<ts>.txt` containing the diag map (one `key=value` per line) — this is the corpus capture input.

**Screen changes:** `ResolutionPreset.veryHigh`; `BoxFit.contain` preview; `_onCameraImage` first asks `controller.wantsFrame` and returns without copying when false; copies planes into a `YuvFrame`; overlay = corners polygon via a new `CornersOverlayPainter` (replace the bbox painter usage: draw the quad through the same rotation/contain mapping — reuse `BarcodeOverlayPainter`'s coordinate mapping but for `BoxFit.contain` and four points); a static centered aiming square (70 % of the shorter screen side, white 2 px stroke, corner ticks); hint text under the status; progress `filled / total`; when `state.pendingLock == lock` call `setFocusMode(FocusMode.locked)` and `setExposureMode(ExposureMode.locked)` (each in try/catch), `unlock` → `FocusMode.auto`/`ExposureMode.auto`, then `controller.consumeLockAction()`; debug toggle reads `debugModeProvider`.

- [ ] **Step 1: debug_mode_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

const _key = 'tuning_debug_mode';

final debugModeProvider = StateNotifierProvider<DebugModeNotifier, bool>((ref) {
  return DebugModeNotifier(ref.watch(sharedPreferencesProvider));
});

class DebugModeNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  DebugModeNotifier(this._prefs) : super(_prefs.getBool(_key) ?? false);

  void set(bool enabled) {
    state = enabled;
    _prefs.setBool(_key, enabled);
  }
}
```
(Check `shared_preferences_provider.dart` for the provider name; adapt if it differs.)

- [ ] **Step 2: Write the controller**

`lib/features/camera/live_scan_controller.dart` (full file):

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/decode/diagnostics.dart';
import '../../core/decode/frame_assembler.dart';
import '../../core/decode/yuv_frame.dart';
import '../../core/format/file_container.dart';
import '../../core/models/decode_result.dart';
import '../../core/services/capture_policy.dart';
import '../../core/services/crypto_service.dart';
import '../../core/services/decode_isolate.dart';

final liveScanControllerProvider =
    StateNotifierProvider<LiveScanController, LiveScanState>((ref) => LiveScanController());

class LiveScanState {
  final bool isScanning;
  final int framesAnalyzed;
  final int filled;
  final int total;
  final ScanHint hint;
  final Float64List? corners;
  final int? imageWidth;
  final int? imageHeight;
  final LockAction pendingLock;
  final bool isDecrypting;
  final DecodeResult? result;
  final String? errorMessage;
  final bool debugEnabled;
  final List<String> debugLog;
  final String? captureStatus;
  final int lastFrameMs;

  const LiveScanState({
    this.isScanning = false,
    this.framesAnalyzed = 0,
    this.filled = 0,
    this.total = 0,
    this.hint = ScanHint.none,
    this.corners,
    this.imageWidth,
    this.imageHeight,
    this.pendingLock = LockAction.none,
    this.isDecrypting = false,
    this.result,
    this.errorMessage,
    this.debugEnabled = false,
    this.debugLog = const [],
    this.captureStatus,
    this.lastFrameMs = 0,
  });

  bool get isComplete => total > 0 && filled >= total;

  LiveScanState copyWith({
    bool? isScanning,
    int? framesAnalyzed,
    int? filled,
    int? total,
    ScanHint? hint,
    Float64List? corners,
    bool clearCorners = false,
    int? imageWidth,
    int? imageHeight,
    LockAction? pendingLock,
    bool? isDecrypting,
    DecodeResult? result,
    String? errorMessage,
    bool? debugEnabled,
    List<String>? debugLog,
    String? captureStatus,
    bool clearCaptureStatus = false,
    int? lastFrameMs,
  }) {
    return LiveScanState(
      isScanning: isScanning ?? this.isScanning,
      framesAnalyzed: framesAnalyzed ?? this.framesAnalyzed,
      filled: filled ?? this.filled,
      total: total ?? this.total,
      hint: hint ?? this.hint,
      corners: clearCorners ? null : (corners ?? this.corners),
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      pendingLock: pendingLock ?? this.pendingLock,
      isDecrypting: isDecrypting ?? this.isDecrypting,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      debugEnabled: debugEnabled ?? this.debugEnabled,
      debugLog: debugLog ?? this.debugLog,
      captureStatus: clearCaptureStatus ? null : (captureStatus ?? this.captureStatus),
      lastFrameMs: lastFrameMs ?? this.lastFrameMs,
    );
  }
}

class LiveScanController extends StateNotifier<LiveScanState> {
  LiveScanController() : super(const LiveScanState());

  final FrameAssembler _assembler = FrameAssembler();
  final CapturePolicy _policy = CapturePolicy();
  DecodeIsolate? _isolate;
  Future<DecodeIsolate>? _spawning;
  RoiHint? _hint;
  bool _debugMode = false;
  bool _captureNext = false;
  int _frameNum = 0;
  static const _maxDebugEntries = 50;

  void updateDebugMode(bool enabled) => _debugMode = enabled;

  /// True when a frame can be processed right now (no copy should be made otherwise).
  bool get wantsFrame => state.isScanning && _isolate != null && !_isolate!.busy;

  Future<void> startScan() async {
    _assembler.reset();
    _policy.reset();
    _hint = null;
    _frameNum = 0;
    state = LiveScanState(isScanning: true, debugEnabled: state.debugEnabled);
    _spawning ??= DecodeIsolate.spawn();
    _isolate ??= await _spawning;
  }

  void stopScan() => state = state.copyWith(isScanning: false);

  void disposeIsolate() {
    _isolate?.dispose();
    _isolate = null;
    _spawning = null;
  }

  @override
  void dispose() {
    disposeIsolate();
    super.dispose();
  }

  void toggleDebug() {
    if (!_debugMode) return;
    state = state.copyWith(debugEnabled: !state.debugEnabled);
  }

  void captureDebugFrame() => _captureNext = true;
  void clearCaptureStatus() => state = state.copyWith(clearCaptureStatus: true);
  void consumeLockAction() => state = state.copyWith(pendingLock: LockAction.none);

  void onCameraFrame(YuvFrame frame) {
    if (!wantsFrame) return;
    final capture = _captureNext;
    _captureNext = false;
    final job = FrameJob(frame: frame, useDrift: true, hint: _hint, capture: capture);
    final n = ++_frameNum;
    _isolate!.decode(job).then((o) => _onOutcome(n, o), onError: (e) => _log('frame=$n isolate error: $e'));
  }

  void _onOutcome(int n, FrameOutcome o) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final (hint, lock) = _policy.update(o, now);
    _hint = o.roi == null ? null : RoiHint(o.roi![0], o.roi![1], o.roi![2], o.roi![3]);
    var rejected = '';
    if (o.status == DecodeStatus.ok && o.data != null) {
      final added = _assembler.add(o.data!, blocksFailed: o.blocksFailed);
      if (!added.accepted) rejected = added.reason;
    }
    if (_debugMode) {
      final d = o.diag.entries.map((e) => '${e.key}=${e.value}').join(' ');
      _log('frame=$n status=${o.status.name} ms=${o.totalMs} filled=${_assembler.filled}/${_assembler.total}${rejected.isEmpty ? '' : ' rejected=$rejected'} $d');
      _overlay('#$n ${o.status.name} ${o.totalMs}ms f=${_assembler.filled}/${_assembler.total}');
    }
    if (o.capturePng != null) _saveCapture(o);
    if (!mounted) return;
    state = state.copyWith(
      framesAnalyzed: n,
      filled: _assembler.filled,
      total: _assembler.total,
      hint: hint,
      corners: o.corners,
      clearCorners: o.corners == null,
      imageWidth: o.width,
      imageHeight: o.height,
      pendingLock: lock == LockAction.none ? state.pendingLock : lock,
      lastFrameMs: o.totalMs,
    );
  }

  void _log(String msg) {
    if (!_debugMode) return;
    for (final line in msg.split('\n')) {
      if (line.isNotEmpty) debugPrint('[cimbar_scan] $line');
    }
  }

  void _overlay(String msg) {
    if (!mounted) return;
    final log = [...state.debugLog, msg];
    if (log.length > _maxDebugEntries) log.removeRange(0, log.length - _maxDebugEntries);
    state = state.copyWith(debugLog: log);
  }

  Future<void> _saveCapture(FrameOutcome o) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      await File('${dir.path}/capture_$ts.png').writeAsBytes(o.capturePng!);
      final lines = o.diag.entries.map((e) => '${e.key}=${e.value}').join('\n');
      await File('${dir.path}/capture_$ts.txt').writeAsString('status=${o.status.name}\n$lines\n');
      if (mounted) state = state.copyWith(captureStatus: 'saved');
    } catch (_) {
      if (mounted) state = state.copyWith(captureStatus: 'failed');
    }
  }

  /// Assemble, strip the length prefix, decrypt if needed, parse the file.
  Future<void> finish(String passphrase) async {
    if (!_assembler.isComplete) return;
    state = state.copyWith(isScanning: false, isDecrypting: true);
    try {
      final payload = FileContainer.stripLengthPrefix(_assembler.framedData());
      Uint8List plain;
      if (FileContainer.isEncrypted(payload)) {
        if (passphrase.isEmpty) {
          state = state.copyWith(isDecrypting: false, errorMessage: 'This file is encrypted: a passphrase is required');
          return;
        }
        plain = CryptoService.decrypt(payload, passphrase);
      } else {
        plain = payload;
      }
      final file = FileContainer.parsePayload(plain);
      final result = DecodeResult(filename: file.fileName, data: file.fileBytes);
      await _autoSave(result);
      state = state.copyWith(isDecrypting: false, result: result);
    } catch (e) {
      state = state.copyWith(isDecrypting: false, errorMessage: '$e');
    }
  }

  Future<String?> _autoSave(DecodeResult result) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${result.filename}');
      await file.writeAsBytes(result.data);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> saveResult() async {
    final r = state.result;
    return r == null ? null : _autoSave(r);
  }

  List<int> get missingSeqs => _assembler.missingSeqs();
}
```

- [ ] **Step 3: Write the screen**

`lib/features/camera/live_scan_screen.dart` (full file). Keep the existing structure (lifecycle, portrait lock, PopScope, error/searching/decrypting/result panels, triple-tap debug overlay, capture button) and change what the design requires:

```dart
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/decode/yuv_frame.dart';
import '../../core/providers/debug_mode_provider.dart';
import '../../core/services/capture_policy.dart';
import '../../core/services/file_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/corners_overlay_painter.dart';
import '../../shared/widgets/result_card.dart';
import 'live_scan_controller.dart';

class LiveScanScreen extends ConsumerStatefulWidget {
  final String passphrase;
  const LiveScanScreen({super.key, this.passphrase = ''});

  @override
  ConsumerState<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends ConsumerState<LiveScanScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _initializing = false;
  bool _disposed = false;
  String? _cameraError;
  bool _finishTriggered = false;
  int _tapCount = 0;
  DateTime _lastTapTime = DateTime(0);
  final ScrollController _debugScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveScanControllerProvider.notifier).startScan();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    _debugScrollController.dispose();
    ref.read(liveScanControllerProvider.notifier).disposeIsolate();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.stopImageStream().catchError((_) {});
      _cameraController?.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing || _disposed) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'no_camera');
        return;
      }
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(camera, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      _cameraController = controller;
      setState(() {});
      await controller.startImageStream(_onCameraImage);
    } catch (e) {
      if (mounted) setState(() => _cameraError = e.toString());
    } finally {
      _initializing = false;
    }
  }

  void _onCameraImage(CameraImage image) {
    if (_disposed || image.planes.length < 3) return;
    final controller = ref.read(liveScanControllerProvider.notifier);
    if (!controller.wantsFrame) return; // drop before copying anything
    final frame = YuvFrame(
      yPlane: Uint8List.fromList(image.planes[0].bytes),
      uPlane: Uint8List.fromList(image.planes[1].bytes),
      vPlane: Uint8List.fromList(image.planes[2].bytes),
      width: image.width,
      height: image.height,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
    controller.onCameraFrame(frame);
  }

  Future<void> _applyLock(LockAction action) async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      if (action == LockAction.lock) {
        await cam.setFocusMode(FocusMode.locked);
        await cam.setExposureMode(ExposureMode.locked);
      } else if (action == LockAction.unlock) {
        await cam.setFocusMode(FocusMode.auto);
        await cam.setExposureMode(ExposureMode.auto);
      }
    } catch (_) {
      // Some devices reject lock modes; scanning continues without them.
    }
  }

  void _onStatusTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds > 500) _tapCount = 0;
    _lastTapTime = now;
    _tapCount++;
    if (_tapCount >= 3) {
      _tapCount = 0;
      ref.read(liveScanControllerProvider.notifier).toggleDebug();
    }
  }

  String _hintText(AppLocalizations l10n, ScanHint hint) => switch (hint) {
        ScanHint.moveCloser => l10n.hintMoveCloser,
        ScanHint.moveBack => l10n.hintMoveBack,
        ScanHint.holdStill => l10n.hintHoldStill,
        ScanHint.adjustAngle => l10n.hintAdjustAngle,
        ScanHint.none => '',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scanState = ref.watch(liveScanControllerProvider);
    final controller = ref.read(liveScanControllerProvider.notifier);
    controller.updateDebugMode(ref.watch(debugModeProvider));

    if (scanState.pendingLock != LockAction.none) {
      final action = scanState.pendingLock;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.consumeLockAction();
        _applyLock(action);
      });
    }
    if (scanState.debugEnabled && scanState.debugLog.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_debugScrollController.hasClients) {
          _debugScrollController.jumpTo(_debugScrollController.position.maxScrollExtent);
        }
      });
    }
    if (scanState.captureStatus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final saved = scanState.captureStatus == 'saved';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved ? 'Frame captured to app documents' : 'Capture failed'),
          backgroundColor: saved ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ));
        controller.clearCaptureStatus();
      });
    }
    if (scanState.isComplete && !_finishTriggered && !scanState.isDecrypting && scanState.result == null && scanState.errorMessage == null) {
      _finishTriggered = true;
      _cameraController?.stopImageStream().catchError((_) {});
      Future.microtask(() => controller.finish(widget.passphrase));
    }

    final cam = _cameraController;
    final previewReady = !_disposed && cam != null && cam.value.isInitialized;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cameraController?.stopImageStream().catchError((_) {});
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (previewReady)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: cam.value.previewSize!.height,
                    height: cam.value.previewSize!.width,
                    child: CameraPreview(cam),
                  ),
                ),
              )
            else if (_cameraError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _cameraError == 'no_camera' ? l10n.noCameraAvailable : l10n.cameraPermissionDenied,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            // Aiming square + located corners
            if (previewReady)
              Positioned.fill(
                child: CustomPaint(
                  painter: CornersOverlayPainter(
                    corners: scanState.isScanning ? scanState.corners : null,
                    sourceImageWidth: scanState.imageWidth ?? cam.value.previewSize!.width.toInt(),
                    sourceImageHeight: scanState.imageHeight ?? cam.value.previewSize!.height.toInt(),
                    sensorOrientation: cam.description.sensorOrientation,
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
            if (scanState.debugEnabled)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  onPressed: controller.captureDebugFrame,
                  icon: const Icon(Icons.camera, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            if (scanState.debugEnabled && scanState.debugLog.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 180,
                child: Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                  color: Colors.black.withOpacity(0.8),
                  padding: const EdgeInsets.all(8),
                  child: ListView(
                    controller: _debugScrollController,
                    shrinkWrap: true,
                    children: [
                      for (final line in scanState.debugLog)
                        Text(line, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _onStatusTap,
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                  child: _buildStatusPanel(l10n, scanState, controller),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel(AppLocalizations l10n, LiveScanState s, LiveScanController controller) {
    if (s.result != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        ResultCard(
          result: s.result!,
          onSave: () async {
            final path = await controller.saveResult();
            if (path != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.fileSaved)));
            }
          },
          onShare: () => FileService.shareResult(s.result!),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel, style: const TextStyle(color: Colors.white70))),
      ]);
    }
    if (s.errorMessage != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, color: Colors.red.shade300, size: 40),
        const SizedBox(height: 8),
        Text(s.errorMessage!, style: TextStyle(color: Colors.red.shade300, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel, style: const TextStyle(color: Colors.white70))),
      ]);
    }
    if (s.isDecrypting) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 12),
        Text(l10n.progressDecrypting, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ]);
    }
    final hint = _hintText(l10n, s.hint);
    if (s.total > 0) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(value: s.filled / s.total, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.greenAccent)),
        const SizedBox(height: 12),
        Text(s.isComplete ? l10n.liveScanComplete : l10n.liveScanProgress(s.filled, s.total), style: const TextStyle(color: Colors.white, fontSize: 16)),
        if (hint.isNotEmpty) ...[const SizedBox(height: 4), Text(hint, style: const TextStyle(color: Colors.amberAccent, fontSize: 14))],
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: Colors.white54),
      const SizedBox(height: 12),
      Text(s.corners == null ? l10n.liveScanAim : l10n.liveScanSearching, style: const TextStyle(color: Colors.white70, fontSize: 16)),
      if (hint.isNotEmpty) ...[const SizedBox(height: 4), Text(hint, style: const TextStyle(color: Colors.amberAccent, fontSize: 14))],
      if (s.framesAnalyzed > 0) ...[
        const SizedBox(height: 4),
        Text(l10n.liveScanFramesAnalyzed(s.framesAnalyzed), style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    ]);
  }
}
```

- [ ] **Step 4: CornersOverlayPainter**

`lib/shared/widgets/corners_overlay_painter.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Draws the static aiming square and, when known, the located finder quad.
/// Maps camera-frame coordinates to the screen for a BoxFit.contain preview
/// rotated by [sensorOrientation] (landscape sensor shown in portrait).
class CornersOverlayPainter extends CustomPainter {
  final Float64List? corners; // tl,tr,bl,br as x,y pairs (frame px)
  final int sourceImageWidth;
  final int sourceImageHeight;
  final int sensorOrientation;

  CornersOverlayPainter({required this.corners, required this.sourceImageWidth, required this.sourceImageHeight, required this.sensorOrientation});

  Offset _map(double x, double y, Size size) {
    final rotated = sensorOrientation == 90 || sensorOrientation == 270;
    final rw = rotated ? sourceImageHeight.toDouble() : sourceImageWidth.toDouble();
    final rh = rotated ? sourceImageWidth.toDouble() : sourceImageHeight.toDouble();
    final scale = (size.width / rw < size.height / rh) ? size.width / rw : size.height / rh; // contain
    final ox = (size.width - rw * scale) / 2, oy = (size.height - rh * scale) / 2;
    double rx, ry;
    if (sensorOrientation == 90) {
      rx = sourceImageHeight - y;
      ry = x;
    } else if (sensorOrientation == 270) {
      rx = y;
      ry = sourceImageWidth - x;
    } else if (sensorOrientation == 180) {
      rx = sourceImageWidth - x;
      ry = sourceImageHeight - y;
    } else {
      rx = x;
      ry = y;
    }
    return Offset(ox + rx * scale, oy + ry * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Aiming square: 70% of the shorter side, centered.
    final side = (size.width < size.height ? size.width : size.height) * 0.7;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: side, height: side);
    final guide = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const tick = 28.0;
    for (final (cx, cy, sx, sy) in [
      (rect.left, rect.top, 1.0, 1.0),
      (rect.right, rect.top, -1.0, 1.0),
      (rect.left, rect.bottom, 1.0, -1.0),
      (rect.right, rect.bottom, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + sx * tick, cy), guide);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + sy * tick), guide);
    }
    final c = corners;
    if (c == null) return;
    final pts = [_map(c[0], c[1], size), _map(c[2], c[3], size), _map(c[6], c[7], size), _map(c[4], c[5], size)];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.green.withOpacity(0.15)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = Colors.greenAccent..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.drawCircle(pts[0], 6, Paint()..color = Colors.orangeAccent); // TL marker
  }

  @override
  bool shouldRepaint(CornersOverlayPainter old) =>
      old.corners != corners || old.sourceImageWidth != sourceImageWidth || old.sourceImageHeight != sourceImageHeight || old.sensorOrientation != sensorOrientation;
}
```
(The 90°/270° mappings mirror `BarcodeOverlayPainter`'s conventions for a point instead of a rect: for 90° clockwise, `(x, y) → (imgH − y, x)`; verify against that file's rect mapping and keep the same convention.)

- [ ] **Step 5: l10n**

Add the seven keys to `app_en.arb` with `@` descriptions; add the same keys with English values to `app_ru.arb`, `app_uk.arb`, `app_tr.arb`, `app_ka.arb` (a translation pass can follow); run `flutter gen-l10n`; commit the regenerated `lib/l10n/generated/*` files this time (they are tracked and must match the ARBs).

- [ ] **Step 6: Compile and analyze**

Run: `cd android && flutter gen-l10n && flutter analyze lib/features/camera lib/shared/widgets lib/core/providers 2>&1 | tail -5` → no errors (warnings in files Task 7 deletes are acceptable until then). The screen cannot be unit-tested without a device; `flutter build apk --debug` is the compile check: run it (`cd android && flutter build apk --debug 2>&1 | tail -3`) and report the result.

- [ ] **Step 7: Commit**

```bash
git add android/lib/features/camera/live_scan_controller.dart android/lib/features/camera/live_scan_screen.dart android/lib/shared/widgets/corners_overlay_painter.dart android/lib/core/providers/debug_mode_provider.dart android/lib/l10n
git commit -m "Live scan on v2: DecodeIsolate, FrameAssembler, capture policy, aiming guide and hints

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 6: Photo path on v2 with in-app capture

**Files:**
- Create: `lib/features/camera/photo_capture_screen.dart`
- Rewrite: `lib/features/camera/camera_controller.dart`; modify `lib/features/camera/camera_screen.dart` (Take Photo opens the capture screen; remove tuning wiring)
- Test: `test/core/services/photo_decode_test.dart` (pure-Dart function)

**Interfaces:**
- `lib/core/services/photo_decoder.dart`: `Future<PhotoDecodeResult> decodePhotoBytes(Uint8List imageBytes, String passphrase)` — runs in `Isolate.run`: `img.decodeImage` → `RgbBuffer.fromImage` → `FrameDecoder().decode(rgb)`; on `ok`: if header total > 1 → error `multiFrame(total)`; else assemble one frame, strip prefix, detect encryption, decrypt, parse; returns `PhotoDecodeResult { DecodeResult? result; String? error; Map<String,String> diag; int? total; }`.
- `PhotoCaptureScreen` returns `Uint8List?` bytes via `Navigator.pop`: `CameraController(camera, ResolutionPreset.max, enableAudio: false)`, `CameraPreview`, a shutter button calling `takePicture()`, reads the XFile bytes.
- `CameraController` (Riverpod) `capturePhoto()` navigates? — controllers must not navigate: the screen pushes `PhotoCaptureScreen` and passes the bytes to `controller.setPhoto(bytes)`; `pickFromGallery()` stays on `image_picker`; `decode(passphrase)` routes GIF bytes to `DecodePipeline` and anything else to `decodePhotoBytes`.

- [ ] **Step 1: Test**

`test/core/services/photo_decode_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/services/photo_decoder.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

Uint8List pngOf(scene) {
  final im = img.Image(width: scene.image.width, height: scene.image.height);
  var i = 0;
  for (var y = 0; y < scene.image.height; y++) {
    for (var x = 0; x < scene.image.width; x++) {
      im.setPixelRgb(x, y, scene.image.rgb[i], scene.image.rgb[i + 1], scene.image.rgb[i + 2]);
      i += 3;
    }
  }
  return img.encodePng(im);
}

void main() {
  test('single-frame golden photo decodes to the file', () async {
    final golden = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));
    final scene = renderScene(loadGoldenFrame('hello', 0), 1000, 1000, SceneSpec()..scale = 1.3..rotationDeg = 5..centerX = 500..centerY = 500);
    final r = await decodePhotoBytes(pngOf(scene), '');
    expect(r.error, isNull, reason: '${r.diag}');
    expect(r.result!.filename, golden.fileName);
    expect(r.result!.data, golden.fileBytes);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a frame of a multi-frame file reports multiFrame with the total', () async {
    final scene = renderScene(loadGoldenFrame('lorem_12k', 2), 1000, 1000, SceneSpec()..scale = 1.3..centerX = 500..centerY = 500);
    final r = await decodePhotoBytes(pngOf(scene), '');
    expect(r.result, isNull);
    expect(r.total, 6);
    expect(r.error, contains('6'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('no barcode → error', () async {
    final photo = loadPhoto('test/fixtures/camera_raw_1280x720_b.png');
    final r = await decodePhotoBytes(pngOf(Scene(photo, const [], Homography(Float64List(9)))), '');
    expect(r.result, isNull);
    expect(r.error, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
```
(For the third test, simplest is to add a small helper in the test that wraps an `RgbBuffer` in the `Scene` type, or change `pngOf` to take an `RgbBuffer` directly — do the latter: `Uint8List pngOf(RgbBuffer b)` and pass `scene.image` / `photo`. Add the `Homography`/`Scene` imports only if still needed; prefer the RgbBuffer form.)

- [ ] **Step 2: photo_decoder.dart**

```dart
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_assembler.dart';
import '../decode/frame_decoder.dart';
import '../decode/rgb_buffer.dart';
import '../format/file_container.dart';
import '../models/decode_result.dart';
import 'crypto_service.dart';

class PhotoDecodeResult {
  final DecodeResult? result;
  final String? error;
  final Map<String, String> diag;
  final int? total;
  const PhotoDecodeResult({this.result, this.error, this.diag = const {}, this.total});
}

/// Decode one still photo (PNG/JPEG bytes) containing a single-frame v2 barcode.
Future<PhotoDecodeResult> decodePhotoBytes(Uint8List imageBytes, String passphrase) {
  return Isolate.run(() => decodePhotoSync(imageBytes, passphrase));
}

PhotoDecodeResult decodePhotoSync(Uint8List imageBytes, String passphrase) {
  final image = img.decodeImage(imageBytes);
  if (image == null) return const PhotoDecodeResult(error: 'Cannot decode image');
  final r = FrameDecoder().decode(RgbBuffer.fromImage(image));
  final diag = r.diag.toMap();
  if (r.status != DecodeStatus.ok) {
    return PhotoDecodeResult(error: 'Barcode ${r.status.name}${r.diag.note.isEmpty ? '' : ': ${r.diag.note}'}', diag: diag);
  }
  final h = r.header!;
  if (h.total > 1) {
    return PhotoDecodeResult(error: 'This file spans ${h.total} frames — use Live Scan', diag: diag, total: h.total);
  }
  final asm = FrameAssembler();
  final added = asm.add(r.data!, blocksFailed: r.diag.rsFailed);
  if (!added.accepted) return PhotoDecodeResult(error: 'Frame rejected (${added.reason})', diag: diag);
  try {
    final payload = FileContainer.stripLengthPrefix(asm.framedData());
    Uint8List plain;
    if (FileContainer.isEncrypted(payload)) {
      if (passphrase.isEmpty) return PhotoDecodeResult(error: 'This file is encrypted: a passphrase is required', diag: diag);
      plain = CryptoService.decrypt(payload, passphrase);
    } else {
      plain = payload;
    }
    final f = FileContainer.parsePayload(plain);
    return PhotoDecodeResult(result: DecodeResult(filename: f.fileName, data: f.fileBytes), diag: diag);
  } catch (e) {
    return PhotoDecodeResult(error: '$e', diag: diag);
  }
}
```

- [ ] **Step 3: CameraController rewrite**

Replace `camera_controller.dart` contents: keep `CameraState` (drop `tuningConfig`), keep `_isGif`, `pickFromGallery`, `_autoSave`, `saveResult`, `reset`; add `void setPhoto(Uint8List bytes, {String? path})`; `decode(passphrase)`: GIF → `DecodePipeline` as today; else `final r = await decodePhotoBytes(bytes, passphrase); state = state.copyWith(isDecoding: false, result: r.result, progress: DecodeProgress(state: r.error == null ? DecodeState.done : DecodeState.error, progress: 1, message: r.error ?? 'Decoded: ${r.result!.filename}'));` and auto-save on success. Remove the `CameraDecodePipeline` and tuning imports.

- [ ] **Step 4: PhotoCaptureScreen**

```dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen still capture; pops with the JPEG bytes (or null).
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});
  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  CameraController? _controller;
  String? _error;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'no_camera');
        return;
      }
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final c = CameraController(camera, ResolutionPreset.max, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final c = _controller;
    if (c == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      if (mounted) setState(() {
        _error = '$e';
        _taking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (c != null && c.value.isInitialized)
          Positioned.fill(child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: c.value.previewSize!.height, height: c.value.previewSize!.width, child: CameraPreview(c))))
        else if (_error != null)
          Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white, size: 28), style: IconButton.styleFrom(backgroundColor: Colors.black54)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: Center(
            child: FloatingActionButton.large(
              onPressed: c == null || _taking ? null : _take,
              backgroundColor: Colors.white,
              child: _taking ? const CircularProgressIndicator() : const Icon(Icons.camera_alt, color: Colors.black, size: 36),
            ),
          ),
        ),
      ]),
    );
  }
}
```
In `camera_screen.dart`: the "Take Photo" button does `final bytes = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => const PhotoCaptureScreen())); if (bytes != null) controller.setPhoto(bytes);`; remove `controller.tuningConfig = …` and the tuning import.

- [ ] **Step 5: Run** — `flutter test test/core/services/photo_decode_test.dart` (3 pass); `flutter analyze lib/features/camera lib/core/services` → no errors; `flutter build apk --debug` compiles.

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/services/photo_decoder.dart android/lib/features/camera/photo_capture_screen.dart android/lib/features/camera/camera_controller.dart android/lib/features/camera/camera_screen.dart android/test/core/services/photo_decode_test.dart
git commit -m "Photo path on v2: in-app capture via takePicture and isolate decode

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 7: Delete v1

**Files:** per the Global Constraints delete list, plus:
- Modify: `lib/core/services/crypto_service.dart` (own `static const List<int> magic = [0xCB, 0x42, 0x01, 0x00]; static const int pbkdf2Iterations = 150000;` replacing `CimbarConstants.*`), `lib/features/settings/settings_screen.dart` (replace the Decode Tuning section with one `SwitchListTile` bound to `debugModeProvider`; keep language and about), `lib/l10n/*.arb` (remove now-unused tuning strings only if `flutter analyze`/gen-l10n do not complain about unused keys — unused ARB keys are harmless; leave them), `android/tests/run_all.sh` unchanged.
- Verify nothing else imports deleted files: `grep -rn "cimbar_constants\|decode_tuning\|frame_locator\|live_scanner\|camera_decode_pipeline\|frame_decode_isolate\|cimbar_decoder\|symbol_hash\|image_preprocessing\|perspective_transform\|yuv_converter" lib test tool` must return nothing after the deletions.

- [ ] **Step 1: Delete and fix imports** (`git rm` each file; fix `crypto_service.dart` and `settings_screen.dart`; grep as above).
- [ ] **Step 2: Full verification** — `cd android && flutter analyze` → **No issues found!** (this is the first fully clean analyze; the previously "pre-existing" issues lived in deleted files and the rewritten UI). `sh tests/run_all.sh` → all pass (expect roughly 242 − 7 v1 files' tests + the new ones); `flutter build apk --debug` compiles.
- [ ] **Step 3: Commit** — `git add -A android/lib android/test && git commit -m "Remove the v1 decoder, tuning config and v1 tests

Co-Authored-By: …
Claude-Session: …"` (with the two trailer lines in full).

---

### Task 8: CI and docs

**Files:**
- Modify: `.github/workflows/ci.yml`: Flutter job "Run tests" → `sh tests/run_all.sh` (working-directory android); add a job `web-tests` (ubuntu, `actions/setup-node@v4` with node-version 20, `working-directory: web-app`, run `sh tests/run_all.sh`); upload `android/build/corpus_report.txt` and `android/build/benchmark.txt` as artifacts.
- Docs: `android/CLAUDE.md` — replace the v1 sections ("Decoding Pipelines", "Core Services" entries for deleted files, "Live Scanning Architecture", "Isolate Architecture", "Two-Channel Debug Logging", "Camera Decode Improvements", "Design Decisions" items that reference tuning/v1, the Tests table) with the v2 description: live scan = camera stream → `YuvFrame` → `DecodeIsolate` (one worker, frames dropped while busy, no copy) → `FrameDecoder.decodeYuv420` (Y-plane locate, ROI RGB, hint from the last ROI) → `FrameAssembler` on the main isolate → `finish()`; `CapturePolicy` lock/unlock and hints with their thresholds; photo = `PhotoCaptureScreen` (takePicture, max resolution) → `decodePhotoBytes` in `Isolate.run`; debug: triple-tap overlay, capture button writes `capture_<ts>.png/.txt` to app documents — these are the corpus inputs; performance numbers from the benchmark test (before/after from Task 2's report) and the on-device measurement procedure (enable debug, read `ms=` in logcat). Root `CLAUDE.md`: remove "Camera Decode Improvements (from libcimbar C++ analysis)" and the v1 "Known Subtleties" that no longer apply; Interoperability → "web app and Android app both on v2; live scan and photo decode v2". `README.md`: Android section describes live scan/photo on v2 and the corpus capture workflow; remove the v1 caveat added in Plan 1. `CHANGELOG.md` Unreleased: Added (live scan and photo on v2, focus/exposure lock, aiming guide, hints, in-app photo capture), Removed (v1 decoder, tuning settings), Changed (CI runs both suites). Spec: set `Status: Implemented (Plans 1–4); real-capture corpus pending` and add a short "Deviations recorded during implementation" list (devNorm 0.35, blur 1.0, grid gate ±10, ROI margin 4.5 modules, hint threshold 6 px, dotted-pattern 25 %, module floor 3 ds px).
- Corpus: `test/fixtures/corpus/README.md` — add the on-device capture procedure (Settings → debug on, triple-tap the status panel, aim, press the capture icon; pull `capture_<ts>.png/.txt` with `adb pull`; create `<case>/capture.png` + `meta.json` with the golden name and frame shown, e.g. from the `.txt`'s `seq=` line).

- [ ] **Step 1: CI edit, docs edits, README, CHANGELOG, spec status.**
- [ ] **Step 2: Verify** — `cd android && sh tests/run_all.sh` green; `cd web-app && sh tests/run_all.sh` green; `flutter analyze` clean.
- [ ] **Step 3: Commit** — `git add .github/workflows/ci.yml android/CLAUDE.md CLAUDE.md README.md CHANGELOG.md docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md android/test/fixtures/corpus/README.md && git commit -m "CI runs both suites; docs for the v2 camera integration

Co-Authored-By: …
Claude-Session: …"` (full trailer lines).

---

## Self-review notes

- Spec coverage: §8 (Tasks 4–6: resolution, Y-plane locate, ROI, single isolate with frame dropping before copy, lock/unlock, contain preview, aiming square, hints, progress, `takePicture`, performance target via the benchmark + on-device procedure), §6.9/§7.2 (Task 7), §9.3 capture workflow (Tasks 5, 8), §9.5 CI (Task 8), §10 steps 6 and 8. Step 7 (the user captures the corpus) follows this plan.
- Deviations recorded: ROI margin 4.5 modules rather than §8's "one module" (the finder centers sit 3.5 cells inside the grid edge); hint "move closer" at 6 px to match the locator floor; `decode()`'s `useDrift` defaults to false when a grid is supplied.
- Names used across tasks: `YuvFrame{yPlane,uPlane,vPlane,width,height,yRowStride,uvRowStride,uvPixelStride}`, `RoiHint(x,y,w,h)`, `RgbBuffer.fromYuv420(f,{x0,y0,w,h})`/`originX/originY`, `LumaPlane.fromYPlane/crop/originX/originY`, `FrameDecoder.decodeYuv420(f,{useDrift,hint})`, `Diagnostics.roi/roiMs`, `FrameJob`, `FrameOutcome{status,data,blocksFailed,fileId,seq,total,encrypted,corners,module,roi,diag,totalMs,width,height,capturePng}`, `DecodeIsolate.spawn/busy/decode/dispose/runJob`, `CapturePolicy.update → (ScanHint, LockAction)`, `LiveScanController.wantsFrame/onCameraFrame/consumeLockAction/finish/disposeIsolate`, `CornersOverlayPainter`, `decodePhotoBytes/decodePhotoSync → PhotoDecodeResult`, `PhotoCaptureScreen`, `debugModeProvider` — spelled identically in every task.
- Known risk: Flutter UI code in Tasks 5–6 is compile-checked via `flutter build apk --debug` but only exercised on a device; the pure-Dart pieces they depend on (isolate, policy, decoder, photo decoder) are unit-tested.
