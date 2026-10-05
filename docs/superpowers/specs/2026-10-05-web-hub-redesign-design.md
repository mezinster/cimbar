# Web app hub redesign — design

Date: 2026-10-05 · Status: approved in conversation, section by section · Branch: `feat/web-hub-redesign`

## Goal

Make the web app (`web-app/index.html`) work well **on phones** and make a good **first impression**.
Today about 330 px of a phone screen goes to a header (wordmark, tagline, four badges, language picker).
Decode leads with drag-and-drop, which phones can't do; the live scanner is the third button down.
The Decode button is red. About is a spec sheet. There is no dark mode.

The redesign replaces the Encode / Decode / About tabs with a **Send / Receive hub** in a hub-and-spoke layout.

## Visual reference

The Superdesign project "CimBar Web — phone-first redesign" (`7098886c-cef9-492f-8ccf-f9921e74cff7`) is the visual spec.
All drafts are 390 px mobile, direction A ("editorial, modernised"):

| Screen | Draft id |
|---|---|
| Hub (v2, chosen) | `a4415609-7106-48e8-96de-eb36e520622e` |
| 1 Send — compose | `2298bb52-9b75-477b-820b-45f5028dfdf6` |
| 2 Send — ready | `7aab3297-4eff-4257-bb45-431d029bee29` |
| 3 Present | `29146693-2690-4dce-90ca-dc6fad92a242` |
| 4 Receive — scanner | `15fb90f6-143c-40d7-86f0-f8025929c8c9` |
| 5 Receive — encrypted | `190085c7-59e1-497f-9f20-cdcc0cd5bd8d` |
| 6 Receive — file result | `e462f66b-2017-4c5f-b8e5-bd7877f2ad55` |
| 7 Receive — text result | `a832262c-2917-4dca-b8cd-2ae6bffe6bd6` |
| 8 How it works | `efcf9bf1-6909-4a28-a0d9-0c1fc7dce446` |
| 9 Language sheet | `9f7e2e88-92e6-4392-a4ea-2869b2906371` |

Rejected: a Material 3 branch (`030d41d9-…`), because it looked like every other M3 app.

Fetch any draft's HTML with `npx --yes @superdesign/cli@latest get-design --draft-id <id> --output <file>`. This needs Node ≥ 22.

The drafts are **Tailwind-CDN + Iconify mockups**. They are not code to copy. The implementation is vanilla CSS on the existing tokens, with inline SVG icons.

Known draft defects, which are **not** to be reproduced:
- In page 9 the hub behind the sheet has empty cards and a tinted demo.
- In page 8 the step-01 thumbnail is a tinted crop.
- Page 6 has an unboxed back button and a stranded "Receive another" link. Follow pages 5 and 7 instead.

## Approach

**The rebuild happens in place.** The new markup and CSS replace the old inside `index.html`.

The inline `<script>` stays the **single** orchestration block. `tests/test_page_logic.js` asserts exactly one, and `deploy-webapp.yml` stages a fixed file list.

**No new files are served.** No framework, no build step, no CDN script.

Extracting `styles.css` is a separate follow-up PR. It would also change the deploy stage list, the content-type table, the verify step and the healthcheck.

## 1. Screens, routes, navigation

Routing uses the hash. Routes are `#/…`. The empty hash is the hub.

`resolveRoute(hash, state) → { route, redirect }` is a **pure function** that the tests can reach.

| Route | Screen | Guard → redirect |
|---|---|---|
| `#/` | Hub | — |
| `#/send` | Compose (File \| Text). Encoding progress is shown inline in the sticky action area. | — |
| `#/send/ready` | Ready: preview, Present, Share GIF, Download | no encoded GIF → `#/send` |
| `#/receive` | Opens the scanner overlay | no `getUserMedia` → `#/receive/files` |
| `#/receive/files` | Choose GIF · Photograph frames (rank/total progress) · Start over | — |
| `#/receive/unlock` | Passphrase for a complete, encrypted session | no complete session → `#/receive` |
| `#/receive/done` | File result or text result (`isTextMessage`) | no result → `#/` |
| `#/how` | How it works (replaces About) | — |
| unknown | — | → `#/` |

The language sheet is a `<dialog>` and has no route.

- **When encoding completes**, `history.replaceState` to `#/send/ready`, so Back goes to the hub and not to a spent form.
- **Overlays push a history entry.** Present and the scanner each push one when they open. The Android back gesture closes the overlay. ✕ and Esc call `history.back()`, so there is a single close path.
- **If camera permission is denied** or the camera is unavailable, close the scanner and go to `#/receive/files` with the notice "Camera unavailable — choose a GIF or photograph the frames instead."
- **Desktop (≥ 840 px)** uses the same routes in a centred 720 px column. On the hub, the demo tile and the choice cards sit side by side.
- **Drag-and-drop** is kept on Compose and on `#/receive/files`. Its hint text shows only under `@media (hover: hover)`.
- **Removed:** the header badges and tagline, the tab bar, the red Decode button, the "How decoding works" callout (its content moves to `#/how`), and the always-visible receive passphrase field.
- **State:** the existing script globals (`encResult`/GIF, `photoSession`, `decFile`) stay the source of truth. The router only reads them.
- **Invariants to keep:**
  - `photoSession.done` is set only after `finishDecode` resolves.
  - `photoSession.finishing` covers the attempt itself.
  - The wrong-file guard runs before `add()`.

## 2. Visual system

**Tokens.** The `:root` block is extended, not renamed.

- **Kept:** `--bg #f5f3ef`, `--surface #fff`, `--border #e2ddd6`, `--text #1a1714`, `--text2 #5c554e`, `--text3 #8a827a`, `--accent #2d6a4f`, `--accent-l #d8f0e5`, `--accent-d #1b4332`, `--warn #c0392b`, `--warn-l`, `--radius 14px`, `--radius-sm 8px`, `--shadow`, `--shadow-lg`.
- **Added:** `--accent-fg` (green text and icons on surfaces), `--accent-line #bfe3d1`, `--signal #00FF66`, `--scrim rgba(26,23,20,.45)`, `--overlay-glass rgba(255,255,255,.08)`.
- **Dropped:** `--info` and `--info-l`.

**Dark theme.** It is automatic only, under `@media (prefers-color-scheme: dark)`. There is no toggle.

| Token | Light | Dark |
|---|---|---|
| `--bg` | `#f5f3ef` | `#171512` |
| `--surface` | `#ffffff` | `#211e1a` |
| `--border` | `#e2ddd6` | `#3a352f` |
| `--text` / `--text2` / `--text3` | `#1a1714` / `#5c554e` / `#8a827a` | `#efe9e1` / `#bdb4a9` / `#8f877d` |
| `--accent` (fills under white text) | `#2d6a4f` | `#2d6a4f` |
| `--accent-fg` | `#2d6a4f` | `#7fc8a2` |
| `--accent-l` / `--accent-line` | `#d8f0e5` / `#bfe3d1` | `#1d3a2c` / `#2c5a43` |

- **Theme colour:** the current `<meta name="theme-color">` gains a `media="(prefers-color-scheme: dark)"` twin set to `#171512`.
- **Contrast:** every text/surface pair meets WCAG AA, 4.5:1 for body text and 3:1 for large text and icons.

**Type.** These fonts are already loaded, so none are added.
- DM Serif Display: the wordmark, screen titles and the hero headline only.
- DM Sans: all UI text.
- DM Mono: numbers, metadata and chips.

**Icons.** The Lucide icons we need (about 25) are inlined once as a hidden SVG `<symbol>` sprite.
- Use them as `<svg class="i"><use href="#i-<name>"/></svg>`, with `stroke="currentColor"`.
- The sprite carries the Lucide ISC licence notice.
- Never use the Iconify CDN: it is offline-hostile, and the deploy verifier rejects it.

**Components:**
- top bar: the hub variant (logo `favicon.svg` 28 px + serif wordmark "Cim<em>Bar</em>" + bordered 36 px utility buttons) and the sub-screen variant (boxed back arrow + serif title);
- choice card: filled `--accent`, or tonal `--accent-l` with an `--accent-line` border;
- icon chip;
- disclosure row (`<details>`);
- segmented control;
- sticky action bar;
- buttons: primary, secondary and text-link;
- file pill;
- bottom sheet (`<dialog>`);
- black overlay chrome: glass round buttons, signal pill, dark progress sheet.

All tap targets are ≥ 48 px.

**Hub content:**
- the top bar;
- a black demo tile with the "LIVE DEMO" chip and a real animated CimBar, plus the caption "Try it: scan this with another phone";
- the serif headline "Send a file through the air.";
- the sub-line "Phone to phone, screen to camera. No network, no cable, no pairing.";
- the Send card (filled) and the Receive card (tonal);
- chips: AES-256 · Works offline · Nothing uploaded;
- a "How it works" disclosure with three mini steps;
- the footer `v<version> · open source`.

**Demo GIF.** It is generated **at runtime** by the page's own encoder, so no new asset needs to be staged. The payload is the already-deployed `icon-512.png`, fetched same-origin, about 8 KB.
- It is rendered once at load, after the encoder scripts, and cached in memory.
- That PNG is already compressed, but deflate still shrinks it a little (8008 B to 6835 B). The result is 4 source frames plus 1 repair frame plus a repair frame, which gives a genuinely animated loop. A short text would encode to one static frame.
- Scanning the demo yields `cimbar.png`, the app icon, which shows off the file path and Open.
- If the fetch fails (for example on a `file://` page), the tile shows a static rendered frame of a fixed short text instead. The tile never shows an error.

**Motion.** All of it is wrapped in `prefers-reduced-motion: no-preference`:
- a 150 ms fade/slide between routes;
- the sheet slides up;
- the Present hint fades after 3 s.

## 3. Behaviours, errors, i18n

**Progressive enhancements.** Each control is shown only when its API exists.
- **Wake Lock.** `navigator.wakeLock.request('screen')` runs when Present opens and is released when it closes. It is re-acquired on `visibilitychange` → visible while Present is open. The "Screen stays on" pill shows only while a lock is held.
- **Share GIF.** Shown when `navigator.canShare?.({ files: [gifFile] })`. The file is `cimbar-<basename>.gif` as `image/gif`. An `AbortError` is silent. When Share is hidden, Download takes the full row.
- **Share received file.** Same rule. The MIME type comes from a small extension map, falling back to `application/octet-stream`.
- **Open.** `URL.createObjectURL` in a new tab, only for pdf, png, jpg/jpeg, gif, webp, svg, txt, md, csv, json, mp3, mp4 and webm. The URL is revoked after 60 s. For other types the control is hidden.

**Errors.** No `alert()` or `confirm()` remains anywhere.
- "Create code" is disabled until a file or non-empty text is present. The `selectFileFirst`, `enterTextFirst` and `selectGifFirst` branches go away.
- The wrong-file guard and the GIF-discards-session guard become a confirm sheet with Discard and Keep. The strings `photoWrongFile` and `gifDiscardsSession` are kept, with the same semantics.
- An encrypted file with a missing or wrong passphrase goes to `#/receive/unlock`, which shows an inline error. Retry goes through the existing completion path; nothing is re-scanned.
- Encode and decode failures show as an inline error card on the current screen, using the existing translated messages.
- Scanner worker failures keep the existing `LiveScan` stop reason and Resume, shown in the scanner's bottom sheet.
- The `#logEnc` and `#logDec` panes move behind a collapsed "Details" disclosure.

**i18n.**
- **New keys** (about 35) are added to all five languages in `i18n.js`. `test_i18n.js` enforces the key set and placeholders.
- **Delete keys for removed UI:** `tagline`, `badgeClientSide`, `badgeNoUpload`, `tabEncode`, `tabDecode`, `tabAbout`, `howDecodingHtml`, `selectFileFirst`, `enterTextFirst`, `selectGifFirst`, plus any others the removal orphans.
- **Reuse the About texts** on `#/how`.
- **Check overflow at 360 px** in `ru` and `ka`.

## 4. Testing, verification, delivery

**Automated (Node, CI):**
- All existing suites stay green. The DOM stub in `test_page_logic.js` gains the new ids; its behavioural assertions are not weakened.
- New `tests/test_router.js` covers every guard in `resolveRoute`, plus unknown and empty hashes.
- New `tests/test_markup.js` is a set of static assertions over `index.html`:
  - no external `<script src>`;
  - every `<use href="#i-…">` has a `<symbol id>`;
  - dark tokens exist under `prefers-color-scheme: dark`;
  - no `alert(`/`confirm(` in the inline script;
  - no `btn-danger`.

  Each guard is shown to **fail** on the pre-redesign `index.html` before it is trusted.
- `run_all.sh` picks up the new files.

**Browser** (headless Windows Chrome from WSL):
- Screenshot every route at 360 and 390 px, light and dark, in en, ru and ka.
- Measured checks:
  - no horizontal overflow;
  - no clipped labels (`scrollWidth ≤ clientWidth`);
  - tap targets ≥ 48 px;
  - token contrast.

**End-to-end** (local): update `tools/e2e_live_scan.js` to go through `#/receive`. It must still produce a byte-identical golden payload, including an encrypted golden through `#/receive/unlock`.

**Hardware (owed, reported as unverified):**
- Present on one phone and scan on another.
- Wake Lock holds through 2 minutes of Present, including after a notification glance.
- Share GIF to Telegram on Android.
- The camera-denied fallback.
- iOS Safari without Wake Lock or Share.

**Delivery:**
- One PR from `feat/web-hub-redesign`.
- `CHANGELOG.md` gets an entry under `[Unreleased] → Changed`.
- No version bump: `test_browser_load.js` ties `data-version` to the newest released entry.
- Deploy is manual afterwards.
- The Flutter app is untouched.

**Out of scope:**
- extracting `styles.css`;
- a manual theme toggle;
- the scanner's `?debug=1` panel;
- the Flutter app.
