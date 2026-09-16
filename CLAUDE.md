# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Application

There is no build step. Open `web-app/index.html` directly in a browser, or serve the web-app directory with a local static server (required for Web Crypto API in some browsers):

```bash
cd web-app
python3 -m http.server 8080
# then open http://localhost:8080
```

No npm, no compilation, no install step.

## Architecture

This repo has two components:

- **`web-app/`** — A single-page browser app that encodes any file into an animated GIF where each frame is a grid of colored geometric symbols (Color Icon Matrix Barcode), and decodes it back. Everything runs client-side; there is no server.
- **`android/`** — Android is still on v1 until Plan 2 lands; GIFs produced by the current web app will not decode on Android yet. A Flutter Android app that decodes CimBar GIFs via file import or live camera scanning. Ports the full decode pipeline to Dart. See `android/CLAUDE.md` for Android-specific details.

### Web App

**Encoding pipeline:**

```
File → [optional: encrypt (crypto.js)] → RS encode (rs.js) → draw frames (cimbar.js) → GIF encode (gif-encoder.js) → Animated GIF
```

**Decoding pipeline:**

```
Animated GIF → GIF decode (gif-decoder.js) → sample pixels (cimbar.js) → RS decode (rs.js) → [auto-detect: decrypt (crypto.js)] → File
```

Encryption is optional. On encode, if a passphrase is provided, the payload is encrypted with AES-256-GCM before RS encoding. On decode, encryption is auto-detected by checking for magic bytes `CB 42` at the start of the recovered payload.

**Module responsibilities (all in `web-app/`):**

- `index.html` — all UI (tabs, drag-drop, progress, stats, present mode) and the orchestrating inline `<script>` that drives the full encode/decode flow
- `format.js` — CimBar v2 format constants and pure helpers shared by encoder, decoder and tests: loads `spec/cimbar-v2.json` in Node or `format-data.js` in the browser. Exposes cell geometry (`usableCellPositions`, `cellOrigin`), header codec (`encodeHeader`/`decodeHeader`), bit packing (`packCells`/`unpackCells`, `cellValue`/`cellSymbol`/`cellColor`), and frame byte-budget helpers (`rawBytesPerFrame`, `rsBlockSizes`, `dataBytesPerFrame`, `fileBytesPerFrame`). Exposes `window.CimbarFormat`
- `format-data.js` — **generated**; a browser-loadable mirror of `spec/cimbar-v2.json` (the browser cannot `require()` JSON). Sets `window.CIMBAR_SPEC`. Regenerate with `node tools/gen_format_data.js` whenever the spec changes
- `cimbar.js` — core v2 barcode logic built on `format.js`: `renderFrame`/`decodeFrameExact` (draw/read frame pixels), `encodeRSFrame`/`decodeRSFrame` (RS encode/decode with byte-stride interleaving), `splitIntoFrames`/`FrameAssembler` (chunk a payload into headered frames and reassemble them out of order), `buildPayload`/`parsePayload`/`withLengthPrefix`/`stripLengthPrefix` (file container). Exposes `window.Cimbar`
- `crypto.js` — AES-256-GCM via Web Crypto API; wire format is `[CB 42 01 00 magic | 16-byte salt | 12-byte IV | ciphertext+tag]`. PBKDF2 with 150,000 SHA-256 iterations for key derivation. Exposes `window.CimbarCrypto`
- `rs.js` — Reed-Solomon RS(255, 191) over GF(256): 64 ECC bytes per 255-byte block, tolerates up to 32 byte errors. Berlekamp-Massey + Chien search + Forney. Exposes `class ReedSolomon`
- `gif-encoder.js` — pure-JS GIF89a encoder; builds a 256-color palette seeded with the v2 spec palette, quantizes frames, LZW-compresses. Exposes `class GifEncoder`
- `gif-decoder.js` — pure-JS GIF89a parser; handles LZW decode, interlacing, disposal modes. Returns `Array<{imageData, width, height, delay}>`. Exposes `class GifDecoder`
- `tools/tile_rules.js` — tile representation and the §3.4 constraints (fill ratio, pairwise Hamming distance, shifted-tile Hamming distance, rotation/mirror uniqueness) shared by the generator and `test_tiles.js`
- `tools/gen_tiles.js` — seeded random search that produces the 16-tile set committed to `spec/cimbar-v2.json`. Usage: `node tools/gen_tiles.js [startSeed]`
- `tools/gen_format_data.js` — writes `format-data.js` from `spec/cimbar-v2.json`. Usage: `node tools/gen_format_data.js`
- `tools/gen_goldens.js` — renders reference GIFs with the production encoder into `test-data/goldens/<name>.gif` plus a `<name>.json` ground-truth sidecar (payload, per-frame header, raw bytes, per-cell symbol/color). Usage: `node tools/gen_goldens.js`
- `tools/node_crypto.js` — Node implementation of the `crypto.js` wire format (Node has no Web Crypto) used only so `gen_goldens.js` can produce encrypted goldens without a browser

## Format v2

The wire format is fully specified in `spec/cimbar-v2.json` (the single source of truth, loaded by `web-app/format.js`); the design rationale is in `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md`.

- **Grid:** 64×64 cells. Each cell is 8×8 px with a 1 px black gap after it (9 px pitch), giving a 576 px grid plus a 16 px quiet zone on each side = 608 px frame.
- **Finders:** four QR-style 7×7-cell finder patterns at the grid corners (1:1:3:1:1 ratio), each reserving an 8×8-cell corner block. `usableCells = 4096 − 256 = 3840`.
- **Bits per cell:** 4 colors (green/cyan/yellow/magenta) × 16 tile shapes (8×8 binary tiles from `spec/cimbar-v2.json`, generated by `tools/gen_tiles.js`) = 6 bits/cell (4 symbol bits + 2 color bits).
- **Per-frame byte budget:** `3840 × 6 bits = 2880` raw bytes → RS(255,191) framing gives `2112` data bytes → minus the 8-byte frame header = `2104` file bytes per frame.
- **Frame header** (first 8 bytes of a frame's protected data): `[ver 0x02][flags][fileId u16][seq u16][total u16]`, big-endian, `flags` bit 0 = encrypted.

**Breaking change:** v1 GIFs (7 bits/cell, 8 colors, corner-dot symbols, center metadata block, no per-frame header) do not decode with v2 software, and v2 GIFs do not decode with v1 software.

## Interoperability

The web app encodes and decodes CimBar v2 only. The Android app still implements v1 and cannot decode v2 GIFs; it will move to v2 in Plan 2. Until then, `test-data/goldens/` (golden v2 GIFs plus JSON ground-truth sidecars, generated by `web-app/tools/gen_goldens.js`) is the interoperability contract both sides will be tested against once Android's decoder is ported. Encryption is optional and unchanged across v1/v2 — unencrypted GIFs can be decoded without a passphrase, and encrypted payloads are auto-detected by their `CB 42 01 00` magic header.

The web app is available at https://nfcarchiver.com/cimbar/

## Web App Tests

All tests live in `web-app/tests/`. Run from the `web-app/` directory (no install needed beyond Node.js):

```bash
cd web-app
sh tests/run_all.sh          # run all tests (tiles + format + frame + RS + goldens + pipeline)
node tests/test_tiles.js     # single test
node tests/test_format.js
node tests/test_frame.js
node tests/test_rs.js
node tests/test_goldens.js
node tests/test_pipeline_node.js
python3 tests/test_pipeline.py                              # Python orchestrator (runs all Node tests)
python3 tests/test_pipeline.py ../test-data/goldens/hello.gif 608   # also runs GIF structure check
python3 tests/test_gif.py path/to/output.gif [size]          # standalone GIF check (needs Pillow)
```

| File | What it tests |
|------|--------------|
| `tests/test_tiles.js` | `tools/tile_rules.js` and `tools/gen_tiles.js`: hex↔tile round trip, Hamming/shift/rotation/mirror helpers, `checkTile`/`checkPair`/`checkSet`, deterministic seeded generation, uniform 2×2-block tile structure. |
| `tests/test_format.js` | `format.js` and `spec/cimbar-v2.json`: grid/finder constant self-consistency, palette, tile set validity, capacity derivation (2880/2112/2104), `format-data.js` freshness, reserved-cell geometry, header encode/decode, `packCells`/`unpackCells` round trip, `cellValue`/`cellSymbol`/`cellColor`. |
| `tests/test_frame.js` | `cimbar.js` v2 API: `renderFrame` finder/cell painting, `decodeFrameExact` round trip, `encodeRSFrame`/`decodeRSFrame` (including failed-block zero-fill), `splitIntoFrames` header/padding, `FrameAssembler` accept/dedup/reject/complete, payload helpers, and a full GIF round trip via `MockCanvas`. |
| `tests/test_rs.js` | Reed-Solomon encode/decode: clean round-trip, ≤32 error correction, >32 error detection, Forney/Omega correctness. |
| `tests/test_goldens.js` | Decodes each GIF in `test-data/goldens/` and checks frames, cells, headers and payload against its `<name>.json` ground-truth sidecar (see `tools/gen_goldens.js`). Android's Plan 2/3 test suites are planned to consume the same goldens. |
| `tests/test_pipeline_node.js` | Full GIF encode→decode pipeline. Tests the 4-byte length prefix that prevents AES-GCM auth-tag corruption from RS zero-padding. Three cases: multi-frame, out-of-order assembly, single-frame. |
| `tests/test_gif.py` | Structural check on a real GIF: `GIF89a` magic, 608×608 dimensions, global color table flag, frame count, palette slots 0–5 against the v2 spec palette (+ black, white). Palette/frame checks require Pillow; the rest run without it. |
| `tests/test_pipeline.py` | Python subprocess orchestrator: runs the six Node scripts above and, if a GIF path is given, `test_gif.py`. |
| `tests/mock_canvas.js` | Node.js mock of Canvas 2D API. `getImageData` returns a copy of the pixel buffer (matching browser behavior). |

### Known Subtleties (Web)

- `decodeFrameExact` unpacks exactly `usableCells × 6 / 8 = 2880` bytes (an exact division, no rounding); `decodeRSFrame` uses `format.js`'s `rawBytesPerFrame()` as the byte limit so block boundaries match the encoder.
- `MockCanvas.getImageData` must return a copy (`_pixels.slice()`), not a reference — the real DOM API always copies, and GifEncoder stores the returned object by reference.
- The 4-byte big-endian length prefix in frame data is the only mechanism that strips RS zero-padding before AES-GCM decryption.

## Camera Decode Improvements (from libcimbar C++ analysis)

Reference: [sz3/libcimbar](https://github.com/sz3/libcimbar/tree/master/src/lib)

### Implemented (Priorities 1–5, 7–8)

All implemented in the Android app. See `android/CLAUDE.md` for full details.

1. **White-balance from finder patterns** — Von Kries chromatic adaptation from finder corner cells. Corner quadrant search (8-cell range) finds finder whites through crop padding. WB shared from warp strategies to crop fallback via `whitePoint` parameter
2. **Perspective transform** — DLT homography, 3-tier fallback (4-point → 2-point → crop+resize), NN sampling with `.floor()` (Dart's `.round()` uses banker's rounding which corrupts cell alignment)
3. **Anchor-based finder pattern detection** — bright→dark→bright run-length scanning, brightness-based TL identification + cross-product rotation-invariant classification (asymmetric finders: TL has no inner dot)
4. **Average hash symbol detection with drift tracking** — 64-bit hashes, Hamming distance, ±15px drift accumulation
5. **Relative color matching** — channel-range normalization, (R-G, G-B, B-R) difference comparison
7. **Pre-processing: adaptive threshold + sharpening** — grayscale → optional 3×3 Laplacian sharpen → adaptive threshold (integral image for O(1) local mean). Auto-sharpens when source region < target frame size. Opt-in via `DecodeTuningConfig.useAdaptiveThreshold`. Only affects symbol detection (Pass 1); color detection uses original RGB.
8. **Center-cross color averaging** — 5-pixel cross (center + 4 cardinal neighbors) at grid position for camera color detection, absorbing JPEG noise, subpixel fringing, and interpolation artifacts. GIF path keeps single center pixel. Grid position used (not drift-corrected) because corner dots are at grid-relative positions.

### Planned (not yet implemented)

6. **Lens distortion correction** — radial distortion coefficient from edge midpoint deviation

### Not planned

- **Fountain codes** (wirehair) — our adjacency-chain approach is simpler; fountain codes would require a significant new dependency
