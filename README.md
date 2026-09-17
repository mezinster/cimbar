# CimBar — Color Icon Matrix Barcode

CimBar encodes any file into an animated GIF where each frame is a grid of colored squares, then decodes it back.

Try it now at **https://nfcarchiver.com/cimbar/**

This repo contains:

- **`web-app/`** — A browser-based encoder/decoder. Everything runs client-side — no server, no install, no data leaves your machine.
- **`android/`** — A Flutter Android app that decodes CimBar GIFs via GIF import, live camera scanning, or a photo.

Each cell in the grid carries 6 bits of data: 2 bits select one of 4 bright colors (green, cyan, yellow, light magenta — RGB (255, 85, 255)), and 4 bits select one of 16 tile shapes drawn on a black background. A single 608 px frame size fits four QR-style finder patterns, one at each corner, so the decoder can locate and orient the grid at a glance — from a camera as well as from an exact image. Every frame carries a header with a sequence number and total frame count, so frames can be captured out of order and reassembled. Files can optionally be encrypted with AES-256-GCM before encoding, so the GIF is unreadable without the passphrase.

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

## Deploying the web app

The web app is deployed to `https://nfcarchiver.com/cimbar/` by the manual GitHub Actions workflow **Deploy web app** (`.github/workflows/deploy-webapp.yml`), the same pipeline shape as the NFC Archiver and Banana Split web apps that share the bucket. Run it from the Actions tab on `master` (the `production` environment refuses other branches); tick *dry_run* to see the upload plan without touching S3. The build job runs the web test suite, stages exactly the files `index.html` loads, stamps `<!-- cimbar-build:<sha> -->` into the page, and hands the bundle to a credentialed job that snapshots the live prefix, uploads scripts then `index.html` (no-cache), invalidates CloudFront, and verifies the public URL with `web-app/tools/healthcheck.js`; a failed verification restores the snapshot. Credentials come from GitHub OIDC (`AWS_DEPLOY_ROLE_ARN` on the `production` environment); the bucket, prefix, distribution and site URL are environment variables.

## Android App

The `android/` directory contains a Flutter app that decodes CimBar v2 GIFs on Android devices via file import, in-app photo capture, or live camera scanning.

### Features

- **Import GIF** — Pick a CimBar GIF file, optionally enter the passphrase, decode and save/share the original file
- **Camera** — Take a photo in-app (or pick one from the gallery) for a single-frame barcode, or use Live Scan for a multi-frame animated barcode
- **Settings** — Developer debug switch (live-scan diagnostics overlay/logcat and corpus capture button), language selection (English, Russian, Turkish, Ukrainian, Georgian)

### Live Camera Scanning

For multi-frame CimBar barcodes (animated GIFs):

1. Go to the **Camera** tab, optionally enter the passphrase, and tap **Live Scan** to open the full-screen camera.
2. Line the barcode up inside the aiming square; the camera locks focus and exposure once it's found, and unlocks again if it's lost for 2 seconds.
3. Hints ("move closer", "move back", "hold still", "adjust angle/lighting") appear when the barcode is located but not decoding well.
4. A progress bar shows frames filled out of the total as they're captured, in any order.
5. When all frames are captured, the app auto-decrypts (if needed) and shows the result.

The scanner reassembles frames using their header's sequence number and total frame count — no adjacency-chain guessing is needed. Each camera frame is decoded on a background isolate so the UI stays responsive; a busy decoder simply drops the next frame rather than queuing it.

### Building

Requires Flutter 3.44+ and Java 17:

```bash
cd android
flutter pub get
flutter gen-l10n
flutter build apk --debug      # debug APK
flutter build apk --release    # release APK
```

Note: the Android build pins Gradle 9.1 / AGP 9.0.1 to match Flutter 3.44; use Flutter 3.44 or newer (see `android/CLAUDE.md`'s Build section).

### Running tests

```bash
cd android
sh tests/run_all.sh
```

The Android app ports the full v2 decode pipeline from the web app to Dart — GF(256) arithmetic, Reed-Solomon RS(255,191), the finder locator, homography grid model, white balance, drift solver, cell classifier, AES-256-GCM decryption, and the live-scan/photo capture layer — all with matching unit tests, plus a synthetic-degradation test harness and a real-capture corpus benchmark.

### Capturing a corpus sample

The decode pipeline is also checked against real camera captures, not just synthetic scenes. To contribute one: enable Settings → Developer → debug switch, start Live Scan, triple-tap the status panel to turn on the capture button, aim at a barcode, and tap the camera icon to save a `capture_<ts>.png`/`.txt` pair to the app's documents directory. See `android/test/fixtures/corpus/README.md` for how to pull those files off the device and turn them into a corpus test case.

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

Requires the Flutter SDK:

```bash
cd android
sh tests/run_all.sh           # never bare `flutter test` — see android/CLAUDE.md's Build section
```

Tests cover GF(256) arithmetic, Reed-Solomon encode/decode, the v2 format layer (header, bit packing, RS framing, file container), the camera decode layer (finder locator, homography grid model, white balance, drift solver, cell classifier) against a synthetic-degradation harness, AES-256-GCM crypto, `CapturePolicy`, `DecodeIsolate`, photo and GIF-import decode, and a real-capture corpus benchmark.

---

## Compatibility

**Web App:** Requires Web Crypto API (`crypto.subtle`). Works in all modern browsers on HTTPS or `localhost`. Does not work on `file://` in Firefox (use the local server method above).

**Android App:** Requires Android 7.0+ (API 24). Built with Flutter 3.44+.
