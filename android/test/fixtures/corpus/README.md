# Real-capture corpus

Each case is a directory with a `meta.json` and (normally) a `capture.png`, plus a pointer to
the golden that was on screen. `test/core/decode/corpus_benchmark_test.dart` decodes every
case, prints one table row each (also written to `build/corpus_report.txt`, echoed by
`tests/run_all.sh`), and asserts the case's `expect` block. Thresholds are only ever raised.

`meta.json`:

```json
{
  "capture": "capture.png",
  "device": "Pixel 7",
  "display": "Dell U2720Q 27in 4K, present mode",
  "distanceCm": 40,
  "golden": "hello",
  "frame": 0,
  "expect": { "status": ["ok"], "symbolAccuracy": 0.99, "colorAccuracy": 0.99, "rsOkBlocks": 12 }
}
```

- `golden`: name of the sidecar in `test-data/goldens/` shown when the capture was taken, or
  `null` for negative cases. `frame`: which frame of that golden was on screen.
- `expect.status`: acceptable `DecodeStatus` names. Accuracy and RS thresholds apply only
  when `golden` is set and the status is `ok`.

Capture checklist (spec §9.3): for `hello` and `lorem_12k`, in present mode, using the app's
debug capture button: laptop monitor at 30 cm and 60 cm, straight-on and ~20° angled;
phone-to-phone at 15 cm and 30 cm; one in dim light. Record device and display names.

The two `v1_720p_negative_*` cases point at the existing v1 captures and must never decode.
