# Wide (tablet) Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the approved `spike/wide-layout` prototype into shipped code: rail + two panes on wide windows, live Send preview, translated, tested.

**Architecture:** One helper file (`lib/shared/widgets/wide_layout.dart`) decides "wide" from window size and provides `TwoPane`, `EmptyPane`, `CentredColumn`, `adaptiveBody`. `AppShell` swaps the bottom bar for a rail; Send/Import/Camera feed their existing form children to `adaptiveBody` with a right pane; `SendPreview` re-encodes in an isolate and loops source frames.

**Tech Stack:** Flutter 3.44.8, Riverpod, go_router, flutter gen-l10n (ARB in `app/lib/l10n/`, generated code committed in `app/lib/l10n/generated/`).

**Spec:** `docs/superpowers/specs/2026-11-27-wide-layout-design.md`

## Global Constraints

- Wide = `MediaQuery.sizeOf(context).width >= 840 && shortestSide >= 600`. No platform/device checks.
- Phone layout (narrow) must render exactly as before: existing tests run unchanged.
- Left pane width 440; centred column max width 680.
- Preview debounce 350 ms; preview includes the trimmed passphrase (same `SendRequest` the controller builds), so N matches Present/Share GIF.
- Every new string in all seven ARB files (en, ru, uk, tr, ka, pl, be); `test/shared/arb_translation_test.dart` must pass.
- Present, Live Scan, photo capture, photo optimiser, dialogs: untouched.
- All work in `/Users/topol/cimbar-wide` on branch `spike/wide-layout`; run commands from `app/`.

## Review Focus

1. A stale preview: typing fast, then the older (slower, e.g. encrypted) encode finishing last must not replace the newer frame → Task 3 test `stale encode result is dropped`.
2. Clearing the text box (or switching Text→File with no file) must return the preview to the empty pane, not leave the last barcode → Task 3 test `clearing input shows the empty pane`.
3. Rotating an iPhone Pro Max (956×440) must keep the bottom bar and one column → Task 1 test `phone landscape stays narrow`.
4. An encode error (e.g. a file over the container cap) must not crash the preview; it shows the empty pane → Task 3 test `encode failure shows the empty pane`.
5. Leaving the Send tab while an encode or frame timer is pending must not throw (setState after dispose) → Task 3 test `dispose mid-encode is quiet`.

---

### Task 1: Wide helpers and the shell rail

**Files:**
- Modify: `app/lib/shared/widgets/wide_layout.dart` (spike version exists; keep API, add doc comments)
- Modify: `app/lib/shared/widgets/app_shell.dart` (spike version exists)
- Test: `app/test/shared/wide_layout_test.dart` (new)

**Interfaces:**
- Produces: `bool isWide(BuildContext)`, `TwoPane({required List<Widget> left, required Widget right})`, `EmptyPane({required IconData icon, required String text})`, `CentredColumn({required Widget child})`, `Widget adaptiveBody(BuildContext, {required Widget right, required List<Widget> children})`.

- [ ] **Step 1: Write tests** (pump `AppShell` around a placeholder child inside a `GoRouter` with the five tab routes, as `test/shared/nav_labels_test.dart` does; set `tester.view.physicalSize`/`devicePixelRatio = 1`):
  - `ipad portrait uses the rail` — 1032×1376: `find.byType(NavigationRail)` one, `NavigationBar` none; tapping rail label of tab 3 navigates to `/camera`.
  - `phone portrait uses the bottom bar` — 430×932: `NavigationBar` one, rail none.
  - `phone landscape stays narrow` — 956×440: `NavigationBar` one.
  - `small tablet portrait is narrow` — 744×1133: `NavigationBar` one (width < 840).
  - `adaptiveBody`: at 1032×1376 finds `TwoPane`; at 430×932 finds a `ListView` with `keyboardDismissBehavior == onDrag` and no `TwoPane`.
- [ ] **Step 2: Run** `flutter test test/shared/wide_layout_test.dart` — expected PASS already (spike code); temporarily invert the `>= 840` check to confirm the tests catch it, then restore.
- [ ] **Step 3: Commit** `feat(app): wide-window shell rail and two-pane helpers`.

### Task 2: Strings

**Files:**
- Modify: `app/lib/l10n/app_{en,ru,uk,tr,ka,pl,be}.arb`, regenerate `app/lib/l10n/generated/*`

**Interfaces:**
- Produces getters: `l10n.wideSendEmpty`, `l10n.wideResultEmpty`, `l10n.previewFullScreen`. The frame counter reuses existing `l10n.presentSource(i, n)`.

- [ ] **Step 1:** Add to `app_en.arb` with `@` descriptions:
  - `wideSendEmpty`: "Your barcode appears here as you type" (tablet Send, empty preview pane)
  - `wideResultEmpty`: "The decoded file appears here" (tablet Import/Camera, empty result pane)
  - `previewFullScreen`: "Full screen" (button under the tablet preview; opens Present)
- [ ] **Step 2:** Translate into ru, uk, tr, ka, pl, be, matching each file's existing terms for "barcode", "decoded file", "full screen".
- [ ] **Step 3:** `flutter gen-l10n` then `flutter test test/shared/arb_translation_test.dart` — PASS.
- [ ] **Step 4: Commit** `feat(app): strings for the tablet layout in all seven languages`.

### Task 3: Send live preview

**Files:**
- Modify: `app/lib/features/send/send_preview.dart` (spike version exists)
- Modify: `app/lib/features/send/send_screen.dart` (pass passphrase controller)
- Test: `app/test/features/send_preview_test.dart` (new)

**Interfaces:**
- Consumes: Task 1 helpers, Task 2 getters, `encodeInIsolate(SendRequest)`, `estimateFrames(SendState, encrypted:)`.
- Produces: `SendPreview({Key? key, required TextEditingController passphrase, VoidCallback? onPresent, Future<EncodedPayload> Function(SendRequest)? encode, Future<ui.Image> Function(Uint8List rgba)? toImage})` — `encode` defaults to `encodeInIsolate`, `toImage` to `decodeImageFromPixels` (tests inject both, as `PresentScreen` does).

- [ ] **Step 1: Write tests** (pump `SendScreen` at 1032×1376 with `sendControllerProvider` overridden, fake `encode`/`toImage` injected through a provider or by pumping `SendPreview` directly with the shared controller):
  - `empty input shows the empty pane` — `find.text(l10n.wideSendEmpty)`.
  - `typing shows a preview after the debounce` — enter text, pump 349 ms: no `RawImage`; pump to 350 ms + settle: one `RawImage`, text `presentSource(1, N)` where N = `estimateFrames(state, encrypted: false)`.
  - `passphrase is part of the request` — type text and passphrase " pw "; fake encoder records `req.passphrase == 'pw'`.
  - `stale encode result is dropped` — first encode completes after the second (Completers); only the second payload's frame count is shown.
  - `clearing input shows the empty pane`.
  - `encode failure shows the empty pane` — fake encoder throws.
  - `multi-frame preview loops at the frame delay` — payload of 3, delay 200: after 200 ms counter reads frame 2.
  - `tapping the preview opens Present` — `find.byType(PresentScreen)` after tap.
  - `dispose mid-encode is quiet` — start encode, switch to another tab (or pump an empty widget), complete the Completer, no exception.
  - `phone width has no preview` — 430×932: no `SendPreview`.
- [ ] **Step 2: Run** `flutter test test/features/send_preview_test.dart` — expect failures (passphrase, l10n, injection, error handling not in the spike).
- [ ] **Step 3: Implement** in `send_preview.dart`: replace hard-coded strings with Task 2 getters and `presentSource`; drop the "· compressed" suffix; listen to `passphrase` (re-schedule on change) and build the request with `passphrase.text.trim()` and `TextMessage.fileName(DateTime(2000))` for text; wrap encode in try/catch → empty pane; generation counter guards every await (encode, toImage, timer); cancel timers in `dispose`. In `send_screen.dart`: `SendPreview(passphrase: _pass, onPresent: canSend ? _present : null)`.
- [ ] **Step 4: Run** the new test file and `flutter test test/features/send_screen_test.dart test/shared/keyboard_and_language_sheet_test.dart` — PASS.
- [ ] **Step 5: Commit** `feat(app): live barcode preview on tablet Send`.

### Task 4: Import, Camera, Files, About

**Files:**
- Modify (spike versions exist): `app/lib/features/import/import_screen.dart`, `app/lib/features/camera/camera_screen.dart`, `app/lib/features/files/files_screen.dart`, `app/lib/features/settings/settings_screen.dart`
- Test: `app/test/features/wide_screens_test.dart` (new)

**Interfaces:**
- Consumes: Task 1 helpers, `l10n.wideResultEmpty`.

- [ ] **Step 1: Write tests** (controllers overridden with a state holding a `DecodeResult`, as `test/features/camera_screen_share_test.dart` builds them):
  - `import: result in the right pane on a tablet` — 1032×1376: `ResultCard` is a descendant of `TwoPane`'s right side (its left edge > 440); without a result `find.text(l10n.wideResultEmpty)`.
  - `import: result under the form on a phone` — 430×932: `ResultCard` below the Decode button (`getTopLeft` y greater).
  - same two for camera.
  - `files and about are centred on a tablet` — the list's width ≤ 680 at 1032×1376.
- [ ] **Step 2: Run** — PASS expected on spike code except strings; replace the spike's hard-coded empty-pane text with `l10n.wideResultEmpty`.
- [ ] **Step 3: Run** the full suite `flutter test` and `flutter analyze` — all green.
- [ ] **Step 4: Commit** `feat(app): tablet result pane for Import and Camera; centred Files and About`.

### Task 5: Docs, screenshots, PR

- [ ] **Step 1:** `app/CLAUDE.md`: a "Tablet layout" paragraph (wide test, rail, panes, preview behaviour, where the helpers live) and rows for the three new test files in the test table. Update spec line "4 new ARB keys" → "3 new keys; the counter reuses `presentSource`".
- [ ] **Step 2:** Run `store-screens/capture.sh`; if the capture test fails on the iPad because it finds tabs via `NavigationBar`, switch it to tapping tab labels by text/icon (works for rail and bar). Inspect the new `captures/ipad/en/*.png`.
- [ ] **Step 3:** Push the branch, open the PR (rename branch to `feat/wide-layout`), wait for CI; fix Podfile.lock drift from the CI artifact if it appears.
