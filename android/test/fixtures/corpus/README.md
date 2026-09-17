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

The camera path is real: a case's status comes from the locator → homography → white point → drift → RS chain, and the table's `hammingMean` and `symbolAcc` are meaningful. Real captures are still to be added (spec §9.3 checklist).

To capture one from a device:

1. In the app, go to Settings → Developer and turn on the debug switch.
2. Open Camera → Live Scan.
3. Triple-tap the status panel at the bottom of the screen to turn on the debug overlay (this also reveals a camera icon in the top-right).
4. Aim the phone at the barcode (present mode on a monitor, or phone-to-phone) per the capture checklist above.
5. Tap the camera icon. It saves `capture_<ts>.png` (the full RGB camera frame) and `capture_<ts>.txt` (`status=` plus one `key=value` diagnostic line per field, including `seq=`) to the app's documents directory.
6. Pull both files off the device, e.g.:
   ```
   adb shell run-as <applicationId> ls files/          # find the exact filenames
   adb exec-out run-as <applicationId> cat files/capture_<ts>.png > capture_<ts>.png
   adb exec-out run-as <applicationId> cat files/capture_<ts>.txt > capture_<ts>.txt
   ```
   (or browse to them with Android Studio's Device Explorer, under `data/data/<applicationId>/app_flutter/`).
7. Create a new `test/fixtures/corpus/<case>/` directory with `capture.png` (the pulled PNG) and a `meta.json` following the format above — set `golden` and `frame` from what was on screen when you captured it (`frame` is the `seq=` value in the pulled `.txt` file).
