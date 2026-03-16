# Camera Decode Debug Infrastructure

**Date:** 2026-03-16
**Status:** Approved

## Problem

After 3 weeks of iterating on the live camera decode feature, debugging cycles are slow because:
1. No way to reproduce camera-specific failures in tests (only GIF import has integration tests)
2. Free-text diagnostic logs are hard to parse and compare across runs

## Improvement 1: Structured Diagnostic Logging

### Format

Replace current free-text `debugInfo` construction in `frame_decode_isolate.dart` with space-separated `key=value` lines, one per pipeline stage. Each line is prefixed with `frame=N`. Values containing spaces use double quotes.

Tag: Keep `[cimbar_scan]` prefix for `adb logcat | grep cimbar_scan` compatibility.

### API changes required

**`LocateResult`** — add optional diagnostic fields. Currently `locate()` returns only the cropped image, bounding box, and finder center points. The candidate count, TL luma, brightness gap, and parallelogram deviation are computed inside private methods and discarded. Add:

```dart
class LocateResult {
  // ... existing fields ...
  final int? candidateCount;    // total finder candidates before selection
  final double? tlLuma;         // TL center pixel luma
  final bool? gapOk;            // brightness gap >= 45
  final double? devNorm;        // parallelogram deviation normalized by side²
}
```

Populated in `_selectAndClassify()` and threaded back through `locate()`. All nullable — only set when anchor-based detection runs (not luma-threshold fallback).

**`DecodeStats`** — add RS block tracking fields:

```dart
class DecodeStats {
  // ... existing fields ...
  int rsBlocks = 0;    // total RS blocks attempted
  int rsOk = 0;        // blocks that decoded successfully
  int rsFail = 0;      // blocks that failed RS decode
}
```

Populated in `decodeRSFrame()` which currently silently catches failures. Thread an optional `DecodeStats` parameter through `decodeRSFrame()` to record per-block outcomes.

### Fields per stage

**locate:**
```
frame=N stage=locate candidates=7 tl=152,88 tr=410,92 bl=148,350 br=412,354 tlLuma=51 gapOk=true devNorm=0.003
```
- `candidates` — total finder candidates before selection (from `LocateResult.candidateCount`)
- `tl/tr/bl/br` — selected corner coordinates (x,y) (from `LocateResult.*FinderCenter`)
- `tlLuma` — TL center pixel luma (from `LocateResult.tlLuma`)
- `gapOk` — whether brightness gap >= 45 (from `LocateResult.gapOk`)
- `devNorm` — parallelogram deviation (from `LocateResult.devNorm`)

**warp:**
```
frame=N stage=warp strategy=4pt srcPts="152,88 410,92 148,350 412,354" dstSize=256
```
- `strategy` — 4pt, 2pt, or crop
- `srcPts` — source corner points used for transform
- `dstSize` — target frame size in pixels

**wb:**
```
frame=N stage=wb wpR=230 wpG=242 wpB=238 src=warp
```
- `wpR/wpG/wpB` — observed white point RGB values (from `DecodeStats.wbWhitePoint`, already available). More useful for debugging than derived gains — shows the actual color cast directly
- `src` — where white point came from: warp (shared from warp strategy), crop (sampled from crop image), none (no WB applied)

**decode:**
```
frame=N stage=decode cells=1015 rsBlocks=28 rsOk=26 rsFail=2 errRate=0.071 hashMean=8.2 hashMax=22 driftXFinal=2 driftYFinal=-1
```
- `cells` — usable cells in frame
- `rsBlocks` — total RS blocks (from `DecodeStats.rsBlocks`)
- `rsOk/rsFail` — RS blocks that decoded/failed (from `DecodeStats.rsOk/rsFail`)
- `errRate` — `rsFail / rsBlocks` (block-level failure rate)
- `hashMean/hashMax` — average and max hamming distance (from `DecodeStats.hammingAvg/hammingMax`). Only present when `useHashDetection=true`; omitted otherwise
- `driftXFinal/driftYFinal` — accumulated drift at end of frame (from `DecodeStats.driftXFinal/driftYFinal`)

**gate:**
```
frame=N stage=gate pass=true bytes=3391 method=4pt
```
- `pass` — whether quality gate passed
- `bytes` — decoded payload bytes
- `method` — which warp strategy produced the accepted result (duplicates `warp.strategy` intentionally — multiple strategies may be attempted, this records which one succeeded)

### Implementation scope

Modify these functions in `frame_decode_isolate.dart`:
- `decodeFrameInIsolate()` — emit locate line (from `FrameLocator.locate()` result)
- `_tryDecode()` — emit warp line (per strategy attempt)
- `_tryDecodeResized()` — emit wb and decode lines (receives pre-warped image)
- `decodeFrameInIsolate()` — emit gate line, assemble final `debugInfo` from structured lines

The `overlayLine` (short AR overlay string) is unchanged — it serves a different purpose (real-time UI feedback).

### Backward compatibility

This is a replace, not an addition. Old free-text format is removed. Since logs are ephemeral (not persisted or parsed by other tools), there's no migration concern.

## Improvement 2: End-to-End Camera Frame Test

### File

`android/test/core/services/camera_decode_integration_test.dart` — add a new `group('Camera full-frame decode', ...)` alongside the existing tests (which cover crop-path WB validation on pre-cropped fixtures). The existing tests are not modified.

### Approach

Approach C: Call pipeline stages directly with RGB image input (skip YUV conversion). Produce structured diagnostic output matching the logging format above, so test output can be diffed against live ADB logs.

### Pipeline

```
PNG fixture (1280x720)
  → image.decodeImage()
  → FrameLocator.locate()
  → PerspectiveTransform.warpPerspective() (or crop fallback)
  → CimbarDecoder.sampleFinderWhite() (WB)
  → CimbarDecoder.decodeFramePixels() (with WB)
  → CimbarDecoder.decodeRSFrame()
  → Assertions + structured diagnostic output
```

### Fixtures

Two raw camera frame PNGs already committed:
- `test/fixtures/camera_raw_1280x720_a.png` (946KB) — typical scanning frame
- `test/fixtures/camera_raw_1280x720_b.png` (905KB) — best-quality frame from session

Both captured from real phone scanning a 256x256 CimBar barcode on a Dell monitor. Note: the existing camera_decode_integration_test uses different fixtures (`crop_frame_*.png`) for the crop-path WB tests.

### Assertions (sanity gates)

| Check | Assertion | Rationale |
|-------|-----------|-----------|
| Finder detection | `locate()` returns non-null | Finders found at all |
| Finder count | `corners.length == 4` | All 4 corners detected |
| Parallelogram | `devNorm < 0.09` | Validates parallelogram fix |
| Warp output | warped image is `frameSize x frameSize` | Basic warp sanity |
| WB reasonable | each wpR/G/B in `[128, 255]` | White point not absurdly dark or clipped |
| RS partial decode | `rsOk > 0` | At least some blocks decode |

Assertions are intentionally loose. Camera frames may have too many errors for full decode. The test's primary value is diagnostic output for debugging.

### Test structure

```dart
void main() {
  group('Camera full-frame decode', () {
    test('frame A - full pipeline', () {
      final img = _loadFixture('camera_raw_1280x720_a.png');
      final result = _runPipeline(img, frameNum: 1);
      _assertSanity(result);
      _printDiagnostics(result);
    });

    test('frame B - full pipeline', () {
      final img = _loadFixture('camera_raw_1280x720_b.png');
      final result = _runPipeline(img, frameNum: 2);
      _assertSanity(result);
      _printDiagnostics(result);
    });
  });
}
```

**`_loadFixture(name)`** — reads PNG from `test/fixtures/`, decodes to `image.Image`.

**`_runPipeline(img, frameNum)`** — calls each pipeline stage sequentially, captures intermediate results into a `PipelineResult` data class (fields: `LocateResult? locateResult`, `img.Image? warped`, `int? frameSize`, `List<int>? wpRGB`, `String? wbSrc`, `Uint8List? pixelBytes`, `Uint8List? rsBytes`, `DecodeStats? stats`, `String? strategy`), collects structured key-value diagnostic pairs.

**`_printDiagnostics(result)`** — outputs structured lines in the same format as the isolate logging, so output can be compared with ADB logs.

**`_assertSanity(result)`** — runs the loose assertions from the table above.

### What this enables

- Reproduce camera-specific failures without a phone
- Compare test diagnostic output with live ADB logs to pinpoint where behavior diverges
- Regression test for finder detection, warp, WB, and decode on real camera images
- Fast iteration: change code, run test, see structured output — no deploy/scan cycle

## Out of scope

- YUV conversion testing (camera hardware concern, not decode logic)
- Lens distortion correction (planned but not yet implemented)
- Strict decode success assertions (camera quality varies too much)
