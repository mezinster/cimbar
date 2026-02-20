# CimBar — Color Icon Matrix Barcode

CimBar encodes any file into an animated GIF where each frame is a grid of colored squares, then decodes it back.

Try it now at **https://nfcarchiver.com/cimbar/**

This repo contains:

- **`web-app/`** — A browser-based encoder/decoder. Everything runs client-side — no server, no install, no data leaves your machine.
- **`android/`** — A Flutter Android app that decodes CimBar GIFs via file import, binary import, or (future) live camera scanning.

Each cell in the grid carries 7 bits of data: 3 bits select one of 8 colors, and 4 bits select one of 16 symbol patterns. Files are encrypted with AES-256-GCM before encoding, so the GIF is unreadable without the passphrase.

### What the symbols look like

The 16 symbol patterns are all combinations of 4 binary corner markers. Each 8×8 cell is filled with its foreground color; then for each 0-bit in the symbol index, a small 2×2 black dot is placed at the corresponding corner:

```
bit 3 → top-left      bit 2 → top-right
bit 1 → bottom-left   bit 0 → bottom-right
```

So `symIdx=15` (all bits 1) is a plain solid square — no dots. `symIdx=0` (all bits 0) has a dot at every corner. All other 14 patterns have 1–3 dots in various corner combinations.

The center pixel is always the foreground color (never dotted), which is how color detection works — the decoder samples the center to identify which of the 8 colors the cell is, then samples the 4 corners to read the symbol bits.

This approach was chosen over more decorative shapes (circles, triangles, etc.) because it guarantees a perfect round-trip: the decoder samples exactly the pixels the encoder painted, with no ambiguity.

---

## Quick Start

### Option A — Open directly

Just open `web-app/index.html` in a modern browser (Chrome, Edge, Firefox). No web server needed.

### Option B — Local server (recommended for Firefox)

Firefox requires a server for the Web Crypto API to work:

```bash
cd web-app
python3 -m http.server 8080
```

Then open `http://localhost:8080` in your browser.

---

## Encoding a file

1. Click the **Encode** tab.
2. Drag and drop any file onto the drop zone, or click it to browse.
3. Enter a passphrase. Keep it — you'll need it to decode.
4. Choose a **frame size** (larger = more data per frame, slower to encode):
   - `128 px` — ~70 KB per frame
   - `192 px` — ~160 KB per frame
   - `256 px` — ~285 KB per frame (default, good balance)
   - `384 px` — ~660 KB per frame
5. Click **Encrypt & Encode to GIF**.
6. Watch the preview animate as frames are rendered.
7. Click **Download GIF** to save the result.

The stats panel shows the number of frames, encoded size, and usable cells per frame.

---

## Decoding a GIF

1. Click the **Decode** tab.
2. Drag and drop the GIF file, or click to browse.
3. Enter the same passphrase used during encoding.
4. Click **Decode & Decrypt**.
5. The original file is downloaded automatically with its original filename.

If the passphrase is wrong or the GIF is corrupted, you will see an error message.

---

## Importing a binary payload

The **Import Binary** tab accepts the raw encrypted binary that the open-source C++ `cimbar` scanner produces when it reads a physical CimBar printout with a camera. Paste or load the binary and enter the passphrase to decrypt it directly, without needing the GIF.

---

## Android App

The `android/` directory contains a Flutter app that can decode CimBar GIFs on Android devices.

### Features

- **Import GIF** — Pick a CimBar GIF file, enter the passphrase, decode and save the original file
- **Import Binary** — Decrypt raw binary output from the C++ `cimbar` scanner
- **Camera** — Coming soon (placeholder in MVP)
- **Settings** — Language selection (English, Russian, Turkish, Ukrainian, Georgian)

### Building

Requires Flutter 3.24+ and Java 17:

```bash
cd android
flutter pub get
flutter gen-l10n
flutter build apk --debug      # debug APK
flutter build apk --release    # release APK
```

### Running tests

```bash
cd android
flutter test
```

The Android app ports the full decode pipeline from the web app to Dart, including GF(256) arithmetic, Reed-Solomon RS(255,223), CimBar pixel decoding, and AES-256-GCM decryption — all with matching unit tests.

---

## Error correction

Each frame uses Reed-Solomon RS(255, 223) coding: up to 16 byte errors per 255-byte block can be corrected automatically. This makes the GIF resilient to minor pixel corruption (e.g., from re-encoding or screenshots), though lossless transfer is strongly preferred.

---

## Wire format

The encrypted binary has a fixed header for interoperability with the C++ `cimbar` scanner:

```
[CB 42 01 00]  4 bytes  magic
[16 bytes]     16 bytes salt  (random per file)
[12 bytes]     12 bytes IV    (random per file)
[variable]     ciphertext + 16-byte AES-GCM tag
```

Key derivation: PBKDF2-SHA256, 150,000 iterations.

Inside the GIF frames, the frame stream begins with a 4-byte big-endian `uint32` length prefix (= encrypted payload length) so the decoder can strip Reed-Solomon zero-padding before passing the ciphertext to AES-GCM.

---

## Running the tests

### Web App

Tests require only Node.js (no npm). Run from the `web-app/` directory:

```bash
cd web-app
sh tests/run_all.sh
```

Individual tests:

```bash
cd web-app
node tests/test_symbols.js        # symbol encode/decode round-trip (128 combos)
node tests/test_rs.js             # Reed-Solomon correction
node tests/test_pipeline_node.js  # full GIF pipeline with length prefix
python tests/test_gif.py path/to/output.gif 256   # GIF structure (needs Pillow)
python tests/test_pipeline.py                     # Python orchestrator
```

### Android App

Requires Flutter SDK:

```bash
cd android
flutter test
```

Tests cover GF(256) arithmetic, Reed-Solomon encode/decode, symbol round-trip, AES-GCM crypto, and the full RS frame pipeline.

---

## Compatibility

**Web App:** Requires Web Crypto API (`crypto.subtle`). Works in all modern browsers on HTTPS or `localhost`. Does not work on `file://` in Firefox (use the local server method above).

**Android App:** Requires Android 7.0+ (API 24). Built with Flutter 3.24+.
