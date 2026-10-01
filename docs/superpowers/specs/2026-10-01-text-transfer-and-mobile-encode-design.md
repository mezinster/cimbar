# Text transfer, and encoding on Android/iOS

Status: Approved design, not yet planned
Date: 2026-10-01
Builds on: `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` (frame image, §4.1 file
container), `docs/superpowers/specs/2026-09-18-cimbar-v2.1-rateless-and-compression-design.md`
(coding layer, compression, GIF/present composition)
Ports from: `web-app/cimbar.js`, `web-app/compress.js`, `web-app/gif-encoder.js` (encode side)

## 1. Problem

Often the thing to move between two devices is not a file but a piece of text: a note,
a link, a password, a snippet. Today that means saving it to a file, choosing the file,
and on the receiving side finding the downloaded file and opening it in something else.

And only the web app can send. The Android/iOS app is decode-only, so a phone can never
be the sender: phone-to-phone transfer, the most natural offline case, is impossible.

## 2. Goals and non-goals

Goals:

- **Text mode on every platform.** Type or paste text, encode it, transfer it as CimBar
  (GIF or present mode), and on the receiving device see the text itself, copy it, and save
  it as a `.txt` file.
- **Android/iOS can send.** A Dart encoder producing frames identical to the web encoder,
  shown full screen (present mode) or shared as an animated GIF. The Send screen takes text
  **or a file**.
- **Full interoperability** in all directions: web → app, app → web, app → app; every
  existing receive path (GIF import, share-in, photo, live scan; web GIF/photo/live scan).

Non-goals:

- **No standard QR code.** Text travels in CimBar, reusing compression, encryption and
  rateless repair, with no length limit. (Chosen during design over ISO QR.)
- **No format change.** No new header flag, no container change (§3 explains why).
- No web-side change to file sending or its limits.
- No iOS signing/distribution work (iOS remains compile-checked only, see `app/CLAUDE.md`).
- No rich text, no auto-linking of URLs in received text.

## 3. The text-message convention

A text message is an **ordinary v2.1 file container** (format spec §4.1) whose file name
marks it as text. Nothing on the wire distinguishes it from a file.

**Sender.** Text mode builds the container with
`name = textMessageName(now) = "message-YYYYMMDD-HHMMSS.txt"` (local time, zero-padded)
and `bytes = UTF-8(text)` with no BOM added and line endings left as typed.

**Receiver.** After the existing decode completes (decrypt, inflate, `parsePayload`), the
result is shown as text iff `isTextMessage(name, bytes)`:

1. `name` ends in `.txt`, compared ASCII-case-insensitively (`notes.TXT` qualifies,
   `notes.txt.bin` does not);
2. `bytes.length ≤ 1 048 576` (1 MiB);
3. `bytes` is strictly valid UTF-8 (no overlong forms, no surrogates, no truncated
   sequence). A leading UTF-8 BOM (`EF BB BF`) is allowed and is not shown.

Otherwise the existing file result is shown, unchanged. An empty `.txt` (0 bytes) is a text
message with empty content.

**Why a convention and not a flag.** Header flag bits 3–7 are reserved and every current
decoder rejects a frame that sets one (reason `flags`). A "text" flag would make every frame
unreadable to released apps and the deployed web app, as compression did to v0.9.1. Under
the convention an old receiver still gets a correct `message-….txt` file.

**Accepted side effect.** A small UTF-8 `.txt` file sent as a file is also shown in the text
view. Save still writes it under its original name, so nothing is lost.

**Implementations.** Web: `isTextMessage` and `textMessageName` in `web-app/cimbar.js`
(exported on `Cimbar`; no new page script). Dart: `app/lib/core/format/text_message.dart`.
Both are tested against one shared fixture (§8.1).

## 4. Web app

### 4.1 Encode tab

- A `File | Text` segmented control above the input. File mode is today's drop zone,
  unchanged. Text mode shows a `<textarea>` and, live as the user types, the UTF-8 byte
  count and the frame estimate (`ceil((container + 4) / 2104)` before compression, labelled
  as an upper bound).
- The two inputs are mutually exclusive: switching mode keeps each mode's content but only
  the visible one is encoded.
- Encode with empty text is disabled. Passphrase, frame delay, GIF download and present mode
  are reused unchanged; text mode only replaces where `(fileName, fileBytes)` come from.

### 4.2 Decode result

`finishDecode` (the single completion point for GIF, photo session and live scan) checks
`Cimbar.isTextMessage`. On true it shows a text panel instead of (not in addition to) the
automatic file download:

- read-only, scrollable, selectable text, filled with **`textContent` only, never
  `innerHTML`**; received text is untrusted;
- **Copy** (`navigator.clipboard.writeText`; on failure select the text and show a
  translated "press Ctrl+C" hint);
- **Save as .txt**: downloads the exact received bytes under the received name.

A completed photo session's "no repeat download" guarantee becomes "no repeat result": a
later photo of the same file still does nothing.

## 5. Dart encoder (`app/lib/core/encode/`)

A port of the web encode path. Every unit is pure Dart (no Flutter import) so it runs in an
isolate and in plain `dart test`.

| File | Responsibility | Built on |
|---|---|---|
| `payload_encoder.dart` | `(name, bytes, passphrase?, fileId?) → EncodedPayload{bodies, fileId, encrypted, compressed, total}`: container → deflate if it saves ≥ `compression.minSaving` → optional encrypt → length prefix → split into `total` bodies of 2104 bytes, zero-padded | `FileContainer` (+ new `buildPayload`, `withLengthPrefix`), `ZLibCodec`, `CryptoService.encrypt` |
| `frame_builder.dart` | `sourceFrame(p, seq)`, `repairFrame(p, r)` → 2112-byte frame data (header + body); `gifRepairCount(n)` | `FrameHeader` (+ new `encode`), `Rateless.coefficients`/`combine` |
| `cell_grid.dart` | frame data → `RsFraming.encodeFrame` → `BitPacking.packCells` → 3840 cell values | existing |
| `frame_raster.dart` | cells → 608×608 palette-index buffer (`Uint8List`): quiet zone, finders, 8×8 tiles in palette colors, 1 px black gaps, exactly as `renderFrame` | `Tiles`, `CimbarSpec` |
| `gif_writer.dart` | list of index buffers + delay → GIF89a bytes, global palette in the web encoder's slot order, **no quantization** | `image` package only if it accepts a fixed palette without remapping, else a direct port of `gif-encoder.js`'s LZW |

Rules carried over from the web encoder:

- `fileId` is random (`Random.secure`, 16 bits) unless injected; injection exists for tests.
- `CryptoService.encrypt` gains optional `salt`/`iv` parameters, **test-only**, so encrypted
  goldens can be reproduced; production callers never pass them.
- Compression decision and flag exactly as `compress.js`'s `maybeDeflate` (§2 of the v2.1
  spec). Deflate *bytes* may differ from Node's zlib; only the decision rule and the decoded
  result must match.
- Coding applies only up to `coding.maxFrames`; the mobile UI never exceeds it (§7).

## 6. Mobile UI

### 6.1 Send tab (`app/lib/features/send/`)

A new shell tab **Send** (icon `Icons.send_outlined`), placed first in the bar; the app's
initial route stays `/import`, so launching still opens on receive. Contents:

- `Text | File` toggle. Text: multi-line `TextField` with a live byte count and frame
  estimate. File: the existing `file_picker` flow, showing name and size.
- The existing `PassphraseField` (optional).
- Frame delay: 100 / 200 / 400 ms (default 200 ms), as the web app.
- **Present** and **Share GIF** buttons.

Encoding runs in `Isolate.run` (top-level entry function; the Riverpod-capture pitfall from
`decode_isolate.dart` applies) and reports a translated error on failure.

### 6.2 Present screen

- Pushed with `Navigator.of(context, rootNavigator: true)` (go_router pitfall: a full-screen
  route on the shell's nested navigator survives tab switches).
- `CustomPainter` draws the current cell grid at the largest square that fits the screen
  with a white quiet zone, anti-aliasing off. Black background outside the frame.
- Sequence: source frames `0..N−1` once, then repair frames `r = 0, 1, 2, …` forever. For
  `N = 1` the single source frame repeats. A frame counter is shown below the frame.
- The next frame is built while the current one is displayed. If the §8.2 benchmark shows
  repair generation at the cap does not fit in 100 ms on the main isolate, frames are
  generated in a long-lived background isolate.
- Screen kept awake (`wakelock_plus`) and brightness set to maximum (`screen_brightness`,
  app-level only) while visible. Both are restored on every exit: back, error, dispose,
  app backgrounded (playback also pauses in the background and resumes on return).
- Both plugins must keep the APK at `CAMERA` as its only permission
  (`test/android_manifest_test.dart`) and pull no Google Play Services (F-Droid). If either
  fails that, it is replaced by a small platform channel (`FLAG_KEEP_SCREEN_ON` /
  window brightness; `isIdleTimerDisabled` / `UIScreen.brightness`).

### 6.3 Share GIF

Builds N source + `gifRepairCount(N)` repair frames, writes the GIF to the temp directory as
`<name>.gif` (text mode: the `message-….gif` stem) and hands it to `share_plus`.

### 6.4 Receiving text

`ResultCard` (used by Import, Camera and Live Scan) shows a new `TextResultView` when
`isTextMessage` holds: selectable plain `Text` (no linkify), **Copy** (`Clipboard.setData`
with a snackbar), **Save** (writes the exact bytes into the existing Files list under the
received name) and **Share** (the text, through `share_plus`). Otherwise the existing file UI.

## 7. Limits and errors

| Case | Behaviour |
|---|---|
| Empty text | Encode / Present / Share GIF disabled |
| Mobile send above `coding.maxFrames` source frames (4096, ~8.6 MB) | Present and Share GIF disabled, translated hint with the limit |
| Mobile Share GIF above 500 source frames (~1 MB) | Share GIF disabled with a hint; Present still allowed |
| Received `.txt` invalid UTF-8 or > 1 MiB | Existing file result |
| Decrypt / inflate / RS failures | Unchanged existing messages |
| Clipboard write fails (web) | Text selected, "press Ctrl+C" hint |
| Present screen loses focus / app backgrounded | Pause; wakelock and brightness restored |
| Encode isolate throws | Translated error, Send screen state kept |

Every new user-visible string has a key in all five web languages (`i18n.js`) and all five
ARB files.

## 8. Testing

### 8.1 Shared fixtures (the contract)

- **Encoder parity with the goldens.** For every `test-data/goldens/` case, the Dart encoder
  with the golden's `fileId` (and, for encrypted ones, the golden's salt/IV) must reproduce
  the sidecar's per-frame raw bytes and per-cell values, and `frame_raster` must equal the
  decoded golden GIF frame **pixel for pixel**. Coded goldens: source bodies are taken from
  the sidecar (avoiding deflate-implementation differences) and the repair frames must match
  exactly.
- **Reverse direction.** A Dart tool (`app/tool/gen_dart_goldens.dart`) writes
  `test-data/goldens/dart_text.gif` + sidecar (a multi-line UTF-8 text message with
  Cyrillic, Georgian and emoji, N ≥ 2, repair frames included). `test_goldens.js` decodes it
  and asserts `isTextMessage` and the exact text.
- **`test-data/text-message.json`.** Table of `{name, bytesHex | repeat, expected}` cases:
  plain ASCII, multi-script UTF-8, BOM, `.TXT`, `notes.txt.bin`, no extension, invalid
  continuation byte, overlong form, encoded surrogate, truncated tail, exactly 1 MiB, 1 MiB
  + 1, empty. Asserted by a new `web-app/tests/test_text_message.js` and a Dart test.

### 8.2 Dart

- Round trip: encode → `cell_grid` → `frame_raster` → existing exact `FrameDecoder` →
  `RatelessAssembler` → payload, for source-only, repair-only and shuffled-mixed frames,
  plain/compressed/encrypted.
- `gif_writer` output parses with the existing `GifParser` back to identical index buffers,
  and its palette equals the spec palette in slot order.
- Benchmark: `repairFrame` at N = 345 and N = 4096, printed, asserted under a generous bound.
- Widget tests: Send tab enable/disable rules and caps, Present screen sequence
  (source then repair, pause on lifecycle change, restore on dispose with fake
  wakelock/brightness), `TextResultView` actions.
- `android_manifest_test.dart` still passes (no new permission).

### 8.3 Web

- `test_text_message.js` (§8.1, and `textMessageName` format).
- `test_page_logic.js`: text-mode encode builds the right container; Encode disabled for
  empty text; `finishDecode` shows the text panel (via `textContent`) for a text message
  from each route (GIF, photo session, live scan) and the file download otherwise; Save
  writes the exact bytes.
- `test_i18n.js` covers the new keys automatically.

### 8.4 Manual, on devices

Phone → phone (Present + Live Scan), phone Share GIF → messenger → import on the other
phone, web text → phone (present + Live Scan), phone Present → web live scan, an encrypted
text message each way, and iOS (simulator for Send/Present/Share; device when available).

## 9. Documentation

`CLAUDE.md` (pipeline, module list, test table and counts), `app/CLAUDE.md` (encoder, Send
tab), CHANGELOG, Fastlane full descriptions in five locales ("send text and files from your
phone"), the web About tab. The format spec gains a short §4.1 note pointing to §3 here.

## 10. Build order

1. Shared text rule + fixture (web and Dart).
2. Web text mode (encode toggle, decode text panel).
3. Dart encoder core (`payload_encoder`, `frame_builder`, `cell_grid`), golden byte parity.
4. `frame_raster` + pixel parity; `gif_writer` + `dart_text.gif` golden.
5. Mobile `TextResultView` in `ResultCard`.
6. Send tab + Share GIF.
7. Present screen (wakelock, brightness, lifecycle, benchmark-driven isolate decision).
8. Docs, store text, device checklist.

Steps 1–2 ship value on their own (web ↔ web, web → app receive) and can merge before the
mobile sender if useful.

## 11. Open risks

- **Present mode on a phone screen.** The frame is drawn at non-integer scale, so 1 px gaps
  become 1–2 device pixels; the camera path's homography and drift solver should absorb it,
  but this is verified only on devices (§8.4).
- **Repair-frame cost at N near 4096** on low-end phones: mitigated by the background
  isolate (§6.2), measured by the benchmark.
- **`image` package GIF encoder** may remap palettes; if so, port `gif-encoder.js` (§5).
- **Plugins vs F-Droid/permissions:** guarded by tests, fallback to platform channels (§6.2).
