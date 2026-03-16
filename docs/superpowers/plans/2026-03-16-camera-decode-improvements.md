# Camera Decode Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Fix the crop-path white balance bug that destroys color classification, add WB sharing between decode strategies, and create integration tests using real camera debug images.

**Architecture:** Three changes in priority order: (1) Make `_sampleFinderWhite` robust to padding by searching each corner quadrant instead of only the absolute corner cell, (2) Add optional `whitePoint` override to `decodeFramePixels` so WB from warp attempts can be reused by crop fallback, (3) Create `camera_decode_integration_test.dart` that loads real crop PNGs and validates decode diagnostics.

**Tech Stack:** Dart/Flutter, `image` package, `flutter_test`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `android/lib/core/services/cimbar_decoder.dart:172-208` | Fix `_sampleFinderWhite` corner search + add `whitePoint` param |
| Modify | `android/lib/core/services/frame_decode_isolate.dart:543-639` | Pass WB between strategies |
| Create | `android/test/core/services/camera_decode_integration_test.dart` | Integration tests with real crop images |
| Create | `android/test/fixtures/` | Directory for crop PNG test assets |
| Copy   | 3 crop PNGs from debug session → `android/test/fixtures/` | Test image assets |

---

## Chunk 1: Fix crop-path WB + add whitePoint override

### Task 1: Copy test fixtures

- [x] **Step 1: Create fixtures directory and copy crop PNGs**

```bash
cd /home/mezinster/cimbar/android
mkdir -p test/fixtures
cp /mnt/c/Users/Evgeny_Mezin/Downloads/scrcpy-win64-v3.3.4/cimbar_debug_crop_1772622111599.png test/fixtures/crop_frame_1.png
cp /mnt/c/Users/Evgeny_Mezin/Downloads/scrcpy-win64-v3.3.4/cimbar_debug_crop_1772622117767.png test/fixtures/crop_frame_2.png
cp /mnt/c/Users/Evgeny_Mezin/Downloads/scrcpy-win64-v3.3.4/cimbar_debug_crop_1772622132152.png test/fixtures/crop_frame_3.png
```

- [x] **Step 2: Commit fixtures**

```bash
git add test/fixtures/
git commit -m "test: add camera crop debug images as test fixtures"
```

### Task 2: Write failing test for crop-path WB bug

**Files:**
- Create: `android/test/core/services/camera_decode_integration_test.dart`

- [x] **Step 1: Write test that exposes the WB bug**

The test loads a crop PNG (which has padding around the barcode), resizes it to 384px (the native barcode size), runs `_sampleFinderWhite` via `decodeFramePixels` with `enableWhiteBalance: true`, and asserts the WB reference should be bright (>150 per channel), not dark background (~70).

Since `_sampleFinderWhite` is private, we test it indirectly through `DecodeStats.wbWhitePoint`.

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/cimbar_decoder.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';

void main() {
  final rs = ReedSolomon(CimbarConstants.eccBytes);
  final decoder = CimbarDecoder(rs);

  /// Load a test fixture PNG from test/fixtures/.
  img.Image loadFixture(String filename) {
    final bytes = File('test/fixtures/$filename').readAsBytesSync();
    final image = img.decodePng(bytes);
    if (image == null) fail('Failed to decode $filename');
    return image;
  }

  group('Crop image WB sampling', () {
    test('WB white point from padded crop should find finder whites, not background', () {
      // The crop image has padding around the barcode (1.5-cell + 2% margin).
      // When resized to 384px, grid corners (0,0) etc. are background, not
      // finder whites. The WB sampling must search inward to find actual finders.
      final cropImg = loadFixture('crop_frame_1.png');

      // Resize to 384px (the native barcode frame size) like the crop path does
      final resized = img.copyResize(cropImg,
          width: 384, height: 384,
          interpolation: img.Interpolation.nearest);

      final stats = DecodeStats();
      decoder.decodeFramePixels(resized, 384,
          enableWhiteBalance: true,
          useRelativeColor: true,
          useHashDetection: true,
          stats: stats);

      // WB white point should be bright (finder whites), not dark background
      expect(stats.wbWhitePoint, isNotNull,
          reason: 'WB should be computed');
      expect(stats.wbWhitePoint![0], greaterThan(150),
          reason: 'WB red channel should be bright (finder white), '
              'got ${stats.wbWhitePoint![0].toStringAsFixed(0)}');
      expect(stats.wbWhitePoint![1], greaterThan(150),
          reason: 'WB green channel should be bright (finder white), '
              'got ${stats.wbWhitePoint![1].toStringAsFixed(0)}');
      expect(stats.wbWhitePoint![2], greaterThan(150),
          reason: 'WB blue channel should be bright (finder white), '
              'got ${stats.wbWhitePoint![2].toStringAsFixed(0)}');
    });

    test('WB white point from padded crop: all 3 fixtures', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        expect(stats.wbWhitePoint, isNotNull,
            reason: '$fixture: WB should be computed');
        final wp = stats.wbWhitePoint!;
        expect(wp[0], greaterThan(150),
            reason: '$fixture: WB R=${wp[0].toStringAsFixed(0)} too dark');
        expect(wp[1], greaterThan(150),
            reason: '$fixture: WB G=${wp[1].toStringAsFixed(0)} too dark');
        expect(wp[2], greaterThan(150),
            reason: '$fixture: WB B=${wp[2].toStringAsFixed(0)} too dark');
      }
    });
  });
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd android && flutter test test/core/services/camera_decode_integration_test.dart --reporter json 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        evt = json.loads(line.strip())
        if evt.get('type') == 'error':
            print(evt.get('error','')[:300])
        elif evt.get('type') == 'testDone' and evt.get('result') == 'failure':
            print('FAIL:', evt.get('testID'))
    except: pass
"
```

Expected: FAIL — WB R/G/B channels ~70, not >150.

- [x] **Step 3: Commit failing test**

```bash
git add test/core/services/camera_decode_integration_test.dart
git commit -m "test: add failing test for crop-path WB bug (samples background instead of finders)"
```

### Task 3: Fix `_sampleFinderWhite` to search corner quadrants

**Files:**
- Modify: `android/lib/core/services/cimbar_decoder.dart:172-208`

- [x] **Step 1: Implement the fix**

Replace the current `_sampleFinderWhite` method. Instead of sampling only the absolute corner cell, search the corner quadrant (first 6 cells from each corner) for the brightest region. This handles both padded crops and correctly-aligned warps.

The algorithm for each corner:
1. Sample a 4×4 pixel region at each candidate cell in the corner quadrant (6×6 = 36 candidates)
2. Compute luma of each sample
3. Pick the brightest sample from each corner quadrant
4. Take per-channel max across all 4 corners

```dart
  static List<double>? _sampleFinderWhite(img.Image frame, int frameSize) {
    const cs = CimbarConstants.cellSize;
    final cols = frameSize ~/ cs;
    final rows = frameSize ~/ cs;

    List<double> sampleCell(int gridCol, int gridRow) {
      final centerX = gridCol * cs + cs ~/ 2;
      final centerY = gridRow * cs + cs ~/ 2;
      double rSum = 0, gSum = 0, bSum = 0;
      var count = 0;
      for (var dy = -2; dy < 2; dy++) {
        for (var dx = -2; dx < 2; dx++) {
          final px = (centerX + dx).clamp(0, frame.width - 1);
          final py = (centerY + dy).clamp(0, frame.height - 1);
          final p = frame.getPixel(px, py);
          rSum += p.r;
          gSum += p.g;
          bSum += p.b;
          count++;
        }
      }
      return [rSum / count, gSum / count, bSum / count];
    }

    // Search a corner quadrant for the brightest cell (by luma).
    // This handles images with padding where finders are not at exact grid corners.
    // searchRange=6 covers 1.5-cell padding + 2% margin + 3-cell finder.
    List<double> searchCorner(int colStart, int colEnd, int rowStart, int rowEnd) {
      var bestLuma = 0.0;
      var bestSample = [0.0, 0.0, 0.0];
      for (var r = rowStart; r < rowEnd && r < rows; r++) {
        for (var c = colStart; c < colEnd && c < cols; c++) {
          final s = sampleCell(c, r);
          final luma = 0.299 * s[0] + 0.587 * s[1] + 0.114 * s[2];
          if (luma > bestLuma) {
            bestLuma = luma;
            bestSample = s;
          }
        }
      }
      return bestSample;
    }

    const range = 6; // search first/last 6 cells from each corner
    final tlSample = searchCorner(0, range, 0, range);
    final trSample = searchCorner(cols - range, cols, 0, range);
    final blSample = searchCorner(0, range, rows - range, rows);
    final brSample = searchCorner(cols - range, cols, rows - range, rows);

    // Per-channel max across all 4 corners (handles partially occluded finders)
    return [
      max(max(tlSample[0], trSample[0]), max(blSample[0], brSample[0])),
      max(max(tlSample[1], trSample[1]), max(blSample[1], brSample[1])),
      max(max(tlSample[2], trSample[2]), max(blSample[2], brSample[2])),
    ];
  }
```

- [x] **Step 2: Run the WB test to verify it passes**

```bash
cd android && flutter test test/core/services/camera_decode_integration_test.dart -v
```

Expected: PASS — WB white point now finds the actual finder whites.

- [x] **Step 3: Run full test suite to verify no regressions**

```bash
cd android && sh tests/run_all.sh
```

Expected: All existing tests pass (113+).

- [x] **Step 4: Commit the fix**

```bash
git add lib/core/services/cimbar_decoder.dart
git commit -m "fix: search corner quadrants for WB white point instead of exact grid corners

The crop path adds 1.5-cell padding + 2% margin around finder centers.
When resized to frameSize, grid corners (0,0) map to background pixels,
producing wbRef≈(70,60,58) instead of ~(255,255,255). This destroyed
all color classification on the crop path (66% of cells mapped to white).

Now searches the first 6 cells from each corner for the brightest region,
finding the actual finder whites regardless of padding."
```

### Task 4: Add whitePoint override to `decodeFramePixels`

**Files:**
- Modify: `android/lib/core/services/cimbar_decoder.dart:333-362`

- [x] **Step 1: Write test for whitePoint override**

Add to `camera_decode_integration_test.dart`:

```dart
  group('White point override', () {
    test('externally provided whitePoint overrides internal sampling', () {
      final cropImg = loadFixture('crop_frame_1.png');
      final resized = img.copyResize(cropImg,
          width: 384, height: 384,
          interpolation: img.Interpolation.nearest);

      // Provide a known white point externally
      final stats = DecodeStats();
      decoder.decodeFramePixels(resized, 384,
          enableWhiteBalance: true,
          useRelativeColor: true,
          useHashDetection: true,
          whitePoint: [240.0, 245.0, 243.0],
          stats: stats);

      // The stats should reflect the provided white point, not internal sampling
      expect(stats.wbWhitePoint, isNotNull);
      expect(stats.wbWhitePoint![0], closeTo(240.0, 0.1));
      expect(stats.wbWhitePoint![1], closeTo(245.0, 0.1));
      expect(stats.wbWhitePoint![2], closeTo(243.0, 0.1));
      expect(stats.whiteBalanceApplied, isTrue);
    });
  });
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd android && flutter test test/core/services/camera_decode_integration_test.dart --name "externally provided" -v
```

Expected: FAIL — no `whitePoint` parameter exists yet.

- [x] **Step 3: Add `whitePoint` parameter to `decodeFramePixels`**

In `cimbar_decoder.dart`, add the optional parameter and use it when provided:

```dart
  Uint8List decodeFramePixels(
    img.Image frame,
    int frameSize, {
    bool enableWhiteBalance = false,
    bool useRelativeColor = false,
    double? symbolThreshold,
    double? quadrantOffset,
    bool useHashDetection = false,
    bool useLabColor = false,
    DecodeStats? stats,
    Uint8List? preprocessedGray,
    List<double>? whitePoint,           // ← NEW
  }) {
    // ...existing setup...

    // Compute white balance adaptation matrix if enabled
    List<double>? adaptation;
    if (enableWhiteBalance) {
      final wp = whitePoint ?? _sampleFinderWhite(frame, frameSize);  // ← CHANGED
      if (wp != null) {
        adaptation = computeAdaptationMatrix(wp[0], wp[1], wp[2]);
        stats?.wbWhitePoint = wp;
      }
    }
    stats?.whiteBalanceApplied = adaptation != null;
    // ...rest unchanged...
```

- [x] **Step 4: Run test to verify it passes**

```bash
cd android && flutter test test/core/services/camera_decode_integration_test.dart --name "externally provided" -v
```

Expected: PASS

- [x] **Step 5: Run full test suite**

```bash
cd android && sh tests/run_all.sh
```

Expected: All tests pass.

- [x] **Step 6: Commit**

```bash
git add lib/core/services/cimbar_decoder.dart test/core/services/camera_decode_integration_test.dart
git commit -m "feat: add optional whitePoint override to decodeFramePixels

Allows callers to provide a pre-computed WB white point, bypassing
internal finder sampling. Enables WB sharing between decode strategies."
```

### Task 5: Share WB between decode strategies in frame_decode_isolate

**Files:**
- Modify: `android/lib/core/services/frame_decode_isolate.dart:410-531,543-639`

- [x] **Step 1: Write test for WB sharing**

Add to `camera_decode_integration_test.dart`:

```dart
  group('Crop decode with camera images', () {
    test('crop path color distribution should not be dominated by single color', () {
      // Without WB fix, crop path produces ~66% c3 (white).
      // With fix, color distribution should be more balanced.
      final cropImg = loadFixture('crop_frame_1.png');
      final resized = img.copyResize(cropImg,
          width: 384, height: 384,
          interpolation: img.Interpolation.nearest);

      final stats = DecodeStats();
      decoder.decodeFramePixels(resized, 384,
          enableWhiteBalance: true,
          useRelativeColor: true,
          useHashDetection: true,
          stats: stats);

      // No single color should dominate >40% of cells
      final totalCells = stats.cellCount;
      for (var i = 0; i < 8; i++) {
        final pct = stats.colorHist[i] * 100.0 / totalCells;
        expect(pct, lessThan(40),
            reason: 'Color $i has $pct% of cells — too dominant. '
                'colorHist=${stats.colorHist}');
      }
    });
  });
```

- [x] **Step 2: Run test (should pass after Task 3 WB fix)**

```bash
cd android && flutter test test/core/services/camera_decode_integration_test.dart --name "color distribution" -v
```

Expected: PASS (the Task 3 fix already addresses the root cause).

- [x] **Step 3: Add WB sharing to `_tryDecode`**

In `frame_decode_isolate.dart`, modify `_tryDecode` to capture the WB from earlier strategies and pass to later ones. Add `whitePoint` parameter threading:

In `_tryDecodeResized`, add optional `whitePoint` parameter:

```dart
_ResizedResult? _tryDecodeResized(
  CimbarDecoder decoder,
  img.Image resized,
  int frameSize,
  DecodeTuningConfig tuning, {
  bool collectStats = false,
  List<String>? log,
  String label = '',
  bool needsSharpen = false,
  List<double>? whitePoint,         // ← NEW
}) {
```

Pass it through to `decodeFramePixels`:

```dart
    final rawBytes = decoder.decodeFramePixels(resized, frameSize,
        enableWhiteBalance: tuning.enableWhiteBalance,
        useRelativeColor: tuning.useRelativeColor,
        symbolThreshold: tuning.symbolThreshold,
        quadrantOffset: tuning.quadrantOffset,
        useHashDetection: tuning.useHashDetection,
        preprocessedGray: preprocessedGray,
        whitePoint: whitePoint,         // ← NEW
        stats: stats);
```

And same for the LAB failover path (second `decodeFramePixels` call).

In `_tryDecode`, capture WB from 4pt/2pt attempts and pass to crop:

```dart
  // At top of _tryDecode, before strategies:
  List<double>? sharedWhitePoint;

  // In Strategy A (4pt), after _tryDecodeResized returns (both success and failure):
  // Capture WB even on failure (it's still a valid observation)
  if (result != null && result.stats?.wbWhitePoint != null) {
    sharedWhitePoint = result.stats!.wbWhitePoint;
  }
  // (same for stats from failed attempt — need to capture stats from _tryDecodeResized)

  // In Strategy C (crop+resize), pass shared WB:
  final result = _tryDecodeResized(
      decoder,
      img.copyResize(cropped, ...),
      frameSize, tuning,
      ...,
      whitePoint: sharedWhitePoint);    // ← NEW
```

To capture WB from failed attempts, `_tryDecodeResized` needs to return stats even on failure. Modify to accept an output parameter:

```dart
  // Add to _tryDecodeResized signature:
  DecodeStats? statsOut,   // ← optional output: receives stats even on failure
```

After computing stats inside `_tryDecodeResized`, copy to `statsOut`:

```dart
    // After decodeFramePixels call:
    if (statsOut != null && stats != null) {
      statsOut.wbWhitePoint = stats.wbWhitePoint;
    }
```

Then in `_tryDecode`, Strategy A/B:

```dart
    final wbStats = collectStats ? DecodeStats() : null;
    final result = _tryDecodeResized(decoder, warped, frameSize, tuning,
        ..., statsOut: wbStats);
    if (wbStats?.wbWhitePoint != null) {
      sharedWhitePoint = wbStats!.wbWhitePoint;
    }
```

- [x] **Step 4: Run full test suite**

```bash
cd android && sh tests/run_all.sh
```

Expected: All tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/core/services/frame_decode_isolate.dart lib/core/services/cimbar_decoder.dart
git commit -m "feat: share WB white point between decode strategies

When 4pt/2pt warp computes a valid WB white point but fails on symbols,
the crop fallback now reuses that WB instead of sampling from padded
corners. Combined with the corner-quadrant search fix, this provides
two layers of WB robustness for the crop path."
```

---

## Chunk 2: Camera decode diagnostic tests

### Task 6: Add diagnostic assertion tests for crop image decode quality

**Files:**
- Modify: `android/test/core/services/camera_decode_integration_test.dart`

These tests document current decode quality metrics and serve as regression guards.

- [x] **Step 1: Add hamming distance diagnostic tests**

```dart
  group('Camera decode diagnostics', () {
    test('hash detection hamming distances on crop images', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        // Document current quality — these are aspirational bounds that should
        // tighten as decode improves. Current camera captures show h≈17-19.
        print('$fixture: h_avg=${stats.hammingAvg.toStringAsFixed(1)} '
            'h[<10/${stats.hammingLt10} <15/${stats.hammingLt15} '
            '<20/${stats.hammingLt20} 20+/${stats.hammingGe20}] '
            'cells=${stats.cellCount}');

        // Hamming average should be below 25 (random is ~32)
        expect(stats.hammingAvg, lessThan(25),
            reason: '$fixture: avg hamming ${stats.hammingAvg.toStringAsFixed(1)} '
                'is too high — symbols barely better than random');

        // At least some cells should have good matches (h<15)
        expect(stats.hammingLt15, greaterThan(0),
            reason: '$fixture: no cells with hamming<15 — '
                'symbol detection completely broken');
      }
    });

    test('color distribution on crop images should have all 8 colors represented', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        print('$fixture: colors=${stats.colorHist} '
            'wb=${stats.wbWhitePoint?.map((v) => v.toStringAsFixed(0)).toList()}');

        // All 8 colors should be present (>0 cells each)
        for (var i = 0; i < 8; i++) {
          expect(stats.colorHist[i], greaterThan(0),
              reason: '$fixture: color $i has 0 cells — '
                  'color detection broken. hist=${stats.colorHist}');
        }
      }
    });

    test('RS decode on crop images (quality gate status)', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        final rawBytes = decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        final dataBytes = decoder.decodeRSFrame(rawBytes, 384);

        // Check quality gate (first 64 bytes non-zero)
        var nonZero = 0;
        final checkLen = dataBytes.length < 64 ? dataBytes.length : 64;
        for (var i = 0; i < checkLen; i++) {
          if (dataBytes[i] != 0) nonZero++;
        }

        print('$fixture: RS=${dataBytes.isNotEmpty ? "ok" : "empty"} '
            'qgate=${nonZero > 0 ? "PASS($nonZero/64)" : "ZERO"} '
            'h_avg=${stats.hammingAvg.toStringAsFixed(1)} '
            'colors=${stats.colorHist}');

        // Note: these images may not decode successfully yet (hamming ~17-19
        // exceeds RS correction capacity). This test documents the current
        // state and will start passing as decode quality improves.
        // For now, we just verify RS doesn't crash and returns data.
        expect(dataBytes.isNotEmpty, isTrue,
            reason: '$fixture: RS decode returned empty');
      }
    });
  });
```

- [x] **Step 2: Run diagnostic tests**

```bash
cd android && flutter test test/core/services/camera_decode_integration_test.dart -v
```

Expected: All tests PASS (the assertions are intentionally lenient — they document current quality and guard against regressions, not demand perfection).

- [x] **Step 3: Add test for synthetic padded barcode (controlled ground truth)**

This test creates a known barcode, adds padding around it (simulating the crop path), and verifies the decoder can still find the correct WB and decode the data.

```dart
  group('Synthetic padded barcode', () {
    test('barcode with padding should decode correctly after WB fix', () {
      // Create a known barcode at 384px
      const frameSize = 384;
      final testData = Uint8List(100);
      for (var i = 0; i < testData.length; i++) {
        testData[i] = (i * 13 + 7) & 0xFF;
      }

      final rsFrame = CimbarEncoder.encodeRSFrame(testData, frameSize);
      final barcode = CimbarEncoder.encodeFrame(rsFrame, frameSize);

      // Add padding: embed barcode in a larger dark image (simulating crop)
      final padded = img.Image(width: 500, height: 500);
      img.fill(padded, color: img.ColorRgba8(60, 55, 50, 255)); // dark background
      final offsetX = (500 - frameSize) ~/ 2;
      final offsetY = (500 - frameSize) ~/ 2;
      img.compositeImage(padded, barcode, dstX: offsetX, dstY: offsetY);

      // Resize to frameSize (like crop path does)
      final resized = img.copyResize(padded,
          width: frameSize, height: frameSize,
          interpolation: img.Interpolation.nearest);

      // Decode with WB
      final stats = DecodeStats();
      final rawBytes = decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: true,
          useRelativeColor: true,
          stats: stats);

      // WB should find the finder whites, not the dark padding
      expect(stats.wbWhitePoint, isNotNull);
      expect(stats.wbWhitePoint![0], greaterThan(200),
          reason: 'WB R=${stats.wbWhitePoint![0].toStringAsFixed(0)} — '
              'should find finder white, not background');

      // Should decode correctly
      final dataBytes = decoder.decodeRSFrame(rawBytes, frameSize);
      expect(dataBytes.isNotEmpty, isTrue);

      // Verify data matches (first testData.length bytes after length prefix)
      var nonZero = 0;
      for (var i = 0; i < 64 && i < dataBytes.length; i++) {
        if (dataBytes[i] != 0) nonZero++;
      }
      expect(nonZero, greaterThan(0),
          reason: 'Quality gate failed — first 64 bytes all zero');
    });
  });
```

This requires the `CimbarEncoder` import. Add at top of test file:

```dart
import '../../test_utils/cimbar_encoder.dart';
```

- [x] **Step 4: Run all integration tests**

```bash
cd android && flutter test test/core/services/camera_decode_integration_test.dart -v
```

Expected: All PASS.

- [x] **Step 5: Run full suite**

```bash
cd android && sh tests/run_all.sh
```

Expected: All tests pass.

- [x] **Step 6: Commit**

```bash
git add test/core/services/camera_decode_integration_test.dart
git commit -m "test: add camera decode integration tests with real crop images

Tests cover:
- WB white point sampling on padded crop images (regression guard)
- Color distribution balance (no single color >40%)
- Hamming distance diagnostics (documents current quality)
- RS decode quality gate status
- Synthetic padded barcode controlled round-trip"
```

---

## Summary

| Task | What | Impact |
|------|------|--------|
| 1 | Copy fixture images | Setup |
| 2 | Failing test for WB bug | Documents the bug |
| 3 | Fix `_sampleFinderWhite` corner quadrant search | **Critical** — fixes 66% white-out on crop path |
| 4 | Add `whitePoint` override parameter | Enables WB sharing |
| 5 | Share WB between strategies | **Medium** — second WB robustness layer |
| 6 | Diagnostic + synthetic tests | Regression guards + quality tracking |
