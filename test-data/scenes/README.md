# Scene fixtures

Generated files — do not hand-edit. Each `<name>.png` / `<name>.json` pair is a
synthetic camera-like scene (a golden GIF frame composited into a canvas with
a known scale, rotation, keystone, blur, brightness, noise or seed) rendered
by the same harness the Dart camera-decode test suite uses
(`app/test/test_utils/synthetic_scene.dart`), so both the Dart and the
JavaScript decode-layer test suites can assert against one shared ground
truth instead of each re-implementing scene rendering.

Regenerate with:

```bash
cd app
dart run tool/gen_scene_fixtures.dart
```

## Sidecar shape

```json
{
  "name": "plain_s13",
  "golden": "hello",
  "frameIndex": 0,
  "width": 1920,
  "height": 1080,
  "finderCenters": { "tl": [x, y], "tr": [x, y], "bl": [x, y], "br": [x, y] },
  "homography": [9 doubles],
  "locate": {
    "candidates": int, "clusters": int,
    "module": double, "devNorm": double,
    "tlLuma": double, "secondLuma": double,
    "corners": { "tl": [x, y], "tr": [x, y], "bl": [x, y], "br": [x, y] }
  },
  "decode": {
    "wrong": int, "wrongIndices": [ints],
    "blocksFailed": int,
    "hammingMean": double, "hammingMax": int,
    "driftMeanAbs": double, "driftMaxAbs": double
  },
  "cells": [3840 ints]
}
```

- `finderCenters` are the exact (not detected) TL/TR/BL/BR finder-core centers
  in scene pixels, derived analytically from the scene's placement.
- `homography` is the row-major 3x3 frame-to-scene projective transform
  (`h[8] == 1`).
- `locate` is what the **Dart `FinderLocator` detected** in the committed PNG
  (not the analytic `finderCenters` above it, which is the geometric truth the
  locator is *trying* to find). It exists as the Dart <-> JS parity contract:
  `web-app/finder-locator.js` is a transliteration of
  `app/lib/core/decode/finder_locator.dart`, and both suites assert these
  numbers, so either side drifting is a test failure rather than a silent
  divergence. `candidates`/`clusters` must match exactly; the floats are
  asserted to 1e-9 (the observed delta between the two runtimes is 0).
- `decode` is what the **Dart `FrameDecoder.decode` camera path** (locate ->
  homography -> grid gate -> white point -> drift -> sample/classify -> RS)
  produced from the committed PNG. It is the Dart <-> JS parity contract for
  everything *below* the locator, which the `locate` block alone cannot pin:
  the homography fit, the white point, the drift field, the sampler and the
  classifier could all diverge between the two ports with both suites still
  green. `wrong`/`wrongIndices` are measured against the `cells` ground truth
  below, and both suites assert the exact index **set**, not a percentage —
  1% of 3840 is 38 cells, which fits inside RS's 32-byte-per-block correction
  budget, so a real divergence (a transposed drift index, a sign flip on
  dx/dy) would decode cleanly and never show up. Seven fixtures record
  `wrong: 0`; `blur_s20` records four indices. Integers must match exactly;
  the floats are asserted to 1e-12 (the observed delta between the two
  runtimes is 0 on every fixture, including `blur_s20`'s wrong-cell set,
  which is the *same four cells* on both sides).
- `cells` is the ground-truth 6-bit value (`symbol << 2 | color`) of each of
  the 3840 usable cells of the golden frame named by `golden`/`frameIndex` —
  i.e. `test-data/goldens/<golden>.json`'s `frames[frameIndex].cells`, never a
  decode of the degraded scene itself.

## Consumers

- `app/test/tool/scene_fixtures_test.dart` (Dart): asserts every PNG has a
  sidecar, that each fixture decodes to its recorded `cells` through a grid
  built from its recorded `finderCenters`, and that the Dart `FinderLocator`
  and full camera path still reproduce their recorded `locate` and `decode`
  blocks.
- `web-app/tests/test_finder_locator.js` (JavaScript): asserts the ported
  locator lands within 2 px of `finderCenters`, that its module estimate is
  within 1 px of `9 * scale`, and that it reproduces the recorded `locate`
  block field-for-field.
- `web-app/tests/test_photo_decode.js` (JavaScript): runs the ported chain
  (`CimbarPhoto.decode`) over each PNG and asserts the `decode` block
  field-for-field — the exact wrong-cell index set, `blocksFailed`, and the
  hamming/drift diagnostics.
