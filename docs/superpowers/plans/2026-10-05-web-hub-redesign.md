# Web Hub Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the web app's Encode / Decode / About tabs with a phone-first Send / Receive hub. The new UI has an editorial look and dark mode, and it adds in-page dialogs, Wake Lock for Present, and Web Share.

**Architecture:** Everything is rebuilt in place inside `web-app/index.html`.
- The new markup and CSS replace the old.
- There is still exactly **one** inline `<script>`.
- No new served files, no framework, no CDN script.
- A pure `resolveRoute(hash, state)` drives hash routing (`#/send`, `#/receive`, …).
- The existing script globals (`outputBlob`, `encodeState`, `photoSession`, `decFile`, `textResult`) stay the source of truth.
- `alert()`/`confirm()` are replaced by in-page UI, behind seams the Node test harness can stub.

**Tech Stack:** Vanilla HTML/CSS/JS as classic scripts with `window.*` globals. The Node ≥ 22 test suite (`sh tests/run_all.sh`) uses a `vm`-based page harness. Visual checks use headless Chrome on the Windows host. Icons are Lucide (`lucide-static@0.460.0`, ISC licence), inlined as an SVG sprite.

**Spec:** `docs/superpowers/specs/2026-10-05-web-hub-redesign-design.md`. Read it before Task 1.

The visual reference is the Superdesign drafts listed in the spec. To fetch a draft:

```bash
source ~/.nvm/nvm.sh && nvm use 22
npx --yes @superdesign/cli@latest get-design --draft-id <id> --output /tmp/<name>.html
```

The drafts are Tailwind + Iconify mockups. **Never copy their `<script>` tags or Tailwind classes.** Translate them into the vanilla CSS below.

## Global Constraints

- All work happens in `~/cimbar` on branch `feat/web-hub-redesign`. Tests run from `web-app/` with `sh tests/run_all.sh`. The shell default is Node 14, so run `source ~/.nvm/nvm.sh && nvm use 22` first.
- `index.html` must keep **exactly one** inline `<script>` block. `tests/test_page_logic.js` asserts this.
- **No external `<script src>`.** The only external resource stays the existing Google Fonts stylesheet `<link>`.
- **No new files served from `web-app/`.** `deploy-webapp.yml` stages a fixed list. Test files (`tests/…`) and dev tools are fine.
- The 21 local `<script src>` tags stay in their current order. `test_browser_load.js` asserts the order.
- Keep `<span id="appVersion" data-version="0.12.1">` and `<span id="buildSha">dev</span>` verbatim. The deploy workflow stamps them.
- **i18n:**
  - Every new string goes into **all five** languages (en, ru, uk, tr, ka) in `web-app/i18n.js`.
  - `en` is the source.
  - Translations must keep `{placeholders}` identical.
  - A button label may be at most about 1.4× the English length.
  - `test_i18n.js` enforces the key set.
- **Tokens:** use only the colours, fonts and radii in spec §2. Use `var(--accent-fg)` for green **text or icons on surfaces**, never `var(--accent)`.
- Tap targets ≥ 48 px. Layout must fit at 360 px width with no horizontal scroll.
- **Untrusted content** (received text, file names) goes in via `textContent`, never `innerHTML`.
- **Don't weaken the existing behavioural invariants:**
  - `photoSession.done` is set only after `finishDecode` resolves.
  - The `finishing` flag guards the attempt.
  - The wrong-file guard runs before `add()`.
  - A finished session doesn't re-deliver its file.

  When a test has to change, only its **observation mechanism** changes (Task 3 has the mapping). The asserted counts and semantics stay the same.
- Commit after each task with a conventional message: `feat(web): …`, `test(web): …`, `docs(web): …`.

## Review Focus

Most likely to bite first:

1. **Reloading or deep-linking a route whose state is gone.** For example, a reload on `#/send/ready` or `#/receive/done`. The page must redirect: `resolveRoute` guards and `test_router.js` cover this in Task 2.
2. **The Back gesture with an overlay open.** Back must close Present or the scanner and must not leave the page or double-pop. Task 6 covers Present and Task 7 covers the scanner, each with a harness test asserting a single `history.back()`.
3. **A wrong-file frame arriving while the confirm sheet is open.** It must not stack a second prompt or drop accumulated frames. LiveScan awaits `onFrame`, so `addFrame` becomes `async` and the existing "prompts once" test is kept (Task 3).
4. **A received `.svg` (or `.html`) file and "Open".** A `blob:` URL inherits the page's origin, so an SVG with script would run as us. Task 8's `canOpen` allow-list excludes svg and html, with a test.
5. **A long Russian or Georgian label at 360 px.** It must not overflow or clip. Task 11 measures `scrollWidth` vs `clientWidth` on every route in `ru` and `ka`.

---

## File map

| File | Change |
|---|---|
| `web-app/index.html` | Rewritten `<style>`, new markup (screens, sheets, sprite) and inline-script changes (router, seams, encode refactor, Wake Lock, Share, Open, demo) |
| `web-app/i18n.js` | New keys ×5 languages; orphaned keys deleted |
| `web-app/tests/page_harness.js` | **New.** The `freshPage()` vm harness and frame helpers, extracted from `test_page_logic.js` |
| `web-app/tests/test_page_logic.js` | Imports the harness; observation mechanisms updated per Task 3; new tests for Present, scanner, results |
| `web-app/tests/test_router.js` | **New.** `resolveRoute` guards |
| `web-app/tests/test_markup.js` | **New.** Static guards over `index.html` |
| `web-app/tests/run_all.sh` | Runs the two new test files |
| `web-app/tools/e2e_live_scan.js` | Drives `#/receive`, unlock, and Save |
| `CLAUDE.md`, `CHANGELOG.md` | Describe the new UI |

---

### Task 1: Extract the page harness (tests only, no behaviour change)

**Files:**
- Create: `web-app/tests/page_harness.js`
- Modify: `web-app/tests/test_page_logic.js` (lines 1–225 move out; tests stay)

**Interfaces:**
- Produces: `require('./page_harness')` → `{ freshPage, makeFrame, makeCompletingFrame, makeFrameWithPayload, encryptedPayload, okResult, Fmt, Core, RatelessMod, ReedSolomon }`.
- `freshPage(opts?)` → `{ ctx, elements, calls }`. In `opts`, `{ camera: false }` removes `navigator.mediaDevices`.
- The harness is extended for later tasks:
  - `location.hash`;
  - `history.replaceState`/`pushState` that update `location.hash` when given a `#…` URL;
  - `document.querySelectorAll` → `[]`;
  - `document.documentElement`;
  - element `hidden`/`dataset`/`disabled`/`showModal()`/`close()`/`open`;
  - `scrollTo`, `matchMedia`, `fetch` undefined.

- [ ] **Step 1: Create `tests/page_harness.js`.** Move into it, verbatim, everything in `test_page_logic.js` from `const INLINE_SCRIPT = …` through `const okResult = …`: `INLINE_SCRIPT`, `REQUIRED_GLOBALS`, `freshPage`, `makeFrame`, `makeCompletingFrame`, `makeFrameWithPayload`, `encryptedPayload`, `okResult`. Also move the `require`s they need. Then apply these edits inside `freshPage`:

```js
// in makeEl(id): add the properties later tasks read and write
const el = {
  id,
  style: {}, dataset: {}, hidden: false, disabled: false, open: false,
  classList: { /* unchanged */ },
  innerHTML: '', textContent: '', value: '', scrollTop: 0,
  appendChild(child) { if (child && child.textContent) el.innerHTML += child.textContent + '\n'; },
  addEventListener() {},
  setAttribute(k, v) { el['attr_' + k] = v; },
  showModal() { el.open = true; }, close() { el.open = false; },
  click() { el._clicked = (el._clicked || 0) + 1; },
};
```

```js
// documentStub additions
querySelectorAll: () => [],
querySelector: () => null,
documentElement: makeEl('html'),
visibilityState: 'visible',
```

```js
// sandbox: replace `location` and `history`, add the rest
location: { search: '', hash: '' },
history: {
  state: null,
  pushState(s, _t, url) { this.state = s; if (typeof url === 'string' && url[0] === '#') sandbox.location.hash = url; calls.pushes = (calls.pushes || 0) + 1; },
  replaceState(s, _t, url) { this.state = s; if (typeof url === 'string' && url[0] === '#') sandbox.location.hash = url; },
  back() { this.state = null; calls.backs = (calls.backs || 0) + 1; },
},
scrollTo() {},
matchMedia: () => ({ matches: false, addEventListener() {} }),
```

`freshPage` takes `opts = {}`. When `opts.camera === false`, use `navigator: {}` and not the `mediaDevices` stub. Export everything listed under **Produces**.

- [ ] **Step 2: Point `test_page_logic.js` at the harness.** Replace the moved block with:

```js
const { freshPage, makeFrame, makeCompletingFrame, makeFrameWithPayload, encryptedPayload, okResult, Fmt, Core } = require('./page_harness');
```

Keep `assert`, `assertEq`, `test` and the runner where they are.

- [ ] **Step 3: Run the suite.**

Run: `cd ~/cimbar/web-app && node tests/test_page_logic.js`
Expected: the same PASS count as on `master`. Check with `git stash; node tests/test_page_logic.js | tail -1; git stash pop`.

- [ ] **Step 4: Commit.**

```bash
git add web-app/tests/page_harness.js web-app/tests/test_page_logic.js
git commit -m "test(web): extract the inline-script vm harness into page_harness.js"
```

---

### Task 2: Pure router

**Files:**
- Modify: `web-app/index.html`, inline script. Add a `// ── Routing` section right after the `const t = …; CimbarI18n.apply();` lines, and delete `switchTab`.
- Create: `web-app/tests/test_router.js`
- Modify: `web-app/tests/run_all.sh`, `web-app/tests/page_harness.js` (add `'resolveRoute', 'navigate', 'renderRoute'` to `REQUIRED_GLOBALS`)

**Interfaces:**
- Produces:
  - `ROUTES: string[]`
  - `resolveRoute(hash: string, s: {hasGif, hasCamera, needsUnlock, hasResult}) → {route: string, redirect: string|null}`
  - `routeState() → that s`
  - `navigate(hash: string, opts?: {replace?: boolean})`
  - `renderRoute()`
  - `screenFor(route) → string`
  - `onEnterRoute(route, prev)`: an extension point, filled in by later tasks
  - the `currentRoute` let-binding
  - the `unlockPending` let-binding (set in Task 3)
- Consumes: the `outputBlob`, `photoSession`, `decFile` and `textResult` globals.

- [ ] **Step 1: Write the failing test** `tests/test_router.js`:

```js
'use strict';
const { freshPage } = require('./page_harness');
let passed = 0, failed = 0;
function assertEq(a, b, msg) { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = []; const test = (name, fn) => tests.push({ name, fn });

const all = { hasGif: true, hasCamera: true, needsUnlock: true, hasResult: true };
const none = { hasGif: false, hasCamera: false, needsUnlock: false, hasResult: false };

test('empty and root hashes are the hub, no redirect', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('', none), { route: '/', redirect: null }, 'empty');
  assertEq(ctx.resolveRoute('#', none), { route: '/', redirect: null }, 'bare #');
  assertEq(ctx.resolveRoute('#/', none), { route: '/', redirect: null }, '#/');
});
test('every known route resolves to itself when its state exists', () => {
  const { ctx } = freshPage();
  for (const r of ctx.ROUTES) assertEq(ctx.resolveRoute('#' + r, all), { route: r, redirect: null }, r);
});
test('unknown hashes go to the hub', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/nope', all), { route: '/', redirect: '#/' }, 'unknown');
  assertEq(ctx.resolveRoute('#send', all), { route: '/', redirect: '#/' }, 'missing slash');
});
test('reload on #/send/ready with no GIF goes back to compose', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/send/ready', none), { route: '/send', redirect: '#/send' }, 'ready guard');
});
test('#/receive without a camera API falls back to files', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/receive', none), { route: '/receive/files', redirect: '#/receive/files' }, 'camera guard');
});
test('#/receive/unlock with nothing to unlock chains through #/receive', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/receive/unlock', { ...none, hasCamera: true }), { route: '/receive', redirect: '#/receive' }, 'with camera');
  assertEq(ctx.resolveRoute('#/receive/unlock', none), { route: '/receive/files', redirect: '#/receive/files' }, 'chained to files');
});
test('#/receive/done with no result goes to the hub', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/receive/done', none), { route: '/', redirect: '#/' }, 'done guard');
});
test('navigate replace vs push, and routeState reflects the page', () => {
  const { ctx, calls } = freshPage();
  ctx.navigate('#/how');
  assertEq(ctx.location.hash, '#/how', 'pushed hash');
  assertEq(calls.pushes, 1, 'one push');
  ctx.navigate('#/send', { replace: true });
  assertEq(ctx.location.hash, '#/send', 'replaced hash');
  assertEq(calls.pushes, 1, 'replace does not push');
  assertEq(ctx.routeState().hasGif, false, 'no GIF yet');
  assertEq(ctx.routeState().hasCamera, true, 'harness has getUserMedia');
});
test('navigating to a guarded route lands on the redirect', () => {
  const { ctx } = freshPage();
  ctx.navigate('#/send/ready');
  assertEq(ctx.location.hash, '#/send', 'redirect applied to the URL');
});

(async () => {
  console.log('\ntest_router.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
```

- [ ] **Step 2: Run it to verify it fails.**

Run: `node tests/test_router.js`
Expected: the harness throws `expected the inline page script to define a top-level function 'resolveRoute'`.

- [ ] **Step 3: Implement.** In the inline script, replace the `// ── Tab switching` section with:

```js
// ── Routing (hash-based, spec §1) ─────────────────────────
// Hashes never reach the server, so this works on the static S3/CloudFront
// deploy with no rewrite rules. resolveRoute is pure (tests/test_router.js);
// navigate/renderRoute are the thin glue around it.
const ROUTES = ['/', '/send', '/send/ready', '/receive', '/receive/files', '/receive/unlock', '/receive/done', '/how'];
let currentRoute = null;
let unlockPending = false;   // a completion failed for lack of / a wrong passphrase (Task 3)

function resolveRoute(hash, s) {
  const asked = String(hash || '').replace(/^#/, '') || '/';
  let route = ROUTES.includes(asked) ? asked : '/';
  for (let i = 0; i < ROUTES.length; i++) {   // guards can chain (unlock → receive → files)
    const next =
      route === '/send/ready' && !s.hasGif ? '/send' :
      route === '/receive' && !s.hasCamera ? '/receive/files' :
      route === '/receive/unlock' && !s.needsUnlock ? '/receive' :
      route === '/receive/done' && !s.hasResult ? '/' : null;
    if (!next) break;
    route = next;
  }
  return { route, redirect: route === asked ? null : '#' + route };
}

function routeState() {
  return {
    hasGif: !!outputBlob,
    hasCamera: !!(navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function'),
    needsUnlock: unlockPending,
    hasResult: !!(textResult || fileResult),
  };
}

// '/receive' has no screen of its own: the scanner overlay opens over the files screen.
function screenFor(route) { return route === '/receive' ? '/receive/files' : route; }

function navigate(hash, opts) {
  if (opts && opts.replace) history.replaceState(history.state, '', hash);
  else history.pushState(null, '', hash);
  renderRoute();
}

function renderRoute() {
  const { route, redirect } = resolveRoute(location.hash, routeState());
  if (redirect) history.replaceState(history.state, '', redirect);
  if (route === currentRoute) return;
  const prev = currentRoute;
  currentRoute = route;
  const screen = screenFor(route);
  document.querySelectorAll('.screen').forEach((el) => { el.hidden = el.dataset.route !== screen; });
  if (typeof scrollTo === 'function') scrollTo(0, 0);
  onEnterRoute(route, prev);
}

// Per-route side effects; later tasks add cases.
function onEnterRoute(route, prev) {}

window.addEventListener('hashchange', renderRoute);
```

`fileResult` is declared in Task 3. For now, add `let fileResult = null;` next to `let textResult = null;` so `routeState` loads.

`outputBlob` is declared later in the script with `let`. `routeState` runs only after load, so the TDZ is fine.

At the very end of the inline script, before `</script>`, add `renderRoute();`.

Add `'resolveRoute', 'navigate', 'renderRoute'` to `REQUIRED_GLOBALS` in `page_harness.js`.

In `run_all.sh`, add after the page-logic block:

```sh
echo ""; echo "--- Router (hash routes and guards) ---"
node tests/test_router.js
```

**Note:** removing `switchTab` breaks the old tab buttons' `onclick` until Task 4 replaces that markup. That's acceptable mid-branch; nothing in the tests clicks them.

- [ ] **Step 4: Run the tests.**

Run: `node tests/test_router.js && sh tests/run_all.sh`
Expected: router 9/9 PASS; the full suite passes.

- [ ] **Step 5: Commit.**

```bash
git add web-app/index.html web-app/tests/test_router.js web-app/tests/page_harness.js web-app/tests/run_all.sh
git commit -m "feat(web): pure hash router with state guards"
```

---

### Task 3: In-page dialogs and result seams (no `alert`/`confirm`)

**Files:**
- Modify: `web-app/index.html`, inline script: `addFrame`, `addPhoto`, `handleDecFile`, `onScanFrame`, `startEncode`, `updateTextInfo`, `startDecode`, `finishDecode`, `completePhotoSession`, `showTextResult`, `hideTextResult`, `resetPhotoSession`. Also add minimal markup for `#confirmSheet`, `#fileOut` and `#decError`, placed inside the existing decode card for now; Task 7 and Task 8 move it.
- Modify: `web-app/tests/page_harness.js`, `web-app/tests/test_page_logic.js`
- Modify: `web-app/i18n.js` (new keys)

**Interfaces:**
- Produces:
  - `askConfirm(message: string) → Promise<boolean>`
  - `showError(side: 'enc'|'dec', message: string)` / `clearError(side)`: they write into `#encError` / `#decError`.
  - `showFileResult(name: string, bytes: Uint8Array)`: sets `fileResult = {name, bytes}` and navigates to `#/receive/done` (replace).
  - `showUnlock(wrongPass: boolean)`: sets `unlockPending = true`, writes `#unlockError`, and navigates to `#/receive/unlock` (replace).
  - `addFrame(r)` is now `async` and returns the same result objects as before.
  - `finishDecode` errors carry `err.needPass = true` for a missing or wrong passphrase.
- Consumes: `navigate` (Task 2).

- [ ] **Step 1: Update the harness** (`page_harness.js`, end of `freshPage`, after the `REQUIRED_GLOBALS` check):

```js
// In-page dialogs replace confirm(); keep the old test vocabulary.
ctx.askConfirm = async (msg) => { calls.confirmPrompts.push(msg); return calls.confirmResult; };
// The file result is a screen now, not an auto-download: count deliveries.
calls.fileResults = 0;
const realShowFileResult = ctx.showFileResult;
ctx.showFileResult = (...a) => { calls.fileResults++; return realShowFileResult(...a); };
```

Add `'askConfirm', 'showFileResult', 'showUnlock', 'showError'` to `REQUIRED_GLOBALS`.

- [ ] **Step 2: Update `test_page_logic.js`'s observation mechanisms.** This is the complete mapping. Change nothing else.

| Old observation | New observation |
|---|---|
| `calls.anchorClicks` (file delivered) | `calls.fileResults`, with the same expected numbers |
| `calls.alerts.includes('encryptedNeedPass')` | `ctx.location.hash === '#/receive/unlock'` |
| `calls.alerts[calls.alerts.length - 1] === 'selectGifFirst'` | `elements['decError'].textContent === 'selectGifFirst'` |
| `ctx.addFrame(x)` (sync) | `await ctx.addFrame(x)` |
| `calls.alerts.length === 0` (lines ~263, ~626) | unchanged; must still hold |

Two tests change meaning, deliberately, per spec §3:

```js
// replaces 'file mode with nothing staged: Encode explains and stays usable'
test('file mode with nothing staged: Create code is disabled and a click is a no-op', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.setEncMode('file');
  assertEq(elements['encBtn'].disabled, true, 'disabled until a file is chosen');
  await ctx.startEncode();
  assertEq(calls.alerts.length, 0, 'no alert');
  ctx.onFileSelect({ files: [{ name: 'a.bin', size: 3, arrayBuffer: async () => new ArrayBuffer(3) }] }, 'enc');
  assertEq(elements['encBtn'].disabled, false, 'enabled once a file is staged');
});

test('a wrong passphrase routes to unlock with the wrong-pass message, session intact', async () => {
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 11, seq: 0, total: 1, encrypted: true });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  ctx.CimbarCrypto = { decryptBytes: async () => { throw new Error('Decryption failed — wrong passphrase or corrupted data'); } };
  elements['passDec'].value = 'nope';
  await ctx.addPhoto({});
  assertEq(ctx.location.hash, '#/receive/unlock', 'routed to unlock');
  assertEq(elements['unlockError'].textContent, 'wrongPass', 'says the passphrase was wrong');
  assertEq(calls.fileResults, 0, 'nothing delivered');
  ctx.CimbarCrypto = { decryptBytes: async () => new Uint8Array(4) };
  await ctx.startDecode();
  assertEq(calls.fileResults, 1, 'Unlock (startDecode) retries the intact session');
});
```

- [ ] **Step 3: Run the tests to verify they fail.**

Run: `node tests/test_page_logic.js`
Expected: FAIL. Harness: `expected … top-level function 'askConfirm'`.

- [ ] **Step 4: Implement in the inline script.**

```js
// ── In-page dialogs and messages (spec §3: no alert()/confirm()) ──
function askConfirm(message) {
  const dlg = document.getElementById('confirmSheet');
  document.getElementById('confirmText').textContent = message;
  return new Promise((resolve) => {
    const done = (v) => { dlg.close(); resolve(v); };
    document.getElementById('confirmDiscard').onclick = () => done(true);
    document.getElementById('confirmKeep').onclick = () => done(false);
    dlg.oncancel = (e) => { e.preventDefault(); done(false); };   // Esc / back = Keep (the safe choice)
    dlg.showModal();
  });
}

function showError(side, message) {
  const el = document.getElementById(side === 'enc' ? 'encError' : 'decError');
  el.textContent = message;          // messages may quote untrusted names: never innerHTML
  el.hidden = false;
}
function clearError(side) {
  const el = document.getElementById(side === 'enc' ? 'encError' : 'decError');
  el.textContent = ''; el.hidden = true;
}
```

Make these edits in the existing functions:

1. `updateTextInfo`: in file mode, `btn.disabled = !encFile;` replaces `btn.disabled = false;`. `onFileSelect`'s enc branch and the drop handler call `updateTextInfo()` after setting `encFile`.
2. `startEncode`: delete the `alert(...)` line. When `!input`, just restore the button and `return`. In `catch`, also call `showError('enc', t('errorPrefix', { msg: err.message }))`. Call `clearError('enc')` at the start.
3. `handleDecFile`: `if (!(await askConfirm(t('gifDiscardsSession', { n: photoSession.asm.rank })))) { … }` replaces `confirm(...)`.
4. `addFrame` becomes `async function addFrame(r)`. Its guard becomes `if (!(await askConfirm(t('photoWrongFile', { n: photoSession.asm.rank })))) { return { kind: 'kept', … }; }`. **Keep** the `h.valid && photoSession.asm.fileId !== null && h.fileId !== photoSession.asm.fileId` expression textually intact; `test_browser_load.js` greps for it.
5. `addPhoto`: `const res = await addFrame(r);`.
6. `onScanFrame` becomes `async`: `const res = await addFrame(r);`. LiveScan already `await`s `onFrame` (`live-scan.js:345`), so one prompt blocks the loop. That is what keeps "prompts once" true.
7. `startDecode`: `if (!photoSession) { showError('dec', t('selectGifFirst')); return; }` replaces the alert. Call `clearError('dec')` at the start.
8. `finishDecode`, encrypted branch:

```js
if (isEncrypted) {
  if (!pass) { const e = new Error(t('passRequired')); e.needPass = true; e.wrongPass = false; throw e; }
  log(t('decrypting'), 'info', 'logDec');
  setProgress(80, t('decryptingShort'), 'progDecFill', 'progDecPct', 'progDecLabel');
  try { decrypted = await CimbarCrypto.decryptBytes(payloadBytes, pass); }
  catch (e) { e.needPass = true; e.wrongPass = true; throw e; }
}
```

   The tail: replace the anchor download with `showFileResult(filename, fileData);`, and after `showTextResult(...)` add `unlockPending = false;`. In `showFileResult`, set `unlockPending = false;` too.

9. `logDecodeError(err)`: first line `if (err.needPass) { showUnlock(!!err.wrongPass); return; }`. In its final `else`, also call `showError('dec', t('errorPrefix', { msg: err.message }))`.
10. New functions:

```js
// `let fileResult = null;` already exists next to `textResult` (Task 2) — do not redeclare it.

function showUnlock(wrongPass) {
  unlockPending = true;
  const err = document.getElementById('unlockError');
  err.textContent = wrongPass ? t('wrongPass') : '';
  err.hidden = !wrongPass;
  navigate('#/receive/unlock', { replace: true });
}

function showFileResult(name, bytes) {
  fileResult = { name, bytes };
  unlockPending = false;
  document.getElementById('fileOutName').textContent = name;              // untrusted
  document.getElementById('fileOutMeta').textContent = fmtBytes(bytes.length);
  document.getElementById('fileOut').style.display = 'block';
  document.getElementById('textOut').style.display = 'none';
  navigate('#/receive/done', { replace: true });
}

function saveFile() {
  if (!fileResult) return;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([fileResult.bytes]));
  a.download = fileResult.name;
  a.click();
}
```

   `showTextResult` gains `document.getElementById('fileOut').style.display = 'none'; navigate('#/receive/done', { replace: true });`. `hideTextResult` and `resetPhotoSession` also clear `fileResult = null; unlockPending = false;` and hide `#fileOut`.

11. Minimal markup. Put it inside the current decode card; Tasks 7/8 move it to its final screens:

```html
<div class="form-error" id="decError" role="alert" hidden></div>
<div class="output-section" id="fileOut" style="display:none">
  <div id="fileOutName"></div><div id="fileOutMeta"></div>
  <button type="button" class="btn btn-primary" id="saveFileBtn" onclick="saveFile()" data-i18n="saveToDevice">Save to device</button>
</div>
<div id="unlockError" class="form-error" hidden></div>
```

   Next to `#encBtn`, add `<div class="form-error" id="encError" role="alert" hidden></div>`. Before `<canvas id="workCanvas">`, add:

```html
<dialog class="sheet" id="confirmSheet" aria-labelledby="confirmText">
  <p id="confirmText"></p>
  <div class="sheet-actions">
    <button type="button" class="btn" id="confirmKeep" data-i18n="confirmKeep">Keep</button>
    <button type="button" class="btn btn-primary" id="confirmDiscard" data-i18n="confirmDiscard">Discard</button>
  </div>
</dialog>
```

12. `i18n.js`: add these keys to `en`, and translate them into ru/uk/tr/ka:

```js
saveToDevice: 'Save to device',
confirmKeep: 'Keep',
confirmDiscard: 'Discard',
wrongPass: 'Wrong passphrase — try again',
```

    Delete `selectFileFirst`, `enterTextFirst` and `encryptedNeedPass` from all five tables. They now have no caller; check with `grep -n "selectFileFirst\|enterTextFirst\|encryptedNeedPass" web-app/index.html`, which must print nothing.

- [ ] **Step 5: Run the tests.**

Run: `sh tests/run_all.sh`
Expected: all suites pass, including the two new tests. Then confirm no dialogs remain:

```bash
grep -nE '\balert\(|\bconfirm\(' web-app/index.html
```

It must print nothing.

- [ ] **Step 6: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/page_harness.js web-app/tests/test_page_logic.js
git commit -m "feat(web): in-page confirm sheet, unlock and file-result seams replace alert/confirm"
```

---

### Task 4: Design foundation, app shell, hub and language sheet

**Files:**
- Modify: `web-app/index.html`: the whole `<style>` block (replaced), `<head>` theme-color, the `<header>`/tab bar/footer markup (replaced), and the inline script (`onEnterRoute`, language sheet).
- Modify: `web-app/i18n.js`
- Test: `web-app/tests/test_page_logic.js` (one new test)

**Interfaces:**
- Produces:
  - CSS classes, used by every later task: `.screen`, `.topbar`, `.topbar-sub`, `.icon-btn`, `.wordmark`, `.choice`, `.choice--primary`, `.choice--tonal`, `.chips`, `.chip`, `.disclosure`, `.btn`, `.btn-primary`, `.btn-secondary`, `.btn-link`, `.btn-row`, `.action-bar`, `.sheet`, `.sheet-actions`, `.form-error`, `.card`, `.overlay`, `.glass-btn`, `.signal-pill`, `.i` (icon).
  - Markup convention: `<section class="screen" data-route="/…" hidden>`.
  - Icon usage: `<svg class="i" aria-hidden="true"><use href="#i-NAME"/></svg>`.
  - `openLanguageSheet()`, `chooseLanguage(code)`.
- Consumes: Task 2's router (`.screen[data-route]`).

- [ ] **Step 1: Write the failing test** (append to `test_page_logic.js`):

```js
test('choosing a language from the sheet sets it and closes the sheet', () => {
  const { ctx, elements } = freshPage();
  let set = null;
  ctx.CimbarI18n.setLang = (c) => { set = c; };
  ctx.openLanguageSheet();
  assertEq(elements['langSheet'].open, true, 'sheet open');
  ctx.chooseLanguage('ka');
  assertEq(set, 'ka', 'language applied');
  assertEq(elements['langSheet'].open, false, 'sheet closed');
});
```

Add `'openLanguageSheet', 'chooseLanguage'` to `REQUIRED_GLOBALS`.

- [ ] **Step 2: Run it to verify it fails.**

Run: `node tests/test_page_logic.js`
Expected: harness error `… top-level function 'openLanguageSheet'`.

- [ ] **Step 3: Build the icon sprite.** Download the pinned Lucide SVGs and generate `<symbol>`s:

```bash
mkdir -p /tmp/lucide && cd /tmp/lucide
for n in arrow-left arrow-right arrow-up-from-line scan-line camera globe circle-help sparkles lock wifi-off cloud-off smartphone file-up file-text x eye eye-off sliders-horizontal maximize share-2 download rotate-ccw sun image check circle-check copy external-link monitor-play chevron-down chevron-right shield grid-3x3 refresh-cw archive gauge circle-alert; do
  curl -fsS -o $n.svg https://unpkg.com/lucide-static@0.460.0/icons/$n.svg || echo "MISSING $n"
done
node -e '
const fs=require("fs");const out=[];
for(const f of fs.readdirSync(".").filter(f=>f.endsWith(".svg")).sort()){
  const s=fs.readFileSync(f,"utf8");const inner=s.replace(/^[\s\S]*?<svg[^>]*>/,"").replace(/<\/svg>\s*$/,"").trim();
  out.push(`<symbol id="i-${f.slice(0,-4)}" viewBox="0 0 24 24">${inner}</symbol>`);}
fs.writeFileSync("sprite.html",out.join("\n"));'
```

Expected: no `MISSING` lines. If one is missing, its name changed in 0.460.0: open `https://unpkg.com/lucide-static@0.460.0/icons/` and use the current name everywhere.

Insert this right after `<body>`:

```html
<!-- icon-sprite:start — Lucide icons (lucide-static 0.460.0), ISC License, Copyright (c) Lucide Contributors -->
<svg xmlns="http://www.w3.org/2000/svg" style="display:none">
  <!-- paste /tmp/lucide/sprite.html here -->
</svg>
<!-- icon-sprite:end -->
```

The symbols inherit stroke from the CSS (`.i { stroke: currentColor; fill: none; … }`), because Lucide's paths carry no stroke attributes of their own.

- [ ] **Step 4: Replace the `<style>` block.** Keep the existing rules that the scanner, Present and log still need until Tasks 6–7 restyle them: `#present*`, `#scanner*`, `.scan-*`, `.log*`, `.progress-*`, `.spinner`, `.strength-*`, `.text-out`, `.hidden`, `.sr-only`. Delete everything else and write:

```css
:root {
  --bg:#f5f3ef; --surface:#ffffff; --surface2:#f9f8f5; --border:#e2ddd6;
  --text:#1a1714; --text2:#5c554e; --text3:#8a827a;
  --accent:#2d6a4f; --accent-fg:#2d6a4f; --accent-l:#d8f0e5; --accent-d:#1b4332; --accent-line:#bfe3d1;
  --warn:#c0392b; --warn-l:#fde8e6;
  --signal:#00FF66; --scrim:rgba(26,23,20,.45); --overlay-glass:rgba(255,255,255,.08);
  --radius:14px; --radius-sm:8px;
  --shadow:0 2px 12px rgba(0,0,0,.07),0 1px 3px rgba(0,0,0,.05);
  --shadow-lg:0 8px 32px rgba(0,0,0,.10),0 2px 8px rgba(0,0,0,.06);
  --serif:'DM Serif Display',Georgia,serif; --sans:'DM Sans',system-ui,sans-serif; --mono:'DM Mono',ui-monospace,monospace;
  color-scheme: light;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg:#171512; --surface:#211e1a; --surface2:#1c1916; --border:#3a352f;
    --text:#efe9e1; --text2:#bdb4a9; --text3:#8f877d;
    --accent-fg:#7fc8a2; --accent-l:#1d3a2c; --accent-d:#cfeedd; --accent-line:#2c5a43;
    --warn:#ef8a7e; --warn-l:#3a1f1b; --scrim:rgba(0,0,0,.6);
    --shadow:0 2px 12px rgba(0,0,0,.4); --shadow-lg:0 8px 32px rgba(0,0,0,.5);
    color-scheme: dark;
  }
}
*,*::before,*::after { box-sizing:border-box; }
html,body { margin:0; background:var(--bg); color:var(--text); font:15px/1.5 var(--sans); -webkit-text-size-adjust:100%; }
.page { max-width:720px; margin:0 auto; padding:0 16px calc(24px + env(safe-area-inset-bottom)); min-height:100dvh; }
.screen[hidden] { display:none !important; }
.i { width:20px; height:20px; stroke:currentColor; fill:none; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; flex:none; }

/* top bars */
.topbar { display:flex; align-items:center; justify-content:space-between; height:56px; padding-top:env(safe-area-inset-top); }
.wordmark { display:flex; align-items:center; gap:8px; font:400 22px/1 var(--serif); color:var(--text); text-decoration:none; }
.wordmark img { width:28px; height:28px; }
.wordmark em { color:var(--accent-fg); }
.topbar-actions { display:flex; gap:6px; }
.icon-btn { display:inline-flex; align-items:center; gap:6px; min-height:40px; min-width:40px; padding:0 10px; border-radius:var(--radius-sm);
  border:1px solid var(--border); background:var(--surface); color:var(--text2); font:500 13px var(--sans); cursor:pointer; }
.icon-btn .i { width:18px; height:18px; }
.topbar-sub { display:flex; align-items:center; gap:12px; height:56px; }
.topbar-sub h1 { margin:0; font:400 22px/1.1 var(--serif); }
/* a 40px visual button inside a 48px hit area */
.icon-btn.back { padding:0; width:40px; justify-content:center; position:relative; }
.icon-btn.back::after { content:''; position:absolute; inset:-4px; }

/* surfaces */
.card { background:var(--surface); border:1px solid var(--border); border-radius:var(--radius); padding:16px; box-shadow:var(--shadow); }

/* hub */
.demo { background:#000; border-radius:var(--radius); padding:16px; display:flex; flex-direction:column; align-items:center; box-shadow:0 8px 28px rgba(26,23,20,.18); }
.demo-chip { align-self:flex-start; font:500 10px var(--mono); letter-spacing:.12em; padding:4px 8px; border-radius:4px; background:rgba(0,255,100,.14); color:var(--signal); }
.demo-chip::before { content:''; display:inline-block; width:6px; height:6px; border-radius:50%; background:var(--signal); margin-right:6px; vertical-align:middle; }
.demo img { width:240px; height:240px; margin-top:12px; image-rendering:pixelated; border-radius:6px; background:#111; }
.demo-caption { display:flex; align-items:center; gap:6px; margin-top:12px; font-size:12px; color:rgba(255,255,255,.72); }
.demo-caption .i { color:var(--signal); width:16px; height:16px; }
.hero-title { font:400 30px/1.1 var(--serif); margin:20px 0 8px; }
.hero-sub { color:var(--text2); margin:0; }
.choices { display:grid; gap:12px; margin-top:20px; }
.choice { display:flex; flex-direction:column; justify-content:space-between; min-height:120px; padding:16px; border-radius:var(--radius); text-decoration:none; }
.choice-top { display:flex; justify-content:space-between; }
.choice-top .i:first-child { width:30px; height:30px; }
.choice-title { font:400 24px/1 var(--serif); }
.choice-sub { font-size:13px; margin-top:6px; }
.choice--primary { background:var(--accent); color:#fff; box-shadow:0 6px 18px rgba(45,106,79,.28); }
.choice--primary .choice-sub { color:rgba(255,255,255,.85); }
.choice--tonal { background:var(--accent-l); color:var(--accent-d); border:1px solid var(--accent-line); }
.choice--tonal .choice-sub { color:var(--accent-fg); }
.chips { display:flex; flex-wrap:wrap; gap:8px; margin-top:16px; }
.chip { display:inline-flex; align-items:center; gap:6px; height:32px; padding:0 12px; border-radius:var(--radius-sm); background:var(--surface);
  border:1px solid var(--border); color:var(--text2); font:500 13px var(--sans); }
.chip .i { width:16px; height:16px; color:var(--accent-fg); }
.disclosure { margin-top:16px; background:var(--surface); border:1px solid var(--border); border-radius:var(--radius); box-shadow:var(--shadow); }
.disclosure > summary { display:flex; align-items:center; justify-content:space-between; min-height:52px; padding:0 16px; cursor:pointer; list-style:none; font-weight:500; }
.disclosure > summary::-webkit-details-marker { display:none; }
.disclosure > summary .i:last-child { color:var(--text3); transition:transform .15s; }
.disclosure[open] > summary .i:last-child { transform:rotate(180deg); }
.disclosure-body { padding:0 16px 16px; }
.steps-mini { display:flex; align-items:center; gap:8px; }
.steps-mini > div { flex:1; text-align:center; font:12px var(--mono); color:var(--text2); }
.steps-mini .tile { width:36px; height:36px; margin:0 auto 6px; border-radius:var(--radius-sm); display:grid; place-items:center; background:var(--accent-l); color:var(--accent-fg); }
.footer { text-align:center; margin-top:24px; font:11px var(--mono); color:var(--text3); }
.footer a { color:inherit; }

/* buttons */
.btn { display:inline-flex; align-items:center; justify-content:center; gap:8px; min-height:48px; padding:0 18px; border-radius:var(--radius);
  border:1px solid var(--border); background:var(--surface); color:var(--text); font:600 15px var(--sans); cursor:pointer; width:100%; text-decoration:none; }
.btn-primary { background:var(--accent); border-color:var(--accent); color:#fff; box-shadow:0 6px 18px rgba(45,106,79,.22); }
.btn-secondary { background:var(--accent-l); border-color:var(--accent-line); color:var(--accent-d); }
.btn-link { background:none; border:0; color:var(--accent-fg); width:auto; min-height:48px; font-weight:500; }
.btn:disabled { opacity:.45; cursor:not-allowed; box-shadow:none; }
.btn-row { display:flex; gap:10px; }
.btn-row > .btn { flex:1; }
.action-bar { position:sticky; bottom:0; padding:12px 0 calc(12px + env(safe-area-inset-bottom)); background:linear-gradient(to top, var(--bg) 70%, transparent); }
.form-error { display:flex; gap:8px; margin-top:12px; padding:10px 12px; border-radius:var(--radius-sm); background:var(--warn-l); color:var(--warn); font-size:14px; }
.form-error[hidden] { display:none; }

/* sheets (dialog) */
.sheet { border:0; padding:8px 16px calc(16px + env(safe-area-inset-bottom)); margin:auto auto 0; width:100%; max-width:560px;
  border-radius:20px 20px 0 0; background:var(--surface); color:var(--text); }
.sheet::backdrop { background:var(--scrim); }
.sheet-handle { width:36px; height:4px; border-radius:2px; background:var(--border); margin:4px auto 12px; }
.sheet h2 { font:400 24px var(--serif); margin:0 0 12px; }
.sheet-actions { display:flex; gap:10px; margin-top:16px; }
.sheet-actions > .btn { flex:1; }
.lang-list { list-style:none; margin:0; padding:0; }
.lang-list button { display:flex; align-items:center; gap:10px; width:100%; min-height:52px; padding:0 12px; border:0; border-radius:var(--radius-sm);
  background:none; color:var(--text); font:15px var(--sans); text-align:left; cursor:pointer; }
.lang-list button[aria-checked="true"] { background:var(--accent-l); }
.lang-list .code { font:11px var(--mono); color:var(--text3); border:1px solid var(--border); border-radius:4px; padding:1px 5px; }
.lang-list .i { margin-left:auto; color:var(--accent-fg); visibility:hidden; }
.lang-list button[aria-checked="true"] .i { visibility:visible; }

/* black overlays (Present, scanner): shared chrome */
.glass-btn { display:grid; place-items:center; width:48px; height:48px; border-radius:50%; border:0; background:var(--overlay-glass); color:#fff; cursor:pointer; }
.signal-pill { display:inline-flex; align-items:center; gap:6px; height:32px; padding:0 12px; border-radius:16px; background:rgba(0,0,0,.55);
  border:1px solid rgba(0,255,102,.35); color:var(--signal); font:500 13px var(--mono); }

@media (min-width:840px) {
  .hub-grid { display:grid; grid-template-columns:1fr 1fr; gap:24px; align-items:start; }
  .hub-grid .choices { margin-top:0; }
}
@media (prefers-reduced-motion: no-preference) {
  .screen:not([hidden]) { animation:screen-in .15s ease-out; }
  @keyframes screen-in { from { opacity:0; transform:translateY(6px); } to { opacity:1; transform:none; } }
  .sheet[open] { animation:sheet-in .2s ease-out; }
  @keyframes sheet-in { from { transform:translateY(100%); } to { transform:none; } }
}
```

In `<head>`, replace `<meta name="theme-color" content="#f5f3ef">` with:

```html
<meta name="theme-color" content="#f5f3ef" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#171512" media="(prefers-color-scheme: dark)">
```

If `tests/test_web_icons.js` asserts the old single `theme-color` tag, update its regex to accept the `media` attribute. Keep the light value `#f5f3ef` asserted.

- [ ] **Step 5: Replace the header, tab bar and footer with the shell and hub.** The old `#tab-encode`, `#tab-decode` and `#tab-about` panels become screens for now. Change `<div class="tab-panel active" id="tab-encode">` to `<section class="screen" data-route="/send" id="tab-encode" hidden>`, and likewise `/receive/files` for decode and `/how` for about. Tasks 5, 7 and 9 rebuild their insides. The hub:

```html
<div class="page">
  <section class="screen" data-route="/" hidden>
    <header class="topbar">
      <a class="wordmark" href="#/"><img src="favicon.svg" alt="" width="28" height="28">Cim<em>Bar</em></a>
      <div class="topbar-actions">
        <button type="button" class="icon-btn" onclick="openLanguageSheet()" aria-label="Language" data-i18n-title="language">
          <svg class="i" aria-hidden="true"><use href="#i-globe"/></svg><span id="langCode">EN</span></button>
        <a class="icon-btn" href="#/how"><svg class="i" aria-hidden="true"><use href="#i-circle-help"/></svg><span data-i18n="howTitle">How it works</span></a>
      </div>
    </header>
    <div class="hub-grid">
      <div>
        <div class="demo">
          <span class="demo-chip" data-i18n="demoChip">LIVE DEMO</span>
          <img id="demoGif" alt="" width="240" height="240">
          <div class="demo-caption"><svg class="i" aria-hidden="true"><use href="#i-smartphone"/></svg><span data-i18n="demoCaption">Try it: scan this with another phone</span></div>
        </div>
        <h1 class="hero-title" data-i18n="heroTitle">Send a file through the air.</h1>
        <p class="hero-sub" data-i18n="heroSub">Phone to phone, screen to camera. No network, no cable, no pairing.</p>
      </div>
      <div>
        <nav class="choices">
          <a class="choice choice--primary" href="#/send">
            <span class="choice-top"><svg class="i"><use href="#i-arrow-up-from-line"/></svg><svg class="i"><use href="#i-arrow-right"/></svg></span>
            <span><span class="choice-title" data-i18n="sendTitle">Send</span><span class="choice-sub" data-i18n="sendSub" style="display:block">A file or a message → animated code</span></span>
          </a>
          <a class="choice choice--tonal" href="#/receive">
            <span class="choice-top"><svg class="i"><use href="#i-scan-line"/></svg><svg class="i"><use href="#i-camera"/></svg></span>
            <span><span class="choice-title" data-i18n="receiveTitle">Receive</span><span class="choice-sub" data-i18n="receiveSub" style="display:block">Scan a code with your camera</span></span>
          </a>
        </nav>
        <div class="chips">
          <span class="chip"><svg class="i"><use href="#i-lock"/></svg><span data-i18n="chipAes">AES-256</span></span>
          <span class="chip"><svg class="i"><use href="#i-wifi-off"/></svg><span data-i18n="chipOffline">Works offline</span></span>
          <span class="chip"><svg class="i"><use href="#i-cloud-off"/></svg><span data-i18n="chipNoUpload">Nothing uploaded</span></span>
        </div>
        <details class="disclosure">
          <summary><span style="display:flex;gap:8px;align-items:center"><svg class="i" style="color:var(--accent-fg)"><use href="#i-sparkles"/></svg><span data-i18n="howTitle">How it works</span></span><svg class="i"><use href="#i-chevron-down"/></svg></summary>
          <div class="disclosure-body">
            <div class="steps-mini">
              <div><span class="tile"><svg class="i"><use href="#i-lock"/></svg></span><span data-i18n="stepEncode">Encode</span></div>
              <svg class="i" style="color:var(--text3)"><use href="#i-chevron-right"/></svg>
              <div><span class="tile"><svg class="i"><use href="#i-monitor-play"/></svg></span><span data-i18n="stepPresent">Present</span></div>
              <svg class="i" style="color:var(--text3)"><use href="#i-chevron-right"/></svg>
              <div><span class="tile"><svg class="i"><use href="#i-scan-line"/></svg></span><span data-i18n="stepScan">Scan</span></div>
            </div>
            <a class="btn-link" href="#/how" data-i18n="howMore">More about how it works</a>
          </div>
        </details>
      </div>
    </div>
    <p class="footer">v<span class="js-version">0.12.1</span> · <a href="https://github.com/mezinster/cimbar" data-i18n="openSource">open source</a></p>
  </section>
  <!-- existing screens follow -->
</div>
```

The decorative `<svg class="i">` elements inside links get `aria-hidden="true"`; add it to every one. The `.js-version` text is filled from `#appVersion`'s `data-version` at load: `document.querySelectorAll('.js-version').forEach(e => e.textContent = document.getElementById('appVersion').dataset.version)`. That keeps `#appVersion` the single source.

Before `<canvas id="workCanvas">`, add the language sheet:

```html
<dialog class="sheet" id="langSheet" aria-labelledby="langSheetTitle">
  <div class="sheet-handle"></div>
  <h2 id="langSheetTitle" data-i18n="languageTitle">Language</h2>
  <ul class="lang-list" id="langList"></ul>
</dialog>
```

- [ ] **Step 6: Script.** Remove the `langSelect` usage. `i18n.js`'s `apply()` already tolerates its absence. Add:

```js
// ── Language sheet ────────────────────────────────────────
function openLanguageSheet() {
  const list = document.getElementById('langList');
  list.innerHTML = '';
  for (const l of CimbarI18n.LANGUAGES) {
    const li = document.createElement('li');
    const b = document.createElement('button');
    b.type = 'button';
    b.setAttribute('role', 'menuitemradio');
    b.setAttribute('aria-checked', String(l.code === CimbarI18n.getLang()));
    b.onclick = () => chooseLanguage(l.code);
    const name = document.createElement('span'); name.textContent = l.name;
    const code = document.createElement('span'); code.className = 'code'; code.textContent = l.code.toUpperCase();
    b.append(name, code);
    b.insertAdjacentHTML('beforeend', '<svg class="i" aria-hidden="true"><use href="#i-check"/></svg>');
    li.appendChild(b); list.appendChild(li);
  }
  document.getElementById('langSheet').showModal();
}
function chooseLanguage(code) {
  CimbarI18n.setLang(code);
  document.getElementById('langSheet').close();
  updateLangCode();
}
function updateLangCode() {
  const el = document.getElementById('langCode');
  if (el && CimbarI18n.getLang) el.textContent = CimbarI18n.getLang().toUpperCase();
}
```

Call `updateLangCode()` right after `CimbarI18n.apply();` at the top.

The harness `CimbarI18n` stub has no `LANGUAGES`/`getLang`/`setLang`. Add `LANGUAGES: [{ code: 'en', name: 'English' }, { code: 'ka', name: 'ქართული' }], getLang: () => 'en', setLang() {}` to it in `page_harness.js`, and give `makeEl` `append(){}` and `insertAdjacentHTML(){}`.

`i18n.js`: add to `en`, and translate ×4:

```js
howTitle: 'How it works', howMore: 'More about how it works',
demoChip: 'LIVE DEMO', demoCaption: 'Try it: scan this with another phone',
heroTitle: 'Send a file through the air.',
heroSub: 'Phone to phone, screen to camera. No network, no cable, no pairing.',
sendTitle: 'Send', sendSub: 'A file or a message → animated code',
receiveTitle: 'Receive', receiveSub: 'Scan a code with your camera',
chipAes: 'AES-256', chipOffline: 'Works offline', chipNoUpload: 'Nothing uploaded',
stepEncode: 'Encode', stepPresent: 'Present', stepScan: 'Scan',
openSource: 'open source', languageTitle: 'Language', back: 'Back',
```

`chipAes` and `demoChip` may stay identical in every language.

- [ ] **Step 7: Run the tests and look at the page.**

Run: `sh tests/run_all.sh`. Expected: all pass.

Then serve and screenshot the hub at 390 px in light and dark. Use the recipe in Task 11, Step 1 with just `#/`. Compare with draft `a4415609` (v2). Expected: same layout, real logo, chips with icons, no tab bar.

- [ ] **Step 8: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/page_harness.js web-app/tests/test_page_logic.js web-app/tests/test_web_icons.js
git commit -m "feat(web): editorial tokens with dark theme, icon sprite, hub and language sheet"
```

---

### Task 5: Send — compose and ready, encode refactor, Share GIF

**Files:**
- Modify: `web-app/index.html`: the `/send` screen markup (rebuilt), a new `/send/ready` screen, and script changes to `startEncode`, a new `encodeToGif`, `downloadGif`, `shareGif`, `onEnterRoute`.
- Modify: `web-app/i18n.js`
- Test: `web-app/tests/test_page_logic.js`

**Interfaces:**
- Produces:
  - `encodeToGif(input: {name, bytes}, opts: {pass: string, frameDelay: number, onProgress?: (pct, label) => void, onLog?: (msg, cls) => void}) → Promise<{blob: Blob, state: encodeState-shaped object, stats: {frames, repair, bytes, compressedPct|null, encrypted}}>`. It uses its **own** `document.createElement('canvas')`, never `#workCanvas`, so the hub demo can encode concurrently.
  - `canShareFiles(type: string) → boolean`
  - `shareBlob(blob, name, type) → Promise<void>`
  - `shareGif()`
- Consumes: `navigate` (Task 2), `showError`/`clearError` (Task 3).

- [ ] **Step 1: Write the failing tests** (append):

```js
test('a finished encode replaces #/send with #/send/ready', async () => {
  const { ctx, elements } = freshPage();
  ctx.encodeToGif = async () => ({ blob: { size: 10 }, state: { frames: [1], bodies: [], fileId: 1, opts: {}, delayMs: 200, repairEnabled: false },
                                    stats: { frames: 1, repair: 0, bytes: 10, compressedPct: null, encrypted: false } });
  ctx.navigate('#/send');
  ctx.setEncMode('text');
  elements['textEnc'].value = 'hi';
  ctx.updateTextInfo();
  await ctx.startEncode();
  assertEq(ctx.location.hash, '#/send/ready', 'on the ready screen');
  assertEq(ctx.routeState().hasGif, true, 'GIF held for the guard');
});

test('Share GIF is hidden when the browser cannot share files', () => {
  const { ctx } = freshPage();
  assertEq(ctx.canShareFiles('image/gif'), false, 'harness navigator has no canShare');
  ctx.navigator.canShare = () => true;
  ctx.File = class { constructor(b, n, o) { this.name = n; this.type = o.type; } };
  assertEq(ctx.canShareFiles('image/gif'), true, 'canShare with files');
});
```

In the harness sandbox, add `File: class { constructor(b, n, o) { this.name = n; this.type = (o || {}).type; } }`. Add `'encodeToGif', 'canShareFiles', 'shareBlob', 'shareGif'` to `REQUIRED_GLOBALS`.

- [ ] **Step 2: Run them to verify they fail.**

Run: `node tests/test_page_logic.js`
Expected: harness error naming `encodeToGif`.

- [ ] **Step 3: Refactor the encode.** Move the body of `startEncode` from `// 1. Read file and build payload` through `outputBlob = gif.finish();` into:

```js
// The whole encode pipeline (spec: CLAUDE.md "Encoding pipeline"), UI-free so
// both the Send screen and the hub demo use it. Its own canvas: the demo may
// encode while the user is encoding.
async function encodeToGif(input, opts) {
  const progress = opts.onProgress || (() => {});
  const say = opts.onLog || (() => {});
  const isEncrypted = opts.pass.length > 0;
  progress(5, t('reading'));
  const payload = Cimbar.buildPayload(input.name, input.bytes);
  say(t('fileInfo', { name: input.name, size: fmtBytes(input.bytes.length) }), 'ok');
  const z = await CimbarCompress.maybeDeflate(payload);
  say(z.compressed ? t('compressedInfo', { size: fmtBytes(z.bytes.length), pct: Math.round(100 * z.bytes.length / payload.length) }) : t('notCompressed'), z.compressed ? 'ok' : 'info');
  let framedPayload;
  if (isEncrypted) {
    progress(15, t('encryptingShort'));
    framedPayload = await CimbarCrypto.encryptBytes(z.bytes, opts.pass);
    say(t('encrypted', { size: fmtBytes(framedPayload.length) }), 'ok');
  } else {
    progress(15, t('encoding'));
    framedPayload = z.bytes;
    say(t('payloadNoEnc', { size: fmtBytes(framedPayload.length) }), 'ok');
  }
  const framedData = Cimbar.withLengthPrefix(framedPayload);
  const fileId = crypto.getRandomValues(new Uint16Array(1))[0];
  const fopts = { encrypted: isEncrypted, compressed: z.compressed };
  const frames = Cimbar.splitIntoFrames(framedData, fileId, fopts);
  say(t('framesInfo', { n: frames.length, per: CimbarFormat.fileBytesPerFrame(), id: fileId.toString(16) }), 'info');
  const maxN = CimbarFormat.SPEC.coding.maxFrames;
  const R = frames.length > maxN ? 0 : Cimbar.gifRepairCount(frames.length);
  if (frames.length > maxN) say(t('tooLargeForCoding', { max: maxN }), 'err');
  const bodies = Cimbar.frameBodies(frames);
  const state = { frames, bodies, fileId, opts: fopts, delayMs: opts.frameDelay * 10, repairEnabled: frames.length > 1 && frames.length <= maxN };

  const size = CimbarFormat.SPEC.grid.framePx;
  const canvas = document.createElement('canvas');
  canvas.width = size; canvas.height = size;
  const ctx = canvas.getContext('2d');
  const rs = new ReedSolomon(CimbarFormat.SPEC.rs.eccBytes);
  const gif = new GifEncoder(size, size, opts.frameDelay);
  const totalFrames = frames.length + R;
  let repairId = 0;
  for (let f = 0; f < totalFrames; f++) {
    progress(25 + (f / totalFrames) * 65, t('encodingFrame', { i: f + 1, n: totalFrames }));
    let data;
    if (f < frames.length) data = frames[f];
    else {
      for (let misses = 0; ; ) {
        try { data = Cimbar.repairFrame(bodies, fileId, repairId, fopts); break; }
        catch (e) { if (!e.degenerate) throw e; repairId = (repairId + 1) & 0xFFFF; if (++misses >= 64) throw new Error('no usable repair id'); }
      }
      repairId = (repairId + 1) & 0xFFFF;
    }
    Cimbar.renderFrame(ctx, Cimbar.encodeRSFrame(data, rs));
    gif.addFrame(canvas);
    if (f % 4 === 0) await sleep(0);
  }
  progress(93, t('compiling'));
  await sleep(10);
  const blob = gif.finish();
  return { blob, state, stats: { frames: frames.length, repair: R, bytes: framedPayload.length,
    compressedPct: z.compressed ? Math.round(100 * z.bytes.length / payload.length) : null, encrypted: isEncrypted } };
}
```

`startEncode` becomes:

```js
async function startEncode() {
  const btn = document.getElementById('encBtn');
  if (btn.disabled) return;
  btn.disabled = true;
  clearError('enc');
  const input = await encodeInput();
  if (!input) { btn.disabled = false; updateTextInfo(); return; }
  const pass = document.getElementById('passEnc').value.trim();
  const frameDelay = parseInt(document.getElementById('frameDelay').value);
  document.getElementById('progEnc').style.display = 'block';
  document.getElementById('logEnc').innerHTML = '';
  outputBlob = null; encodeState = null;
  try {
    const res = await encodeToGif(input, {
      pass, frameDelay,
      onProgress: (pct, label) => setProgress(pct, label, 'progEncFill', 'progEncPct', 'progEncLabel'),
      onLog: (msg, cls) => log(msg, cls, 'logEnc'),
    });
    outputBlob = res.blob; encodeState = res.state; encodeName = input.name;
    showReady(res.stats);
    setProgress(100, t('done'), 'progEncFill', 'progEncPct', 'progEncLabel');
    log(t('gifReady', { size: fmtBytes(outputBlob.size) }), 'ok', 'logEnc');
    navigate('#/send/ready', { replace: true });
  } catch (err) {
    log(t('errorPrefix', { msg: err.message }), 'err', 'logEnc');
    showError('enc', t('errorPrefix', { msg: err.message }));
    console.error(err);
  }
  document.getElementById('progEnc').style.display = 'none';
  btn.disabled = false;
  updateTextInfo();
}

let encodeName = '';
function showReady(stats) {
  const img = document.getElementById('gifOut');
  if (img.src && img.src.startsWith('blob:')) URL.revokeObjectURL(img.src);
  img.src = URL.createObjectURL(outputBlob);
  const parts = [t('readyFrames', { n: stats.repair ? stats.frames + ' + ' + stats.repair : stats.frames }), fmtBytes(outputBlob.size)];
  if (stats.compressedPct !== null) parts.push(t('metaCompressed'));
  if (stats.encrypted) parts.push(t('metaEncrypted'));
  document.getElementById('readyMeta').textContent = parts.join(' · ');
  document.getElementById('readyHelp').textContent = t('readyHelp', { n: stats.frames });
  document.getElementById('shareGifBtn').hidden = !canShareFiles('image/gif');
  document.getElementById('delayHint').style.display = stats.frames > 100 ? 'block' : 'none';
}

function gifFileName() { return 'cimbar-' + (encodeName.replace(/\.[^.]*$/, '') || 'message') + '.gif'; }

function downloadGif() {
  if (!outputBlob) return;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(outputBlob);
  a.download = gifFileName();
  a.click();
}

function canShareFiles(type) {
  try { return !!(navigator.canShare && navigator.canShare({ files: [new File([new Uint8Array(1)], 'x', { type })] })); }
  catch (_) { return false; }
}

async function shareBlob(blob, name, type) {
  try { await navigator.share({ files: [new File([blob], name, { type })] }); }
  catch (e) { if (e && e.name !== 'AbortError') showError('dec', t('errorPrefix', { msg: e.message })); }
}
function shareGif() { if (outputBlob) shareBlob(outputBlob, gifFileName(), 'image/gif'); }
```

The old `#sFrames`/`#sBytes`/`#sPerFrame`/`#sCompressed` stats and the `statFrames*` code are deleted. `#delayHint` stays, on the ready screen.

`.btn` innerHTML spinner swaps go away. Progress is shown by `#progEnc` inside the action bar (markup below).

- [ ] **Step 4: Markup.** Replace the old `/send` screen contents. Keep these ids, which the script and tests use: `encModeFile`, `encModeText`, `encFileField`, `encTextField`, `dropEnc`, `fileEnc`, `pillEnc`, `pillEncText`, `textEnc`, `textEncInfo`, `passEnc`, `strengthFillEnc`, `frameDelay`, `encBtn`, `encError`, `progEnc`, `progEncLabel`, `progEncPct`, `progEncFill`, `logEnc`.

```html
<section class="screen" data-route="/send" hidden>
  <header class="topbar-sub"><a class="icon-btn back" href="#/" aria-label="Back" data-i18n-title="back"><svg class="i" aria-hidden="true"><use href="#i-arrow-left"/></svg></a><h1 data-i18n="sendTitle">Send</h1></header>
  <div class="seg" role="tablist">
    <button type="button" role="tab" class="seg-btn active" id="encModeFile" onclick="setEncMode('file')"><svg class="i" aria-hidden="true"><use href="#i-file-text"/></svg><span data-i18n="encModeFile">File</span></button>
    <button type="button" role="tab" class="seg-btn" id="encModeText" onclick="setEncMode('text')"><span data-i18n="encModeText">Text</span></button>
  </div>
  <div id="encFileField">
    <label class="pick" id="dropEnc">
      <input type="file" id="fileEnc" class="sr-only" onchange="onFileSelect(this,'enc')">
      <span class="pick-icon"><svg class="i" aria-hidden="true"><use href="#i-file-up"/></svg></span>
      <span class="pick-title" data-i18n="chooseFile">Choose a file</span>
      <span class="pick-hint" data-i18n="chooseFileHint">Any type · up to ~80 KB is quickest</span>
      <span class="pick-drop" data-i18n="dropHere">or drop it here</span>
    </label>
    <div class="file-pill" id="pillEnc"><svg class="i" aria-hidden="true"><use href="#i-file-text"/></svg><span id="pillEncText"></span>
      <button type="button" class="icon-btn" onclick="clearEncFile()" aria-label="Remove"><svg class="i" aria-hidden="true"><use href="#i-x"/></svg></button></div>
  </div>
  <div id="encTextField" style="display:none">
    <label for="textEnc" class="sr-only" data-i18n="textToEncode">Text to send</label>
    <textarea id="textEnc" rows="8" data-i18n-placeholder="textEncPlaceholder" oninput="updateTextInfo()"></textarea>
    <div class="field-hint" id="textEncInfo"></div>
  </div>
  <details class="disclosure">
    <summary><span class="row"><svg class="i" aria-hidden="true"><use href="#i-lock"/></svg><span data-i18n="addPassphrase">Add a passphrase</span> <span class="muted" data-i18n="optional">(optional)</span></span><svg class="i" aria-hidden="true"><use href="#i-chevron-down"/></svg></summary>
    <div class="disclosure-body">
      <div class="pass-field"><input type="password" id="passEnc" autocomplete="new-password" data-i18n-placeholder="passEncPlaceholder" oninput="updateStrength(this.value,'strengthFillEnc')">
        <button type="button" class="icon-btn" onclick="togglePass('passEnc', this)" aria-label="Show"><svg class="i" aria-hidden="true"><use href="#i-eye"/></svg></button></div>
      <div class="strength-track"><div class="strength-fill" id="strengthFillEnc"></div></div>
      <div class="field-hint" data-i18n="passEncHintShort">Receiver needs it to open the file</div>
    </div>
  </details>
  <details class="disclosure">
    <summary><span class="row"><svg class="i" aria-hidden="true"><use href="#i-sliders-horizontal"/></svg><span data-i18n="advanced">Advanced</span></span><svg class="i" aria-hidden="true"><use href="#i-chevron-down"/></svg></summary>
    <div class="disclosure-body">
      <label for="frameDelay" data-i18n="frameSpeed">Frame speed</label>
      <select id="frameDelay">
        <option value="10" data-i18n="delayFast">100 ms (fast)</option>
        <option value="20" selected data-i18n="delayNormal">200 ms</option>
        <option value="40" data-i18n="delaySlow">400 ms (slow)</option>
      </select>
    </div>
  </details>
  <div class="form-error" id="encError" role="alert" hidden></div>
  <div class="action-bar">
    <div class="progress-section" id="progEnc">
      <div class="progress-header"><span id="progEncLabel" data-i18n="processing">Processing…</span><span id="progEncPct">0%</span></div>
      <div class="progress-track"><div class="progress-fill" id="progEncFill"></div></div>
      <details class="disclosure details-log"><summary data-i18n="details">Details</summary><div class="log" id="logEnc"></div></details>
    </div>
    <button type="button" class="btn btn-primary" id="encBtn" onclick="startEncode()"><svg class="i" aria-hidden="true"><use href="#i-sparkles"/></svg><span data-i18n="createCode">Create code</span></button>
  </div>
</section>

<section class="screen" data-route="/send/ready" hidden>
  <header class="topbar-sub"><a class="icon-btn back" href="#/" aria-label="Back"><svg class="i" aria-hidden="true"><use href="#i-arrow-left"/></svg></a><h1 data-i18n="readyTitle">Ready to send</h1></header>
  <div class="demo"><span class="demo-chip" data-i18n="readyChip">READY</span><img id="gifOut" alt="" class="ready-gif"></div>
  <p class="meta" id="readyMeta"></p>
  <button type="button" class="btn btn-primary" onclick="openPresent()"><svg class="i" aria-hidden="true"><use href="#i-maximize"/></svg><span data-i18n="presentFullScreen">Present full screen</span></button>
  <div class="btn-row" style="margin-top:10px">
    <button type="button" class="btn btn-secondary" id="shareGifBtn" onclick="shareGif()" hidden><svg class="i" aria-hidden="true"><use href="#i-share-2"/></svg><span data-i18n="shareGif">Share GIF</span></button>
    <button type="button" class="btn btn-secondary" onclick="downloadGif()"><svg class="i" aria-hidden="true"><use href="#i-download"/></svg><span data-i18n="download">Download</span></button>
  </div>
  <p class="field-hint center" id="readyHelp"></p>
  <div class="field-hint center" id="delayHint" style="display:none" data-i18n="delayHint">Over 100 frames: 400 ms is safer for phone capture</div>
  <p class="center"><a class="btn-link" href="#/send" data-i18n="sendAnother">Send something else</a></p>
</section>
```

Add the screen CSS: `.seg`, `.seg-btn`, `.pick`, `.pick-*`, `.file-pill`, `.pass-field`, `.row`, `.muted`, `.meta`, `.center`, `.ready-gif`, `.details-log`, `.field-hint`, `select`, `textarea`, and `input[type=password]`. Rules:
- 48 px controls, `var(--radius-sm)`, `var(--border)`, `var(--surface)` background, `var(--text)` colour.
- `.meta` is `var(--mono)` 12px `var(--text2)`, centred.
- `.ready-gif` is `width:min(300px,100%)` with `aspect-ratio:1` and `image-rendering:pixelated`.
- `.pick` is a dashed-border column, centred, min-height 150px.
- `.pick-drop` is `display:none`, except under `@media (hover:hover) and (pointer:fine)`.
- `.file-pill` uses `display:none` and is `display:flex` when `.show`.
- `.progress-section` uses `display:none` and is shown by the script setting `style.display='block'`.

Match draft `2298bb52` (compose) and `7aab3297` (ready).

New script helpers:

```js
function clearEncFile() { encFile = null; document.getElementById('pillEnc').classList.remove('show'); document.getElementById('fileEnc').value = ''; updateTextInfo(); }
function togglePass(id, btn) {
  const el = document.getElementById(id);
  const show = el.type === 'password';
  el.type = show ? 'text' : 'password';
  btn.querySelector('use').setAttribute('href', show ? '#i-eye-off' : '#i-eye');
}
```

`showPill` now writes `name · size` with `textContent` (it already does).

- [ ] **Step 5: i18n.** Add to `en`, and translate ×4:

```js
chooseFile: 'Choose a file', chooseFileHint: 'Any type · up to ~80 KB is quickest', dropHere: 'or drop it here',
addPassphrase: 'Add a passphrase', optional: '(optional)', passEncHintShort: 'Receiver needs it to open the file',
advanced: 'Advanced', frameSpeed: 'Frame speed', createCode: 'Create code', details: 'Details',
readyTitle: 'Ready to send', readyChip: 'READY', readyFrames: '{n} frames',
metaCompressed: 'compressed', metaEncrypted: 'encrypted',
shareGif: 'Share GIF', download: 'Download',
readyHelp: 'Present on this screen and scan it with the other phone — any {n} frames rebuild the file, in any order.',
sendAnother: 'Send something else',
```

Delete `encodeBtn`, `statFrames`, `statFramesCoded`, `statBytes`, `statPerFrame`, `statCompressed`, `fileToEncode`, `dropFileHtml`, `dropHint`, `passEncHint`, `frameDelay` (the label key, not the element id), and `downloadGif`, **if** `grep -n "'KEY'\|\"KEY\"" web-app/index.html` shows no remaining use for each.

- [ ] **Step 6: Run the tests.**

Run: `sh tests/run_all.sh`. Expected: all pass, including the 2 new tests.

Browser: serve, open `#/send` at 390 px, encode a small file, and land on `#/send/ready`. Compare with the drafts. Press Back: you must land on `#/`, not on compose.

- [ ] **Step 7: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/page_harness.js web-app/tests/test_page_logic.js
git commit -m "feat(web): Send compose and ready screens, UI-free encodeToGif, Share GIF"
```

---

### Task 6: Present — overlay chrome, Back gesture, Wake Lock

**Files:**
- Modify: `web-app/index.html`: the `#present` markup and CSS, `openPresent`/`closePresent`, the keydown and popstate listeners, and new Wake Lock functions.
- Modify: `web-app/i18n.js`
- Test: `web-app/tests/test_page_logic.js`

**Interfaces:**
- Produces:
  - `requestClosePresent()`
  - `acquireWakeLock() → Promise<void>`
  - `releaseWakeLock()`
  - the `wakeLock` let-binding
  - `history.state.cimbarPresent === true` while Present is open
- Consumes: `encodeState` (Task 5).

- [ ] **Step 1: Write the failing tests:**

```js
test('Present pushes one history entry; closing via the UI pops it exactly once', () => {
  const { ctx, calls } = freshPage();
  ctx.setInterval = () => 1; ctx.clearInterval = () => {};
  ctx.presentDraw = () => {}; ctx.layoutPresent = () => {};   // rendering is covered elsewhere; this test is about history
  ctx.openPresentWith({ frames: [new Uint8Array(1)], bodies: [], fileId: 1, opts: {}, delayMs: 200, repairEnabled: false });
  assertEq(calls.pushes, 1, 'one entry pushed');
  assertEq(ctx.history.state && ctx.history.state.cimbarPresent, true, 'entry marked');
  ctx.requestClosePresent();
  assertEq(calls.backs, 1, 'UI close goes through history.back()');
});

test('Wake Lock: pill shows only while a lock is held, and it is re-acquired on return', async () => {
  const { ctx, elements } = freshPage();
  let requests = 0, sentinel = null;
  ctx.navigator.wakeLock = { request: async () => { requests++; sentinel = { released: false, addEventListener(_e, fn) { this.onrel = fn; }, release: async function () { this.onrel && this.onrel(); } }; return sentinel; } };
  ctx.presentOpenForTest(true);
  await ctx.acquireWakeLock();
  assertEq(elements['wakePill'].hidden, false, 'pill visible with a lock');
  sentinel.onrel();                       // the browser dropped it (tab hidden)
  assertEq(elements['wakePill'].hidden, true, 'pill hidden without a lock');
  await ctx.onVisibilityChange();
  assertEq(requests, 2, 're-acquired when visible again');
});

test('no Wake Lock API: no pill and no error', async () => {
  const { ctx, elements } = freshPage();
  ctx.presentOpenForTest(true);
  await ctx.acquireWakeLock();
  assertEq(elements['wakePill'].hidden, true, 'pill hidden');
});
```

Two test seams go in the page script:
- `openPresentWith(state)` sets `encodeState = state` and calls `openPresent()`.
- `presentOpenForTest(open)` sets the private `presentOpen` flag.

Both are one-liners, and their names are honest about their purpose. Add `'requestClosePresent', 'acquireWakeLock', 'releaseWakeLock', 'onVisibilityChange', 'openPresentWith', 'presentOpenForTest'` to `REQUIRED_GLOBALS`.

The harness sandbox needs `setInterval: () => 1` and `clearInterval: () => {}` defaults. The test stubs `presentDraw` and `layoutPresent` by reassigning the globals, the same technique as `ctx.toImageData`, so no canvas stub is needed.

- [ ] **Step 2: Run them to verify they fail.**

Run: `node tests/test_page_logic.js`
Expected: FAIL. Harness error naming `requestClosePresent`.

- [ ] **Step 3: Implement.** Markup, replacing the old `#present`:

```html
<div id="present" class="overlay" role="dialog" aria-modal="true">
  <canvas id="presentCanvas"></canvas>
  <button type="button" class="glass-btn present-close" onclick="requestClosePresent()" aria-label="Close" data-i18n-title="scanClose"><svg class="i" aria-hidden="true"><use href="#i-x"/></svg></button>
  <span class="signal-pill present-wake" id="wakePill" hidden><svg class="i" aria-hidden="true"><use href="#i-sun"/></svg><span data-i18n="screenOn">Screen stays on</span></span>
  <span class="present-hint" id="presentHint" data-i18n="presentHint">Point the other phone's camera here</span>
  <div id="presentStatus"></div>
</div>
```

CSS:
- `#present` is `position:fixed; inset:0; background:#000; z-index:1000; display:none; align-items:center; justify-content:center`, with `.open` setting `display:flex`.
- `.present-close` sits top-left at `calc(12px + env(safe-area-inset-top))`/12px; `.present-wake` top-right.
- `.present-hint` is a translucent pill below centre, with `animation: hint-out 0s 3s forwards` (or a 0.4 s fade starting at 3 s inside `prefers-reduced-motion: no-preference`; with reduced motion it simply hides after 3 s via the same keyframe at 0 duration).
- `#presentStatus` stays bottom-left in mono grey.

Match draft `29146693`. Remove the old `onclick="closePresent()"` and title from the container: a tap on the code must **not** close Present.

Script:

```js
let presentOpen = false, wakeLock = null;

function openPresentWith(state) { encodeState = state; openPresent(); }    // test seam
function presentOpenForTest(open) { presentOpen = open; }                   // test seam

function openPresent() {
  if (!encodeState) return;
  if (presentTimer) { clearInterval(presentTimer); presentTimer = null; }
  presentIdx = 0; presentRepair = 0; presentOpen = true;
  document.getElementById('present').classList.add('open');
  history.pushState({ cimbarPresent: true }, '');
  layoutPresent();
  presentDraw();
  presentTimer = setInterval(presentDraw, encodeState.delayMs);
  const el = document.documentElement;
  if (el.requestFullscreen) el.requestFullscreen().catch(() => {});
  acquireWakeLock();
}

// UI close (✕, Esc): go through history so the Back gesture and the button share one path.
function requestClosePresent() {
  if (history.state && history.state.cimbarPresent) history.back();   // popstate → closePresent()
  else closePresent();
}

function closePresent() {
  if (presentTimer) { clearInterval(presentTimer); presentTimer = null; }
  presentOpen = false;
  document.getElementById('present').classList.remove('open');
  releaseWakeLock();
  if (document.fullscreenElement && document.exitFullscreen) document.exitFullscreen().catch(() => {});
}

function showWakePill() { document.getElementById('wakePill').hidden = !wakeLock; }

async function acquireWakeLock() {
  if (!presentOpen || !(navigator.wakeLock && navigator.wakeLock.request)) { showWakePill(); return; }
  try {
    const lock = await navigator.wakeLock.request('screen');
    wakeLock = lock;
    lock.addEventListener('release', () => { if (wakeLock === lock) wakeLock = null; showWakePill(); });
  } catch (_) { wakeLock = null; }
  showWakePill();
}

function releaseWakeLock() {
  const lock = wakeLock; wakeLock = null;
  if (lock) lock.release().catch(() => {});
  showWakePill();
}

// Browsers drop a screen lock whenever the tab is hidden; take it back on return.
async function onVisibilityChange() {
  if (document.visibilityState === 'visible' && presentOpen && !wakeLock) await acquireWakeLock();
}
document.addEventListener('visibilitychange', onVisibilityChange);
```

The keydown listener's Escape branch becomes `if (scanner) closeScanner(); else if (presentOpen) requestClosePresent();`.

Replace the scanner-only popstate listener with:

```js
window.addEventListener('popstate', () => {
  if (scanner) scanner.scan.stop('back');
  if (presentOpen) closePresent();
});
```

`presentDraw`'s degenerate-repair bail-out calls `requestClosePresent()` instead of `closePresent()`.

**i18n:** add `screenOn: 'Screen stays on'` and `presentHint: "Point the other phone's camera here"` (×5). Delete `presentTitle` if it is now unused.

- [ ] **Step 4: Run the tests.**

Run: `sh tests/run_all.sh`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/page_harness.js web-app/tests/test_page_logic.js
git commit -m "feat(web): Present overlay with Back-gesture close and Screen Wake Lock"
```

---

### Task 7: Receive — the scanner opens from `#/receive`, the files screen and the camera fallback

**Files:**
- Modify: `web-app/index.html`: the `#scanner` markup and CSS, the `/receive/files` screen (rebuilt from the old decode card), `openScanner`, `onScanStopped`, `onEnterRoute`, the LiveScan `onError` handler.
- Modify: `web-app/i18n.js`
- Test: `web-app/tests/test_page_logic.js`

**Interfaces:**
- Consumes: `navigate`, `currentRoute`, `onEnterRoute` (Task 2); `showError` (Task 3); the existing `openScanner`/`closeScanner`/`onScanStopped`.
- Produces: `onEnterRoute` handles `'/receive'`; a `lastScanError` let-binding.

- [ ] **Step 1: Write the failing tests:**

```js
test('entering #/receive opens the scanner; closing it without a file returns to the hub', async () => {
  const { ctx, calls } = freshPage();
  ctx.navigate('#/receive');
  await new Promise((r) => setTimeout(r, 0));
  assertEq(calls.liveScans.length, 1, 'scanner started on route entry');
  calls.liveScans[0].stop('closed');
  await new Promise((r) => setTimeout(r, 0));
  assertEq(ctx.location.hash, '#/', 'back to the hub');
});

test('a camera error routes to #/receive/files with the reason shown', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.navigate('#/receive');
  await new Promise((r) => setTimeout(r, 0));
  const scan = calls.liveScans[0];
  scan.o.onError('camDenied');
  scan.stop('error');
  await new Promise((r) => setTimeout(r, 0));
  assertEq(ctx.location.hash, '#/receive/files', 'fallback screen');
  assertEq(elements['decNotice'].textContent, 'camUnavailable', 'explains the fallback');
});

test('no camera API: #/receive lands on files without starting a scan', () => {
  const { ctx, calls } = freshPage({ camera: false });
  ctx.navigate('#/receive');
  assertEq(ctx.location.hash, '#/receive/files', 'guarded');
  assertEq(calls.liveScans.length, 0, 'no scanner');
});
```

The existing tests that call `ctx.openScanner()` directly stay as they are. They still pass, because `openScanner` keeps working standalone.

- [ ] **Step 2: Run them to verify they fail.**

Run: `node tests/test_page_logic.js`. Expected: FAIL (0 live scans).

- [ ] **Step 3: Implement.** The script:

```js
let lastScanError = null;

function onEnterRoute(route, prev) {
  if (route === '/receive') openScanner();
  // later tasks add cases here
}
```

In `openScanner`, before `s.scan = new …`, set `lastScanError = null;`. The `onError` handler becomes:

```js
onError: (code) => { lastScanError = code; log(scanErrorText(code), 'err', 'logDec'); },
```

At the end of `onScanStopped`, after the existing completion logic, add the routing:

```js
  // Where to land after the scanner closes (spec §1): a completion routed
  // itself (done/unlock); an error falls back to the files screen; a plain
  // close from #/receive returns to the hub.
  if (currentRoute !== '/receive') return;
  if (info.reason === 'error' || info.reason === 'decoderFailed') {
    navigate('#/receive/files', { replace: true });
    showNotice(lastScanError === 'scanDecoderFailed' ? scanErrorText('scanDecoderFailed') : t('camUnavailable'));
  } else if (!(photoSession && photoSession.asm.isComplete())) {
    navigate('#/', { replace: true });
  }
```

A completing scan calls `completePhotoSession()` → `showFileResult`/`showTextResult`/`showUnlock`. Each of those navigates away from `/receive`, so the guard above sees a different `currentRoute`. **Order matters:** the existing `await completePhotoSession()` must stay *before* this block.

```js
function showNotice(message) {
  const el = document.getElementById('decNotice');
  el.textContent = message; el.hidden = false;
}
```

The files screen markup replaces the old decode card. Keep these ids: `dropDec`, `fileDec`, `photoDec`, `scanBtn`, `pillDec`, `pillDecText`, `decError`, `progDec`, `progDecLabel`, `progDecPct`, `progDecFill`, `logDec`, `photoStartOverBtn`.

```html
<section class="screen" data-route="/receive/files" hidden>
  <header class="topbar-sub"><a class="icon-btn back" href="#/" aria-label="Back"><svg class="i" aria-hidden="true"><use href="#i-arrow-left"/></svg></a><h1 data-i18n="receiveTitle">Receive</h1></header>
  <div class="notice" id="decNotice" role="status" hidden></div>
  <a class="btn btn-primary" id="scanBtn" href="#/receive" style="display:none"><svg class="i" aria-hidden="true"><use href="#i-scan-line"/></svg><span data-i18n="scanCamera">Scan with camera</span></a>
  <label class="pick" id="dropDec">
    <input type="file" id="fileDec" class="sr-only" accept="image/gif,image/*" onchange="onFileSelect(this,'dec')">
    <span class="pick-icon"><svg class="i" aria-hidden="true"><use href="#i-image"/></svg></span>
    <span class="pick-title" data-i18n="chooseGif">Choose a GIF</span>
    <span class="pick-hint" data-i18n="chooseGifHint">A CimBar GIF, or a photo of one frame</span>
    <span class="pick-drop" data-i18n="dropHere">or drop it here</span>
  </label>
  <input type="file" id="photoDec" accept="image/*" capture="environment" class="sr-only" onchange="onFileSelect(this,'dec')">
  <button type="button" class="btn btn-secondary" onclick="document.getElementById('photoDec').click()"><svg class="i" aria-hidden="true"><use href="#i-camera"/></svg><span data-i18n="photographFrames">Photograph frames</span></button>
  <p class="field-hint" data-i18n="photoFramesHint">One photo per frame — keep going until every frame is in.</p>
  <div class="file-pill" id="pillDec"><svg class="i" aria-hidden="true"><use href="#i-file-text"/></svg><span id="pillDecText"></span></div>
  <div class="form-error" id="decError" role="alert" hidden></div>
  <div class="progress-section" id="progDec">
    <div class="progress-header"><span id="progDecLabel" data-i18n="decoding">Decoding…</span><span id="progDecPct">0%</span></div>
    <div class="progress-track"><div class="progress-fill" id="progDecFill"></div></div>
    <details class="disclosure details-log"><summary data-i18n="details">Details</summary><div class="log" id="logDec"></div></details>
    <button type="button" class="btn-link" id="photoStartOverBtn" style="display:none" onclick="resetPhotoSession()"><svg class="i" aria-hidden="true"><use href="#i-rotate-ccw"/></svg><span data-i18n="photoStartOver">Start over</span></button>
  </div>
</section>
```

**Behaviour change:** choosing a GIF now decodes it immediately. There is no Decode button any more (spec §1). In `handleDecFile`'s GIF branch, after `showPill(...)`, call `await startDecode();`. Any existing harness test that stages a GIF and then calls `startDecode()` itself must still hold: `startDecode` is idempotent per staged file. Check the tests at ~341–389 and ~522–536. Where they assert state *between* staging and decoding, stub `ctx.GifDecoder` to throw a recognisable error so the auto-decode fails fast, and keep their assertions.

The old Decode button `#decBtn`, `.callout` "How decoding works", and the old passphrase field (`#passDec` moves to the unlock screen in Task 8) are removed here. `startDecode` no longer touches `#decBtn`: delete those lines, and the `retryBtn` lines in its session branch. The `#passDec` input must exist before Task 8, so add it now inside a hidden placeholder `<section class="screen" data-route="/receive/unlock" hidden><input type="password" id="passDec"></section>`. Task 8 fills that screen.

Scanner markup, restyled per draft `15fb90f6`. Keep these ids: `scanner`, `scanVideo`, `scanOverlay`, `scanCloseBtn`, `scanCount`, `scanTrack`, `scanFill`, `scanHint`, `scanResumeBtn`, `scanDebug`.

```html
<div id="scanner" role="dialog" aria-modal="true">
  <video id="scanVideo" playsinline muted autoplay></video>
  <canvas id="scanOverlay"></canvas>
  <div class="scan-top">
    <button type="button" class="glass-btn" id="scanCloseBtn" aria-label="Close" data-i18n-title="scanClose" onclick="closeScanner()"><svg class="i" aria-hidden="true"><use href="#i-x"/></svg></button>
    <span class="signal-pill" id="scanCount"></span>
    <span style="width:48px"></span>
  </div>
  <div class="scan-sheet">
    <div class="progress-track" id="scanTrack"><div class="progress-fill" id="scanFill"></div></div>
    <div id="scanHint"></div>
    <button type="button" class="btn btn-primary" id="scanResumeBtn" data-i18n="scanResume" onclick="resumeScanner()">Resume</button>
    <a class="btn btn-ghost-dark" href="#/receive/files" onclick="closeScanner()"><svg class="i" aria-hidden="true"><use href="#i-image"/></svg><span data-i18n="loadInstead">Load a GIF or photo instead</span></a>
    <pre id="scanDebug"></pre>
  </div>
</div>
```

**Gotcha in the "Load instead" link:** clicking it calls `closeScanner()` → `onScanStopped` with reason `'closed'` → `history.back()` (the overlay entry). The link's own hash navigation then pushes `#/receive/files`. Write this exact sequence in the click handler to avoid a race:

```js
function loadInsteadOfScanning(e) {
  e.preventDefault();
  if (scanner) scanner.scan.stop('closed');
  navigate('#/receive/files', { replace: true });
}
```

Use `onclick="loadInsteadOfScanning(event)"`. Then the `currentRoute !== '/receive'` early return in `onScanStopped` would wrongly *not* route, so `navigate` runs after `stop`. Verify the order with the browser check in Step 5.

`showScanProgress`'s count text becomes `` `${asm.rank} / ${asm.total}` `` plus ` frames` via `t('scanFrames', {rank, total})`.

CSS:
- `.scan-top` is a flex row, space-between, at the top with the safe area.
- `.scan-sheet` is pinned to the bottom, with a `rgba(20,20,20,.82)` background, `backdrop-filter: blur(8px)`, top corners rounded 20 px, white text, and padding plus safe area.
- `.btn-ghost-dark` has a transparent background, a 1 px `rgba(255,255,255,.2)` border, white text, and a 48 px minimum height.
- `#scanFill` uses `background: var(--signal)`.

**i18n** (×5):

```js
chooseGif: 'Choose a GIF', chooseGifHint: 'A CimBar GIF, or a photo of one frame',
photographFrames: 'Photograph frames', photoFramesHint: 'One photo per frame — keep going until every frame is in.',
loadInstead: 'Load a GIF or photo instead', scanFrames: '{rank} / {total} frames',
camUnavailable: 'Camera unavailable — choose a GIF or photograph the frames instead.',
```

Delete `howDecodingHtml`, `decodeBtn`, `choosePhotoOrGif`, `dropGifHtml`, `takePhoto` and `passDecPlaceholder` where unused.

- [ ] **Step 4: Run the tests.**

Run: `sh tests/run_all.sh`. Expected: all pass.

- [ ] **Step 5: Browser check.** Serve the app, then:
1. Open `#/` and tap Receive. The scanner opens; headless Chrome has no camera, so the error path applies: it must land on `#/receive/files` with the notice.
2. Choose `test-data/goldens/hello.gif` through the file input. Expected: an automatic decode, then `#/receive/done` with a text or file result.
3. Test the Back gesture: with the scanner open, `history.back()` closes it and lands on `#/`.

- [ ] **Step 6: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/test_page_logic.js web-app/tests/page_harness.js
git commit -m "feat(web): Receive opens the camera directly; files screen and camera fallback"
```

---

### Task 8: Unlock and result screens — Save, Open, Share, Copy

**Files:**
- Modify: `web-app/index.html`: the `/receive/unlock` and `/receive/done` screens, plus new `canOpen`, `mimeFor`, `openFile`, `shareFile`, `unlock`, `discardAndRescan`, and the Copied chip.
- Modify: `web-app/i18n.js`
- Test: `web-app/tests/test_page_logic.js`

**Interfaces:**
- Produces: `mimeFor(name) → string`, `canOpen(name) → boolean`, `openFile()`, `shareFile()`, `unlock()`, `discardAndRescan()`.
- Consumes: `fileResult`, `textResult`, `showFileResult`, `showUnlock` (Task 3); `canShareFiles`, `shareBlob` (Task 5); `startDecode`, `resetPhotoSession`.

- [ ] **Step 1: Write the failing tests:**

```js
test('Open is offered only for types a browser renders safely — never svg or html', () => {
  const { ctx } = freshPage();
  for (const n of ['a.pdf', 'b.PNG', 'c.jpeg', 'd.txt', 'e.mp4', 'f.json']) assertEq(ctx.canOpen(n), true, n);
  for (const n of ['x.svg', 'y.html', 'z.htm', 'w.xhtml', 'noext', 'v.exe', 'u.zip']) assertEq(ctx.canOpen(n), false, n);
  assertEq(ctx.mimeFor('report.PDF'), 'application/pdf', 'case-insensitive');
  assertEq(ctx.mimeFor('a.bin'), 'application/octet-stream', 'fallback');
});

test('file result screen: Open hidden for an unsafe type, Share hidden without canShare', async () => {
  const { ctx, elements } = freshPage();
  ctx.showFileResult('evil.svg', new Uint8Array(3));
  assertEq(elements['openFileBtn'].hidden, true, 'svg cannot be opened');
  assertEq(elements['shareFileBtn'].hidden, true, 'no canShare in harness');
  assertEq(elements['fileOutName'].textContent, 'evil.svg', 'name via textContent');
});

test('Unlock reads the passphrase field and retries; Discard resets and rescans', async () => {
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 12, seq: 0, total: 1, encrypted: true });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});
  assertEq(ctx.location.hash, '#/receive/unlock', 'asked for the passphrase');
  elements['passDec'].value = 'pw';
  await ctx.unlock();
  assertEq(calls.fileResults, 1, 'unlocked');
  ctx.discardAndRescan();
  assertEq(ctx.location.hash, '#/receive', 'rescanning');
  assertEq(ctx.routeState().hasResult, false, 'result cleared');
});
```

Add `'mimeFor', 'canOpen', 'openFile', 'shareFile', 'unlock', 'discardAndRescan'` to `REQUIRED_GLOBALS`.

- [ ] **Step 2: Run them to verify they fail.**

Run: `node tests/test_page_logic.js`. Expected: FAIL (`canOpen` missing).

- [ ] **Step 3: Implement.**

```js
// ── Received file: Open / Share (spec §3) ─────────────────
// Open uses a blob: URL in a new tab. A blob URL inherits THIS page's origin,
// so a received .svg/.html with script would run as us — those are never
// openable. Only inert, browser-rendered types are listed.
const OPENABLE = { pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif',
  webp: 'image/webp', txt: 'text/plain', md: 'text/plain', csv: 'text/csv', json: 'application/json',
  mp3: 'audio/mpeg', mp4: 'video/mp4', webm: 'video/webm' };
const SHARE_TYPES = Object.assign({ zip: 'application/zip', doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }, OPENABLE);

function extOf(name) { const m = /\.([A-Za-z0-9]+)$/.exec(name || ''); return m ? m[1].toLowerCase() : ''; }
function mimeFor(name) { return SHARE_TYPES[extOf(name)] || 'application/octet-stream'; }
function canOpen(name) { return extOf(name) in OPENABLE; }

function openFile() {
  if (!fileResult || !canOpen(fileResult.name)) return;
  const url = URL.createObjectURL(new Blob([fileResult.bytes], { type: OPENABLE[extOf(fileResult.name)] }));
  window.open(url, '_blank', 'noopener');
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}
function shareFile() { if (fileResult) shareBlob(new Blob([fileResult.bytes]), fileResult.name, mimeFor(fileResult.name)); }

async function unlock() { clearError('dec'); await startDecode(); }   // startDecode retries a GIF or a complete session
function discardAndRescan() { resetPhotoSession(); decFile = null; navigate('#/receive', { replace: true }); }
```

In `showFileResult` (Task 3), add:

```js
document.getElementById('fileOutMeta').textContent = [fmtBytes(bytes.length), extOf(name).toUpperCase()].filter(Boolean).join(' · ');
document.getElementById('openFileBtn').hidden = !canOpen(name);
document.getElementById('shareFileBtn').hidden = !canShareFiles(mimeFor(name));
```

`copyText`: on success, show `#copiedChip` for 2 s (`hidden=false`, then `setTimeout(… hidden=true, 2000)`) in addition to the existing log line.

Markup: the two screens, per drafts `190085c7` (unlock), `e462f66b` (file, fixing its back button and link placement) and `a832262c` (text). Move `#textOut`/`#textOutBody`/`#fileOut`/`#fileOutName`/`#fileOutMeta`/`#saveFileBtn`/`#unlockError`/`#passDec` here and delete their Task-3 placeholders:

```html
<section class="screen" data-route="/receive/unlock" hidden>
  <header class="topbar-sub"><a class="icon-btn back" href="#/" aria-label="Back"><svg class="i" aria-hidden="true"><use href="#i-arrow-left"/></svg></a><h1 data-i18n="receiveTitle">Receive</h1></header>
  <div class="card center">
    <span class="badge-icon"><svg class="i" aria-hidden="true"><use href="#i-lock"/></svg></span>
    <h2 class="screen-heading" data-i18n="unlockTitle">This file is protected</h2>
    <p class="field-hint" data-i18n="unlockSub">All frames are in. Enter the passphrase to open it — no need to scan again.</p>
    <div class="pass-field"><input type="password" id="passDec" autocomplete="off" data-i18n-placeholder="passphrase" onkeydown="if(event.key==='Enter')unlock()">
      <button type="button" class="icon-btn" onclick="togglePass('passDec', this)" aria-label="Show"><svg class="i" aria-hidden="true"><use href="#i-eye"/></svg></button></div>
    <div class="form-error" id="unlockError" role="alert" hidden></div>
  </div>
  <button type="button" class="btn btn-primary" style="margin-top:16px" onclick="unlock()"><svg class="i" aria-hidden="true"><use href="#i-lock"/></svg><span data-i18n="unlockBtn">Unlock</span></button>
  <p class="center"><button type="button" class="btn-link" onclick="discardAndRescan()"><svg class="i" aria-hidden="true"><use href="#i-rotate-ccw"/></svg><span data-i18n="discardScan">Discard and scan again</span></button></p>
</section>

<section class="screen" data-route="/receive/done" hidden>
  <header class="topbar-sub"><a class="icon-btn back" href="#/" aria-label="Back"><svg class="i" aria-hidden="true"><use href="#i-arrow-left"/></svg></a><h1 data-i18n="receivedTitle">Received</h1></header>
  <div id="fileOut" style="display:none">
    <div class="center"><span class="badge-icon big"><svg class="i" aria-hidden="true"><use href="#i-circle-check"/></svg></span>
      <h2 class="screen-heading" data-i18n="fileReceived">File received</h2></div>
    <div class="card file-card"><svg class="i" aria-hidden="true"><use href="#i-file-text"/></svg><div><div id="fileOutName" class="file-name"></div><div id="fileOutMeta" class="meta"></div></div></div>
    <button type="button" class="btn btn-primary" id="saveFileBtn" onclick="saveFile()"><svg class="i" aria-hidden="true"><use href="#i-download"/></svg><span data-i18n="saveToDevice">Save to device</span></button>
    <div class="btn-row" style="margin-top:10px">
      <button type="button" class="btn" id="openFileBtn" onclick="openFile()" hidden><svg class="i" aria-hidden="true"><use href="#i-external-link"/></svg><span data-i18n="openFile">Open</span></button>
      <button type="button" class="btn" id="shareFileBtn" onclick="shareFile()" hidden><svg class="i" aria-hidden="true"><use href="#i-share-2"/></svg><span data-i18n="share">Share</span></button>
    </div>
  </div>
  <div id="textOut" style="display:none">
    <div class="center"><span class="badge-icon"><svg class="i" aria-hidden="true"><use href="#i-check"/></svg></span>
      <h2 class="screen-heading" data-i18n="messageReceived">Message received</h2></div>
    <pre id="textOutBody" class="text-out card"></pre>
    <button type="button" class="btn btn-primary" onclick="copyText()"><svg class="i" aria-hidden="true"><use href="#i-copy"/></svg><span data-i18n="copyText">Copy</span></button>
    <span class="chip copied" id="copiedChip" hidden><svg class="i" aria-hidden="true"><use href="#i-check"/></svg><span data-i18n="copied">Copied</span></span>
    <button type="button" class="btn btn-secondary" style="margin-top:10px" onclick="saveText()"><svg class="i" aria-hidden="true"><use href="#i-download"/></svg><span data-i18n="saveTxt">Save as .txt</span></button>
  </div>
  <p class="center"><a class="btn-link" href="#/receive"><svg class="i" aria-hidden="true"><use href="#i-scan-line"/></svg><span data-i18n="receiveAnother">Receive another</span></a></p>
</section>
```

The "Receive another" link must reset first. Give the link `onclick="resetPhotoSession()"` (the hash change follows); `resetPhotoSession` already clears both results.

The existing test 'received text is left-aligned (.text-out overrides .output-section centering)' asserts a CSS rule. Keep `.text-out { text-align:left; white-space:pre-wrap; word-break:break-word; }`, and update that test's selector expectations only if it names `.output-section`. The text card must be left-aligned.

CSS:
- `.badge-icon` is a 64 px circle with `var(--accent-l)` background and `var(--accent-fg)` icon; `.big` is 80 px.
- `.screen-heading` is serif 26 px.
- `.file-card` is a flex row, gap 12, margin 16px 0.
- `.file-name` is weight 500 with `word-break:break-all`.
- `.copied` is `display:inline-flex; margin:8px auto 0`.

**i18n** (×5):

```js
unlockTitle: 'This file is protected', unlockSub: 'All frames are in. Enter the passphrase to open it — no need to scan again.',
unlockBtn: 'Unlock', discardScan: 'Discard and scan again',
receivedTitle: 'Received', fileReceived: 'File received', messageReceived: 'Message received',
openFile: 'Open', share: 'Share', copied: 'Copied', receiveAnother: 'Receive another',
```

Delete `textReceivedTitle` and `savedDownloads` if unused.

- [ ] **Step 4: Run the tests.**

Run: `sh tests/run_all.sh`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/test_page_logic.js web-app/tests/page_harness.js
git commit -m "feat(web): unlock screen and file/text result screens with Save, Open, Share, Copy"
```

---

### Task 9: How it works, the live hub demo, i18n cleanup

**Files:**
- Modify: `web-app/index.html`: the `/how` screen (rebuilt from About), plus `renderDemo` and its call.
- Modify: `web-app/i18n.js`: new keys, and **all** orphaned keys deleted.
- Test: `web-app/tests/test_page_logic.js`, `web-app/tests/test_i18n.js`

**Interfaces:**
- Produces: `renderDemo() → Promise<void>`.
- Consumes: `encodeToGif` (Task 5).

- [ ] **Step 1: Write the failing tests:**

```js
test('hub demo encodes the deployed icon; a fetch failure falls back to a text frame, never an error', async () => {
  const { ctx, elements } = freshPage();
  const seen = [];
  ctx.encodeToGif = async (input) => { seen.push(input.name); return { blob: {}, state: {}, stats: {} }; };
  ctx.fetch = async () => ({ ok: true, arrayBuffer: async () => new ArrayBuffer(8) });
  await ctx.renderDemo();
  assertEq(seen[0], 'cimbar.png', 'icon payload');
  assertEq(elements['demoGif'].src, 'blob://x', 'image set');
  ctx.fetch = async () => { throw new Error('offline'); };
  await ctx.renderDemo();
  assertEq(seen[1], 'hello.txt', 'fallback payload');
});
```

Add `'renderDemo'` to `REQUIRED_GLOBALS`. The harness has no `fetch` by default, so the load-time call must no-op.

Also add to `test_i18n.js`:

```js
test('no orphaned keys: every English key is used by index.html or by i18n.js itself', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const self = new Set(['title']);   // apply() sets document.title from t('title')
  const orphans = Object.keys(en).filter((k) => !self.has(k) && !html.includes(`'${k}'`) && !html.includes(`"${k}"`));
  assertEq(orphans.join(','), '', 'unused keys (delete them from all five tables)');
});
```

- [ ] **Step 2: Run them to verify they fail.**

Run: `node tests/test_page_logic.js; node tests/test_i18n.js`
Expected: FAIL. `renderDemo` is missing, and orphans are listed, e.g. `tagline,badgeClientSide,…`.

- [ ] **Step 3: Implement the demo.**

```js
// ── Hub demo: a real, scannable CimBar of the app icon (spec §2) ──
// icon-512.png is already deployed and already compressed, so deflate skips it
// and it spans several frames + a repair frame: a genuinely animated loop.
// Scanning it from another phone yields cimbar.png.
async function renderDemo() {
  if (typeof fetch !== 'function') return;
  const img = document.getElementById('demoGif');
  let input;
  try {
    const res = await fetch('icon-512.png');
    if (!res.ok) throw new Error('HTTP ' + res.status);
    input = { name: 'cimbar.png', bytes: new Uint8Array(await res.arrayBuffer()) };
  } catch (_) {
    input = { name: 'hello.txt', bytes: new TextEncoder().encode('Hello from CimBar') };
  }
  try {
    const { blob } = await encodeToGif(input, { pass: '', frameDelay: 20 });
    img.src = URL.createObjectURL(blob);
    const how = document.getElementById('howDemo');
    if (how) how.src = img.src;
  } catch (e) { console.error(e); }   // the tile stays an empty black square: never an error UI
}
```

At the end of the script, after `renderRoute();`, add `setTimeout(renderDemo, 0);`. That runs after first paint, so it doesn't delay the hub.

- [ ] **Step 4: Rebuild the How-it-works screen** from draft `efcf9bf1` (replace its tinted thumbnail with `<img id="howDemo">`, whose `src` `renderDemo` also sets). The content:
- three step cards (`.step-card`, serif muted number `01/02/03`, title, text);
- an "Under the hood" `<details class="disclosure">`, closed by default, holding a 2-column grid of the six existing technical cards. Reuse the `about1Title…about6Text` keys and the `aboutIntroHtml`, `capacityHtml` and `paletteHtml` texts inside the disclosure;
- the version line: keep `<span id="appVersion" data-version="0.12.1">v0.12.1</span> · build <span id="buildSha">dev</span>` **verbatim**, with the existing "language-neutral on purpose" comment.

**i18n** (×5):

```js
howStep1: 'Your file becomes an animated code, optionally locked with a passphrase.',
howStep2: 'Show it full screen, or share the GIF.',
howStep3: 'The other phone reads the frames in any order; any N of them rebuild the file.',
underHood: 'Under the hood',
```

**Edit `aboutIntroHtml` in all five languages:** its last sentence mentions "the Encode tab's Text mode". Change it to "Send's Text mode".

- [ ] **Step 5: Delete every orphan the new test lists, from all five tables.** Then make sure the deletion broke nothing:

```bash
node tests/test_i18n.js && grep -n "data-i18n" web-app/index.html | wc -l
```

The second count must be ≥ 40; `test_i18n` requires it.

- [ ] **Step 6: Run the tests.**

Run: `sh tests/run_all.sh`. Expected: all pass.

- [ ] **Step 7: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/test_page_logic.js web-app/tests/test_i18n.js
git commit -m "feat(web): How it works screen, live scannable hub demo, orphaned strings removed"
```

---

### Task 10: Static markup guards, e2e update, docs

**Files:**
- Create: `web-app/tests/test_markup.js`
- Modify: `web-app/tests/run_all.sh`, `web-app/tools/e2e_live_scan.js`, `CLAUDE.md`, `CHANGELOG.md`

- [ ] **Step 1: Write `tests/test_markup.js`.** It takes an optional path, so it can be pointed at the old page:

```js
// Static guards over index.html for things no behavioural test can see.
// Usage: node tests/test_markup.js [path/to/index.html]
'use strict';
const fs = require('fs');
const path = require('path');
const file = process.argv[2] || path.join(__dirname, '..', 'index.html');
const html = fs.readFileSync(file, 'utf8');
const inline = (html.match(/<script>([\s\S]*?)<\/script>/) || [, ''])[1];
let passed = 0, failed = 0;
const test = (name, fn) => { try { fn(); passed++; console.log(`  PASS  ${name}`); } catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); } };
const assert = (c, m) => { if (!c) throw new Error(m); };

console.log(`\ntest_markup.js (${path.basename(file)})`);
test('no external scripts (no Tailwind/Iconify leaking in from design drafts)', () => {
  const ext = [...html.matchAll(/<script[^>]+src="(https?:)?\/\/[^"]+"/g)].map((m) => m[0]);
  assert(ext.length === 0, ext.join(' '));
});
test('every <use href="#i-…"> has a sprite <symbol>', () => {
  const used = new Set([...html.matchAll(/<use href="#(i-[a-z0-9-]+)"/g)].map((m) => m[1]));
  const defined = new Set([...html.matchAll(/<symbol id="(i-[a-z0-9-]+)"/g)].map((m) => m[1]));
  assert(used.size >= 20, `expected the icon sprite in use, found ${used.size} icons`);
  const missing = [...used].filter((u) => !defined.has(u));
  assert(missing.length === 0, 'missing symbols: ' + missing.join(','));
});
test('a dark theme exists and redefines the core tokens', () => {
  const m = html.match(/@media \(prefers-color-scheme: dark\)\s*{\s*:root\s*{([^}]*)}/);
  assert(m, 'no dark :root block');
  for (const tok of ['--bg', '--surface', '--text', '--accent-fg', '--border']) assert(m[1].includes(tok + ':'), `dark theme lacks ${tok}`);
});
test('no alert() or confirm() in the page script', () => {
  assert(!/\b(alert|confirm)\(/.test(inline), 'native dialog call found');
});
test('no red primary action (btn-danger)', () => {
  assert(!html.includes('btn-danger'), 'btn-danger present');
});
test('every route has exactly one screen (except /receive, which is an overlay)', () => {
  for (const r of ['/', '/send', '/send/ready', '/receive/files', '/receive/unlock', '/receive/done', '/how']) {
    const n = html.split(`data-route="${r}"`).length - 1;
    assert(n === 1, `${r}: ${n} screens`);
  }
});
test('green text uses --accent-fg, never --accent, in color: declarations', () => {
  const bad = [...html.matchAll(/(?<![-\w])color\s*:\s*var\(--accent\)/g)];
  assert(bad.length === 0, `${bad.length} color:var(--accent) (fails AA in dark mode — use --accent-fg)`);
});
console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

- [ ] **Step 2: Verify the guards bite on the old page.**

```bash
cd ~/cimbar && git show master:web-app/index.html > /tmp/index-master.html
node web-app/tests/test_markup.js /tmp/index-master.html
```

Expected: FAIL on the sprite, the dark theme, `alert/confirm`, `btn-danger`, the routes and `--accent` colour. At least 6 failures. A guard that *passes* on master is too loose: fix its regex before going on.

- [ ] **Step 3: Run it on the new page.**

Run: `node web-app/tests/test_markup.js`. Expected: 7/7 PASS. Then add it to `run_all.sh`:

```sh
echo ""; echo "--- Markup guards (no CDN, sprite, dark theme, no native dialogs) ---"
node tests/test_markup.js
```

- [ ] **Step 4: Update the e2e.** In `tools/e2e_live_scan.js`, replace the block from `await page.goto(url);` through `const d = await download;` with:

```js
    await page.goto(url.replace('index.html?debug=1', 'index.html?debug=1#/receive'));   // Receive opens the camera
    if (golden.passphrase) {
      await page.waitForURL(/#\/receive\/unlock$/, { timeout: 120000 });
      await page.fill('#passDec', golden.passphrase);
      await page.click('button[onclick="unlock()"]');
    }
    await page.waitForURL(/#\/receive\/done$/, { timeout: 120000 });
    const download = page.waitForEvent('download', { timeout: 30000 });
    await page.click('#saveFileBtn');
    const d = await download;
```

Run it locally against an unencrypted and an encrypted golden:

```bash
NODE_PATH=~/banana_split/node_modules node web-app/tools/e2e_live_scan.js lorem_coded
NODE_PATH=~/banana_split/node_modules node web-app/tools/e2e_live_scan.js lorem_coded_enc
```

Expected: `download … MATCHES the golden` for both. If Playwright isn't available there, say so in the PR. Don't claim it ran.

- [ ] **Step 5: Docs.**
- In `CLAUDE.md`'s Web App section, rewrite these:
  - the `index.html` module bullet: "all UI (hash-routed hub: Send / Receive / How it works, Present and scanner overlays, language sheet) …";
  - the "A staged GIF and a live photo session … Decode button dispatches" paragraph: choosing a GIF decodes immediately, and the unlock screen's **Unlock** (`unlock()` → `startDecode()`) is the retry route for a missing or wrong passphrase;
  - the live-scan sentence "the passphrase field and the Decode-button retry are visible" → "a completed encrypted scan routes to `#/receive/unlock`".

  Add a short **Routing** paragraph: the `resolveRoute` guards, why routing is hash-based (static S3 deploy), and that overlays push a history entry so Back closes them.
- In `CHANGELOG.md` under `## [Unreleased]`, add:

```markdown
### Changed
- **The web app is redesigned for phones.** A Send / Receive hub replaces the Encode / Decode / About tabs. The hub has a live, scannable demo code, and Receive opens the camera directly. The app follows the system dark mode. Present keeps the screen awake (Screen Wake Lock) and closes with the Back gesture. Phones get Share GIF / Share for received files. An encrypted scan asks for the passphrase afterwards, so nothing is re-scanned. Browser `alert`/`confirm` dialogs are gone.
```

- [ ] **Step 6: Run the full suite.**

Run: `sh tests/run_all.sh`. Expected: all pass.

- [ ] **Step 7: Commit.**

```bash
git add web-app/tests/test_markup.js web-app/tests/run_all.sh web-app/tools/e2e_live_scan.js CLAUDE.md CHANGELOG.md
git commit -m "test(web): static markup guards; e2e through #/receive; docs for the hub redesign"
```

---

### Task 11: Browser verification at phone widths (measure, then fix)

**Files:**
- Modify: `web-app/index.html` (only the fixes the measurements demand)
- Create (scratch, not committed): a probe page under the Windows temp directory

- [ ] **Step 1: The screenshot harness.** Headless Chrome on Windows clamps the window to about 500 px wide, so render each route inside an iframe of the target width.

```bash
W=/mnt/c/Users/EvgenyMezin/AppData/Local/Temp/cimbar-verify; rm -rf $W; mkdir -p $W
cp -r ~/cimbar/web-app/* $W/
cd $W && python3 -m http.server 8765 >/dev/null 2>&1 &   # served: fetch(icon-512.png) needs http
```

For each `lang ∈ {en, ru, ka}`, scheme ∈ {light, dark} and width ∈ {360, 390}, write `wrap-<lang>-<scheme>-<w>.html` with one iframe per route:

```html
<html><body style="margin:0;display:flex;gap:8px;background:#666">
<iframe style="width:360px;height:900px;border:0" src="http://localhost:8765/index.html#/"></iframe>
<!-- … one per route: #/send #/send/ready(redirects) #/receive/files #/receive/unlock(redirects) #/how -->
</body></html>
```

**Setting the language:** add `?lang=ru` to each iframe URL. If the page doesn't read `?lang`, set `localStorage['cimbar.lang']` from a tiny same-origin `set-lang.html` first.

**Setting the scheme:** run Chrome with `--force-dark-mode` for dark and `--blink-settings=forceDarkModeEnabled=false` for light. If those don't switch `prefers-color-scheme`, use `--enable-features=WebContentsForceDark:inversion_method/cielab_based` only as a last resort, and say so.

```bash
"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=2700,950 --virtual-time-budget=8000 \
  --screenshot='C:\Users\EvgenyMezin\AppData\Local\Temp\cimbar-verify\shot-ru-light-360.png' \
  'http://localhost:8765/wrap-ru-light-360.html'
```

Look at every screenshot alongside its draft.

- [ ] **Step 2: Measured probe.** Inject this probe into a copy of `index.html`, at the end of `<body>`, after the inline script:

```html
<pre id="PROBE"></pre>
<script>
setTimeout(() => {
  const out = [];
  for (const r of ['#/', '#/send', '#/receive/files', '#/how']) {
    location.hash = r; renderRoute();
    const scr = document.querySelector('.screen:not([hidden])');
    if (document.documentElement.scrollWidth > innerWidth) out.push(`${r} OVERFLOW page ${document.documentElement.scrollWidth}>${innerWidth}`);
    scr.querySelectorAll('button, a, .chip, h1, .choice-title, .seg-btn').forEach((el) => {
      if (el.scrollWidth > el.clientWidth + 1) out.push(`${r} CLIP ${el.tagName}.${el.className} "${el.textContent.trim().slice(0, 30)}" ${el.scrollWidth}>${el.clientWidth}`);
      const b = el.getBoundingClientRect();
      if ((el.tagName === 'BUTTON' || el.classList.contains('btn') || el.classList.contains('icon-btn')) && b.height > 0 && b.height < 40)
        out.push(`${r} SMALL ${el.className} ${Math.round(b.height)}px`);
    });
  }
  document.getElementById('PROBE').textContent = out.join('\n') || 'OK';
}, 1500);
</script>
```

Run it with `--dump-dom` inside a 360 px iframe for `ru` and `ka`, and read `#PROBE`. Expected: `OK`.

Icon buttons are visually 40 px with a 48 px hit area via `::after`, so the probe's threshold is 40.

- [ ] **Step 3: Contrast check.**

```bash
node -e '
const L=(h)=>{const c=[1,3,5].map(i=>parseInt(h.slice(i,i+2),16)/255).map(v=>v<=.03928?v/12.92:((v+.055)/1.055)**2.4);return .2126*c[0]+.7152*c[1]+.0722*c[2]};
const cr=(a,b)=>{const[x,y]=[L(a),L(b)].sort((p,q)=>q-p);return ((x+.05)/(y+.05)).toFixed(2)};
const pairs={light:[["#1a1714","#f5f3ef"],["#5c554e","#ffffff"],["#8a827a","#ffffff"],["#2d6a4f","#ffffff"],["#ffffff","#2d6a4f"],["#1b4332","#d8f0e5"],["#c0392b","#fde8e6"]],
 dark:[["#efe9e1","#171512"],["#bdb4a9","#211e1a"],["#8f877d","#211e1a"],["#7fc8a2","#211e1a"],["#ffffff","#2d6a4f"],["#cfeedd","#1d3a2c"],["#ef8a7e","#3a1f1b"]]};
for(const[k,v]of Object.entries(pairs))for(const[f,b]of v)console.log(k,f,"on",b,cr(f,b));'
```

Expected: body text pairs ≥ 4.5. `--text3` is used only for ≤ 12 px *decorative or metadata* text and needs ≥ 3.0. Any pair below its bar: adjust that token's value in **both** `:root` blocks and the spec table, then re-run.

- [ ] **Step 4: Fix what the measurements found, then re-run Steps 1–3 until clean.** Typical fixes:
- `white-space:nowrap` with `text-overflow:ellipsis` only on *metadata*, never on a button label;
- shorter translations, under the 1.4× rule;
- `flex-wrap` on `.btn-row` below 360 px.

- [ ] **Step 5: Run the full suite and commit.**

```bash
cd ~/cimbar/web-app && sh tests/run_all.sh
git add web-app/index.html web-app/i18n.js
git commit -m "fix(web): phone-width and contrast fixes from the browser verification pass"
```

(Skip the commit if nothing needed fixing, and say so.)

- [ ] **Step 6: Write down what remains unverified.** Put it in the PR description, copied from spec §4 "Hardware (owed)":
- Present on one phone and scan on another;
- Wake Lock through 2 minutes, including after a notification glance;
- Share GIF to Telegram;
- the camera-denied fallback on a real phone;
- iOS Safari.

None of these can run here. They're listed as not done, not as passed.
