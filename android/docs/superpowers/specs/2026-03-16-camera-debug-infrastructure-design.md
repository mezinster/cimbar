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

### Fields per stage

**locate:**
```
frame=N stage=locate candidates=7 tl=152,88 tr=410,92 bl=148,350 br=412,354 tlLuma=51 gapOk=true devNorm=0.003
```
- `candidates` — total finder candidates before selection
- `tl/tr/bl/br` — selected corner coordinates (x,y)
- `tlLuma` — TL center pixel luma (for brightness-based TL detection diagnostics)
- `gapOk` — whether brightness gap >= 45 (true = brightness path, false = coordinate fallback)
- `devNorm` — parallelogram deviation normalized by side length squared

**warp:**
```
frame=N stage=warp strategy=4pt srcPts="152,88 410,92 148,350 412,354" dstSize=256
```
- `strategy` — 4pt, 2pt, or crop
- `srcPts` — source corner points used for transform
- `dstSize` — target frame size in pixels

**wb:**
```
frame=N stage=wb r=1.00 g=1.12 b=0.95 src=warp
```
- `r/g/b` — Von Kries channel gains
- `src` — where white point came from: warp (shared from warp strategy), crop (sampled from crop image), none (no WB applied)

**decode:**
```
frame=N stage=decode cells=1015 rsBlocks=28 rsOk=26 rsFail=2 errRate=0.071 hashMean=8.2 hashMax=22 driftX=2 driftY=-1
```
- `cells` — usable cells in frame
- `rsBlocks` — total RS blocks
- `rsOk/rsFail` — RS blocks that decoded/failed
- `errRate` — fraction of cells with errors (from RS correction count)
- `hashMean/hashMax` — average and max hamming distance for symbol detection
- `driftX/driftY` — accumulated drift at end of frame

**gate:**
```
frame=N stage=gate pass=true bytes=3391 method=4pt
```
- `pass` — whether quality gate passed
- `bytes` — decoded payload bytes
- `method` — which warp strategy produced the accepted result

### Implementation scope

Modify these functions in `frame_decode_isolate.dart`:
- `_tryDecode()` — emit locate, warp, wb, decode lines
- `_tryDecodeResized()` — emit locate, warp, wb, decode lines (crop path)
- `decodeFrameInIsolate()` — emit gate line, assemble final `debugInfo` from structured lines

The `overlayLine` (short AR overlay string) is unchanged — it serves a different purpose (real-time UI feedback).

### Backward compatibility

This is a replace, not an addition. Old free-text format is removed. Since logs are ephemeral (not persisted or parsed by other tools), there's no migration concern.

## Improvement 2: End-to-End Camera Frame Test

### File

`android/test/core/services/camera_decode_integration_test.dart`

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

Both captured from real phone scanning a 256x256 CimBar barcode on a Dell monitor.

### Assertions (sanity gates)

| Check | Assertion | Rationale |
|-------|-----------|-----------|
| Finder detection | `locate()` returns non-null | Finders found at all |
| Finder count | `corners.length == 4` | All 4 corners detected |
| Parallelogram | `devNorm < 0.09` | Validates parallelogram fix |
| Warp output | warped image is `frameSize x frameSize` | Basic warp sanity |
| WB reasonable | each gain in `[0.5, 2.0]` | Not wildly overcorrecting |
| RS partial decode | `rsOk > 0` | At least some blocks decode |

Assertions are intentionally loose. Camera frames may have too many errors for full decode. The test's primary value is diagnostic output for debugging.

### Test structure

```dart
void main() {
  group('Camera decode integration', () {
    test('frame A - full pipeline', () async {
      final img = _loadFixture('camera_raw_1280x720_a.png');
      final result = _runPipeline(img, frameNum: 1);
      _assertSanity(result);
      _printDiagnostics(result);
    });

    test('frame B - full pipeline', () async {
      final img = _loadFixture('camera_raw_1280x720_b.png');
      final result = _runPipeline(img, frameNum: 2);
      _assertSanity(result);
      _printDiagnostics(result);
    });
  });
}
```

**`_loadFixture(name)`** — reads PNG from `test/fixtures/`, decodes to `image.Image`.

**`_runPipeline(img, frameNum)`** — calls each pipeline stage sequentially, captures intermediate results into a `PipelineResult` data class, collects structured key-value diagnostic pairs.

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
