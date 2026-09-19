# Camera Debug Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured key=value diagnostic logging and end-to-end camera frame integration tests to speed up camera decode debugging.

**Architecture:** Two additive changes — (1) extend `LocateResult` and `DecodeStats` with diagnostic fields, replace free-text `debugInfo` in `frame_decode_isolate.dart` with structured `key=value` lines per pipeline stage; (2) add a new test group to `camera_decode_integration_test.dart` that runs full-frame camera PNGs through locate→warp→WB→decode and prints structured diagnostics.

**Tech Stack:** Dart/Flutter, `image` package, `flutter_test`

**Spec:** `android/docs/superpowers/specs/2026-03-16-camera-debug-infrastructure-design.md`

---

## Chunk 1: API Extensions (LocateResult + DecodeStats)

### Task 1: Add diagnostic fields to LocateResult

**Files:**
- Modify: `android/lib/core/services/frame_locator.dart:8-27` (LocateResult class)
- Test: `android/test/core/services/frame_locator_test.dart`

- [ ] **Step 1: Add fields to LocateResult**

Add 4 nullable diagnostic fields to `LocateResult` and its constructor:

```dart
class LocateResult {
  final img.Image cropped;
  final BarcodeRect boundingBox;
  final Point<double>? tlFinderCenter;
  final Point<double>? trFinderCenter;
  final Point<double>? blFinderCenter;
  final Point<double>? brFinderCenter;

  // Diagnostic fields (populated by anchor-based detection only)
  final int? candidateCount;
  final double? tlLuma;
  final bool? gapOk;
  final double? devNorm;

  const LocateResult({
    required this.cropped,
    required this.boundingBox,
    this.tlFinderCenter,
    this.trFinderCenter,
    this.blFinderCenter,
    this.brFinderCenter,
    this.candidateCount,
    this.tlLuma,
    this.gapOk,
    this.devNorm,
  });
}
```

- [ ] **Step 2: Run existing tests to verify no breakage**

Run: `cd android && flutter test test/core/services/frame_locator_test.dart --reporter json 2>&1 | tail -1 | dart run test/json_test_summary.dart`
Expected: All existing tests pass (fields are nullable, all existing callers use named params).

- [ ] **Step 3: Commit**

```bash
git add android/lib/core/services/frame_locator.dart
git commit -m "feat: add diagnostic fields to LocateResult"
```

### Task 2: Populate LocateResult diagnostics from _selectAndClassify

**Files:**
- Modify: `android/lib/core/services/frame_locator.dart:326-510` (_selectAndClassify), `android/lib/core/services/frame_locator.dart:70-113` (locate)

The challenge: `_selectAndClassify` returns a record of `_FinderCandidate` objects. Diagnostic values (`candidateCount`, `tlLuma`, `gapOk`, `devNorm`) are computed inside it but discarded. We need to thread them back to `locate()` which constructs the `LocateResult`.

- [ ] **Step 1: Extend _selectAndClassify return record with diagnostics**

Change the return type of `_selectAndClassify` from:
```dart
({_FinderCandidate tl, _FinderCandidate br, _FinderCandidate? tr, _FinderCandidate? bl})?
```
to:
```dart
({_FinderCandidate tl, _FinderCandidate br, _FinderCandidate? tr, _FinderCandidate? bl,
  int candidateCount, double tlLuma, bool gapOk, double devNorm})?
```

In `_selectAndClassify` (line ~326):
- Track `candidateCount = candidates.length` at the top (line ~335).
- The `centerLumas` list already has TL luma — capture `tlLuma = centerLumas[darkestIdx]` after TL selection.
- `gapOk` is already the brightness gap check — capture `gapOk = (gap >= 45)` where the gap threshold is checked (around line ~380).
- `devNorm` = `bestDevNorm` from the parallelogram pair search (line ~429). For 2-candidate case (line ~399), set `devNorm = 0.0` (only TL+BR, no parallelogram). For 1-candidate case (line ~396), set `devNorm = -1.0`.

**Return sites to update (7 total):**
- Line ~335: early return `null` for `candidates.length < 2` — no change (returns null).
- Line ~385: `return _selectAndClassifyByCoordinates(candidates)` — this function returns a 4-field record. **Must also update `_selectAndClassifyByCoordinates` to return the 8-field record**, using `candidateCount = candidates.length`, `tlLuma = -1.0`, `gapOk = false`, `devNorm = -1.0` (coordinate path doesn't compute these).
- Line ~396: 1-candidate path — add `candidateCount: candidateCount, tlLuma: tlLuma, gapOk: gapOk, devNorm: -1.0`.
- Lines ~410-411: 2-candidate ternary — restructure from single-line ternary to if/else, add diagnostics with `devNorm: 0.0`.
- Line ~471: no valid parallelogram pair — add diagnostics with `devNorm: bestDevNorm`.
- Lines ~499, ~505: edge ratio failures — add diagnostics with `devNorm: bestDevNorm`.
- Line ~509: final successful return — add `candidateCount: candidateCount, tlLuma: tlLuma, gapOk: gapOk, devNorm: bestDevNorm`.

Also update `_selectAndClassifyByCoordinates` (lines 512-584) return type to match the extended 8-field record. All its return statements need the 4 diagnostic fields with fallback values.

- [ ] **Step 2: Thread diagnostics through locate() into LocateResult**

In `locate()` (line ~102), after `final finders = _selectAndClassify(merged, photo)`:

```dart
if (finders != null) {
  return _computeCropFromAnchors(
    photo, finders.tl, finders.br, origW, origH,
    tr: finders.tr, bl: finders.bl,
    candidateCount: finders.candidateCount,
    tlLuma: finders.tlLuma,
    gapOk: finders.gapOk,
    devNorm: finders.devNorm,
  );
}
```

Update `_computeCropFromAnchors` to accept and pass through the 4 diagnostic fields to `LocateResult`.

- [ ] **Step 3: Write test verifying diagnostics are populated**

Add to `frame_locator_test.dart`:

```dart
test('LocateResult includes diagnostic fields', () {
  // Use the existing centered barcode test image (384px barcode on 800x600)
  final image = _createTestImage(800, 600, barcodeSize: 384);
  final result = FrameLocator.locate(image);

  // Diagnostics populated by anchor-based detection
  expect(result.candidateCount, isNotNull);
  expect(result.candidateCount, greaterThanOrEqualTo(4));
  expect(result.tlLuma, isNotNull);
  expect(result.tlLuma, lessThan(100)); // TL has no dot → dark center
  expect(result.gapOk, isNotNull);
  expect(result.devNorm, isNotNull);
  expect(result.devNorm, lessThan(0.09)); // good parallelogram
});
```

- [ ] **Step 4: Run tests**

Run: `cd android && flutter test test/core/services/frame_locator_test.dart --reporter json 2>&1 | tail -1 | dart run test/json_test_summary.dart`
Expected: All tests pass including the new one.

- [ ] **Step 5: Commit**

```bash
git add android/lib/core/services/frame_locator.dart android/test/core/services/frame_locator_test.dart
git commit -m "feat: populate LocateResult diagnostic fields from finder detection"
```

### Task 3: Add RS block tracking to DecodeStats and decodeRSFrame

**Files:**
- Modify: `android/lib/core/services/cimbar_decoder.dart:14-66` (DecodeStats), `android/lib/core/services/cimbar_decoder.dart:581-628` (decodeRSFrame)
- Test: `android/test/core/services/cimbar_decoder_test.dart`

- [ ] **Step 1: Write failing test for RS block stats**

Add to `cimbar_decoder_test.dart`:

```dart
test('decodeRSFrame populates RS block stats in DecodeStats', () {
  final decoder = CimbarDecoder();
  const frameSize = 256;

  // Encode a known payload (CimbarEncoder uses static methods)
  final payload = Uint8List.fromList(
      List.generate(100, (i) => i & 0xFF));
  final rsEncoded = CimbarEncoder.encodeRSFrame(payload, frameSize);

  // Introduce some errors to cause 1-2 block failures
  // Corrupt block 0 beyond repair (>32 errors in first 255 bytes)
  for (var i = 0; i < 64; i++) {
    rsEncoded[i] ^= 0xFF;
  }

  final stats = DecodeStats();
  decoder.decodeRSFrame(rsEncoded, frameSize, stats: stats);

  expect(stats.rsBlocks, greaterThan(0));
  expect(stats.rsOk + stats.rsFail, equals(stats.rsBlocks));
  expect(stats.rsFail, greaterThanOrEqualTo(1)); // we corrupted block 0
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd android && flutter test test/core/services/cimbar_decoder_test.dart --reporter json 2>&1 | tail -1 | dart run test/json_test_summary.dart`
Expected: FAIL — `decodeRSFrame` doesn't accept `stats` parameter yet.

- [ ] **Step 3: Add rsBlocks/rsOk/rsFail fields to DecodeStats**

In `DecodeStats` (line ~14), add after the existing fields:

```dart
// RS block decode stats (populated by decodeRSFrame when stats provided)
int rsBlocks = 0;
int rsOk = 0;
int rsFail = 0;
```

- [ ] **Step 4: Add optional stats parameter to decodeRSFrame**

Modify `decodeRSFrame` signature (line ~581):

```dart
Uint8List decodeRSFrame(Uint8List rawBytes, int frameSize, {DecodeStats? stats}) {
```

In Phase 3 (line ~612), track per-block outcomes:

```dart
// Phase 3: RS-decode each block
final result = <int>[];
for (var i = 0; i < n; i++) {
  final blockData = blockSizes[i] - CimbarConstants.eccBytes;
  stats?.rsBlocks++;
  try {
    final decoded = _rs.decode(blocks[i]);
    result.addAll(decoded);
    stats?.rsOk++;
  } catch (_) {
    // If RS decode fails, push zeros
    for (var k = 0; k < blockData; k++) {
      result.add(0);
    }
    stats?.rsFail++;
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd android && flutter test test/core/services/cimbar_decoder_test.dart --reporter json 2>&1 | tail -1 | dart run test/json_test_summary.dart`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/services/cimbar_decoder.dart android/test/core/services/cimbar_decoder_test.dart
git commit -m "feat: add RS block success/failure tracking to DecodeStats"
```

---

## Chunk 2: Structured Diagnostic Logging

### Task 4: Replace free-text debugInfo with structured key=value lines

**Files:**
- Modify: `android/lib/core/services/frame_decode_isolate.dart:296-353` (debugInfo construction), `android/lib/core/services/frame_decode_isolate.dart:369-381` (_writeStats), `android/lib/core/services/frame_decode_isolate.dart:458-459,498-500,529-531` (per-attempt log lines)

This is the largest task. We replace the free-text `debugInfo` StringBuffer with structured `key=value` lines. The `overlayLine` is unchanged.

- [ ] **Step 1: Add a `_formatLocateLine` helper**

Add after `_statsShort` (around line 682):

```dart
/// Format structured locate diagnostic line.
String _formatLocateLine(int frameNum, LocateResult? locateResult, int candidateCount) {
  final sb = StringBuffer('frame=$frameNum stage=locate');
  sb.write(' candidates=$candidateCount');
  if (locateResult != null) {
    if (locateResult.tlFinderCenter != null) {
      sb.write(' tl=${locateResult.tlFinderCenter!.x.toInt()},${locateResult.tlFinderCenter!.y.toInt()}');
    }
    if (locateResult.trFinderCenter != null) {
      sb.write(' tr=${locateResult.trFinderCenter!.x.toInt()},${locateResult.trFinderCenter!.y.toInt()}');
    }
    if (locateResult.blFinderCenter != null) {
      sb.write(' bl=${locateResult.blFinderCenter!.x.toInt()},${locateResult.blFinderCenter!.y.toInt()}');
    }
    if (locateResult.brFinderCenter != null) {
      sb.write(' br=${locateResult.brFinderCenter!.x.toInt()},${locateResult.brFinderCenter!.y.toInt()}');
    }
    if (locateResult.tlLuma != null) {
      sb.write(' tlLuma=${locateResult.tlLuma!.toStringAsFixed(0)}');
    }
    if (locateResult.gapOk != null) {
      sb.write(' gapOk=${locateResult.gapOk}');
    }
    if (locateResult.devNorm != null) {
      sb.write(' devNorm=${locateResult.devNorm!.toStringAsFixed(3)}');
    }
  }
  return sb.toString();
}
```

- [ ] **Step 2: Add `_formatWarpLine`, `_formatWbLine`, `_formatDecodeLine`, `_formatGateLine` helpers**

```dart
String _formatWarpLine(int frameNum, String strategy, String srcPts, int dstSize) {
  return 'frame=$frameNum stage=warp strategy=$strategy srcPts="$srcPts" dstSize=$dstSize';
}

String _formatWbLine(int frameNum, DecodeStats? stats, String src) {
  final sb = StringBuffer('frame=$frameNum stage=wb');
  if (stats?.wbWhitePoint != null) {
    final wp = stats!.wbWhitePoint!;
    sb.write(' wpR=${wp[0].toStringAsFixed(0)} wpG=${wp[1].toStringAsFixed(0)} wpB=${wp[2].toStringAsFixed(0)}');
  }
  sb.write(' src=$src');
  return sb.toString();
}

String _formatDecodeLine(int frameNum, DecodeStats? stats, bool useHashDetection) {
  final sb = StringBuffer('frame=$frameNum stage=decode');
  if (stats != null) {
    sb.write(' cells=${stats.cellCount}');
    sb.write(' rsBlocks=${stats.rsBlocks} rsOk=${stats.rsOk} rsFail=${stats.rsFail}');
    if (stats.rsBlocks > 0) {
      sb.write(' errRate=${(stats.rsFail / stats.rsBlocks).toStringAsFixed(3)}');
    }
    if (useHashDetection && stats.hammingSum > 0) {
      sb.write(' hashMean=${stats.hammingAvg.toStringAsFixed(1)} hashMax=${stats.hammingMax}');
      sb.write(' driftXFinal=${stats.driftXFinal} driftYFinal=${stats.driftYFinal}');
    }
  }
  return sb.toString();
}

String _formatGateLine(int frameNum, bool pass, int bytes, String method) {
  return 'frame=$frameNum stage=gate pass=$pass bytes=$bytes method=$method';
}
```

- [ ] **Step 3: Thread `stats` through `decodeRSFrame` calls in `_tryDecodeResized`**

In `_tryDecodeResized` (line ~591), pass stats to the two `decodeRSFrame` calls:

```dart
// Line ~591: primary decode
final dataBytes = decoder.decodeRSFrame(rawBytes, frameSize, stats: stats);

// Line ~622: LAB failover decode
final dataBytesLab = decoder.decodeRSFrame(rawBytesLab, frameSize, stats: statsLab);
```

- [ ] **Step 4: Add frameNum parameter to `_tryDecode` and `_tryDecodeResized`**

Add `int frameNum = 0` named parameter to `_tryDecodeImage`, `_tryDecode`, and `_tryDecodeResized`. Thread it through all call sites in `decodeFrameInIsolate`.

- [ ] **Step 5: Emit structured warp lines in `_tryDecode`**

In `_tryDecode`, replace the existing per-attempt `log?.add(...)` calls (lines ~458, ~499, ~529) with structured lines. For each strategy (4pt, 2pt, crop), emit:

```dart
// After 4pt warp (line ~450):
log?.add(_formatWarpLine(frameNum, '4pt',
    '${locateResult.tlFinderCenter!.x.toInt()},${locateResult.tlFinderCenter!.y.toInt()} '
    '${locateResult.trFinderCenter!.x.toInt()},${locateResult.trFinderCenter!.y.toInt()} '
    '${locateResult.blFinderCenter!.x.toInt()},${locateResult.blFinderCenter!.y.toInt()} '
    '${locateResult.brFinderCenter!.x.toInt()},${locateResult.brFinderCenter!.y.toInt()}',
    frameSize));

// After 2pt warp (line ~491):
log?.add(_formatWarpLine(frameNum, '2pt',
    '${locateResult.tlFinderCenter!.x.toInt()},${locateResult.tlFinderCenter!.y.toInt()} '
    '${locateResult.brFinderCenter!.x.toInt()},${locateResult.brFinderCenter!.y.toInt()}',
    frameSize));

// After crop (line ~519):
log?.add(_formatWarpLine(frameNum, 'crop', 'resize', frameSize));
```

- [ ] **Step 6: Emit structured wb+decode lines in `_tryDecodeResized`**

In `_tryDecodeResized`, after `decodeRSFrame` returns, emit wb and decode lines. Replace existing `log?.add('  $label RS=...')` calls with:

```dart
// Determine WB source
final wbSrc = whitePoint != null ? 'warp' : (stats?.whiteBalanceApplied == true ? 'crop' : 'none');
log?.add(_formatWbLine(frameNum, stats, wbSrc));
log?.add(_formatDecodeLine(frameNum, stats, tuning.useHashDetection));
```

Also emit for LAB failover path (replace the LAB log lines similarly).

- [ ] **Step 7: Replace debugInfo construction in `decodeFrameInIsolate`**

Replace the `debugInfo` StringBuffer block (lines 296-353) with:

```dart
String? debugInfo;
String? overlayLine;
if (collect) {
  final ok = outcome != null;
  final lines = <String>[];

  // Locate line
  lines.add(_formatLocateLine(0, locateResult,
      locateResult?.candidateCount ?? 0));

  // Per-attempt lines (warp, wb, decode) already in log
  if (log != null) lines.addAll(log);

  // Gate line
  if (ok) {
    lines.add(_formatGateLine(0, true, outcome.data.length, outcome.warpStrategy));
  } else {
    lines.add(_formatGateLine(0, false, 0, 'none'));
  }

  debugInfo = lines.join('\n');

  // overlayLine stays unchanged
  if (ok) {
    overlayLine = 'OK ${outcome.frameSize}px '
        '${outcome.warpStrategy} ${totalMs}ms '
        'f=$findersFound';
  } else {
    overlayLine = 'FAIL ${totalMs}ms f=$findersFound'
        '${locateError != null ? ' err' : ''}';
  }
}
```

- [ ] **Step 8: Remove `_writeStats` and `_statsShort`**

These are no longer used (replaced by structured format helpers). Delete `_writeStats` (lines 369-381) and `_statsShort` (lines 657-682).

Wait — `_statsShort` is still used by the existing per-attempt log lines inside `_tryDecodeResized` (lines 595, 608, 646). These will be replaced in Step 6 above. Verify all references are gone before deleting.

- [ ] **Step 9: Run all tests**

Run: `cd android && sh tests/run_all.sh`
Expected: All tests pass. The structured logging is internal to the isolate path — existing tests don't assert on debugInfo content.

- [ ] **Step 10: Commit**

```bash
git add android/lib/core/services/frame_decode_isolate.dart
git commit -m "feat: replace free-text debugInfo with structured key=value logging"
```

---

## Chunk 3: End-to-End Camera Frame Test

### Task 5: Add camera full-frame decode integration test

**Depends on:** Tasks 1-3 (LocateResult diagnostics + DecodeStats RS tracking). The test uses `locateResult.devNorm`, `locateResult.candidateCount`, and `decodeRSFrame(stats: stats)` which are added in those tasks.

**Files:**
- Modify: `android/test/core/services/camera_decode_integration_test.dart`
- Fixtures: `android/test/fixtures/camera_raw_1280x720_a.png` (already committed), `android/test/fixtures/camera_raw_1280x720_b.png` (already committed)

- [ ] **Step 1: Add imports and PipelineResult class**

At the top of `camera_decode_integration_test.dart`, add imports (some already present):

```dart
import 'dart:math';
import 'package:cimbar_scanner/core/services/frame_locator.dart';
import 'package:cimbar_scanner/core/services/perspective_transform.dart';
```

Add below `main()` function, before the closing of the file:

```dart
/// Intermediate results from each pipeline stage.
class _PipelineResult {
  LocateResult? locateResult;
  img.Image? warped;
  int? frameSize;
  List<double>? wpRGB;
  String wbSrc = 'none';
  Uint8List? pixelBytes;
  Uint8List? rsBytes;
  DecodeStats? stats;
  String strategy = 'none';
  int rsOk = 0;
  int rsFail = 0;
}
```

- [ ] **Step 2: Add `_runPipeline` helper**

```dart
/// Run the full camera decode pipeline on an RGB image.
_PipelineResult _runPipeline(img.Image image, int frameNum) {
  final result = _PipelineResult();
  final decoder = CimbarDecoder();

  // Stage 1: Locate
  result.locateResult = FrameLocator.locate(image);

  // Stage 2: Warp — try 4pt, then 2pt, then crop
  final loc = result.locateResult!;
  img.Image? warped;

  // Try frame sizes: locked to 256 since we know the source barcode
  const frameSize = 256;
  result.frameSize = frameSize;

  if (loc.tlFinderCenter != null &&
      loc.trFinderCenter != null &&
      loc.blFinderCenter != null &&
      loc.brFinderCenter != null) {
    final corners = PerspectiveTransform.computeBarcodeCornersFrom4(
        loc.tlFinderCenter!, loc.trFinderCenter!,
        loc.blFinderCenter!, loc.brFinderCenter!, frameSize);
    if (corners != null) {
      warped = PerspectiveTransform.warpPerspective(image, corners, frameSize);
      result.strategy = '4pt';
    }
  }

  if (warped == null && loc.tlFinderCenter != null && loc.brFinderCenter != null) {
    final corners = PerspectiveTransform.computeBarcodeCorners(
        loc.tlFinderCenter!, loc.brFinderCenter!, frameSize);
    if (corners != null) {
      warped = PerspectiveTransform.warpPerspective(image, corners, frameSize);
      result.strategy = '2pt';
    }
  }

  if (warped == null) {
    warped = img.copyResize(loc.cropped,
        width: frameSize, height: frameSize,
        interpolation: img.Interpolation.nearest);
    result.strategy = 'crop';
  }
  result.warped = warped;

  // Stage 3: White balance
  result.wpRGB = CimbarDecoder.sampleFinderWhite(warped, frameSize);
  if (result.wpRGB != null) {
    result.wbSrc = result.strategy == 'crop' ? 'crop' : 'warp';
  }

  // Stage 4: Decode pixels
  result.stats = DecodeStats();
  result.pixelBytes = decoder.decodeFramePixels(warped, frameSize,
      enableWhiteBalance: true,
      useRelativeColor: true,
      useHashDetection: true,
      whitePoint: result.wpRGB,
      stats: result.stats);

  // Stage 5: RS decode
  result.rsBytes = decoder.decodeRSFrame(result.pixelBytes!, frameSize,
      stats: result.stats);

  return result;
}
```

- [ ] **Step 3: Add `_assertSanity` helper**

```dart
void _assertSanity(_PipelineResult r) {
  // Finder detection
  expect(r.locateResult, isNotNull, reason: 'locate() should find barcode');
  final loc = r.locateResult!;
  final corners = [loc.tlFinderCenter, loc.trFinderCenter,
                    loc.blFinderCenter, loc.brFinderCenter];
  expect(corners.where((c) => c != null).length, equals(4),
      reason: 'Should detect all 4 finder corners');

  // Parallelogram
  if (loc.devNorm != null) {
    expect(loc.devNorm, lessThan(0.09),
        reason: 'Parallelogram deviation should be small');
  }

  // Warp output
  expect(r.warped, isNotNull);
  expect(r.warped!.width, equals(r.frameSize));
  expect(r.warped!.height, equals(r.frameSize));

  // WB reasonable
  if (r.wpRGB != null) {
    for (var i = 0; i < 3; i++) {
      expect(r.wpRGB![i], greaterThanOrEqualTo(128),
          reason: 'White point channel $i should be >= 128');
      expect(r.wpRGB![i], lessThanOrEqualTo(255),
          reason: 'White point channel $i should be <= 255');
    }
  }

  // RS partial decode
  expect(r.stats!.rsOk, greaterThan(0),
      reason: 'At least some RS blocks should decode');
}
```

- [ ] **Step 4: Add `_printDiagnostics` helper**

```dart
void _printDiagnostics(_PipelineResult r, int frameNum) {
  final loc = r.locateResult;
  final stats = r.stats;

  // Locate line
  final locBuf = StringBuffer('frame=$frameNum stage=locate');
  locBuf.write(' candidates=${loc?.candidateCount ?? 0}');
  if (loc?.tlFinderCenter != null) locBuf.write(' tl=${loc!.tlFinderCenter!.x.toInt()},${loc.tlFinderCenter!.y.toInt()}');
  if (loc?.trFinderCenter != null) locBuf.write(' tr=${loc!.trFinderCenter!.x.toInt()},${loc.trFinderCenter!.y.toInt()}');
  if (loc?.blFinderCenter != null) locBuf.write(' bl=${loc!.blFinderCenter!.x.toInt()},${loc.blFinderCenter!.y.toInt()}');
  if (loc?.brFinderCenter != null) locBuf.write(' br=${loc!.brFinderCenter!.x.toInt()},${loc.brFinderCenter!.y.toInt()}');
  if (loc?.tlLuma != null) locBuf.write(' tlLuma=${loc!.tlLuma!.toStringAsFixed(0)}');
  if (loc?.gapOk != null) locBuf.write(' gapOk=${loc!.gapOk}');
  if (loc?.devNorm != null) locBuf.write(' devNorm=${loc!.devNorm!.toStringAsFixed(3)}');
  print(locBuf);

  // Warp line
  print('frame=$frameNum stage=warp strategy=${r.strategy} dstSize=${r.frameSize}');

  // WB line
  final wbBuf = StringBuffer('frame=$frameNum stage=wb');
  if (r.wpRGB != null) {
    wbBuf.write(' wpR=${r.wpRGB![0].toStringAsFixed(0)} wpG=${r.wpRGB![1].toStringAsFixed(0)} wpB=${r.wpRGB![2].toStringAsFixed(0)}');
  }
  wbBuf.write(' src=${r.wbSrc}');
  print(wbBuf);

  // Decode line
  final decBuf = StringBuffer('frame=$frameNum stage=decode');
  if (stats != null) {
    decBuf.write(' cells=${stats.cellCount}');
    decBuf.write(' rsBlocks=${stats.rsBlocks} rsOk=${stats.rsOk} rsFail=${stats.rsFail}');
    if (stats.rsBlocks > 0) {
      decBuf.write(' errRate=${(stats.rsFail / stats.rsBlocks).toStringAsFixed(3)}');
    }
    if (stats.hammingSum > 0) {
      decBuf.write(' hashMean=${stats.hammingAvg.toStringAsFixed(1)} hashMax=${stats.hammingMax}');
      decBuf.write(' driftXFinal=${stats.driftXFinal} driftYFinal=${stats.driftYFinal}');
    }
  }
  print(decBuf);

  // Gate line
  final pass = stats != null && stats.rsOk > 0;
  final bytes = r.rsBytes?.length ?? 0;
  print('frame=$frameNum stage=gate pass=$pass bytes=$bytes method=${r.strategy}');
}
```

- [ ] **Step 5: Add the test group**

Add inside `main()`, after the existing groups:

```dart
group('Camera full-frame decode', () {
  test('frame A - full pipeline', () {
    final image = loadFixture('camera_raw_1280x720_a.png');
    final result = _runPipeline(image, 1);
    _assertSanity(result);
    _printDiagnostics(result, 1);
  });

  test('frame B - full pipeline', () {
    final image = loadFixture('camera_raw_1280x720_b.png');
    final result = _runPipeline(image, 2);
    _assertSanity(result);
    _printDiagnostics(result, 2);
  });
});
```

Note: `loadFixture` already exists at line 17 of the file. Reuse it.

- [ ] **Step 6: Run the new tests**

Run: `cd android && flutter test test/core/services/camera_decode_integration_test.dart --reporter json 2>&1 | tail -1 | dart run test/json_test_summary.dart`
Expected: All tests pass (both existing and new). New tests print structured diagnostics.

To see the diagnostic output:
Run: `cd android && flutter test test/core/services/camera_decode_integration_test.dart --name "frame A" 2>&1 | grep "^frame="`

- [ ] **Step 7: Run full test suite**

Run: `cd android && sh tests/run_all.sh`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add android/test/core/services/camera_decode_integration_test.dart
git commit -m "feat: add end-to-end camera frame decode integration tests"
```

---

## Task 6: Final validation

- [ ] **Step 1: Run full test suite**

Run: `cd android && sh tests/run_all.sh`
Expected: All tests pass (previous 123 + 3 new = 126).

- [ ] **Step 2: Verify structured output format**

Run: `cd android && flutter test test/core/services/camera_decode_integration_test.dart --name "frame A" 2>&1 | grep "stage="`
Expected: 5 lines (locate, warp, wb, decode, gate) with `key=value` format.
