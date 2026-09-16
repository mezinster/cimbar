# CimBar — Color Icon Matrix Barcode

CimBar encodes any file into an animated GIF where each frame is a grid of colored squares, then decodes it back.

Try it now at **https://nfcarchiver.com/cimbar/**

This repo contains:

- **`web-app/`** — A browser-based encoder/decoder. Everything runs client-side — no server, no install, no data leaves your machine.
- **`android/`** — A Flutter Android app that decodes CimBar GIFs via file import, binary import, or live camera scanning.

**Note:** the Android app still implements the previous (v1) format; GIFs from the current web app will not decode on Android until the v2 port lands.

Each cell in the grid carries 6 bits of data: 2 bits select one of 4 bright colors (green, cyan, yellow, light magenta — RGB (255, 85, 255)), and 4 bits select one of 16 tile shapes drawn on a black background. A single 608 px frame size fits four QR-style finder patterns, one at each corner, so the decoder can locate and orient the grid at a glance — from a camera as well as from an exact image. Every frame carries a header with a sequence number and total frame count, so frames can be captured out of order and reassembled. Files are encrypted with AES-256-GCM before encoding, so the GIF is unreadable without the passphrase.

This is the CimBar v2 format — it replaces the original 7-bit/8-color/corner-dot format completely. **Files encoded before this change must be re-encoded**; old GIFs will not decode with the current app, and GIFs made with the current app will not decode with an older version.

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
4. Optionally choose a **frame delay** — `100 ms` (fast), `200 ms` (default), or `400 ms` (slow). There is no frame-size choice in v2: every barcode is a single 608×608 px frame.
5. Click **Encrypt & Encode to GIF**.
6. Watch the preview animate as frames are rendered.
7. Click **Download GIF** to save the result, or **Present full screen** to show the looping GIF full-screen (scaled to fit the viewport) for another device's camera to scan.

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
- **Camera** — Single-photo capture for single-frame barcodes, plus live multi-frame scanning for animated barcodes. Camera decode uses white balance correction, relative color matching, and configurable symbol sensitivity to handle varying lighting conditions.
- **Settings** — Decode tuning (symbol sensitivity, white balance, relative color matching, quadrant offset — all adjustable at runtime and persisted), language selection (English, Russian, Turkish, Ukrainian, Georgian)

### Live Camera Scanning

For multi-frame CimBar barcodes (animated GIFs), the app supports live camera scanning:

1. Go to the **Camera** tab and enter the passphrase.
2. Tap **Live Scan** to open the full-screen camera.
3. Point the camera at the cycling animated GIF on another screen.
4. The overlay shows progress: "Scanning... X/Y frames captured".
5. When all frames are captured, the app auto-decrypts and shows the result.

The scanner handles multi-cycle capture — it can pick up different frames across multiple animation loops and reassemble them in the correct order using adjacency-chain tracking. CimBar frames have no sequence numbers, so the scanner identifies frame order by observing which frame follows which during live capture, and detects frame 0 by its 4-byte length prefix.

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

The Android app ports the full decode pipeline from the web app to Dart, including GF(256) arithmetic, Reed-Solomon RS(255,191), CimBar pixel decoding, AES-256-GCM decryption, and live camera scanning — all with matching unit tests.

---

## Error correction

Each frame uses Reed-Solomon RS(255, 191) coding: 64 ECC bytes per 255-byte block, so up to 32 byte errors per block can be corrected automatically. This makes the GIF resilient to minor pixel corruption (e.g., from re-encoding or screenshots), though lossless transfer is strongly preferred.

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
node tests/test_tiles.js          # tile rules and generator
node tests/test_format.js         # format spec, header, bit packing
node tests/test_frame.js          # frame render/decode, RS framing, assembler
node tests/test_rs.js             # Reed-Solomon correction
node tests/test_goldens.js        # golden GIFs vs. ground-truth sidecars
node tests/test_pipeline_node.js  # full GIF pipeline with length prefix
python3 tests/test_pipeline.py ../test-data/goldens/hello.gif 608   # Python orchestrator + GIF structure check
python3 tests/test_gif.py path/to/output.gif 608                    # GIF structure (needs Pillow)
```

### Android App

Requires Flutter SDK:

```bash
cd android
flutter test
```

Tests cover GF(256) arithmetic, Reed-Solomon encode/decode, symbol round-trip (including camera-exposure threshold), AES-GCM crypto, the full RS frame pipeline, YUV→RGB conversion, and live scanner logic (deduplication, adjacency-chain ordering, frame 0 detection, multi-frame assembly).

---

## Compatibility

**Web App:** Requires Web Crypto API (`crypto.subtle`). Works in all modern browsers on HTTPS or `localhost`. Does not work on `file://` in Firefox (use the local server method above).

**Android App:** Requires Android 7.0+ (API 24). Built with Flutter 3.24+.
