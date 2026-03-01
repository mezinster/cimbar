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
- **`android/`** — A Flutter Android app that decodes CimBar GIFs via file import, binary import, or live camera scanning. Ports the full decode pipeline to Dart. See `android/CLAUDE.md` for Android-specific details.

### Web App

**Encoding pipeline:**

```
File → encrypt (crypto.js) → RS encode (rs.js) → draw frames (cimbar.js) → GIF encode (gif-encoder.js) → Animated GIF
```

**Decoding pipeline:**

```
Animated GIF → GIF decode (gif-decoder.js) → sample pixels (cimbar.js) → RS decode (rs.js) → decrypt (crypto.js) → File
```

**Module responsibilities (all in `web-app/`):**

- `index.html` — all UI (tabs, drag-drop, progress, stats) and the orchestrating inline `<script>` that drives the full encode/decode flow
- `cimbar.js` — core barcode logic: maps bytes→cells (3-bit color + 4-bit symbol = 7 bits/cell), draws finder patterns, reads pixel data back to bytes. Exposes `window.Cimbar`
- `crypto.js` — AES-256-GCM via Web Crypto API; wire format is `[CB 42 01 00 magic | 16-byte salt | 12-byte IV | ciphertext+tag]`. PBKDF2 with 150,000 SHA-256 iterations for key derivation. Exposes `window.CimbarCrypto`
- `rs.js` — Reed-Solomon RS(255, 191) over GF(256): 64 ECC bytes per 255-byte block, tolerates up to 32 byte errors. Berlekamp-Massey + Chien search + Forney. Exposes `class ReedSolomon`
- `gif-encoder.js` — pure-JS GIF89a encoder; builds a 256-color CimBar palette, quantizes frames, LZW-compresses. Exposes `class GifEncoder`
- `gif-decoder.js` — pure-JS GIF89a parser; handles LZW decode, interlacing, disposal modes. Returns `Array<{imageData, width, height, delay}>`. Exposes `class GifDecoder`

## Cell Encoding

Each cell is `CELL_SIZE=8` pixels. A `floor(frameSize/8) × floor(frameSize/8)` grid minus 36 finder-pattern cells (four 3×3 corner blocks) gives usable cells. Each cell encodes 7 bits (3 = color index into 8 colors; 4 = symbol index into 16 shapes). Supported frame sizes: 128, 192, 256, 384 px.

**Symbol design (4-quadrant corner dots):** The 16 symbols are all possible combinations of 4 binary corner markers. For an 8×8 cell, `q = floor(8 × 0.28) = 2 px` and `h = floor(q × 0.75) = 1 px`. The cell is filled with the foreground color; then for each 0-bit in `symIdx`, a `2h × 2h` (2×2) black square is painted at the corresponding corner sample point:

```
bit 3 → TL corner at (q-h, q-h)
bit 2 → TR corner at (size-q-h, q-h)
bit 1 → BL corner at (q-h, size-q-h)
bit 0 → BR corner at (size-q-h, size-q-h)
```

`detectSymbol` samples luma at those same four points plus the center. For the GIF path (no `symbolThreshold`), a point brighter than `center × 0.5 + 20` reads as 1. For the camera path, a configurable multiplicative threshold `center × symbolThreshold` is used instead (default 0.85). The `quadrantOffset` parameter (default 0.28) controls the corner sample position as a fraction of cell size. The center pixel is never covered by a dot, so it always reflects the foreground color and is used for color detection by `nearestColorIdx`.

The visible result is colored squares with 0–4 small black dots at the corners. `symIdx=15` (all bits 1) has no dots. `symIdx=0` (all bits 0) has all four corners dotted.

## RS Block Interleaving

Both encoder (`web-app/cimbar.js encodeRSFrame`) and decoder (`cimbar_decoder.dart decodeRSFrame`, `web-app/cimbar.js decodeRSFrame`) use byte-stride interleaving. After RS-encoding N blocks, byte `j` of block `i` is written to output position `j * N + i`. On decode, the inverse permutation reconstructs each block before RS decoding. Both JS and Dart must use identical block-size computation (same `while` loop). Interleaving is a no-op when N=1.

**Breaking change:** Old GIFs encoded without interleaving will not decode with the new decoder.

## Interoperability

The encrypted binary wire format is compatible across all three implementations: the web app, the Flutter Android app, and the open-source C++ `cimbar` scanner. A GIF encoded with the web app can be decoded by the Android app (via file import or live camera scanning) or scanned with a physical camera and decrypted via the "Import Binary" tab in either app.

The web app is available at https://nfcarchiver.com/cimbar/

## Key Constants (web-app/cimbar.js and android/lib/core/constants/cimbar_constants.dart)

- `CELL_SIZE = 8` (pixels per cell)
- `ECC_BYTES = 64` (RS parity bytes per 255-byte block; RS(255,191) corrects up to 32 errors/block = 12.5%)
- 8-color palette embedded in `web-app/cimbar.js`, `web-app/gif-encoder.js`, and `android/lib/core/constants/cimbar_constants.dart` — must stay in sync across all three

## Web App Tests

All tests live in `web-app/tests/`. Run from the `web-app/` directory (no install needed beyond Node.js):

```bash
cd web-app
sh tests/run_all.sh          # run all tests (symbols + RS + pipeline)
node tests/test_symbols.js   # single test
node tests/test_rs.js
node tests/test_pipeline_node.js
python tests/test_pipeline.py                        # Python orchestrator
python tests/test_pipeline.py output.gif 256         # also runs GIF structure check
python tests/test_gif.py path/to/output.gif [size]   # standalone GIF check (needs Pillow)
```

| File | What it tests |
|------|--------------|
| `tests/test_symbols.js` | `drawSymbol` / `detectSymbol` round-trip for all 128 `(colorIdx 0–7, symIdx 0–15)` combinations via `MockCanvas`. |
| `tests/test_rs.js` | Reed-Solomon encode/decode: clean round-trip, ≤32 error correction, >32 error detection, Forney/Omega correctness. |
| `tests/test_pipeline_node.js` | Full GIF encode→decode pipeline. Tests the 4-byte length prefix that prevents AES-GCM auth-tag corruption from RS zero-padding. Three cases: non-dpf-aligned, dpf-aligned, single-frame. |
| `tests/test_gif.py` | Structural check on a real GIF: `GIF89a` magic, dimensions, color table, frame count, palette slots 0–7. Requires Pillow. |
| `tests/test_pipeline.py` | Python subprocess orchestrator: runs `test_symbols.js`, `test_rs.js`, and optionally `test_gif.py`. |
| `tests/mock_canvas.js` | Node.js mock of Canvas 2D API. `getImageData` returns a copy of the pixel buffer (matching browser behavior). |

### Known Subtleties (Web)

- `decodeFramePixels` returns `ceil(usableCells × 7 / 8)` bytes, but `rawBytesPerFrame` is `floor(...)`. `decodeRSFrame` uses `rawBytesPerFrame(frameSize)` as the byte limit so block boundaries match the encoder.
- `MockCanvas.getImageData` must return a copy (`_pixels.slice()`), not a reference — the real DOM API always copies, and GifEncoder stores the returned object by reference.
- The 4-byte big-endian length prefix in frame data is the only mechanism that strips RS zero-padding before AES-GCM decryption.

## Camera Decode Improvements (from libcimbar C++ analysis)

Reference: [sz3/libcimbar](https://github.com/sz3/libcimbar/tree/master/src/lib)

### Implemented (Priorities 1–5)

All implemented in the Android app. See `android/CLAUDE.md` for full details.

1. **White-balance from finder patterns** — Von Kries chromatic adaptation from finder corner cells
2. **Perspective transform** — DLT homography, 3-tier fallback (4-point → 2-point → crop+resize), NN sampling with `.floor()` (Dart's `.round()` uses banker's rounding which corrupts cell alignment)
3. **Anchor-based finder pattern detection** — bright→dark→bright run-length scanning, brightness-based TL identification + cross-product rotation-invariant classification (asymmetric finders: TL has no inner dot)
4. **Average hash symbol detection with drift tracking** — 64-bit hashes, Hamming distance, ±15px drift accumulation
5. **Relative color matching** — channel-range normalization, (R-G, G-B, B-R) difference comparison

### Planned (not yet implemented)

6. **Lens distortion correction** — radial distortion coefficient from edge midpoint deviation
7. **Pre-processing: adaptive threshold + sharpening** — grayscale → sharpen → adaptive threshold → bitmatrix

### Not planned

- **Fountain codes** (wirehair) — our adjacency-chain approach is simpler; fountain codes would require a significant new dependency
