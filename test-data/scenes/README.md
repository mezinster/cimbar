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
  "cells": [3840 ints]
}
```

- `finderCenters` are the exact (not detected) TL/TR/BL/BR finder-core centers
  in scene pixels, derived analytically from the scene's placement.
- `homography` is the row-major 3x3 frame-to-scene projective transform
  (`h[8] == 1`).
- `cells` is the ground-truth 6-bit value (`symbol << 2 | color`) of each of
  the 3840 usable cells of the golden frame named by `golden`/`frameIndex` —
  i.e. `test-data/goldens/<golden>.json`'s `frames[frameIndex].cells`, never a
  decode of the degraded scene itself.

## Consumers

- `app/test/tool/scene_fixtures_test.dart` (Dart): asserts every PNG has a
  sidecar and that each fixture decodes to its recorded `cells` through a
  grid built from its recorded `finderCenters`.
- The web app's JavaScript decode-layer port (Task 4/7 of the web photo
  decode plan) reads the same PNGs and sidecars as its own ground truth.
