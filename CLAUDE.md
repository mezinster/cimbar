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
- **`android/`** — (planned) An Android app that uses the camera to scan and decode CimBar GIFs.

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
- `rs.js` — Reed-Solomon RS(255, 223) over GF(256): 32 ECC bytes per 255-byte block, tolerates up to 16 byte errors. Berlekamp-Massey + Chien search + Forney. Exposes `class ReedSolomon`
- `gif-encoder.js` — pure-JS GIF89a encoder; builds a 256-color CimBar palette, quantizes frames, LZW-compresses. Exposes `class GifEncoder`
- `gif-decoder.js` — pure-JS GIF89a parser; handles LZW decode, interlacing, disposal modes. Returns `Array<{imageData, width, height, delay}>`. Exposes `class GifDecoder`

**Cell encoding:** Each cell is `CELL_SIZE=8` pixels. A `floor(frameSize/8) × floor(frameSize/8)` grid minus 18 finder-pattern cells gives usable cells. Each cell encodes 7 bits (3 = color index into 8 colors; 4 = symbol index into 16 shapes). Supported frame sizes: 128, 192, 256, 384 px.

**Symbol design (4-quadrant corner dots):** The 16 symbols are all possible combinations of 4 binary corner markers. For an 8×8 cell, `q = floor(8 × 0.28) = 2 px` and `h = floor(q × 0.75) = 1 px`. The cell is filled with the foreground color; then for each 0-bit in `symIdx`, a `2h × 2h` (2×2) black square is painted at the corresponding corner sample point:

```
bit 3 → TL corner at (q-h, q-h)
bit 2 → TR corner at (size-q-h, q-h)
bit 1 → BL corner at (q-h, size-q-h)
bit 0 → BR corner at (size-q-h, size-q-h)
```

`detectSymbol` samples luma at those same four points plus the center; a point brighter than `center × 0.5 + 20` reads as 1, darker reads as 0. The center pixel is never covered by a dot, so it always reflects the foreground color and is used for color detection by `nearestColorIdx`. This design was chosen to guarantee a perfect encode→decode round-trip: every bit position is sampled at exactly the pixel that was drawn for it.

The visible result is colored squares with 0–4 small black dots at the corners. `symIdx=15` (all bits 1) has no dots — a plain solid square. `symIdx=0` (all bits 0) has all four corners dotted.

## Interoperability

The encrypted binary wire format is compatible with the open-source C++ `cimbar` scanner. A GIF encoded here can be scanned with a physical camera and the resulting binary decrypted via the "Import Binary" tab in the UI.

## Key Constants (web-app/cimbar.js)

- `CELL_SIZE = 8` (pixels per cell)
- `ECC_BYTES = 32` (RS parity bytes per 255-byte block)
- 8-color palette embedded in both `web-app/cimbar.js` and `web-app/gif-encoder.js` — must stay in sync

## Test Suite

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

### Test files

| File | What it tests |
|------|--------------|
| `tests/test_symbols.js` | `drawSymbol` / `detectSymbol` round-trip for all 128 `(colorIdx 0–7, symIdx 0–15)` combinations via `MockCanvas`. Each cell must encode and decode back to the exact same 7-bit value. |
| `tests/test_rs.js` | Reed-Solomon encode/decode: clean round-trip, correction of ≤16 injected errors, detection of >16 errors (uncorrectable), and Forney/Omega correctness with errors at known positions. |
| `tests/test_pipeline_node.js` | Full GIF encode → GIF decode pipeline in Node.js using `MockCanvas` + `GifEncoder` + `GifDecoder` + `encodeRSFrame`/`decodeRSFrame`. Tests the 4-byte length prefix that prevents AES-GCM auth-tag corruption from RS zero-padding. Three cases: non-dpf-aligned payload, exactly dpf-aligned payload, and single-frame tiny payload. |
| `tests/test_gif.py` | Structural check on a real GIF file: `GIF89a` magic, correct dimensions, global color table, frame count, and palette slots 0–7 matching the 8 CimBar base colors. Requires `pip install pillow`. |
| `tests/test_pipeline.py` | Python subprocess orchestrator: runs `test_symbols.js`, `test_rs.js`, and optionally `test_gif.py`, prints a PASS/FAIL summary. |
| `tests/mock_canvas.js` | Node.js mock of the browser Canvas 2D API (`fillStyle`, `fillRect`, `getImageData`). `getImageData` returns a copy of the pixel buffer (matching browser behavior — avoids shared-buffer bugs in multi-frame tests). |

### Known subtleties

- `decodeFramePixels` returns `ceil(usableCells × 7 / 8)` bytes, but `rawBytesPerFrame` is `floor(...)`. `decodeRSFrame` explicitly uses `rawBytesPerFrame(frameSize)` as the byte limit so block boundaries match the encoder exactly.
- `MockCanvas.getImageData` must return a copy (`_pixels.slice()`), not a reference — the real DOM API always copies, and GifEncoder stores the returned object by reference.
- The 4-byte big-endian length prefix in frame data (written by the encoder, read by the decoder) is the only mechanism that strips RS zero-padding before AES-GCM decryption.
