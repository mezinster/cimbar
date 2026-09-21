# Web app — live camera scanning

Status: Implemented (plan: docs/superpowers/plans/2026-09-21-web-live-scan.md)
Date: 2026-09-21
Builds on: `docs/superpowers/specs/2026-09-21-web-photo-decode-design.md` (the photo
decode chain and the cross-photo session this feeds; its §9 deferred live scan to here),
`docs/superpowers/specs/2026-09-18-cimbar-v2.1-rateless-and-compression-design.md` (coding layer)
Ports from: `app/lib/core/services/capture_policy.dart`,
`app/lib/features/camera/live_scan_controller.dart` (Android Live Scan)

## 1. Problem

The web app decodes a CimBar barcode from a GIF or from photos. For a
multi-frame file shown on another screen — the normal case, since present mode
exists to be scanned — the photo path makes the user tap the shutter once per
accepted frame. A 120-frame file is 120+ deliberate photos.

The target scenario (chosen during design) is **a phone browser scanning a
screen** that shows a CimBar GIF or present mode: file transfer with no app
installed, and the only camera route on iPhone, which has no store app yet. A
laptop webcam scanning a phone (the reverse direction) should work where it
happens to, but is not designed for.

## 2. Scope

In scope:

- A "Scan with camera" button on the Decode tab opening a full-screen
  viewfinder (`getUserMedia`) that decodes frames continuously in a Web Worker.
- Frames feed **the same session as photos** (`photoSession` and its
  `RatelessAssembler`): scanning, closing, adding a photo of a missing frame
  and scanning again all count toward one file.
- Focus/exposure lock (a port of Android's `CapturePolicy`) where the browser
  supports it — Chrome on Android — and continuous autofocus elsewhere.
- User hints (move closer / move back / hold still / tilt / point at the
  barcode), a finder overlay, a progress counter, and a `?debug=1` panel.
- A local Playwright end-to-end tool driving Chromium's fake camera.

Out of scope:

- ROI cropping or downscaling of camera frames (Android's `RoiHint`). Deferred
  until real-phone timings show locate dominates (§11).
- Zoom and torch controls, a camera picker, `exposureCompensation`.
- Saving a debug capture to a file.
- Any change to the decode modules (`photo-decoder.js` and the eight modules
  under it). Live scan calls `CimbarPhoto.decode` unmodified, so the Dart↔JS
  scene-fixture contract (`test-data/scenes/`) is untouched.

## 3. Why this is feasible now, and where it is weak

Measured during the 2026-09-21 spike: the photo decode chain runs in
110–130 ms per frame in a desktop browser; a phone browser is 3–4× slower,
roughly 2–4 decoded frames per second.

v2.1 coding makes the frame rate mismatch harmless. Present mode shows a frame
every 100/200/400 ms; the scanner catches whichever frames it catches, and any
N linearly independent frames complete the file. Progress is set by decoded
frames per second, not by the display rate, and a frame captured mid-transition
fails RS and is dropped without stalling anything.

The weakness is camera control. `ImageCapture` and the `focusMode` /
`exposureMode` constraints exist only in Chrome (desktop, Android). Safari,
Firefox and every iOS browser (all WebKit) expose no focus lock, so the camera
may hunt mid-scan. There the scanner is best-effort: continuous autofocus,
fewer good frames, same correctness. Detection is by capability, never by
user agent (§6.2).

## 4. Architecture

```
main thread                                           worker (scan-worker.js)
───────────                                           ───────────────────────
<video> ─ frame callback ─ busy? skip
          │
          drawImage → canvas → getImageData
          │
          postMessage({id, width, height, buffer}, [buffer]) ─────►  CimbarPhoto.decode
                                                                          │
          ◄───────────── {id, status, data, blocksFailed, corners, module, diag}
          │
          CapturePolicy.update → hint, lockAction → applyConstraints
          overlay + hint + progress + debug line
          status === 'ok' → onFrame(result) → page's addFrame → photoSession.asm
```

Units and boundaries:

| Unit | Kind | Responsibility | Depends on |
|---|---|---|---|
| `web-app/scan-worker.js` | new, worker script | Loads the decode chain; turns `{id, width, height, buffer}` into a decode result. Stateless. | the decode page scripts, via `importScripts` |
| `web-app/capture-policy.js` | new, page script | `CapturePolicy.update(outcome, nowMs) → {hint, lockAction}`. Pure logic. | nothing |
| `web-app/live-scan.js` | new, page script | `LiveScan` controller (`window.CimbarLiveScan`): camera, frame loop, worker lifecycle, lock constraints, overlay, debug panel. Receives `onFrame(result)` from the page; knows nothing about sessions. | DOM, `Worker`, `CimbarCapturePolicy` |
| `web-app/index.html` | edited | Scanner markup; the button; `addFrame` (shared by photos and live scan); session wiring. | all of the above |
| `web-app/i18n.js` | edited | New keys in all five languages. | — |

The assembler stays on the main thread. Completion (`finishDecode`, passphrase
retry, `confirm()`, download) needs the DOM, and a stateless worker is
disposable — it can be terminated and respawned without losing anything, as
Android does with its decode isolate (`_onIsolateDeath`).

## 5. The worker (`scan-worker.js`)

Every decode module is a classic-script IIFE that reads its dependencies from
`window.*` when `module` is undefined. A worker has no `window`, so the worker
script begins:

```js
self.window = self;
importScripts('rs.js', 'format-data.js', 'format.js', 'rateless.js', 'cimbar.js',
              'rgb-buffer.js', 'luma-plane.js', 'homography.js', 'finder-locator.js',
              'white-point.js', 'cell-sampler.js', 'cell-classifier.js',
              'drift-solver.js', 'photo-decoder.js');
```

in the same relative order as `index.html`. `importScripts` runs them in one
shared global scope — the same situation `test_browser_load.js` already
simulates for the page — so none of them changes.

Message protocol:

- request: `{ id, width, height, buffer }` — `buffer` is the RGBA
  `ArrayBuffer` from `getImageData`, **transferred**, not copied.
- reply: `{ id, status, data, blocksFailed, corners, module, diag }` where
  `corners` and `module` are copied out of `diag` for convenience, `data` is
  a `Uint8Array` (or `null`), and `status` is one of `CimbarPhoto.decode`'s
  statuses (`ok`, `notLocated`, `tooSmall`, `unsupportedGrid`, `rsFailed`,
  `badHeader`).
- An exception inside `decode` is caught and replied as
  `{ id, status: 'error', message }`. It never escapes to the worker's
  `error` event; that event is reserved for load failure and crashes.

`cells` and `raw` from the decode result are not sent back (unused on the main
thread, and 3840 + 2880 bytes per frame of needless copying).

## 6. Camera acquisition

### 6.1 Opening the camera

Opened only from the "Scan with camera" tap (iOS requires a user gesture):

```js
navigator.mediaDevices.getUserMedia({ audio: false, video: {
  facingMode: { ideal: 'environment' },
  width: { ideal: 1920 }, height: { ideal: 1080 } } })
```

- `ideal`, never `exact`: a device without 1080p falls back silently. The
  debug panel shows the resolution actually delivered.
- The `<video>` carries `playsinline muted autoplay`; without `playsinline`
  iOS Safari takes over in its own fullscreen player.
- Errors map to translated messages, each pointing at "Take a photo":
  `NotAllowedError`/`SecurityError` → `camDenied`; `NotFoundError`/
  `OverconstrainedError` → `camNone`; `NotReadableError`/`AbortError` →
  `camBusy`; anything else → `camFailed`.
- If `navigator.mediaDevices?.getUserMedia` is absent (insecure context, old
  browser), the button is hidden and the page is exactly as today.

### 6.2 Focus and exposure lock

At start, read `track.getCapabilities?.()`:

- **Focus lock supported** iff `capabilities.focusMode` includes both
  `'manual'` and `'continuous'`. **Exposure lock supported** iff
  `capabilities.exposureMode` includes both `'manual'` and `'continuous'`.
  Either can be supported without the other; the debug header shows
  `lock=focus+exposure`, `lock=focus`, `lock=exposure` or `lock=unsupported`.
- On `lockAction === 'lock'`: read `track.getSettings()` and pin the current
  values — `{ focusMode: 'manual', focusDistance: settings.focusDistance }`
  and/or `{ exposureMode: 'manual', exposureTime: settings.exposureTime }`,
  each included only if supported and the setting is a number — in one
  `applyConstraints({ advanced: [ … ] })`. Pinning the current value is the
  web equivalent of CameraX locking where it is: setting `'manual'` alone lets
  some devices jump to a default focus distance.
- On `lockAction === 'unlock'`: `{ focusMode: 'continuous' }` and/or
  `{ exposureMode: 'continuous' }`.
- If `applyConstraints` rejects, log it to the debug panel, **disable locking
  for the rest of this scan**, and keep scanning. A failed lock never stops
  decoding.

Without lock support, `CapturePolicy` still runs — its hints do not depend on
locking — and its lock actions are ignored.

### 6.3 Frame acquisition

- Use `video.requestVideoFrameCallback` where present (Chrome, Safari 15.4+):
  it fires once per new camera frame. Otherwise poll with
  `requestAnimationFrame`, skipping ticks where `video.currentTime` has not
  changed.
- A frame is taken only when no decode is in flight (back-pressure, as
  Android's `wantsFrame`); callbacks during a decode do nothing. A slow phone
  lowers fps; no queue ever builds.
- The frame is drawn at `video.videoWidth × video.videoHeight` into a canvas
  obtained with `getContext('2d', { willReadFrequently: true })`, read with
  `getImageData`, and its buffer transferred to the worker.

### 6.4 Lifecycle

- The camera is released (`track.stop()` on every track) on close, on
  completion, on `visibilitychange` → `hidden`, and on `pagehide`.
- Returning to a hidden-then-visible tab shows the scanner **paused**, with a
  "Resume" button (`scanResume`), rather than silently reopening the camera.
- The worker is created when the scanner opens and terminated when it closes.

## 7. Scan loop

### 7.1 Per result

1. `CapturePolicy.update(outcome, now)` → `{ hint, lockAction }`; apply
   `lockAction` (§6.2).
2. Redraw the overlay (§9.3), hint line and debug line.
3. If `status === 'ok'`, call the page's `onFrame(result)`. Only `ok` frames
   reach the session — the rule Android's `_onOutcome` and today's `addPhoto`
   both follow. `rsFailed` frames (including mid-transition captures of
   present mode) are dropped.
4. Clear `busy`.

### 7.2 Worker failures

- A worker `error` event, a reply with `status: 'error'`, or no reply within
  **10 s** of posting counts as one failure: terminate the worker, spawn a
  new one, clear `busy`, continue.
- Three consecutive failures stop scanning and show `scanDecoderFailed`.
  Any successful reply resets the count. (Android: `_onIsolateError`, three in
  a row.)
- A reply whose `id` is not the in-flight request's (a late reply from a
  terminated worker cannot arrive, but a stale id guards the timeout race) is
  ignored.

## 8. Capture policy (`capture-policy.js`)

A transliteration of `app/lib/core/services/capture_policy.dart` with the
same constants: `minModulePx = 6`, `maxModulePx = 40`, `motionPx = 10`,
`unlockAfterMs = 2000`, and the same decision order (module too small → too
large → corner motion → `rsFailed`).

- **Located** means `corners` is non-null **and** `status` is one of `ok`,
  `rsFailed`, `badHeader`, `unsupportedGrid`, `tooSmall`. `tooSmall` is a
  web-only status (the photo decoder's module floor, which runs after the
  locator has filled `corners` and `module`); including it makes a small
  barcode produce `moveCloser` through the module rule. A locator-level
  `tooSmall` (image under 16 px) has no corners and so is not located.
- Returns `hint ∈ { none, moveCloser, moveBack, holdStill, adjustAngle }` and
  `lockAction ∈ { none, lock, unlock }`.
- `LiveScan` adds one hint the policy does not have: no located frame for
  more than **1000 ms** → `hintPoint` ("Point at the barcode").
- Exposes `window.CimbarCapturePolicy` / `module.exports`; IIFE-wrapped like
  its siblings.

## 9. Page integration

### 9.1 `addFrame` — one session, two sources

`addPhoto`'s logic after a successful decode moves into a shared function:

```js
addFrame(r) → { kind, reason, rank, total, complete }
```

| `kind` | Meaning |
|---|---|
| `accepted` | `asm.add` accepted the frame |
| `duplicate` / `dependent` | `asm.add` rejected it as redundant (normal, not an error) |
| `rejected` | `asm.add` rejected it for another `reason` (`rs`, `flags`, …) |
| `kept` | a different file's frame; the user chose to keep the current session |
| `done` | the session already completed; frame ignored (today's `photoAlreadyDone`) |
| `busy` | a completion attempt is running (`finishing`); frame ignored silently |

`complete` is true when this call brought `rank` to `total`.

It owns every existing rule: the `done` and `finishing` guards, session
creation, the wrong-file header check and its `confirm()`, `asm.add`, and the
progress bar. It **does not log and does not start completion**: the caller
runs `completePhotoSession()` when `complete` is true — `addPhoto`
immediately, live scan after closing the scanner. `addPhoto` maps the return
value to exactly today's log lines (`test_page_logic.js` must pass
unchanged); live scan maps it to HUD state.

Live-scan specifics:

- **Wrong file.** The scan loop pauses (no new frames posted) while the
  `confirm()` is open. If the user keeps the current session (`kind: 'kept'`),
  frames carrying that other `fileId` are ignored silently for the rest of
  this scan, so pointing at the other screen does not re-prompt three times a
  second. If they discard, the new session starts from that frame.
- **Completion.** When `addFrame` returns `complete: true`, the scanner stops
  the camera and closes, then calls `completePhotoSession()`, so the
  passphrase field and the existing recovery (type the passphrase, press
  Decode) are visible.
- **Logging.** The Decode log gets one line when a scan starts and one when
  it stops: `scanSummary` ("Scanned {frames} frames, {accepted} accepted").
- **Starting a scan clears a staged GIF** (`decFile`), exactly as choosing a
  photo does; the GIF/session exclusivity rule is unchanged.

### 9.2 Button

`[ Take a photo ]  [ Scan with camera ]` on the Decode tab. Hidden only when
`getUserMedia` is unavailable; shown on desktop too (webcam, best-effort).

### 9.3 Scanner view

A fixed full-viewport layer above the page; `body` scrolling locked while it
is open.

```
┌───────────────────────────────┐
│ ✕                  37 / 120   │  close, rank/total
│      ┌ ─ ─ ─ ─ ─ ─ ─ ┐        │
│        video (cover) +        │
│        overlay canvas         │
│      └ ─ ─ ─ ─ ─ ─ ─ ┘        │
│  ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░  31%    │  after the first accepted header
│       Hold still              │  hint
│  [debug panel, ?debug=1]      │
└───────────────────────────────┘
```

- Chrome elements respect `env(safe-area-inset-*)`; the viewport meta gains
  `viewport-fit=cover`.
- **Close** by ✕, Escape, or the browser Back gesture: opening pushes a
  history entry (`history.pushState`), and `popstate` closes the scanner.
  Closing via ✕/Escape calls `history.back()` to consume that entry. The
  session survives; the Decode tab's progress and "Start over" show it.
- **Overlay.** Corners arrive in video-pixel coordinates; the video is shown
  with `object-fit: cover`, so a pure function `coverTransform(videoW, videoH,
  boxW, boxH) → {scale, dx, dy}` maps them to the overlay canvas. Colours:
  green when the frame was accepted, amber when located but `rsFailed`,
  duplicate or dependent, nothing when not located. The quadrilateral fades
  after 500 ms without a new located frame.
- Styling reuses the page's tokens and `.btn` classes; overlay chrome is dark
  translucent over the video.

### 9.4 Debug panel (`?debug=1`)

A header line (`1920x1080 lock=focus+exposure worker=ok`) and a scrolling list
of at most 50 lines, one per frame:

```
#42 ok 312ms loc=41 smp=198 drf=150 rs=9 mod=11.4 r=37/120 dup=4
```

English only, untranslated — developer output behind a URL flag.

## 10. i18n

New keys, in all five languages (`test_i18n.js` enforces completeness and
placeholders):

| Key | English |
|---|---|
| `scanCamera` | Scan with camera |
| `scanClose` | Close |
| `scanStarting` | Starting camera… |
| `scanPaused` | Scanning paused |
| `scanResume` | Resume |
| `hintPoint` | Point at the barcode |
| `hintCloser` | Move closer |
| `hintBack` | Move back |
| `hintStill` | Hold still |
| `hintAngle` | Tilt to face the screen |
| `camDenied` | Camera permission denied — use "Take a photo" instead |
| `camNone` | No camera found — use "Take a photo" instead |
| `camBusy` | The camera is in use by another app |
| `camFailed` | Couldn't start the camera — use "Take a photo" instead |
| `scanDecoderFailed` | The decoder stopped working — close the scanner and try again |
| `scanSummary` | Scanned {frames} frames, {accepted} accepted |

`howDecodingHtml` is updated in all five languages to mention live scanning.

## 11. Testing

### 11.1 Automated (`sh tests/run_all.sh`, CI job *Web App Tests*)

- **`tests/test_capture_policy.js`** (new): case-for-case port of
  `app/test/core/services/capture_policy_test.dart`, plus `tooSmall` with
  corners → `moveCloser`, and `tooSmall` without corners → not located.
- **`tests/test_scan_worker.js`** (new): runs `scan-worker.js` in a `vm`
  context whose `self`/`importScripts` load the real files from disk into one
  shared scope. Posts each `test-data/scenes/` fixture's pixels (read via
  `tests/png.js`) and asserts the reply's `status`, `blocksFailed`, `data` and
  `corners` equal what `CimbarPhoto.decode` returns directly for the same
  image — the worker adds and loses nothing. A garbage buffer replies
  `notLocated`; a decode that throws replies `status: 'error'`.
- **`tests/test_live_scan.js`** (new): `LiveScan` against fake `video`,
  `MediaStreamTrack` and `Worker` objects:
  - callbacks while a decode is in flight post nothing;
  - `lock` calls `applyConstraints` with the pinned `getSettings()` values,
    only for capabilities that list `manual`; `unlock` restores
    `continuous`; no calls at all when unsupported;
  - a rejected `applyConstraints` disables locking and scanning continues;
  - worker error, `status: 'error'` and a 10 s timeout each respawn; three in a
    row stop with `scanDecoderFailed`; a success resets the count;
  - close, `visibilitychange → hidden` and `pagehide` stop every track;
  - `coverTransform` numeric cases (wider, taller, equal aspect).
- **`tests/test_page_logic.js`** (extended): existing photo tests pass
  unchanged (the `addFrame` refactor preserved behaviour); live frames and
  photos build one session; a wrong-file live frame prompts once and, after
  "keep", further frames of that file are ignored without prompting;
  completion during a scan stops the scanner and runs
  `completePhotoSession`, including the encrypted/passphrase-typed-later retry;
  starting a scan clears a staged GIF.
- **`tests/test_browser_load.js`** (extended): 21 page scripts;
  `capture-policy.js` and `live-scan.js` load after `photo-decoder.js` and
  before `i18n.js`; `CimbarCapturePolicy` and `CimbarLiveScan` exist.
- **Deploy wiring** (extend `tests/test_web_icons.js`): every
  `new Worker('…')` target in `index.html`/`live-scan.js` and every file in
  `scan-worker.js`'s `importScripts(...)` is in `deploy-webapp.yml`'s staging
  list. The workflow's own verify step checks `<script src>` and
  `<link href>` only, and would not notice a missing worker.

### 11.2 Local end-to-end (`tools/e2e_live_scan.js`, not in CI)

Playwright Chromium (`NODE_PATH` as for `tools/gen_store_graphics.js`)
launched with `--use-fake-ui-for-media-stream
--use-fake-device-for-media-stream --use-file-for-fake-video-capture=<y4m>`.
The tool renders a coded golden's frames (`lorem_coded`, source + repair) into
a looping `.y4m` at 1280×720, serves `web-app/`, clicks "Scan with camera",
and asserts the download equals the golden's payload. It verifies the
plumbing — `getUserMedia` → frame callback → worker → `addFrame` → completion
— not camera optics: fake-camera frames are pixel-perfect.

### 11.3 Manual device checklist (before release)

Devices: Android Chrome (lock available), iPhone Safari, iPhone Chrome
(WebKit), Firefox for Android, one desktop webcam.

Scenarios on each: present mode at 200 ms with >100 frames; an encrypted file
with the passphrase typed before and after; pointing at a different file
mid-scan (keep and discard); background and return; the Back gesture;
permission denied; closing mid-scan then finishing with a photo.

Record from the debug panel: delivered resolution, lock state, per-stage
timings and accepted frames per second. **If `locateMs` dominates on phones,
that is the trigger for ROI cropping** (out of scope here).

## 12. Repository constraints

1. **One global scope.** `capture-policy.js` and `live-scan.js` are
   IIFE-wrapped; no top-level `const` collides (`test_browser_load.js`).
2. **Deploy staging.** `scan-worker.js`, `capture-policy.js` and
   `live-scan.js` join the staged list in `.github/workflows/deploy-webapp.yml`
   (all `*.js`, already covered by the Content-Type table).
3. **i18n.** Every new user-visible string has a key in all five languages.
4. **Docs.** `CLAUDE.md` gains the three modules in the module list, a live
   scan pipeline paragraph, the new tests in the table, and the updated
   script count (21).
5. **No decode-module edits.** If implementation finds one necessary, it is a
   design change, and the scene fixtures' Dart↔JS contract applies.
