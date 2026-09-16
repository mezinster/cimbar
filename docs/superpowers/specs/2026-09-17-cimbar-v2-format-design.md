# CimBar v2: Camera-First Format and Decoder — Design Spec

Date: 2026-09-17
Status: Approved design, awaiting implementation plan

## 1. Why

An audit on 2026-09-16 established that no real camera frame has ever RS-decoded with the
current (v1) format. Both real 1280×720 fixtures produce `rsOk=0 rsFail=4 errRate=1.000`, and
the test suite stays green only because the camera integration tests assert that RS was
*attempted* rather than that it *succeeded*. Even geometrically well-aligned crop fixtures
sit at Hamming 17–19 against a random baseline of ~32.

The causes are in the format, not in any one decoder stage:

- Symbol features are 2×2 px dots inside 8 px cells, at the resolution limit of a
  monitor→camera→nearest-neighbour-resample chain.
- Finders are 24 px squares, the same size as a colored cell, so colored cells become
  finder candidates.
- Eight colors spanning luma 64–226 entangle the symbol (dark vs. lit) decision with the
  color decision.
- No gaps between cells, so grid phase cannot be recovered locally.
- No per-frame header, so frame order is inferred from content hashes.
- Four candidate frame sizes multiply every failed frame's work by four.

v2 is a new format designed for the camera path first, kept simple enough that the exact
GIF path is a special case of the same decoder. It replaces v1 completely: v1 GIFs will not
decode with v2 software. This is the third accepted breaking change in the project's history.

## 2. Goals and non-goals

Goals:

- Reliable live decode of a GIF shown on a laptop/desktop monitor and on another phone.
- One decoder shared by Android live scan, Android single photo, Android GIF import and
  web GIF decode.
- A measurement harness (CLI decoder, golden GIFs with ground truth, real-capture corpus
  with asserted thresholds) built before the decoder, so every change is measured.
- One source of truth for the encoder (JS) and one for format constants (a spec JSON).

Non-goals for this milestone:

- Fountain codes. Per-frame sequence numbers are sufficient; missed frames are picked up
  on the next GIF loop.
- Grid sizes other than 64×64. The format supports them (see §3.2) but the decoder rejects
  them in this milestone.
- Printed barcodes.
- Backward compatibility with v1 GIFs.
- Lens distortion correction.

## 3. Frame image

All constants in this section live in `spec/cimbar-v2.json` (§7.1). Numbers here are the
milestone-1 values.

### 3.1 Geometry

| Constant | Value | Notes |
|---|---|---|
| `gridCells` | 64 | cells per side |
| `cellPx` | 8 | lit/dark tile content |
| `gapPx` | 1 | black gap after each cell, right and below |
| `pitchPx` | 9 | `cellPx + gapPx` |
| `gridPx` | 576 | `gridCells × pitchPx` |
| `quietPx` | 16 | black border on every side |
| `framePx` | 608 | `gridPx + 2 × quietPx` |

Background is black everywhere. Only cells and finders contain non-black pixels.

Cell `(col, row)` occupies pixels `x = quietPx + col × pitchPx … +cellPx−1`,
`y = quietPx + row × pitchPx … +cellPx−1`. The gap column/row after it is black.

### 3.2 Finders

Four QR-style finders occupy the 7×7-cell corners of the grid. Each is drawn as solid
blocks with the 1:1:3:1:1 ratio, in cell-pitch units (9 px), with no gaps inside:

- 63×63 px white square,
- 45×45 px black square inset by 9 px,
- 27×27 px white core inset by 18 px.

The 15 cells of each 8×8 corner block not covered by the 7×7 finder (an L on the finder's
inward sides) are left black as a separator. Each corner therefore reserves an 8×8-cell block; 256 cells
in total are reserved and `usableCells = 4096 − 256 = 3840`.

Corner cell ranges: TL cols 0–7 rows 0–7; TR cols 56–63 rows 0–7; BL cols 0–7 rows 56–63;
BR cols 56–63 rows 56–63. Finder centers in cell coordinates: TL (3.5, 3.5),
TR (60.5, 3.5), BL (3.5, 60.5), BR (60.5, 60.5). In pixels: `quietPx + c × pitchPx`.

Asymmetry for orientation: the TL finder's core is solid white. TR, BL and BR carry a
9×9 px black dot at the center of the core (the core's middle cell). The decoder identifies
TL as the finder whose core center is dark-free.

Grid size derivation: `gridCells = round(7 × barcodeSidePx / finderSidePx)`, where both
lengths are measured between finder centers in the same units. A decoder that measures a
value other than 64 reports `unsupportedGrid` and stops. This is how future grid sizes will
be added without a header change.

### 3.3 Colors

Four colors, all bright against black so that lit-vs-dark is a luma decision independent of
hue:

| Index | Name | RGB |
|---|---|---|
| 0 | green | (0, 255, 0) |
| 1 | cyan | (0, 255, 255) |
| 2 | yellow | (255, 255, 0) |
| 3 | magenta | (255, 85, 255) |

Magenta is brightened (G = 85) so its luma stays above 120. The GIF palette contains
exactly these four plus black and white; no quantization is needed.

### 3.4 Symbols (tiles)

Sixteen 8×8 binary tiles. Bit set = pixel lit in the cell color; bit clear = black. A tile
is stored as a 64-bit value, row-major, MSB = top-left pixel, as a 16-hex-digit string.

The tile set is produced once by `web-app/tools/gen_tiles.js` (seeded random search) and
committed to the spec JSON. Constraints the generator enforces and the format unit tests
re-verify:

- fill ratio between 40 % and 60 % (26–38 lit pixels),
- pairwise Hamming distance ≥ 24 between any two tiles,
- pairwise Hamming distance ≥ 16 between any tile and any other tile shifted by
  (±1, 0), (0, ±1) or (±1, ±1) pixels, with the shifted-in border treated as dark,
- no tile equal to another under 90°/180°/270° rotation or mirroring (rotation is resolved
  by the finders, but this keeps orientation errors from aliasing to valid tiles).

Symbol index = position in the array (0–15).

### 3.5 Bit packing

Each cell carries 6 bits: the 4 symbol bits (high) followed by the 2 color bits (low).
The frame's raw byte stream (§4.3) is read MSB-first as a bit stream; cells are filled in
row-major order over all 4096 grid positions, skipping the reserved corner cells. The first
usable cell is (col 8, row 0) and the last is (col 55, row 63).
`3840 × 6 = 23 040 bits = 2 880 bytes` exactly, so no padding bits exist.

## 4. Frame payload

### 4.1 File container (unchanged from v1)

```
[u32 nameLen][name utf8][file bytes]           = payload
payload | CimbarCrypto.encrypt(payload, pass)  = framedPayload (encrypted if passphrase given)
[u32 framedPayload.length][framedPayload]      = framedData
```

Encryption wire format, PBKDF2 parameters and the `CB 42 01 00` magic are unchanged.
`framedData` is split into consecutive chunks of `dataBytesPerFrame − 8` bytes; the last
chunk is zero-padded by the RS encoder as today, and the u32 length prefix strips the
padding on decode.

### 4.2 Frame header

The first 8 bytes of every frame's protected data:

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 | version | `0x02` |
| 1 | 1 | flags | bit 0: encrypted; bits 1–7: 0 |
| 2 | 2 | fileId | big-endian, random per encode run, same in all frames |
| 4 | 2 | seq | big-endian, 0-based |
| 6 | 2 | total | big-endian, number of frames, ≥ 1 |

A decoded frame is **accepted** when all hold: RS succeeded for every block, `version ==
0x02`, `total ≥ 1`, `seq < total`, and, if frames are already collected, `fileId` and
`total` equal the collected ones. A frame with a different `fileId` and successful RS
resets the collection and becomes its first frame. Reserved flag bits 1–7 must be 0; a
non-zero reserved bit rejects the frame (reason `flags`). A frame is rejected when any RS
block fails (reason `rs`).

### 4.3 Reed-Solomon layout

Unchanged codec: RS(255, 191) over GF(256), `ECC_BYTES = 64`, Berlekamp-Massey + Chien +
Forney. Block partition uses the existing loop: fill 255-byte blocks while more than 64
bytes remain; a final short block takes the remainder. For 2 880 raw bytes:

- 11 full blocks: 11 × 191 = 2 101 data bytes,
- 1 short block of 75 bytes: 11 data + 64 ECC,
- `dataBytesPerFrame = 2 112`, of which 8 are the header, so **2 104 file bytes per
  frame**.

Interleaving: with block sizes `s_0..s_{N-1}` (here eleven 255-byte blocks then one
75-byte block), output is produced by iterating `j` from 0 to max(s_i)−1 and, inside it,
`i` from 0 to N−1, appending byte `j` of block `i` whenever `j < s_i`. For `j < 75` this
is position `j × N + i`; for `j ≥ 75` the short block contributes nothing and the
position is `75 × N + (j − 75) × (N − 1) + i`. De-interleaving walks the same loop. Both
encoder and decoder must use exactly this loop; a literal `j × N + i` for all `j` is
wrong.

`ECC_BYTES` stays a single spec constant so it can be retuned from measured block error
rates after the corpus exists.

### 4.4 Assembly

`FrameAssembler` holds `total` slots. An accepted frame is written to slot `seq` (a
repeat is ignored). Complete when every slot is filled; the concatenation of slots in order,
truncated by the u32 length prefix, is `framedPayload`. Progress shown to the user is
`filled / total`.

## 5. GIF container and display

- Frames are 608×608 px, written with the existing `gif-encoder.js`, looping forever.
- Frame delay options become 100 ms, 200 ms (default), 400 ms.
- The web app gets a **present mode**: full-viewport, black background,
  `image-rendering: pixelated`. Scale = the largest integer multiple of 608 px that fits
  the shorter viewport side. If that integer scale leaves more than 40 % of the shorter
  side unused, fractional fit-to-viewport scaling is used instead, because a larger
  barcode with slightly uneven pixel widths beats a small one with exact pixels for the
  camera. If the shorter side is below 608 px (a phone in portrait), the scale is the
  fractional fit below 1× so the whole frame stays on screen. Examples: 1080p monitor →
  1× would use 56 %, so fractional 1.77× (1076 px); 1440p monitor → 2× (1216 px);
  1080-wide phone → 1.77× on the width; 390 px CSS-wide phone → 0.64×.
- The preview thumbnail no longer caps height at 280 px; it shows the GIF at 1× or
  scaled down with `pixelated` only where the viewport is narrower than 608 px.
- Frame-size selection is removed from the UI.

## 6. Decoder

### 6.1 Entry point

```
FrameDecoder.decode(RgbImage image, {GridModel? exactGrid}) → FrameResult
FrameResult { status, Uint8List? data, FrameHeader? header, Diagnostics diag }
status ∈ { ok, notLocated, unsupportedGrid, rsFailed, badHeader }
```

Used by: the live-scan isolate, the single-photo controller, the Android GIF import
pipeline, and (a JS port of the exact path) the web GIF decoder. `exactGrid` is passed by
the GIF paths and skips stages 6.2–6.3.

### 6.2 Locate

1. Luma plane (from the Y plane directly on Android live scan; BT.601 from RGB elsewhere),
   downscaled 2× by area average.
2. Row scan: a row through a finder center reads, on the black background,
   `light(1) dark(1) light(3) dark(1) light(1)` in module units, bounded by dark on both
   sides. Find run sequences matching that 1:1:3:1:1 pattern with every run within 50 %
   of the module estimate (total length ÷ 7).
3. Column scan through the center of each row hit; keep hits whose vertical module
   estimate is within 50 % of the horizontal one.
4. Cluster hits within one module; a cluster is a candidate with center and module size.
5. Choose four: for each pair of candidates as diagonal, find the pair whose
   parallelogram closure error is smallest (existing `devNorm` logic); reject if the best
   error exceeds 0.09 of the mean side length or any two chosen module sizes differ by
   more than 2×.
6. Classify TL: sample a 3×3 px patch at each candidate's center in **full-resolution**
   luma; TL is the one with the brightest center, and it must exceed the others by at
   least 40 luma. Otherwise `notLocated`. Order TR/BL by cross product against TL→BR.

No luma bounding-box fallback, no center-square crop, no multi-size loop.

### 6.3 Grid model

Homography (DLT, existing math) from the four finder centers to cell coordinates
(3.5, 3.5), (60.5, 3.5), (3.5, 60.5), (60.5, 60.5). Grid size check per §3.2. White point
= per-channel 90th-percentile RGB over the four finders' 27×27-core regions, mapped through
the homography; Von Kries adaptation as today. `GridModel` exposes
`toSource(cellX, cellY) → (x, y)` for fractional cell coordinates.

### 6.4 Cell sampling

For each usable cell, sample its 64 tile pixels at fractional cell coordinates
`(col + (i + 0.5)/8, row + (j + 0.5)/8)` mapped to source, bilinear, into an 8×8 RGB patch
and its luma. Sampling happens at source resolution; no intermediate warped image.

### 6.5 Drift

Per cell, a 2D offset in source pixels. Cells are visited by flood fill from the four
corners inward (BFS over the grid, seeds at the four cells adjacent to each finder). A
cell's initial drift is the mean of its already-visited neighbours' drifts. The cell is
sampled at initial drift and at the 8 neighbours at ±1 px; the position with the lowest
Hamming distance wins; if the best is > 20 the search widens to ±2 (24 positions). Drift is
clamped to ±6 px. Diagnostics record the final drift field.

### 6.6 Symbol

Average hash of the 8×8 luma patch (bit = luma > patch mean). Hamming distance to the
16 tiles; the minimum is the symbol. Distance and the runner-up gap go to diagnostics.

### 6.7 Color

Mean RGB over the winning tile's lit pixels only, white-balanced, then nearest palette
entry by Euclidean distance in normalized chroma `(R−G, G−B, B−R) / max(R,G,B)`. Distance
margin goes to diagnostics.

### 6.8 Unpack, RS, header

Bits from cells → 2 880 bytes → de-interleave → RS decode each block → header validation
per §4.2. `Diagnostics` holds: finder centers and module sizes, homography, white point,
Hamming histogram, color margin histogram, drift field stats, per-block RS outcome
(ok / corrected N / failed), stage timings, and, when ground truth is supplied, per-cell
symbol and color correctness.

### 6.9 Removed from v1

Frame-size loop, 4pt/2pt/crop strategy chain, center-crop fallback, LAB failover, adaptive
threshold preprocessing, RS quality gate, center metadata block, content-hash
deduplication, adjacency chain, `symbolThreshold`/`quadrantOffset`/`useRelativeColor`/
`useHashDetection`/`useAdaptiveThreshold` tuning, Settings tuning sliders (the debug toggle
stays).

## 7. Shared spec and code layout

### 7.1 `spec/cimbar-v2.json`

Top-level keys: `version`, `grid` (§3.1 constants), `finder` (sizes, corner cells, center
cells, dot spec), `palette` (4 RGB triples), `tiles` (16 hex strings), `bits`
(`symbolBits: 4`, `colorBits: 2`), `rs` (`blockTotal: 255`, `eccBytes: 64`), `header`
(field offsets and sizes), `gif` (`framePx`, delay options). Loaded at build/test time by
`web-app/format.js` (via a generated `format-data.js` for the browser, produced by
`tools/gen_format_data.js`) and by Dart tests that assert `CimbarSpec` constants equal it.

### 7.2 Android

```
lib/core/format/    cimbar_spec.dart, tiles.dart, palette.dart, frame_header.dart, bit_packing.dart
lib/core/decode/    finder_locator.dart, grid_model.dart, cell_sampler.dart, drift_solver.dart,
                    cell_classifier.dart, frame_decoder.dart, frame_assembler.dart, diagnostics.dart
lib/core/camera/    luma_plane.dart (Y plane + ROI RGB), capture_policy.dart (focus/exposure lock, hints)
lib/core/services/  reed_solomon.dart, galois_field.dart, crypto_service.dart, gif_parser.dart,
                    file_service.dart, decode_pipeline.dart (GIF import, now calls FrameDecoder)
tool/decode_image.dart   CLI (pure Dart)
```

Deleted: `camera_decode_pipeline.dart`, `frame_locator.dart`, `symbol_hash_detector.dart`,
`image_preprocessing.dart`, `perspective_transform.dart` (homography math moves to
`grid_model.dart`), `frame_decode_isolate.dart` decode chain (the isolate wrapper remains
and calls `FrameDecoder`), `live_scanner.dart` (replaced by `frame_assembler.dart`),
`decode_tuning_config.dart`, `decode_tuning_provider.dart`, tuning UI in
`settings_screen.dart`, `test/test_utils/cimbar_encoder.dart`.

### 7.3 Web

`format.js` (spec constants, tiles, palette, header codec, bit packing), `cimbar.js`
(v2 frame renderer and exact frame decoder built on `format.js`), `rs.js`, `crypto.js`,
`gif-encoder.js`, `gif-decoder.js` unchanged, `index.html` (present mode, frame-size menu
removed, delay options per §5), `tools/gen_tiles.js`, `tools/gen_goldens.js`,
`tools/gen_format_data.js` (Node).

## 8. Camera acquisition (Android)

- `ResolutionPreset.veryHigh` (1080p) YUV stream.
- Locate runs on the Y plane only. RGB conversion is limited to the bounding box of the
  four finders plus one module margin.
- One long-lived decode isolate receiving frames over a `SendPort`; frames arriving while
  one is in flight are dropped before any copy is made.
- After the first `ok` or `rsFailed`-with-4-finders result, lock focus and exposure
  (`setFocusMode(locked)`, `setExposureMode(locked)`); unlock after 2 s without a located
  frame.
- Static aiming square in the preview; the decode region equals the preview region (the
  preview uses `BoxFit.contain`, not `cover`). Hints derived from diagnostics: finder
  module < 5 px → "move closer"; module > 40 px → "move back"; finder centers moved >
  10 px between consecutive frames → "hold still"; four finders but `rsFailed` → "adjust
  angle or lighting".
- Progress text: `filled / total` frames, from the header.
- Single photo uses `CameraController.takePicture()` at the plugin's maximum resolution
  instead of `image_picker`; gallery import stays on `image_picker`.
- Performance target: `FrameDecoder.decode` ≤ 150 ms for a 1080p frame on a mid-range
  2022 phone, so every GIF frame at 200 ms delay is seen on the first loop.

## 9. Measurement harness and tests

### 9.1 Goldens

`web-app/tools/gen_goldens.js` renders a fixed set of GIFs with the production JS encoder
into `test-data/goldens/<name>.gif` plus `<name>.json`: the input file bytes, name,
passphrase (if any), and for each frame the header fields, the raw 2 880 bytes, and the
per-cell symbol and color indices. Both suites consume the same goldens. The Dart test
encoder is deleted.

Set: `hello.txt` (1 frame), `lorem_12k.bin` random bytes (6 frames), `lorem_12k` encrypted
(6 frames), `edge_2104.bin` (exactly one frame of data), `edge_2105.bin` (one byte into a
second frame).

### 9.2 CLI decoder

`dart run tool/decode_image.dart <image.png|jpg> [--golden <name.json> --frame <n>]
[--heatmap out.png] [--json]`. Prints the structured stage lines (`stage=locate …`,
`stage=grid …`, `stage=cells …`, `stage=rs …`, `stage=header …`) and, with a golden,
symbol accuracy, color accuracy, and the Hamming and color-margin histograms. `--heatmap`
writes a PNG marking wrong cells. Exit code 0 on `ok`, 1 otherwise.

### 9.3 Corpus

`android/test/fixtures/corpus/<case>/capture.png`, `golden.json` (copy or pointer),
`meta.json` with: `device`, `display`, `distanceCm`, `frame` (which golden frame was on
screen), and `thresholds` `{ symbolAccuracy, colorAccuracy, rsOkBlocks }`. The corpus
benchmark test iterates all cases, prints one table row each, and asserts each case's
thresholds. Thresholds are only ever raised. The two existing 720p v1 captures remain as a
negative case that must return `notLocated` or `unsupportedGrid`.

Initial corpus capture checklist (user, after step 6 of §10): for each of `hello` and
`lorem_12k`, in present mode, capture with the debug capture button: laptop monitor at
30 cm and 60 cm, straight-on and ~20° angled; phone-to-phone at 15 cm and 30 cm; one in
dim light. Record device and display names.

### 9.4 Test layers

| Layer | JS | Dart |
|---|---|---|
| Spec constants match `spec/cimbar-v2.json` | yes | yes |
| Tile set satisfies §3.4 constraints | yes | yes |
| Header and bit-packing round-trips | yes | yes |
| Golden GIF exact decode = payload | yes | yes |
| Synthetic degradations of goldens (scale 1.5–2.5×, rotate 0–360°, perspective skew up to 20°, Gaussian blur σ ≤ 1.5 source px, brightness ±30 %, noise σ 8) → full payload | – | yes |
| Locator on goldens composited onto real photo backgrounds, finder centers within 2 px | – | yes |
| Corpus benchmark with asserted thresholds | – | yes |
| RS, GF, crypto, GIF codec (existing) | yes | yes |

### 9.5 Diagnostics hygiene

Real frame numbers in every log line, dead stopwatches removed, `tests/run_all.sh` prints
the corpus table, CI runs the benchmark and fails on threshold misses.

## 10. Build order

Each step leaves both suites green and is committed separately.

1. `spec/cimbar-v2.json`, `gen_tiles.js`, `format.js`, `cimbar_spec.dart` + format unit
   tests on both sides.
2. JS v2 renderer and exact decoder, `gen_goldens.js`, web golden round-trip tests,
   `index.html` present mode and UI changes.
3. `tool/decode_image.dart` skeleton and corpus benchmark scaffolding (reporting only).
4. Dart `FrameDecoder` exact path, `FrameAssembler`, GIF import switched over, golden
   tests.
5. `FinderLocator`, `GridModel`, `CellSampler`, `DriftSolver`, `CellClassifier`; synthetic
   degradation tests and composited-background locator tests.
6. Camera acquisition (§8), isolate rewired, single photo on the camera plugin.
7. User captures the initial corpus; tune; set thresholds.
8. Delete v1 code (§6.9, §7.2), update `CLAUDE.md`, `android/CLAUDE.md`, `README.md`,
   `CHANGELOG.md`.

Steps 1–5 need no device. Step 7 is the only step that needs the user at a phone.

## 11. Open risks

- Drift (§6.5) is the stage most likely to need iteration; the harness exists to make that
  iteration measurable.
- Pure-Dart throughput at 1080p may miss the 150 ms target on low-end phones; the ROI
  conversion and single isolate are the planned mitigations, FFI is the fallback.
- Present mode at 1× on a 1080p monitor gives 8 px cells on screen; the phone must be
  close enough that a cell spans ≥ 5 camera px. The "move closer" hint covers this.
