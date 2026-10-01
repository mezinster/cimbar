# Text Transfer and Android/iOS Encoding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send text (and, from phones, files) as CimBar from the web app, Android and iOS, and show a received text message as text with Copy and Save.

**Architecture:** A text message is an ordinary v2.1 file container named `message-YYYYMMDD-HHMMSS.txt`; every receiver applies one shared rule (`isTextMessage`) after the existing decode, so the wire format does not change. The web app gains a `File | Text` encode toggle and a text result panel. The Flutter app gains a pure-Dart encoder in `lib/core/encode/` — a port of `cimbar.js`/`gif-encoder.js` proven byte- and pixel-identical against `test-data/goldens/` — plus a Send tab, a full-screen Present screen and Share GIF.

**Tech Stack:** Vanilla JS (no build), Node test scripts; Flutter 3.44.8 / Dart, Riverpod 2 `StateNotifier`, go_router, `image`, `pointycastle`, `share_plus`, new `wakelock_plus` + `screen_brightness`.

**Spec:** `docs/superpowers/specs/2026-10-01-text-transfer-and-mobile-encode-design.md` — read it alongside this plan.

## Global Constraints

- No frame-format change: header flag bits 3–7 stay 0; the container stays `[u32 nameLen][name][bytes]`.
- Text rule: name ends in `.txt` (ASCII case-insensitive) AND `bytes.length ≤ 1048576` AND bytes are strictly valid UTF-8; a leading BOM `EF BB BF` is allowed and not shown; 0 bytes is valid (empty text).
- Text message name: `message-YYYYMMDD-HHMMSS.txt`, local time, zero-padded.
- Sender stores text as UTF-8 exactly as typed: no BOM added, line endings untouched. Only a zero-length text is "empty" (whitespace-only text is sendable).
- Received text is shown as plain text only: web `textContent` (never `innerHTML`), Flutter plain `Text`/`SelectableText` with no linkify. Save writes the exact received bytes.
- Mobile caps, checked on the **encoded** frame count (after compression): send ≤ `CimbarSpec.codingMaxFrames` (4096) source frames; Share GIF ≤ 500 source frames. Over a cap the action is refused with a translated hint (the pre-encode estimate is an upper bound and shown as such).
- Frame delay options 100 / 200 / 400 ms, default 200 ms (`CimbarSpec.delayOptionsMs` / `defaultDelayMs`).
- Web: no new page `<script>` (no deploy-list change); `cimbar.js` code stays inside its IIFE (shared global scope).
- Every new user-visible string: a key in all five `web-app/i18n.js` tables and all five `app/lib/l10n/app_*.arb` files.
- Files under `app/lib/core/encode/` and `app/lib/core/format/text_message.dart` import no Flutter package (they run in isolates and `dart run` tools).
- Full-screen Flutter routes are pushed with `Navigator.of(context, rootNavigator: true)`.
- The APK keeps `CAMERA` as its only permission (`test/android_manifest_test.dart`); no dependency may pull Google Play Services/Firebase/ML Kit. `app/pubspec.lock` is regenerated with Flutter 3.44.8 and committed.
- Work on branch `feat/text-transfer`. Web tests: `cd web-app && sh tests/run_all.sh`. Flutter tests: `cd app && sh tests/run_all.sh` (never bare `flutter test` for the full suite; a single file is fine: `flutter test test/path_test.dart`).

## Review Focus

1. **A received text with a BOM or CRLF line endings** — Copy/display drop the BOM, Save writes the bytes byte-for-byte (BOM and `\r\n` kept). Pinned in Task 3 (web) and Task 8 (Flutter).
2. **Switching the web Encode tab between File and Text after filling both** — only the visible mode is encoded. Pinned in Task 2.
3. **A second decode after a text result** (new GIF staged, photo session reset) — the old text panel disappears. Pinned in Task 3.
4. **Leaving Present by back gesture, error or app backgrounding** — wakelock released and brightness restored on every path; playback pauses in background. Pinned in Task 10.
5. **A huge received text (≈1 MiB, one long line)** — the result card stays bounded and scrollable instead of overflowing. Pinned in Task 8.

---

### Task 1: Shared text-message rule (fixture, web, Dart)

**Files:**
- Create: `test-data/text-message.json`
- Modify: `web-app/cimbar.js` (after `stripLengthPrefix`, and the `API` object)
- Create: `web-app/tests/test_text_message.js`
- Modify: `web-app/tests/run_all.sh`
- Create: `app/lib/core/format/text_message.dart`
- Create: `app/test/core/format/text_message_test.dart`

**Interfaces:**
- Produces (web, on `window.Cimbar` / `module.exports`): `isTextMessage(name: string, bytes: Uint8Array) → boolean`, `decodeTextMessage(name, bytes) → string | null` (BOM stripped; null when not a text message), `textMessageName(date: Date) → string`, `TEXT_MAX_BYTES = 1048576`.
- Produces (Dart): `class TextMessage { static const int maxBytes = 1048576; static String? decode(String name, Uint8List bytes); static bool isTextMessage(String name, Uint8List bytes); static String fileName(DateTime now); }`

- [ ] **Step 1: Write the shared fixture** `test-data/text-message.json`. Bytes are hex; when `repeat` is present the bytes are `hex` repeated `repeat` times.

```json
{
  "description": "Shared contract for isTextMessage (spec 2026-10-01 §3). Asserted by web-app/tests/test_text_message.js and app/test/core/format/text_message_test.dart. bytes = hex repeated `repeat` times (default 1). `text` is the expected decoded string when expected is true.",
  "cases": [
    { "name": "message-20261001-120000.txt", "hex": "48656c6c6f", "expected": true, "text": "Hello", "note": "plain ASCII" },
    { "name": "notes.TXT", "hex": "d09fd180d0b8d0b2d0b5d1820ae18392e18390e183a0e183a3e183ae20f09f9880", "expected": true, "text": "Привет\nგარუხ 😀", "note": "Cyrillic, Georgian, emoji; upper-case extension" },
    { "name": "bom.txt", "hex": "efbbbf41", "expected": true, "text": "A", "note": "leading BOM tolerated and not shown" },
    { "name": "crlf.txt", "hex": "610d0a62", "expected": true, "text": "a\r\nb", "note": "CRLF preserved" },
    { "name": "empty.txt", "hex": "", "expected": true, "text": "", "note": "empty text" },
    { "name": "notes.txt.bin", "hex": "41", "expected": false, "note": ".txt not the final extension" },
    { "name": "notes", "hex": "41", "expected": false, "note": "no extension" },
    { "name": "report.pdf", "hex": "41", "expected": false, "note": "other extension" },
    { "name": "bad.txt", "hex": "41c328", "expected": false, "note": "invalid continuation byte" },
    { "name": "overlong.txt", "hex": "c0af", "expected": false, "note": "overlong encoding" },
    { "name": "surrogate.txt", "hex": "eda080", "expected": false, "note": "encoded UTF-16 surrogate" },
    { "name": "trunc.txt", "hex": "41e282", "expected": false, "note": "truncated multi-byte tail" },
    { "name": "big.txt", "hex": "41", "repeat": 1048576, "expected": true, "note": "exactly 1 MiB" },
    { "name": "toobig.txt", "hex": "41", "repeat": 1048577, "expected": false, "note": "1 MiB + 1" }
  ]
}
```

(The second case's hex was produced with `node -e "console.log(Buffer.from('Привет\nგარუხ 😀').toString('hex'))"`; regenerate it the same way if you edit the text.)

- [ ] **Step 2: Write the failing web test** `web-app/tests/test_text_message.js`:

```js
'use strict';
const fs = require('fs');
const path = require('path');
const C = require('../cimbar.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log(`  PASS  ${name}`); }
  catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); }
}
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }

function caseBytes(c) {
  const one = Buffer.from(c.hex, 'hex');
  const n = c.repeat || 1;
  const out = new Uint8Array(one.length * n);
  for (let i = 0; i < n; i++) out.set(one, i * one.length);
  return out;
}

console.log('\ntest_text_message.js');
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'test-data', 'text-message.json'), 'utf8'));

for (const c of fixture.cases) {
  test(`fixture: ${c.name} (${c.note})`, () => {
    const bytes = caseBytes(c);
    assertEq(C.isTextMessage(c.name, bytes), c.expected, 'isTextMessage');
    const s = C.decodeTextMessage(c.name, bytes);
    if (c.expected) { if (c.text !== undefined) assertEq(s, c.text, 'decoded text'); }
    else assertEq(s, null, 'decodeTextMessage on a non-text payload');
  });
}

test('textMessageName formats local time, zero-padded', () => {
  assertEq(C.textMessageName(new Date(2026, 0, 2, 3, 4, 5)), 'message-20260102-030405.txt', 'name');
});

test('the hello golden (hello.txt) is a text message', () => {
  const side = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'test-data', 'goldens', 'hello.json'), 'utf8'));
  const bytes = new Uint8Array(Buffer.from(side.fileBytesBase64, 'base64'));
  assertEq(C.decodeTextMessage(side.fileName, bytes), 'Hello, CimBar v2!\n', 'decoded');
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
```

- [ ] **Step 3: Run it — expect failure.** `cd web-app && node tests/test_text_message.js` → FAIL (`C.isTextMessage is not a function`).

- [ ] **Step 4: Implement in `web-app/cimbar.js`**, directly after `stripLengthPrefix` (inside the IIFE):

```js
// ── Text messages (spec 2026-10-01 §3) ──────────────────────────────────
// A text message is an ordinary container whose name ends in .txt and whose
// bytes are strict UTF-8 of at most TEXT_MAX_BYTES. Nothing on the wire marks
// it: older receivers simply get a .txt file.
const TEXT_MAX_BYTES = 1048576;

function decodeTextMessage(name, bytes) {
  if (!/\.txt$/i.test(name) || bytes.length > TEXT_MAX_BYTES) return null;
  try {
    // fatal: rejects overlong forms, surrogates and truncated tails;
    // the default ignoreBOM=false drops a leading BOM.
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch (e) {
    return null;
  }
}

function isTextMessage(name, bytes) { return decodeTextMessage(name, bytes) !== null; }

function textMessageName(date) {
  const p = (n) => String(n).padStart(2, '0');
  return `message-${date.getFullYear()}${p(date.getMonth() + 1)}${p(date.getDate())}-` +
    `${p(date.getHours())}${p(date.getMinutes())}${p(date.getSeconds())}.txt`;
}
```

and extend the `API` object's container line to:

```js
  buildPayload, parsePayload, withLengthPrefix, stripLengthPrefix,
  isTextMessage, decodeTextMessage, textMessageName, TEXT_MAX_BYTES,
```

- [ ] **Step 5: Run it — expect pass.** `node tests/test_text_message.js` → all PASS. Then `node tests/test_browser_load.js` → PASS (no new globals leaked).

- [ ] **Step 6: Register in the runner.** In `web-app/tests/run_all.sh`, after the "Goldens" block add:

```sh
echo ""; echo "--- Text-message rule (shared fixture) ---"
node tests/test_text_message.js
```

- [ ] **Step 7: Write the failing Dart test** `app/test/core/format/text_message_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/text_message.dart';

String repoPath(String rel) => '../$rel';

Uint8List caseBytes(Map<String, dynamic> c) {
  final hex = c['hex'] as String;
  final one = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < one.length; i++) {
    one[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  final n = (c['repeat'] as int?) ?? 1;
  final out = Uint8List(one.length * n);
  for (var i = 0; i < n; i++) {
    out.setRange(i * one.length, (i + 1) * one.length, one);
  }
  return out;
}

void main() {
  final fixture = jsonDecode(File(repoPath('test-data/text-message.json')).readAsStringSync()) as Map<String, dynamic>;
  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test('fixture: ${c['name']} (${c['note']})', () {
      final bytes = caseBytes(c);
      expect(TextMessage.isTextMessage(c['name'] as String, bytes), c['expected']);
      final s = TextMessage.decode(c['name'] as String, bytes);
      if (c['expected'] as bool) {
        if (c['text'] != null) expect(s, c['text']);
      } else {
        expect(s, isNull);
      }
    });
  }

  test('fileName formats local time, zero-padded', () {
    expect(TextMessage.fileName(DateTime(2026, 1, 2, 3, 4, 5)), 'message-20260102-030405.txt');
  });
}
```

- [ ] **Step 8: Run it — expect failure.** `cd app && flutter test test/core/format/text_message_test.dart` → compile error (missing file).

- [ ] **Step 9: Implement** `app/lib/core/format/text_message.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

/// The text-message convention (spec 2026-10-01 §3), shared with
/// `isTextMessage`/`decodeTextMessage`/`textMessageName` in web-app/cimbar.js
/// and pinned by test-data/text-message.json: an ordinary container whose
/// name ends in .txt and whose bytes are strict UTF-8 of at most [maxBytes].
class TextMessage {
  TextMessage._();

  static const int maxBytes = 1048576;

  /// The text (leading BOM dropped), or null when this is not a text message.
  static String? decode(String name, Uint8List bytes) {
    if (!name.toLowerCase().endsWith('.txt') || bytes.length > maxBytes) return null;
    final String s;
    try {
      // Dart's strict decoder rejects overlong forms, surrogates and
      // truncated tails exactly like TextDecoder(fatal: true), and keeps a BOM.
      s = utf8.decode(bytes);
    } on FormatException {
      return null;
    }
    return s.startsWith('﻿') ? s.substring(1) : s;
  }

  static bool isTextMessage(String name, Uint8List bytes) => decode(name, bytes) != null;

  static String fileName(DateTime now) {
    String p(int n) => n.toString().padLeft(2, '0');
    return 'message-${now.year}${p(now.month)}${p(now.day)}-'
        '${p(now.hour)}${p(now.minute)}${p(now.second)}.txt';
  }
}
```

- [ ] **Step 10: Run it — expect pass.** `flutter test test/core/format/text_message_test.dart` → all pass.

- [ ] **Step 11: Commit.**

```bash
git add test-data/text-message.json web-app/cimbar.js web-app/tests/test_text_message.js web-app/tests/run_all.sh app/lib/core/format/text_message.dart app/test/core/format/text_message_test.dart
git commit -m "feat: shared text-message rule (.txt + strict UTF-8 ≤ 1 MiB) for web and Dart"
```

---

### Task 2: Web — Text mode on the Encode tab

**Files:**
- Modify: `web-app/index.html` (Encode tab markup around the `fileToEncode` field; `<style>`; inline script: state next to `let encFile`, new functions, `startEncode`)
- Modify: `web-app/i18n.js` (all five tables)
- Modify: `web-app/tests/test_page_logic.js` (new tests; extend `REQUIRED_GLOBALS`)

**Interfaces:**
- Consumes: `Cimbar.textMessageName(date)`, `Cimbar.buildPayload`, `CimbarFormat.fileBytesPerFrame()`.
- Produces (top-level functions in the inline script): `setEncMode(mode: 'file'|'text')`, `updateTextInfo()`, `encodeInput() → Promise<{name: string, bytes: Uint8Array} | null>`.

- [ ] **Step 1: Write failing tests** — append to `web-app/tests/test_page_logic.js` (before the runner IIFE) and add `'setEncMode', 'encodeInput', 'updateTextInfo'` to `REQUIRED_GLOBALS`:

```js
test('text mode: encodeInput builds message-….txt from the textarea, as typed (CRLF kept)', async () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('text');
  elements['textEnc'].value = 'a\r\nб';
  const input = await ctx.encodeInput();
  assert(/^message-\d{8}-\d{6}\.txt$/.test(input.name), 'name: ' + input.name);
  assertEq(Buffer.from(input.bytes).toString('hex'), Buffer.from('a\r\nб', 'utf8').toString('hex'), 'UTF-8 bytes as typed, no BOM');
});

test('text mode: empty text disables Encode; whitespace-only does not', async () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('text');
  elements['textEnc'].value = '';
  ctx.updateTextInfo();
  assertEq(elements['encBtn'].disabled, true, 'empty text disables Encode');
  assertEq(await ctx.encodeInput(), null, 'no input for empty text');
  elements['textEnc'].value = '  \n';
  ctx.updateTextInfo();
  assertEq(elements['encBtn'].disabled, false, 'whitespace-only text is sendable');
});

test('switching modes encodes only the visible input — Review Focus 2', async () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('text');
  elements['textEnc'].value = 'hello';
  ctx.setEncMode('file');
  assertEq(elements['encBtn'].disabled, false, 'file mode never disabled by the text box');
  assertEq(await ctx.encodeInput(), null, 'file mode with no file staged → null, the typed text is NOT encoded');
  assertEq(elements['encTextField'].style.display, 'none', 'text field hidden in file mode');
  assertEq(elements['textEnc'].value, 'hello', 'switching keeps the typed text');
});

test('updateTextInfo shows bytes and an upper-bound frame count', () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('text');
  elements['textEnc'].value = 'x'.repeat(3000);
  ctx.updateTextInfo();
  assert(elements['textEncInfo'].textContent.includes('textEncInfo'), 'uses the textEncInfo key');
});
```

The harness `t` stub returns the key, so the last assertion only checks the key is used. The `freshPage()` sandbox has no `TextEncoder`; add `TextEncoder, TextDecoder,` to the `sandbox` object literal next to `Uint8Array`.

- [ ] **Step 2: Run — expect failure.** `cd web-app && node tests/test_page_logic.js` → FAIL (`expected the inline page script to define a top-level function 'setEncMode'`).

- [ ] **Step 3: Markup.** In the Encode tab replace the opening of the first `.field` (the `fileToEncode` one) so the file field gets an id and a sibling text field follows it:

```html
      <div class="seg" role="tablist">
        <button type="button" class="seg-btn active" id="encModeFile" onclick="setEncMode('file')" data-i18n="encModeFile">File</button>
        <button type="button" class="seg-btn" id="encModeText" onclick="setEncMode('text')" data-i18n="encModeText">Text</button>
      </div>

      <div class="field" id="encFileField">
        <label data-i18n="fileToEncode">File to encode</label>
        <!-- existing dropEnc drop zone and pillEnc pill, unchanged -->
      </div>

      <div class="field" id="encTextField" style="display:none">
        <label for="textEnc" data-i18n="textToEncode">Text to send</label>
        <textarea id="textEnc" rows="8" data-i18n-placeholder="textEncPlaceholder" placeholder="Type or paste text…" oninput="updateTextInfo()"></textarea>
        <div class="field-hint" id="textEncInfo"></div>
      </div>
```

Add to `<style>`:

```css
.seg { display: inline-flex; border: 1px solid var(--border2); border-radius: 8px; overflow: hidden; margin-bottom: 16px; }
.seg-btn { border: 0; background: var(--surface); color: var(--text2); padding: 8px 18px; font: inherit; cursor: pointer; }
.seg-btn.active { background: var(--surface2); color: var(--text); font-weight: 600; }
#textEnc { width: 100%; box-sizing: border-box; resize: vertical; font: 14px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; padding: 10px; border: 1px solid var(--border2); border-radius: 8px; background: var(--surface); color: var(--text); }
```

(Check `--text2` exists in `:root`; if not use `--text3`, which `dropHint` already uses.)

- [ ] **Step 4: Script.** Next to `let encFile = null, decFile = null;` add `let encMode = 'file';` and these functions after `onFileSelect`:

```js
function setEncMode(mode) {
  encMode = mode;
  document.getElementById('encFileField').style.display = mode === 'file' ? 'block' : 'none';
  document.getElementById('encTextField').style.display = mode === 'text' ? 'block' : 'none';
  document.getElementById('encModeFile').classList[mode === 'file' ? 'add' : 'remove']('active');
  document.getElementById('encModeText').classList[mode === 'text' ? 'add' : 'remove']('active');
  updateTextInfo();
}

// Byte count and an upper bound on frames (before compression; encryption adds 48 bytes).
function updateTextInfo() {
  const btn = document.getElementById('encBtn');
  if (encMode !== 'text') { btn.disabled = false; return; }
  const text = document.getElementById('textEnc').value;
  const bytes = new TextEncoder().encode(text).length;
  const framed = 4 + 4 + 27 + bytes + 48; // len prefix + name len + 'message-YYYYMMDD-HHMMSS.txt' + text + crypto
  const frames = Math.max(1, Math.ceil(framed / CimbarFormat.fileBytesPerFrame()));
  document.getElementById('textEncInfo').textContent = t('textEncInfo', { bytes: fmtBytes(bytes), frames });
  btn.disabled = text.length === 0;
}

// What the Encode button sends: the staged file, or the typed text as a text message.
async function encodeInput() {
  if (encMode === 'text') {
    const text = document.getElementById('textEnc').value;
    if (text.length === 0) return null;
    return { name: Cimbar.textMessageName(new Date()), bytes: new TextEncoder().encode(text) };
  }
  if (!encFile) return null;
  return { name: encFile.name, bytes: new Uint8Array(await encFile.arrayBuffer()) };
}
```

In `startEncode`, replace the `if (!encFile) …` guard and the file-reading lines:

```js
async function startEncode() {
  const input = await encodeInput();
  if (!input) { alert(t(encMode === 'text' ? 'enterTextFirst' : 'selectFileFirst')); return; }
  …
    // 1. Build payload
    log(t('readingFile'), 'info', 'logEnc');
    setProgress(5, t('reading'), 'progEncFill', 'progEncPct', 'progEncLabel');
    const payload = Cimbar.buildPayload(input.name, input.bytes);
    log(t('fileInfo', { name: input.name, size: fmtBytes(input.bytes.length) }), 'ok', 'logEnc');
```

and at the end of `startEncode` restore the button through `updateTextInfo()` after `btn.innerHTML = t('encodeBtn');` (so text mode with an empty box stays disabled).

- [ ] **Step 5: Strings.** Add to each `STRINGS` table in `web-app/i18n.js` (placeholders identical in every language):

| key | en | ru | uk | tr | ka |
|---|---|---|---|---|---|
| `encModeFile` | File | Файл | Файл | Dosya | ფაილი |
| `encModeText` | Text | Текст | Текст | Metin | ტექსტი |
| `textToEncode` | Text to send | Текст для отправки | Текст для надсилання | Gönderilecek metin | გასაგზავნი ტექსტი |
| `textEncPlaceholder` | Type or paste text… | Введите или вставьте текст… | Введіть або вставте текст… | Metin yazın veya yapıştırın… | აკრიფეთ ან ჩასვით ტექსტი… |
| `textEncInfo` | {bytes} · at most {frames} frame(s) | {bytes} · не более {frames} кадр(ов) | {bytes} · не більше {frames} кадр(ів) | {bytes} · en fazla {frames} kare | {bytes} · მაქს. {frames} კადრი |
| `enterTextFirst` | Type some text first. | Сначала введите текст. | Спочатку введіть текст. | Önce bir metin yazın. | ჯერ შეიყვანეთ ტექსტი. |

- [ ] **Step 6: Run — expect pass.** `node tests/test_page_logic.js && node tests/test_i18n.js && node tests/test_browser_load.js` → all PASS.

- [ ] **Step 7: Manual check.** `cd web-app && python3 -m http.server 8080`, open http://localhost:8080, Text mode, type a few lines, Encode → GIF appears; Present works; switch to File mode with no file → Encode alerts "select a file".

- [ ] **Step 8: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/test_page_logic.js
git commit -m "feat(web): Text mode on the Encode tab"
```

---

### Task 3: Web — show a received text message

**Files:**
- Modify: `web-app/index.html` (Decode tab markup after `#progDec`; inline script: `finishDecode`, new `showTextResult`/`hideTextResult`/`copyText`/`saveText`, calls in `handleDecFile`/`resetPhotoSession`/`newPhotoSession`)
- Modify: `web-app/i18n.js`
- Modify: `web-app/tests/test_page_logic.js`

**Interfaces:**
- Consumes: `Cimbar.decodeTextMessage(name, bytes) → string|null` (Task 1).
- Produces: top-level `showTextResult(name, bytes, text)`, `hideTextResult()`, `copyText() → Promise<void>`, `saveText()`.

- [ ] **Step 1: Write failing tests** (append; add `'copyText', 'saveText', 'hideTextResult'` to `REQUIRED_GLOBALS`). A helper completes a one-frame session whose container is the given name/bytes:

```js
async function completeWith(ctx, name, bytes) {
  ctx.Cimbar.parsePayload = () => ({ fileName: name, fileBytes: bytes });
  const data = makeCompletingFrame({ fileId: 21, seq: 0, total: 1 });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});
}

test('a decoded text message is shown as text (textContent), not downloaded', async () => {
  const { ctx, elements, calls } = freshPage();
  const bytes = new Uint8Array(Buffer.from('<b>hi</b>\nthere', 'utf8'));
  await completeWith(ctx, 'message-20261001-120000.txt', bytes);
  assertEq(calls.anchorClicks, 0, 'no automatic download for a text message');
  assertEq(elements['textOut'].style.display, 'block', 'text panel visible');
  assertEq(elements['textOutBody'].textContent, '<b>hi</b>\nthere', 'text via textContent');
  assertEq(elements['textOutBody'].innerHTML, '', 'never innerHTML');
});

test('a non-text payload still downloads and keeps the text panel hidden', async () => {
  const { ctx, elements, calls } = freshPage();
  await completeWith(ctx, 'photo.jpg', new Uint8Array([0xff, 0xd8]));
  assertEq(calls.anchorClicks, 1, 'file downloaded');
  assert(elements['textOut'].style.display !== 'block', 'text panel hidden');
});

test('BOM + CRLF: Copy gets the text without BOM, Save writes the exact bytes — Review Focus 1', async () => {
  const { ctx, calls } = freshPage();
  const bytes = new Uint8Array([0xef, 0xbb, 0xbf, 0x61, 0x0d, 0x0a, 0x62]);
  await completeWith(ctx, 'notes.txt', bytes);
  let copied = null;
  ctx.navigator.clipboard = { writeText: async (s) => { copied = s; } };
  await ctx.copyText();
  assertEq(copied, 'a\r\nb', 'clipboard text');
  let blobParts = null;
  ctx.Blob = class { constructor(p) { blobParts = p; } };
  ctx.saveText();
  assertEq(calls.anchorClicks, 1, 'Save downloads');
  assertEq(Buffer.from(blobParts[0]).toString('hex'), 'efbbbf610d0a62', 'exact received bytes');
});

test('a blocked clipboard selects the text and explains', async () => {
  const { ctx, elements } = freshPage();
  await completeWith(ctx, 'n.txt', new Uint8Array([0x61]));
  ctx.navigator.clipboard = { writeText: async () => { throw new Error('denied'); } };
  let selected = false;
  ctx.getSelection = () => ({ selectAllChildren() { selected = true; } });
  await ctx.copyText();
  assert(selected, 'text selected for manual copy');
  assert(elements['logDec'].innerHTML.includes('copyFailedHint'), 'hint logged');
});

test('starting over after a text result hides the old text — Review Focus 3', async () => {
  const { ctx, elements } = freshPage();
  await completeWith(ctx, 'n.txt', new Uint8Array([0x61]));
  ctx.resetPhotoSession();
  assertEq(elements['textOut'].style.display, 'none', 'hidden after reset');
  assertEq(elements['textOutBody'].textContent, '', 'old text cleared');
});
```

- [ ] **Step 2: Run — expect failure.** `node tests/test_page_logic.js` → FAIL on the new `REQUIRED_GLOBALS`.

- [ ] **Step 3: Markup.** After the `#progDec` `</div>` in the Decode tab:

```html
      <div class="output-section" id="textOut" style="display:none">
        <label data-i18n="textReceivedTitle">Received text</label>
        <pre id="textOutBody" class="text-out"></pre>
        <button type="button" class="btn btn-primary" onclick="copyText()" data-i18n="copyText">Copy</button>
        <button type="button" class="btn" onclick="saveText()" data-i18n="saveTxt">Save as .txt</button>
      </div>
```

CSS (`output-section` is hidden by default elsewhere, which is why `display` is set inline):

```css
.text-out { white-space: pre-wrap; overflow-wrap: anywhere; max-height: 50vh; overflow: auto; padding: 12px; margin: 8px 0 12px; border: 1px solid var(--border2); border-radius: 8px; background: var(--surface2); font: 14px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
```

- [ ] **Step 4: Script.** Add near `finishDecode`:

```js
let textResult = null;   // { name, bytes } of the text message on screen

function showTextResult(name, bytes, text) {
  textResult = { name, bytes };
  document.getElementById('textOutBody').textContent = text;   // never innerHTML: untrusted
  document.getElementById('textOut').style.display = 'block';
}

function hideTextResult() {
  textResult = null;
  document.getElementById('textOutBody').textContent = '';
  document.getElementById('textOut').style.display = 'none';
}

async function copyText() {
  if (!textResult) return;
  const body = document.getElementById('textOutBody');
  try {
    await navigator.clipboard.writeText(body.textContent);
    log(t('textCopied'), 'ok', 'logDec');
  } catch (e) {
    const sel = typeof getSelection === 'function' ? getSelection() : null;
    if (sel) sel.selectAllChildren(body);
    log(t('copyFailedHint'), 'err', 'logDec');
  }
}

function saveText() {
  if (!textResult) return;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([textResult.bytes], { type: 'text/plain' }));
  a.download = textResult.name;
  a.click();
}
```

Note `copyText` copies `textContent`, which `decodeTextMessage` already produced without the BOM. In `finishDecode`, replace the block from `// Download the file` to the end with:

```js
  const text = Cimbar.decodeTextMessage(filename, fileData);
  if (text !== null) {
    showTextResult(filename, fileData, text);
    log(t('textReceivedLog', { size: fmtBytes(fileData.length) }), 'ok', 'logDec');
    return;
  }

  // Download the file
  const blob = new Blob([fileData]);
  …unchanged…
```

Call `hideTextResult();` as the first statement of `resetPhotoSession()`, of `newPhotoSession()`, and of `handleDecFile(file)`.

- [ ] **Step 5: Strings** (all five tables):

| key | en | ru | uk | tr | ka |
|---|---|---|---|---|---|
| `textReceivedTitle` | Received text | Полученный текст | Отриманий текст | Alınan metin | მიღებული ტექსტი |
| `copyText` | Copy | Копировать | Копіювати | Kopyala | კოპირება |
| `saveTxt` | Save as .txt | Сохранить как .txt | Зберегти як .txt | .txt olarak kaydet | .txt-ად შენახვა |
| `textCopied` | Copied to clipboard | Скопировано в буфер обмена | Скопійовано в буфер обміну | Panoya kopyalandı | დაკოპირდა ბუფერში |
| `copyFailedHint` | Copy was blocked — the text is selected, press Ctrl+C (⌘C). | Копирование заблокировано — текст выделен, нажмите Ctrl+C (⌘C). | Копіювання заблоковано — текст виділено, натисніть Ctrl+C (⌘C). | Kopyalama engellendi — metin seçildi, Ctrl+C (⌘C) tuşlarına basın. | კოპირება დაიბლოკა — ტექსტი მონიშნულია, დააჭირეთ Ctrl+C (⌘C). |
| `textReceivedLog` | Text message received ({size}) | Получено текстовое сообщение ({size}) | Отримано текстове повідомлення ({size}) | Metin mesajı alındı ({size}) | მიღებულია ტექსტური შეტყობინება ({size}) |

- [ ] **Step 6: Run — expect pass.** `sh tests/run_all.sh` → all suites PASS.

- [ ] **Step 7: Manual check.** Serve the app; encode text (Task 2) and download the GIF; Decode tab → choose that GIF → Decode → the text panel shows it, no download; Copy and Save as .txt work. Also decode `test-data/goldens/lorem_12k.gif` → normal download, no text panel.

- [ ] **Step 8: Commit.**

```bash
git add web-app/index.html web-app/i18n.js web-app/tests/test_page_logic.js
git commit -m "feat(web): show a received text message with Copy and Save as .txt"
```

---

### Task 4: Dart payload encoder (container, compression, encryption) + crypto fix

**Files:**
- Modify: `app/lib/core/services/crypto_service.dart` (`encrypt`)
- Modify: `app/lib/core/format/file_container.dart` (add `buildPayload`, `withLengthPrefix`)
- Modify: `app/lib/core/format/cimbar_spec.dart` (add `compressionMinSaving`)
- Modify: `app/test/core/format/cimbar_spec_test.dart` (assert it against the JSON)
- Create: `app/lib/core/encode/payload_encoder.dart`
- Create: `app/test/core/encode/payload_encoder_test.dart`
- Create: `app/test/core/services/crypto_service_encrypt_test.dart`

**Interfaces:**
- Produces:
  - `CryptoService.encrypt(Uint8List data, String passphrase, {Uint8List? salt, Uint8List? iv}) → Uint8List` (salt/iv for tests only).
  - `FileContainer.buildPayload(String fileName, Uint8List fileBytes) → Uint8List`; `FileContainer.withLengthPrefix(Uint8List bytes) → Uint8List`.
  - `CimbarSpec.compressionMinSaving = 0.05`.
  - `class EncodedPayload { EncodedPayload({required int fileId, required bool encrypted, required bool compressed, required int framedLength, required List<Uint8List> bodies}); final int fileId; final bool encrypted; final bool compressed; final int framedLength; final List<Uint8List> bodies; int get total; }` — each body is exactly `CimbarSpec.fileBytesPerFrame` (2104) bytes.
  - `class PayloadEncoder { static EncodedPayload encode({required String name, required Uint8List bytes, String passphrase = '', int? fileId, bool allowCompression = true, Uint8List? salt, Uint8List? iv}); static bool shouldCompress(int original, int deflated); }`

- [ ] **Step 1: Failing crypto test** `app/test/core/services/crypto_service_encrypt_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/services/crypto_service.dart';

void main() {
  final data = Uint8List.fromList(List.generate(100, (i) => i));

  test('encrypt round-trips through decrypt', () {
    final enc = CryptoService.encrypt(data, 'pw');
    expect(CryptoService.decrypt(enc, 'pw'), data);
  });

  test('salt and IV are fresh per call (no 256-seed space)', () {
    final seen = <String>{};
    for (var i = 0; i < 2000; i++) {
      final enc = CryptoService.encrypt(data, 'pw');
      seen.add(enc.sublist(4, 32).toString()); // salt || iv
    }
    // The old FortunaRandom seed kept only the low byte of the clock: at most
    // 256 distinct (salt, iv) pairs, so 2000 calls always collided.
    expect(seen.length, 2000);
  });

  test('injected salt/iv are used verbatim (golden reproduction only)', () {
    final salt = Uint8List.fromList(List.generate(16, (i) => 0xA0 + i));
    final iv = Uint8List.fromList(List.generate(12, (i) => 0xB0 + i));
    final enc = CryptoService.encrypt(data, 'pw', salt: salt, iv: iv);
    expect(enc.sublist(4, 20), salt);
    expect(enc.sublist(20, 32), iv);
  });
}
```

- [ ] **Step 2: Run — expect failure** (`flutter test test/core/services/crypto_service_encrypt_test.dart`: the uniqueness test fails, the injection test does not compile).

- [ ] **Step 3: Fix `encrypt`.** Replace the `FortunaRandom` seeding and the `salt`/`iv` lines with:

```dart
  static Uint8List encrypt(Uint8List data, String passphrase, {Uint8List? salt, Uint8List? iv}) {
    // Random.secure is the platform CSPRNG. The previous FortunaRandom seed was
    // List<int> → Uint8List of clock values, which kept one byte of entropy:
    // 256 possible (salt, iv) pairs, i.e. AES-GCM nonce reuse under one passphrase.
    final rng = math.Random.secure();
    salt ??= Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    iv ??= Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
    final key = _deriveKey(passphrase, salt);
```

Add `import 'dart:math' as math;` and drop now-unused imports (`flutter analyze` will name them).

- [ ] **Step 4: Run — expect pass**, plus the existing crypto/decode tests: `flutter test test/core/services/`.

- [ ] **Step 5: Failing encoder test** `app/test/core/encode/payload_encoder_test.dart`:

```dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';

String repoPath(String rel) => '../$rel';
Uint8List fixedBytes(int n, int start) => Uint8List.fromList(List.generate(n, (i) => (start + i) & 0xFF));

void main() {
  final goldens = Directory(repoPath('test-data/goldens')).listSync().whereType<File>()
      .where((f) => f.path.endsWith('.json')).map((f) => GoldenSidecar.load(f.path)).toList();

  for (final g in goldens.where((g) => g.repairFrames == 0 && !g.compressed)) {
    test('${g.name}: bodies equal the golden source frames byte for byte', () {
      final p = PayloadEncoder.encode(
        name: g.fileName, bytes: g.fileBytes, passphrase: g.passphrase ?? '', fileId: g.fileId,
        allowCompression: false, salt: fixedBytes(16, 0xA0), iv: fixedBytes(12, 0xB0));
      expect(p.total, g.total);
      expect(p.framedLength, g.framedDataLength);
      expect(p.encrypted, g.passphrase != null);
      for (var i = 0; i < p.total; i++) {
        expect(p.bodies[i], g.frames[i].data.sublist(CimbarSpec.headerLen), reason: 'body $i');
      }
    });
  }

  for (final g in goldens.where((g) => g.compressed)) {
    test('${g.name}: compresses like the web encoder and decodes back', () {
      final p = PayloadEncoder.encode(name: g.fileName, bytes: g.fileBytes, passphrase: g.passphrase ?? '', fileId: g.fileId);
      expect(p.compressed, isTrue);
      final framed = Uint8List.fromList(p.bodies.expand((b) => b).toList());
      final f = decodeFramedPayload(framed, g.passphrase ?? '', compressed: true);
      expect(f.fileName, g.fileName);
      expect(f.fileBytes, g.fileBytes);
    });
  }

  test('incompressible bytes are sent raw', () {
    final rng = math.Random(42);
    final rnd = List.generate(5000, (_) => rng.nextInt(256));
    final p = PayloadEncoder.encode(name: 'r.bin', bytes: Uint8List.fromList(rnd));
    expect(p.compressed, isFalse);
  });

  test('shouldCompress mirrors compress.js: d <= floor(n * 0.95)', () {
    expect(PayloadEncoder.shouldCompress(100, 95), isTrue);
    expect(PayloadEncoder.shouldCompress(100, 96), isFalse);
    expect(PayloadEncoder.shouldCompress(0, 0), isFalse);
  });

  test('random fileId is 16-bit', () {
    final p = PayloadEncoder.encode(name: 'a.txt', bytes: Uint8List.fromList([65]));
    expect(p.fileId, inInclusiveRange(0, 0xFFFF));
    expect(p.total, 1);
    expect(p.bodies.single.length, CimbarSpec.fileBytesPerFrame);
  });
}
```

(The uncompressed web goldens were generated without compression — `gen_goldens.js` gates it on `coded` — hence `allowCompression: false` there; the compressed goldens are compared by round trip because Node's and the platform's zlib may emit different but equally valid streams.)

- [ ] **Step 6: Run — expect failure** (missing `payload_encoder.dart`).

- [ ] **Step 7: Implement.** In `file_container.dart` add to `FileContainer`:

```dart
  /// [u32 nameLen BE][UTF-8 name][file bytes] — web-app/cimbar.js buildPayload.
  static Uint8List buildPayload(String fileName, Uint8List fileBytes) {
    final name = utf8.encode(fileName);
    final out = Uint8List(4 + name.length + fileBytes.length);
    ByteData.sublistView(out).setUint32(0, name.length);
    out.setRange(4, 4 + name.length, name);
    out.setRange(4 + name.length, out.length, fileBytes);
    return out;
  }

  /// [u32 len BE][bytes] — strips RS zero padding on decode (stripLengthPrefix).
  static Uint8List withLengthPrefix(Uint8List bytes) {
    final out = Uint8List(4 + bytes.length);
    ByteData.sublistView(out).setUint32(0, bytes.length);
    out.setRange(4, out.length, bytes);
    return out;
  }
```

In `cimbar_spec.dart`, next to `maxInflatedBytes`: `static const double compressionMinSaving = 0.05;` and in `cimbar_spec_test.dart` next to the `maxInflatedBytes` expectation: `expect(CimbarSpec.compressionMinSaving, comp['minSaving']);`.

Create `app/lib/core/encode/payload_encoder.dart`:

```dart
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/file_container.dart';
import '../services/crypto_service.dart';

/// A file ready for framing: the framed data split into N source bodies.
class EncodedPayload {
  final int fileId;
  final bool encrypted;
  final bool compressed;
  final int framedLength;
  final List<Uint8List> bodies; // each CimbarSpec.fileBytesPerFrame bytes, zero padded
  EncodedPayload({required this.fileId, required this.encrypted, required this.compressed,
      required this.framedLength, required this.bodies});
  int get total => bodies.length;
}

/// Encode side of the container (port of startEncode in web-app/index.html and
/// compress.js maybeDeflate): container → deflate if it saves ≥ 5% → optional
/// AES-GCM → length prefix → split into source bodies.
class PayloadEncoder {
  PayloadEncoder._();

  static bool shouldCompress(int original, int deflated) =>
      original > 0 && deflated <= (original * (1 - CimbarSpec.compressionMinSaving)).floor();

  static EncodedPayload encode({
    required String name,
    required Uint8List bytes,
    String passphrase = '',
    int? fileId,
    bool allowCompression = true,
    Uint8List? salt,
    Uint8List? iv,
  }) {
    final container = FileContainer.buildPayload(name, bytes);
    var body = container;
    var compressed = false;
    if (allowCompression && container.isNotEmpty) {
      final d = Uint8List.fromList(ZLibCodec().encode(container));
      if (shouldCompress(container.length, d.length)) {
        body = d;
        compressed = true;
      }
    }
    final encrypted = passphrase.isNotEmpty;
    if (encrypted) body = CryptoService.encrypt(body, passphrase, salt: salt, iv: iv);
    final framed = FileContainer.withLengthPrefix(body);

    const per = CimbarSpec.fileBytesPerFrame;
    final total = math.max(1, (framed.length + per - 1) ~/ per);
    if (total > 65535) throw ArgumentError('needs $total frames (max 65535)');
    final bodies = List<Uint8List>.generate(total, (seq) {
      final b = Uint8List(per);
      final start = seq * per;
      final end = math.min(framed.length, start + per);
      if (end > start) b.setRange(0, end - start, framed, start);
      return b;
    });
    return EncodedPayload(
      fileId: fileId ?? math.Random.secure().nextInt(0x10000),
      encrypted: encrypted,
      compressed: compressed,
      framedLength: framed.length,
      bodies: bodies,
    );
  }
}
```

- [ ] **Step 8: Run — expect pass.** `flutter test test/core/encode/payload_encoder_test.dart test/core/format/cimbar_spec_test.dart`.

- [ ] **Step 9: Commit.**

```bash
git add app/lib/core/services/crypto_service.dart app/lib/core/format/file_container.dart app/lib/core/format/cimbar_spec.dart app/lib/core/encode/payload_encoder.dart app/test/core/encode/payload_encoder_test.dart app/test/core/services/crypto_service_encrypt_test.dart app/test/core/format/cimbar_spec_test.dart
git commit -m "feat(app): payload encoder; fix CryptoService.encrypt's 256-value salt/IV space"
```

---

### Task 5: Dart frame builder and cell grid (golden byte parity)

**Files:**
- Create: `app/lib/core/encode/frame_builder.dart`
- Create: `app/lib/core/encode/cell_grid.dart`
- Create: `app/test/core/encode/frame_builder_test.dart`

**Interfaces:**
- Consumes: `EncodedPayload` (Task 4), `FrameHeader(...).encode()`, `Rateless.coefficients/combine`, `RsFraming.encodeFrame`, `BitPacking.packCells`, `CimbarSpec.gifRepairCount`.
- Produces:
  - `class RepairFrame { final Uint8List data; final int r; final int nextR; }`
  - `class FrameBuilder { static Uint8List sourceFrame(EncodedPayload p, int seq); static RepairFrame nextRepair(EncodedPayload p, int fromR); static List<Uint8List> gifFrames(EncodedPayload p); }` — `nextRepair` skips degenerate (all-zero) coefficient rows, as `startEncode` does, giving up after 64; `gifFrames` returns N source then `gifRepairCount(N)` repair frames (repairs only when `1 < N ≤ codingMaxFrames`).
  - `class CellGrid { static Uint8List raw(Uint8List frameData); static Uint8List cells(Uint8List frameData); }` — 2880 raw bytes / 3840 cell values.

- [ ] **Step 1: Failing test** `app/test/core/encode/frame_builder_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/encode/cell_grid.dart';
import 'package:cimbar_scanner/core/encode/frame_builder.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';

String repoPath(String rel) => '../$rel';

/// The payload a golden was built from, taken from its source frames — so
/// repair frames can be checked without depending on zlib's exact output.
EncodedPayload payloadOf(GoldenSidecar g) => EncodedPayload(
      fileId: g.fileId,
      encrypted: g.passphrase != null,
      compressed: g.compressed,
      framedLength: g.framedDataLength,
      bodies: [for (final f in g.frames.where((f) => !f.repair)) f.data.sublist(CimbarSpec.headerLen)],
    );

void main() {
  final goldens = Directory(repoPath('test-data/goldens')).listSync().whereType<File>()
      .where((f) => f.path.endsWith('.json')).map((f) => GoldenSidecar.load(f.path)).toList();

  for (final g in goldens) {
    test('${g.name}: frames, raw bytes and cells equal the sidecar', () {
      final p = payloadOf(g);
      // The five pre-v2.1 goldens carry source frames only (gen_goldens.js gates
      // repair frames on `coded`); the coded ones carry the full GIF composition.
      final frames = g.frameCount == g.total
          ? [for (var s = 0; s < p.total; s++) FrameBuilder.sourceFrame(p, s)]
          : FrameBuilder.gifFrames(p);
      expect(frames.length, g.frames.length);
      for (var i = 0; i < frames.length; i++) {
        expect(frames[i], g.frames[i].data, reason: 'frame $i data');
        expect(CellGrid.raw(frames[i]), g.frames[i].raw, reason: 'frame $i raw');
        expect(CellGrid.cells(frames[i]), g.frames[i].cells, reason: 'frame $i cells');
      }
    });
  }

  test('repair-only frames reassemble a 9-frame text file', () {
    final text = Uint8List.fromList(List.generate(17000, (i) => 0x41 + (i * 31 % 26)));
    final p = PayloadEncoder.encode(name: 'n.txt', bytes: text, allowCompression: false);
    expect(p.total, greaterThan(1));
    final asm = RatelessAssembler();
    var r = 0;
    while (!asm.isComplete) {
      final rf = FrameBuilder.nextRepair(p, r);
      asm.add(rf.data);
      r = rf.nextR;
    }
    final f = decodeFramedPayload(asm.framedData(), '');
    expect(f.fileBytes, text);
  });

  test('a one-frame file has no repair frames in its GIF', () {
    final p = PayloadEncoder.encode(name: 'a.txt', bytes: Uint8List.fromList([65]));
    expect(FrameBuilder.gifFrames(p).length, 1);
  });

  test('repair frame generation at N=345 and N=4096 stays fast', () {
    for (final n in [345, 4096]) {
      final p = EncodedPayload(fileId: 0x1234, encrypted: false, compressed: false, framedLength: n * 2104,
          bodies: List.generate(n, (i) => Uint8List(CimbarSpec.fileBytesPerFrame)..fillRange(0, 2104, i & 0xFF)));
      final sw = Stopwatch()..start();
      for (var r = 0; r < 3; r++) {
        FrameBuilder.nextRepair(p, r);
      }
      final ms = sw.elapsedMilliseconds / 3;
      // ignore: avoid_print
      print('repair frame at N=$n: ${ms.toStringAsFixed(1)} ms');
      expect(ms, lessThan(250), reason: 'N=$n'); // ~21 ms JIT on the dev machine; generous for CI
    }
  });
}
```

- [ ] **Step 2: Run — expect failure** (missing files).

- [ ] **Step 3: Implement** `app/lib/core/encode/frame_builder.dart`:

```dart
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import '../format/rateless.dart';
import 'payload_encoder.dart';

class RepairFrame {
  final Uint8List data; // 2112 bytes: header + combined body
  final int r; // repair id used
  final int nextR; // repair id to try next
  const RepairFrame(this.data, this.r, this.nextR);
}

/// Source and repair frames (port of splitIntoFrames/repairFrame and the
/// repair-id loop in startEncode, web-app/cimbar.js + index.html).
class FrameBuilder {
  FrameBuilder._();

  static Uint8List _frame(EncodedPayload p, {required bool repair, required int seq, required Uint8List body}) {
    final f = Uint8List(CimbarSpec.dataBytesPerFrame);
    f.setRange(0, CimbarSpec.headerLen, FrameHeader(
      version: CimbarSpec.version, encrypted: p.encrypted, repair: repair,
      compressed: p.compressed, fileId: p.fileId, seq: seq, total: p.total).encode());
    f.setRange(CimbarSpec.headerLen, CimbarSpec.headerLen + body.length, body);
    return f;
  }

  static Uint8List sourceFrame(EncodedPayload p, int seq) =>
      _frame(p, repair: false, seq: seq, body: p.bodies[seq]);

  /// The first usable repair frame at id ≥ [fromR] (mod 65536): an all-zero
  /// coefficient row carries nothing and is skipped, as the web encoder does.
  static RepairFrame nextRepair(EncodedPayload p, int fromR) {
    var r = fromR & 0xFFFF;
    for (var misses = 0; misses < 64; misses++) {
      final coef = Rateless.coefficients(p.fileId, r, p.total);
      if (coef.any((c) => c != 0)) {
        final body = Rateless.combine(p.bodies, coef);
        return RepairFrame(_frame(p, repair: true, seq: r, body: body), r, (r + 1) & 0xFFFF);
      }
      r = (r + 1) & 0xFFFF;
    }
    throw StateError('no usable repair id');
  }

  /// N source frames, then gifRepairCount(N) repair frames when coding applies.
  static List<Uint8List> gifFrames(EncodedPayload p) {
    final out = [for (var s = 0; s < p.total; s++) sourceFrame(p, s)];
    if (p.total > 1 && p.total <= CimbarSpec.codingMaxFrames) {
      var r = 0;
      for (var i = 0; i < CimbarSpec.gifRepairCount(p.total); i++) {
        final rf = nextRepair(p, r);
        out.add(rf.data);
        r = rf.nextR;
      }
    }
    return out;
  }
}
```

`app/lib/core/encode/cell_grid.dart`:

```dart
import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/rs_framing.dart';
import '../services/reed_solomon.dart';

/// Frame data → RS-encoded interleaved raw bytes → 3840 cell values.
class CellGrid {
  CellGrid._();

  static final ReedSolomon _rs = ReedSolomon(CimbarSpec.rsEccBytes);

  static Uint8List raw(Uint8List frameData) => RsFraming.encodeFrame(frameData, _rs);

  static Uint8List cells(Uint8List frameData) => BitPacking.packCells(raw(frameData));
}
```

(Check `ReedSolomon`'s constructor in `reed_solomon.dart`; `frame_decoder.dart:25` builds it as `ReedSolomon(CimbarSpec.rsEccBytes)`.)

- [ ] **Step 4: Run — expect pass.** `flutter test test/core/encode/frame_builder_test.dart`. Record the printed benchmark numbers in the commit message.

- [ ] **Step 5: Commit.**

```bash
git add app/lib/core/encode/frame_builder.dart app/lib/core/encode/cell_grid.dart app/test/core/encode/frame_builder_test.dart
git commit -m "feat(app): frame builder and cell grid, byte-identical to the goldens"
```

---

### Task 6: Dart frame raster and GIF writer (pixel and byte parity)

**Files:**
- Create: `app/lib/core/encode/frame_raster.dart`
- Create: `app/lib/core/encode/gif_writer.dart`
- Create: `app/test/core/encode/frame_raster_test.dart`

**Interfaces:**
- Consumes: `CellGrid.cells`, `FrameBuilder.gifFrames` (Task 5), `Tiles.bits` (`app/lib/core/format/tiles.dart:9`; `bits[sym][y * 8 + x]` is 0/1 — confirm in the file), `CimbarSpec` finder constants.
- Produces:
  - `class FrameRaster { static const int black = 4; static const int white = 5; static Uint8List render(Uint8List cells); static Uint8List toRgb(Uint8List indices); static Uint8List toRgba(Uint8List indices); }` — `render` returns `framePx * framePx` palette indices (0–3 spec palette, 4 black, 5 white).
  - `class GifWriter { static Uint8List encode(List<Uint8List> indexFrames, {required int delayCs, int width = CimbarSpec.framePx, int height = CimbarSpec.framePx}); }`
  - `Uint8List buildGif(EncodedPayload p, int delayMs)` — top-level, isolate-safe: `GifWriter.encode([for (f in FrameBuilder.gifFrames(p)) FrameRaster.render(CellGrid.cells(f))], delayCs: delayMs ~/ 10)`.

- [ ] **Step 1: Failing test** `app/test/core/encode/frame_raster_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/encode/cell_grid.dart';
import 'package:cimbar_scanner/core/encode/frame_raster.dart';
import 'package:cimbar_scanner/core/encode/gif_writer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final jsons = Directory(repoPath('test-data/goldens')).listSync().whereType<File>()
      .where((f) => f.path.endsWith('.json')).map((f) => f.path).toList()..sort();

  for (final path in jsons) {
    final g = GoldenSidecar.load(path);
    final gifPath = path.replaceAll('.json', '.gif');

    test('${g.name}: raster equals the golden GIF pixels', () {
      final frames = GifParser.parseFrames(File(gifPath).readAsBytesSync());
      for (var i = 0; i < g.frames.length; i++) {
        final rgb = FrameRaster.toRgb(FrameRaster.render(CellGrid.cells(g.frames[i].data)));
        expect(rgb, RgbBuffer.fromImage(frames[i]).rgb, reason: 'frame $i pixels');
      }
    });

    test('${g.name}: GifWriter output is byte-identical to the golden .gif', () {
      final indexFrames = [for (final f in g.frames) FrameRaster.render(CellGrid.cells(f.data))];
      expect(GifWriter.encode(indexFrames, delayCs: g.delayMs ~/ 10), File(gifPath).readAsBytesSync());
    });
  }

  test('a rendered frame decodes exactly back to its cells', () {
    final g = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));
    final idx = FrameRaster.render(CellGrid.cells(g.frames[0].data));
    final r = FrameDecoder().decodeExact(RgbBuffer(608, 608, FrameRaster.toRgb(idx)));
    expect(r.cells, g.frames[0].cells);
  });
}
```

(`dart_text` from Task 7 joins these loops automatically: its GIF is written by `GifWriter`, so both assertions hold for it by construction.)

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement** `app/lib/core/encode/frame_raster.dart` — a direct port of `renderFrame`/`drawTile`/`drawFinder` (web-app/cimbar.js):

```dart
import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/tiles.dart';

/// Cells → 608×608 palette indices, pixel-identical to renderFrame in
/// web-app/cimbar.js: black background (quiet zone and gaps included), tile
/// "on" pixels in the cell's palette color, then the four finders on top.
/// Index 0–3 = CimbarSpec.palette, 4 = black, 5 = white — the slot order of
/// gif-encoder.js's palette, so indices go into the GIF unchanged.
class FrameRaster {
  FrameRaster._();

  static const int black = 4;
  static const int white = 5;
  static const int _size = CimbarSpec.framePx;

  static void _fill(Uint8List px, int x, int y, int w, int h, int v) {
    for (var yy = y; yy < y + h; yy++) {
      px.fillRange(yy * _size + x, yy * _size + x + w, v);
    }
  }

  static Uint8List render(Uint8List cells) {
    final px = Uint8List(_size * _size)..fillRange(0, _size * _size, black);
    final pos = CimbarSpec.usableCellPositions;
    for (var k = 0; k < pos.length; k++) {
      final ox = CimbarSpec.cellOriginX(pos[k].col);
      final oy = CimbarSpec.cellOriginY(pos[k].row);
      final t = Tiles.bits[BitPacking.cellSymbol(cells[k])];
      final c = BitPacking.cellColor(cells[k]);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          if (t[y * 8 + x] != 0) px[(oy + y) * _size + ox + x] = c;
        }
      }
    }
    for (final corner in const ['tl', 'tr', 'bl', 'br']) {
      final c = CimbarSpec.finderCenters[corner]!;
      // Math.round in JS; the values are exact integers for this spec
      // (16 + 3.5·9 − 31.5 = 16, 16 + 60.5·9 − 31.5 = 529), floor(x + 0.5) matches either way.
      final ox = (CimbarSpec.quietPx + c[0] * CimbarSpec.pitchPx - CimbarSpec.finderOuterPx / 2 + 0.5).floor();
      final oy = (CimbarSpec.quietPx + c[1] * CimbarSpec.pitchPx - CimbarSpec.finderOuterPx / 2 + 0.5).floor();
      const o = CimbarSpec.finderOuterPx, ri = CimbarSpec.finderRingInsetPx;
      _fill(px, ox, oy, o, o, white);
      _fill(px, ox + ri, oy + ri, o - 2 * ri, o - 2 * ri, black);
      _fill(px, ox + CimbarSpec.finderCoreInsetPx, oy + CimbarSpec.finderCoreInsetPx,
          CimbarSpec.finderCorePx, CimbarSpec.finderCorePx, white);
      if (CimbarSpec.finderDotOn.contains(corner)) {
        _fill(px, ox + CimbarSpec.finderDotInsetPx, oy + CimbarSpec.finderDotInsetPx,
            CimbarSpec.finderDotPx, CimbarSpec.finderDotPx, black);
      }
    }
    return px;
  }

  static List<int> _rgbOf(int i) => i < 4
      ? CimbarSpec.palette[i]
      : (i == white ? const [255, 255, 255] : const [0, 0, 0]);

  static Uint8List toRgb(Uint8List indices) {
    final out = Uint8List(indices.length * 3);
    for (var i = 0; i < indices.length; i++) {
      final c = _rgbOf(indices[i]);
      out[i * 3] = c[0]; out[i * 3 + 1] = c[1]; out[i * 3 + 2] = c[2];
    }
    return out;
  }

  static Uint8List toRgba(Uint8List indices) {
    final out = Uint8List(indices.length * 4);
    for (var i = 0; i < indices.length; i++) {
      final c = _rgbOf(indices[i]);
      out[i * 4] = c[0]; out[i * 4 + 1] = c[1]; out[i * 4 + 2] = c[2]; out[i * 4 + 3] = 255;
    }
    return out;
  }
}
```

(Check `CellPos` field names in `cimbar_spec.dart` — `CellPos(col, row)`; adjust `.col`/`.row` if they differ.)

`app/lib/core/encode/gif_writer.dart` — a line-for-line port of `web-app/gif-encoder.js` (`finish`, `buildPalette`, `lzwCompress`) taking index buffers instead of quantizing; keep the quirks (the clear code is emitted at the *current* code size inside `reset`; codes grow when `nextCode > 1 << codeSize`):

```dart
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'cell_grid.dart';
import 'frame_builder.dart';
import 'frame_raster.dart';
import 'payload_encoder.dart';

/// Port of web-app/gif-encoder.js. Frames arrive as palette indices
/// (FrameRaster), so nothing is quantized and the output is byte-identical to
/// the web encoder's for the same frames.
class GifWriter {
  GifWriter._();

  static Uint8List palette() {
    final pal = Uint8List(256 * 3);
    var idx = 0;
    final fixed = [...CimbarSpec.palette, const [0, 0, 0], const [255, 255, 255]];
    for (final c in fixed) {
      pal[idx * 3] = c[0]; pal[idx * 3 + 1] = c[1]; pal[idx * 3 + 2] = c[2];
      idx++;
    }
    for (var v = 0; v <= 255 && idx < 256; v += 8) {
      pal[idx * 3] = v; pal[idx * 3 + 1] = v; pal[idx * 3 + 2] = v;
      idx++;
    }
    for (var r = 0; r < 6 && idx < 256; r++) {
      for (var g = 0; g < 6 && idx < 256; g++) {
        for (var b = 0; b < 6 && idx < 256; b++) {
          pal[idx * 3] = r * 51; pal[idx * 3 + 1] = g * 51; pal[idx * 3 + 2] = b * 51;
          idx++;
        }
      }
    }
    return pal;
  }

  static Uint8List encode(List<Uint8List> indexFrames,
      {required int delayCs, int width = CimbarSpec.framePx, int height = CimbarSpec.framePx}) {
    final out = BytesBuilder(copy: false);
    void word(int n) => out.add([n & 0xFF, (n >> 8) & 0xFF]);
    out.add('GIF89a'.codeUnits);
    word(width);
    word(height);
    out.add([0xF7, 0, 0]);
    out.add(palette());
    out.add([0x21, 0xFF, 0x0B]);
    out.add('NETSCAPE2.0'.codeUnits);
    out.add([0x03, 0x01, 0x00, 0x00, 0x00]);
    for (final indices in indexFrames) {
      out.add([0x21, 0xF9, 0x04, 0x04]);
      word(delayCs);
      out.add([0x00, 0x00]);
      out.add([0x2C]);
      word(0); word(0); word(width); word(height);
      out.add([0x00]);
      const lzwMin = 8;
      out.add([lzwMin]);
      out.add(_lzw(indices, lzwMin));
    }
    out.add([0x3B]);
    return out.takeBytes();
  }

  static Uint8List _lzw(Uint8List indices, int minCodeSize) {
    final clearCode = 1 << minCodeSize;
    final eofCode = clearCode + 1;
    var codeSize = minCodeSize + 1;
    var nextCode = eofCode + 1;
    final out = BytesBuilder(copy: false);
    var bitBuf = 0, bitCount = 0;
    final sub = Uint8List(256);
    var subLen = 0;

    void emit(int code, int n) {
      bitBuf |= code << bitCount;
      bitCount += n;
      while (bitCount >= 8) {
        sub[subLen++] = bitBuf & 0xFF;
        bitBuf >>= 8;
        bitCount -= 8;
        if (subLen == 255) {
          out.addByte(255);
          out.add(Uint8List.fromList(sub.sublist(0, 255)));
          subLen = 0;
        }
      }
    }

    final table = <int, int>{};
    void reset() {
      table.clear();
      emit(clearCode, codeSize);
      codeSize = minCodeSize + 1;
      nextCode = eofCode + 1;
    }

    reset();
    var prefix = indices[0];
    for (var i = 1; i < indices.length; i++) {
      final suffix = indices[i];
      final key = (prefix << 8) | suffix;
      final hit = table[key];
      if (hit != null) {
        prefix = hit;
      } else {
        emit(prefix, codeSize);
        if (nextCode <= 4095) {
          table[key] = nextCode++;
          if (nextCode > (1 << codeSize) && codeSize < 12) codeSize++;
        } else {
          reset();
        }
        prefix = suffix;
      }
    }
    emit(prefix, codeSize);
    emit(eofCode, codeSize);
    if (bitCount > 0) {
      sub[subLen++] = bitBuf & 0xFF;
      bitBuf = 0;
      bitCount = 0;
    }
    if (subLen > 0) {
      out.addByte(subLen);
      out.add(Uint8List.fromList(sub.sublist(0, subLen)));
    }
    out.addByte(0);
    return out.takeBytes();
  }
}

/// The downloadable GIF for [p]: N source + gifRepairCount(N) repair frames.
/// Top-level so it can run in Isolate.run.
Uint8List buildGif(EncodedPayload p, int delayMs) => GifWriter.encode(
      [for (final f in FrameBuilder.gifFrames(p)) FrameRaster.render(CellGrid.cells(f))],
      delayCs: delayMs ~/ 10,
    );
```

- [ ] **Step 4: Run — expect pass.** `flutter test test/core/encode/frame_raster_test.dart`. If the GIF byte test fails while the pixel test passes, diff the first differing offset against `gif-encoder.js` — the port is wrong, not the golden.

- [ ] **Step 5: Commit.**

```bash
git add app/lib/core/encode/frame_raster.dart app/lib/core/encode/gif_writer.dart app/test/core/encode/frame_raster_test.dart
git commit -m "feat(app): frame raster and GIF writer, pixel- and byte-identical to the goldens"
```

---

### Task 7: Dart-written golden `dart_text` decoded by the web suite

**Files:**
- Create: `app/tool/gen_dart_goldens.dart`
- Create (generated): `test-data/goldens/dart_text.gif`, `test-data/goldens/dart_text.json`
- Modify: `test-data/goldens/README.md`
- Modify: `web-app/tests/test_goldens.js` (one extra assertion)

**Interfaces:**
- Consumes: `PayloadEncoder.encode`, `FrameBuilder.gifFrames`, `CellGrid.raw/cells`, `FrameRaster.render`, `GifWriter.encode`, `FrameHeader.decode`, `Rateless.coefficients`, `TextMessage.fileName`.
- Produces: a golden in the **coded sidecar schema** written by `gen_goldens.js` (`name, fileName, fileBytesBase64, passphrase, fileId, total, delayMs, framedDataLength, compressed, sourceFrames, repairFrames, frameCount, frames[{seq, repair, r, header{version,encrypted,repair,compressed,fileId,seq,total}, dataHex, rawHex, cells, coef12}]`), so `test_goldens.js` and every Dart golden loop verify it with no schema change.

- [ ] **Step 1: Write the generator** `app/tool/gen_dart_goldens.dart` (pure Dart; run with `dart run`):

```dart
// Writes test-data/goldens/dart_text.{gif,json}: a text message encoded by
// the Dart encoder, in the coded sidecar schema of web-app/tools/gen_goldens.js,
// so the web suite proves a phone-made GIF decodes in JS.
// Usage: cd app && dart run tool/gen_dart_goldens.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cimbar_scanner/core/encode/cell_grid.dart';
import 'package:cimbar_scanner/core/encode/frame_builder.dart';
import 'package:cimbar_scanner/core/encode/frame_raster.dart';
import 'package:cimbar_scanner/core/encode/gif_writer.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/frame_header.dart';
import 'package:cimbar_scanner/core/format/rateless.dart';

const words = ['CimBar', 'текст', 'повідомлення', 'მესიჯი', 'metin', 'frame', 'код', '😀', 'Ünïcödé', 'line'];

String hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Deterministic LCG text: compressible (repeated vocabulary) yet large enough
  // that the deflated container spans several frames.
  var s = 12345;
  final sb = StringBuffer();
  for (var line = 0; line < 2000; line++) {
    for (var w = 0; w < 8; w++) {
      s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
      sb.write(words[s % words.length]);
      sb.write(w == 7 ? '\n' : ' ');
    }
  }
  final text = Uint8List.fromList(utf8.encode(sb.toString()));
  const name = 'message-20261001-120000.txt';
  final p = PayloadEncoder.encode(name: name, bytes: text, fileId: 0x2001);
  if (!p.compressed || p.total < 2) throw StateError('want compressed, N >= 2; got ${p.compressed}, ${p.total}');

  final frames = FrameBuilder.gifFrames(p);
  final side = <String, Object?>{
    'name': 'dart_text', 'fileName': name, 'fileBytesBase64': base64.encode(text),
    'passphrase': null, 'fileId': p.fileId, 'total': p.total, 'delayMs': CimbarSpec.defaultDelayMs,
    'framedDataLength': p.framedLength, 'compressed': p.compressed, 'sourceFrames': p.total,
    'repairFrames': frames.length - p.total, 'frameCount': frames.length,
    'frames': [
      for (final data in frames)
        () {
          final h = FrameHeader.decode(data).header!;
          final raw = CellGrid.raw(data);
          return {
            'seq': h.seq, 'repair': h.repair, 'r': h.repair ? h.seq : null,
            'header': {'version': h.version, 'encrypted': h.encrypted, 'repair': h.repair,
                       'compressed': h.compressed, 'fileId': h.fileId, 'seq': h.seq, 'total': h.total},
            'dataHex': hex(data), 'rawHex': hex(raw), 'cells': CellGrid.cells(data).toList(),
            'coef12': h.repair ? Rateless.coefficients(h.fileId, h.seq, h.total).sublist(0, h.total < 12 ? h.total : 12).toList() : null,
          };
        }(),
    ],
  };
  const dir = '../test-data/goldens';
  File('$dir/dart_text.gif').writeAsBytesSync(GifWriter.encode(
      [for (final f in frames) FrameRaster.render(CellGrid.cells(f))], delayCs: CimbarSpec.defaultDelayMs ~/ 10));
  File('$dir/dart_text.json').writeAsStringSync(jsonEncode(side));
  stdout.writeln('dart_text: ${p.total} source + ${frames.length - p.total} repair frames, ${text.length} text bytes');
}
```

(`coef12` must match `gen_goldens.js`: `codingCoefficients(...).subarray(0, 12)`, i.e. `min(12, total)` values.)

- [ ] **Step 2: Generate.** `cd app && dart run tool/gen_dart_goldens.dart` → prints e.g. `dart_text: 5 source + 2 repair frames`. If `dart run` refuses a Flutter import anywhere in the chain, an encode file imports Flutter — fix that file, don't work around it.

- [ ] **Step 3: Pin the text in the web suite.** In `web-app/tests/test_goldens.js`, after the per-golden payload check, add for `side.name === 'dart_text'`:

```js
    if (side.name === 'dart_text') {
      const text = C.decodeTextMessage(parsed.fileName, parsed.fileBytes);
      assertEq(text, Buffer.from(side.fileBytesBase64, 'base64').toString('utf8'), 'dart_text decodes as a text message');
    }
```

(Use whichever variable names `test_goldens.js` already has for the parsed payload and the cimbar module — read the file around line 41.)

- [ ] **Step 4: Run both suites.** `cd web-app && node tests/test_goldens.js` → PASS including `dart_text` (all frames, source-only, every-k-th-dropped). `cd app && sh tests/run_all.sh` → PASS (the golden loops in `frame_decoder_golden_test.dart`, Task 5 and Task 6 now cover `dart_text`).

- [ ] **Step 5: README.** Add a `dart_text` row to `test-data/goldens/README.md`: "text message encoded by the Dart encoder (`app/tool/gen_dart_goldens.dart`), compressed, N source + 25% repair; regenerate only when the Dart encoder changes — zlib output may differ across machines, the sidecar records whatever was written."

- [ ] **Step 6: Commit.**

```bash
git add app/tool/gen_dart_goldens.dart test-data/goldens/dart_text.gif test-data/goldens/dart_text.json test-data/goldens/README.md web-app/tests/test_goldens.js
git commit -m "test: dart_text golden — a Dart-encoded text message decoded by the web suite"
```

---

### Task 8: Flutter — show a received text message in `ResultCard`

**Files:**
- Modify: `app/lib/shared/widgets/result_card.dart`
- Modify: `app/lib/l10n/app_en.arb`, `app_ru.arb`, `app_uk.arb`, `app_tr.arb`, `app_ka.arb` (then `flutter gen-l10n`)
- Modify: `app/lib/features/import/import_screen.dart`, `app/lib/features/camera/camera_screen.dart`, `app/lib/features/camera/live_scan_screen.dart` (pass `onShareText`)
- Modify: `app/test/shared/result_card_test.dart`

**Interfaces:**
- Consumes: `TextMessage.decode` (Task 1).
- Produces: `ResultCard({required DecodeResult result, VoidCallback? onOpen, VoidCallback? onExport, VoidCallback? onShare, ValueChanged<String>? onShareText})`. When `TextMessage.decode(result.filename, result.data)` is non-null the card shows the text (selectable, scrollable, height-bounded) with **Copy** (built in: `Clipboard.setData` + snackbar) and, when `onShareText != null`, **Share text**; the existing Open / Save to device / Share File buttons stay (Save to device writes the exact bytes via `FileService.exportBytes`).

- [ ] **Step 1: Failing widget tests** — append to `app/test/shared/result_card_test.dart`:

```dart
  testWidgets('a text message shows its text, Copy and Share text', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final shared = <String>[];
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('line 1\r\nстрока 2')]);
    await tester.pumpWidget(host(ResultCard(
      result: DecodeResult(filename: 'message-20261001-120000.txt', data: bytes),
      onShareText: shared.add,
    )));
    expect(find.text('line 1\r\nстрока 2'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, ['line 1\r\nстрока 2'], reason: 'BOM dropped, CRLF kept — Review Focus 1');
    expect(find.text('Copied to clipboard'), findsOneWidget);
    await tester.tap(find.text('Share text'));
    expect(shared, ['line 1\r\nстрока 2']);
  });

  testWidgets('a binary file shows no text view', (tester) async {
    await tester.pumpWidget(host(ResultCard(result: result, onShareText: (_) {})));
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('1 MiB of one long line stays bounded and scrollable — Review Focus 5', (tester) async {
    final big = Uint8List(TextMessage.maxBytes)..fillRange(0, TextMessage.maxBytes, 0x41);
    await tester.pumpWidget(host(SingleChildScrollView(child: ResultCard(
      result: DecodeResult(filename: 'big.txt', data: big)))));
    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.byKey(const Key('textResultBody')));
    expect(box.height, lessThanOrEqualTo(320));
  });
```

Add imports: `dart:convert`, `package:flutter/services.dart`, `package:cimbar_scanner/core/format/text_message.dart`. The `host` helper must provide a `ScaffoldMessenger` (MaterialApp does) for the snackbar.

- [ ] **Step 2: Run — expect failure.** `cd app && flutter test test/shared/result_card_test.dart`.

- [ ] **Step 3: Strings.** Add to `app_en.arb` (with `@` descriptions) and the translations to the other four ARB files:

| key | en | ru | uk | tr | ka |
|---|---|---|---|---|---|
| `receivedText` | Received text | Полученный текст | Отриманий текст | Alınan metin | მიღებული ტექსტი |
| `copyText` | Copy | Копировать | Копіювати | Kopyala | კოპირება |
| `textCopied` | Copied to clipboard | Скопировано в буфер обмена | Скопійовано в буфер обміну | Panoya kopyalandı | დაკოპირდა ბუფერში |
| `shareText` | Share text | Поделиться текстом | Поділитися текстом | Metni paylaş | ტექსტის გაზიარება |

Run `flutter gen-l10n`.

- [ ] **Step 4: Implement.** In `result_card.dart` add the field `final ValueChanged<String>? onShareText;` (constructor `this.onShareText`), and in `build`, after the size `Text` and before the button `Wrap`:

```dart
            if (text != null) ...[
              const SizedBox(height: 12),
              Text(l10n.receivedText, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Container(
                key: const Key('textResultBody'),
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                // Plain text only: received text is untrusted, nothing is linkified.
                child: SingleChildScrollView(child: SelectableText(text)),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.textCopied)));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(l10n.copyText),
                ),
                if (onShareText != null)
                  OutlinedButton.icon(
                    onPressed: () => onShareText!(text),
                    icon: const Icon(Icons.share),
                    label: Text(l10n.shareText),
                  ),
              ]),
            ],
```

with `final text = TextMessage.decode(result.filename, result.data);` at the top of `build`, and imports `package:flutter/services.dart` and `../../core/format/text_message.dart`.

In each of the three screens add to the existing `ResultCard(...)`:

```dart
              onShareText: (t) => SharePlus.instance.share(ShareParams(text: t)),
```

(import `package:share_plus/share_plus.dart`).

- [ ] **Step 5: Run — expect pass.** `flutter test test/shared/result_card_test.dart`, then `sh tests/run_all.sh`.

- [ ] **Step 6: Commit.**

```bash
git add app/lib/shared/widgets/result_card.dart app/lib/l10n app/lib/features/import/import_screen.dart app/lib/features/camera/camera_screen.dart app/lib/features/camera/live_scan_screen.dart app/test/shared/result_card_test.dart
git commit -m "feat(app): show a received text message with Copy and Share text"
```

---

### Task 9: Flutter — Send tab (text or file, Share GIF)

**Files:**
- Create: `app/lib/features/send/send_controller.dart`
- Create: `app/lib/features/send/send_screen.dart`
- Create: `app/lib/core/encode/send_jobs.dart` (isolate entry points)
- Modify: `app/lib/app.dart` (route `/send`), `app/lib/shared/widgets/app_shell.dart` (tab first)
- Modify: the five ARB files
- Create: `app/test/features/send_controller_test.dart`, `app/test/features/send_screen_test.dart`
- Modify: `app/test/features/camera_navigation_test.dart` if it hard-codes tab indices (the Import tab moves from index 0 to 1)

**Interfaces:**
- Consumes: `PayloadEncoder.encode`, `buildGif` (Task 6), `TextMessage.fileName`, `FileService.shareFile`, `PassphraseField`, `FilePickerZone`.
- Produces:
  - `send_jobs.dart`: `class SendRequest { final String name; final Uint8List bytes; final String passphrase; }`; top-level `EncodedPayload encodeRequest(SendRequest r)`; constants `const int maxSendFrames = CimbarSpec.codingMaxFrames; const int maxGifFrames = 500;`.
  - `enum SendMode { text, file }`; `class SendState { SendMode mode; String text; String? fileName; Uint8List? fileBytes; int delayMs; bool busy; String? error; }` (with `copyWith`); `SendState.inputName/inputBytes` getters; `int estimateFrames(SendState s, {bool encrypted})`.
  - `class SendController extends StateNotifier<SendState>` with `setMode`, `setText`, `setFile(String name, Uint8List bytes)`, `setDelay(int ms)`, `Future<EncodedPayload?> encode(String passphrase, {required int cap})` — returns null and sets `error` (a key-like code: `'empty'`, `'tooLarge:<frames>:<max>'`, `'failed:<msg>'`) when refused; `Future<void> shareGif(String passphrase)`.
  - `final sendControllerProvider = StateNotifierProvider<SendController, SendState>(...)`, with the encoder/sharer injectable for tests: `SendController({EncodedPayload Function(SendRequest)? encoder, Future<void> Function(String name, Uint8List gif)? shareGifBytes, DateTime Function()? now})`.

- [ ] **Step 1: Failing controller tests** `app/test/features/send_controller_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/encode/send_jobs.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';

EncodedPayload fakePayload(int n) => EncodedPayload(fileId: 1, encrypted: false, compressed: false,
    framedLength: n * 2104, bodies: List.generate(n, (_) => Uint8List(2104)));

void main() {
  test('text mode sends message-….txt with the UTF-8 text as typed', () async {
    SendRequest? seen;
    final c = SendController(encoder: (r) { seen = r; return fakePayload(1); }, now: () => DateTime(2026, 10, 1, 12));
    c.setText('a\r\nб');
    final p = await c.encode('', cap: maxSendFrames);
    expect(p, isNotNull);
    expect(seen!.name, 'message-20261001-120000.txt');
    expect(seen!.bytes, [0x61, 0x0d, 0x0a, 0xd0, 0xb1]);
  });

  test('empty text is refused; whitespace is not', () async {
    final c = SendController(encoder: (_) => fakePayload(1));
    expect(await c.encode('', cap: maxSendFrames), isNull);
    expect(c.state.error, 'empty');
    c.setText(' ');
    expect(await c.encode('', cap: maxSendFrames), isNotNull);
  });

  test('file mode sends the file under its own name', () async {
    SendRequest? seen;
    final c = SendController(encoder: (r) { seen = r; return fakePayload(1); })
      ..setMode(SendMode.file)
      ..setFile('photo.jpg', Uint8List.fromList([1, 2]));
    await c.encode('pw', cap: maxSendFrames);
    expect(seen!.name, 'photo.jpg');
    expect(seen!.passphrase, 'pw');
  });

  test('caps are checked on the encoded frame count', () async {
    final c = SendController(encoder: (_) => fakePayload(501))..setText('x');
    expect(await c.encode('', cap: maxSendFrames), isNotNull);
    expect(await c.encode('', cap: maxGifFrames), isNull);
    expect(c.state.error, 'tooLarge:501:500');
  });

  test('shareGif hands a GIF named after the input to the sharer', () async {
    String? sharedName;
    final c = SendController(encoder: (_) => fakePayload(1), shareGifBytes: (n, g) async { sharedName = n; },
        now: () => DateTime(2026, 10, 1, 12))..setText('hi');
    await c.shareGif('');
    expect(sharedName, 'message-20261001-120000.gif');
    expect(c.state.busy, isFalse);
  });

  test('an encoder exception becomes an error and keeps the input', () async {
    final c = SendController(encoder: (_) => throw StateError('boom'))..setText('keep me');
    expect(await c.encode('', cap: maxSendFrames), isNull);
    expect(c.state.error, startsWith('failed:'));
    expect(c.state.text, 'keep me');
  });
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement** `app/lib/core/encode/send_jobs.dart`:

```dart
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'payload_encoder.dart';

const int maxSendFrames = CimbarSpec.codingMaxFrames;
const int maxGifFrames = 500;

class SendRequest {
  final String name;
  final Uint8List bytes;
  final String passphrase;
  const SendRequest(this.name, this.bytes, this.passphrase);
}

/// Isolate entry point (top-level: an Isolate.run closure must not capture a
/// Riverpod notifier — see decode_isolate.dart).
EncodedPayload encodeRequest(SendRequest r) =>
    PayloadEncoder.encode(name: r.name, bytes: r.bytes, passphrase: r.passphrase);
```

`app/lib/features/send/send_controller.dart`:

```dart
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/encode/gif_writer.dart';
import '../../core/encode/payload_encoder.dart';
import '../../core/encode/send_jobs.dart';
import '../../core/format/cimbar_spec.dart';
import '../../core/format/text_message.dart';
import '../../core/services/file_service.dart';

enum SendMode { text, file }

class SendState {
  final SendMode mode;
  final String text;
  final String? fileName;
  final Uint8List? fileBytes;
  final int delayMs;
  final bool busy;
  final String? error;

  const SendState({this.mode = SendMode.text, this.text = '', this.fileName, this.fileBytes,
      this.delayMs = CimbarSpec.defaultDelayMs, this.busy = false, this.error});

  SendState copyWith({SendMode? mode, String? text, String? fileName, Uint8List? fileBytes,
      int? delayMs, bool? busy, String? error, bool clearError = false}) => SendState(
        mode: mode ?? this.mode, text: text ?? this.text, fileName: fileName ?? this.fileName,
        fileBytes: fileBytes ?? this.fileBytes, delayMs: delayMs ?? this.delayMs, busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error));

  bool get hasInput => mode == SendMode.text ? text.isNotEmpty : fileBytes != null;
}

/// Upper bound on source frames before compression (name of a text message is 27 bytes).
int estimateFrames(SendState s, {required bool encrypted}) {
  final nameLen = s.mode == SendMode.text ? 27 : (s.fileName?.length ?? 0) * 4;
  final bytes = s.mode == SendMode.text ? utf8Length(s.text) : (s.fileBytes?.length ?? 0);
  final framed = 4 + 4 + nameLen + bytes + (encrypted ? 48 : 0);
  return (framed + CimbarSpec.fileBytesPerFrame - 1) ~/ CimbarSpec.fileBytesPerFrame;
}

int utf8Length(String s) => const Utf8Codec().encoder.convert(s).length;

final sendControllerProvider = StateNotifierProvider<SendController, SendState>((ref) => SendController());

class SendController extends StateNotifier<SendState> {
  SendController({EncodedPayload Function(SendRequest)? encoder,
      Future<void> Function(String name, Uint8List gif)? shareGifBytes, DateTime Function()? now})
      : _encoder = encoder,
        _shareGifBytes = shareGifBytes ?? _shareViaSheet,
        _now = now ?? DateTime.now,
        super(const SendState());

  final EncodedPayload Function(SendRequest)? _encoder;
  final Future<void> Function(String, Uint8List) _shareGifBytes;
  final DateTime Function() _now;

  void setMode(SendMode m) => state = state.copyWith(mode: m, clearError: true);
  void setText(String t) => state = state.copyWith(text: t, clearError: true);
  void setFile(String name, Uint8List bytes) => state = state.copyWith(fileName: name, fileBytes: bytes, clearError: true);
  void setDelay(int ms) => state = state.copyWith(delayMs: ms);

  SendRequest? _request(String passphrase) {
    if (!state.hasInput) return null;
    return state.mode == SendMode.text
        ? SendRequest(TextMessage.fileName(_now()), Uint8List.fromList(const Utf8Codec().encode(state.text)), passphrase)
        : SendRequest(state.fileName!, state.fileBytes!, passphrase);
  }

  Future<EncodedPayload?> encode(String passphrase, {required int cap}) async {
    final req = _request(passphrase);
    if (req == null) {
      state = state.copyWith(error: 'empty');
      return null;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final enc = _encoder;
      final p = enc != null ? enc(req) : await Isolate.run(() => encodeRequest(req));
      if (p.total > cap) {
        state = state.copyWith(busy: false, error: 'tooLarge:${p.total}:$cap');
        return null;
      }
      state = state.copyWith(busy: false);
      return p;
    } catch (e) {
      state = state.copyWith(busy: false, error: 'failed:$e');
      return null;
    }
  }

  Future<void> shareGif(String passphrase) async {
    final p = await encode(passphrase, cap: maxGifFrames);
    if (p == null) return;
    state = state.copyWith(busy: true);
    try {
      final delay = state.delayMs;
      final gif = _encoder != null ? buildGif(p, delay) : await Isolate.run(() => buildGif(p, delay));
      final base = state.mode == SendMode.text ? TextMessage.fileName(_now()) : state.fileName!;
      final stem = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
      await _shareGifBytes('$stem.gif', gif);
      state = state.copyWith(busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, error: 'failed:$e');
    }
  }

  static Future<void> _shareViaSheet(String name, Uint8List gif) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${FileService.safeBasename(name)}');
    await f.writeAsBytes(gif);
    await FileService.shareFile(f.path);
  }
}
```

(Add `import 'dart:convert';` for `Utf8Codec`. A file name's UTF-8 length is bounded by `4 × length`, which keeps the estimate an upper bound without encoding the name.)

- [ ] **Step 4: Run controller tests — expect pass.**

- [ ] **Step 5: Strings** (five ARB files; `sendEstimate`, `sendTooLarge`, `sendFailed`, `presentSource`, `presentRepair` carry placeholders declared in `app_en.arb`'s `@` metadata):

| key | en | ru | uk | tr | ka |
|---|---|---|---|---|---|
| `tabSend` | Send | Отправить | Надіслати | Gönder | გაგზავნა |
| `sendModeText` | Text | Текст | Текст | Metin | ტექსტი |
| `sendModeFile` | File | Файл | Файл | Dosya | ფაილი |
| `sendTextHint` | Type or paste text… | Введите или вставьте текст… | Введіть або вставте текст… | Metin yazın veya yapıştırın… | აკრიფეთ ან ჩასვით ტექსტი… |
| `sendEstimate` | {size} · at most {frames} frames | {size} · не более {frames} кадров | {size} · не більше {frames} кадрів | {size} · en fazla {frames} kare | {size} · მაქს. {frames} კადრი |
| `sendFrameDelay` | Frame delay | Задержка кадра | Затримка кадру | Kare gecikmesi | კადრის დაყოვნება |
| `sendPresent` | Present on screen | Показать на экране | Показати на екрані | Ekranda göster | ეკრანზე ჩვენება |
| `sendShareGif` | Share GIF | Поделиться GIF | Поділитися GIF | GIF paylaş | GIF-ის გაზიარება |
| `sendEmpty` | Type some text or choose a file first. | Сначала введите текст или выберите файл. | Спочатку введіть текст або виберіть файл. | Önce metin yazın veya dosya seçin. | ჯერ შეიყვანეთ ტექსტი ან აირჩიეთ ფაილი. |
| `sendTooLarge` | Too large: {frames} frames (limit {max}). | Слишком много: {frames} кадров (лимит {max}). | Забагато: {frames} кадрів (ліміт {max}). | Çok büyük: {frames} kare (sınır {max}). | ზედმეტად დიდია: {frames} კადრი (ლიმიტი {max}). |
| `sendFailed` | Encoding failed: {error} | Ошибка кодирования: {error} | Помилка кодування: {error} | Kodlama başarısız: {error} | კოდირება ვერ მოხერხდა: {error} |
| `presentSource` | Frame {i} of {n} | Кадр {i} из {n} | Кадр {i} з {n} | Kare {i} / {n} | კადრი {i} / {n} |
| `presentRepair` | Repair frame {r} | Кадр восстановления {r} | Кадр відновлення {r} | Onarım karesi {r} | აღდგენის კადრი {r} |

`flutter gen-l10n`.

- [ ] **Step 6: Screen** `app/lib/features/send/send_screen.dart` — a `ConsumerStatefulWidget` following `import_screen.dart`'s layout (`Scaffold` + `AppBar(title: Text(l10n.tabSend), actions: const [LanguageSwitcherButton()])` + `ListView(padding: EdgeInsets.all(16))`):
  - `SegmentedButton<SendMode>` (`sendModeText` / `sendModeFile`) → `setMode`.
  - Text mode: `TextField(key: Key('sendText'), controller: _text, maxLines: 10, minLines: 4, decoration: InputDecoration(hintText: l10n.sendTextHint, border: OutlineInputBorder()), onChanged: controller.setText)`.
  - File mode: `FilePickerZone(onTap: _pickFile, selectedFileName: state.fileName)`, `_pickFile` = `FilePicker.pickFiles(withData: true)` → `setFile(name, bytes)`.
  - `Text(l10n.sendEstimate(size, estimateFrames(state, encrypted: _pass.text.isNotEmpty)))` when `state.hasInput`.
  - `PassphraseField(controller: _pass)`.
  - Delay: `DropdownButton<int>` over `CimbarSpec.delayOptionsMs` labelled `sendFrameDelay` → `setDelay`.
  - Two buttons, enabled when `state.hasInput && !state.busy`: `FilledButton.icon(icon: Icon(Icons.slideshow), label: Text(l10n.sendPresent), onPressed: _present)` and `OutlinedButton.icon(icon: Icon(Icons.gif_box_outlined), label: Text(l10n.sendShareGif), onPressed: () => controller.shareGif(_pass.text))`.
  - `state.busy` → `LinearProgressIndicator`; `state.error` → an error `Text` mapping `'empty'` → `sendEmpty`, `'tooLarge:f:m'` → `sendTooLarge(f, m)`, `'failed:x'` → `sendFailed(x)`.
  - `_present()`: `final p = await controller.encode(_pass.text, cap: maxSendFrames); if (p == null || !mounted) return; await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PresentScreen(payload: p, delayMs: state.delayMs)));` — `PresentScreen` arrives in Task 10; until then leave `_present` showing a `SnackBar` with `l10n.sendPresent` and add the push in Task 10.

- [ ] **Step 7: Route and tab.** In `app.dart` add the `/send` `GoRoute` (NoTransitionPage, `SendScreen()`) first in the shell's routes; `initialLocation` stays `/import`. In `app_shell.dart`: `static const _tabs = ['/send', '/import', '/camera', '/files', '/settings'];` and prepend `NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: l10n.tabSend)`.

- [ ] **Step 8: Widget test** `app/test/features/send_screen_test.dart`: pump `SendScreen` inside `ProviderScope(overrides: [sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(1)))])` + the localized `MaterialApp` host from `result_card_test.dart`; assert the Present/Share GIF buttons are disabled with an empty text box, enabled after `enterText(find.byKey(Key('sendText')), 'hi')`, and that switching to File shows the picker zone and disables the buttons again (no file). Also update `camera_navigation_test.dart` if it taps tabs by index.

- [ ] **Step 9: Run.** `flutter analyze && sh tests/run_all.sh` → clean / all pass.

- [ ] **Step 10: Commit.**

```bash
git add app/lib/core/encode/send_jobs.dart app/lib/features/send app/lib/app.dart app/lib/shared/widgets/app_shell.dart app/lib/l10n app/test/features
git commit -m "feat(app): Send tab — text or file, Share GIF"
```

---

### Task 10: Flutter — Present screen

**Files:**
- Modify: `app/pubspec.yaml`, `app/pubspec.lock` (add `wakelock_plus`, `screen_brightness`)
- Create: `app/lib/features/send/present_sequencer.dart`
- Create: `app/lib/features/send/screen_controls.dart`
- Create: `app/lib/features/send/present_screen.dart`
- Modify: `app/lib/features/send/send_screen.dart` (`_present` pushes `PresentScreen`)
- Create: `app/test/features/present_sequencer_test.dart`, `app/test/features/present_screen_test.dart`

**Interfaces:**
- Consumes: `EncodedPayload`, `FrameBuilder.sourceFrame/nextRepair`, `CellGrid.cells`, `FrameRaster.render/toRgba`, `CimbarSpec.codingMaxFrames`.
- Produces:
  - `class PresentStep { final Uint8List data; final bool repair; final int index; }` (`index` = seq for a source frame, r for a repair frame)
  - `class PresentSequencer { PresentSequencer(EncodedPayload p); PresentStep next(); }` — source `0..N−1` once, then repair frames forever from `r = 0` (skipping degenerate ids); when `N == 1` or `N > codingMaxFrames` it loops the source frames.
  - `abstract class ScreenControls { Future<void> keepAwake(bool on); Future<void> maxBrightness(); Future<void> restoreBrightness(); }` and `class PluginScreenControls implements ScreenControls` (wakelock_plus + screen_brightness).
  - `PresentScreen({required EncodedPayload payload, required int delayMs, ScreenControls? controls})`.

- [ ] **Step 1: Dependencies.** `cd app && flutter pub add wakelock_plus screen_brightness`, then `flutter pub get` (Flutter 3.44.8). Build the release APK's merged manifest and check permissions: `flutter build apk --release --split-per-abi --target-platform android-arm64` then `grep -o 'uses-permission[^>]*' build/app/outputs/logs/manifest-merger-release-report.txt | sort -u`. Expected: no permission besides `CAMERA` once `AndroidManifest.xml`'s existing `tools:node="remove"` entries apply; `flutter test test/android_manifest_test.dart` passes. Also check that neither package pulls `com.google.android.gms`/`firebase` (`grep -i -E 'gms|firebase' pubspec.lock build/app/outputs/logs/manifest-merger-release-report.txt` → nothing). If a permission appears that the app doesn't need (e.g. `WAKE_LOCK`), add a `tools:node="remove"` entry beside the existing ones; if a plugin needs Play Services, drop it and implement `ScreenControls` with a `MethodChannel('cimbar/screen')` in `MainActivity.kt` (`window.addFlags(FLAG_KEEP_SCREEN_ON)`, `window.attributes.screenBrightness`) and `AppDelegate.swift` (`UIApplication.shared.isIdleTimerDisabled`, `UIScreen.main.brightness`).

- [ ] **Step 2: Failing sequencer test** `app/test/features/present_sequencer_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';
import 'package:cimbar_scanner/features/send/present_sequencer.dart';

void main() {
  test('source frames once, then repair frames forever', () {
    final p = PayloadEncoder.encode(name: 'n.txt', bytes: Uint8List(9000), allowCompression: false);
    final seq = PresentSequencer(p);
    final steps = List.generate(p.total + 5, (_) => seq.next());
    expect([for (final s in steps.take(p.total)) s.repair], everyElement(isFalse));
    expect([for (final s in steps.take(p.total)) s.index], List.generate(p.total, (i) => i));
    expect([for (final s in steps.skip(p.total)) s.repair], everyElement(isTrue));
  });

  test('a receiver that missed every source frame still completes from repair frames', () {
    final bytes = Uint8List.fromList(List.generate(9000, (i) => i * 7 & 0xFF));
    final p = PayloadEncoder.encode(name: 'n.bin', bytes: bytes, allowCompression: false);
    final seq = PresentSequencer(p);
    for (var i = 0; i < p.total; i++) {
      seq.next(); // missed
    }
    final asm = RatelessAssembler();
    while (!asm.isComplete) {
      asm.add(seq.next().data);
    }
    expect(decodeFramedPayload(asm.framedData(), '').fileBytes, bytes);
  });

  test('a one-frame file loops its source frame', () {
    final p = PayloadEncoder.encode(name: 'a.txt', bytes: Uint8List.fromList([65]));
    final seq = PresentSequencer(p);
    expect([for (var i = 0; i < 3; i++) seq.next().repair], [false, false, false]);
  });
}
```

- [ ] **Step 3: Run — expect failure. Implement** `present_sequencer.dart`:

```dart
import 'dart:typed_data';

import '../../core/encode/frame_builder.dart';
import '../../core/encode/payload_encoder.dart';
import '../../core/format/cimbar_spec.dart';

class PresentStep {
  final Uint8List data;
  final bool repair;
  final int index;
  const PresentStep(this.data, this.repair, this.index);
}

/// Present-mode order (v2.1 spec, as the web app's present mode): the N
/// source frames once, then repair frames r = 0, 1, 2, … without end. With no
/// repair frames available (N == 1, or N above the coding cap) the source pass loops.
class PresentSequencer {
  PresentSequencer(this.payload);

  final EncodedPayload payload;
  int _source = 0;
  int _r = 0;
  bool _sourcesDone = false;

  bool get _coded => payload.total > 1 && payload.total <= CimbarSpec.codingMaxFrames;

  PresentStep next() {
    if (!_sourcesDone) {
      final s = _source++;
      if (_source == payload.total) {
        if (_coded) {
          _sourcesDone = true;
        } else {
          _source = 0;
        }
      }
      return PresentStep(FrameBuilder.sourceFrame(payload, s), false, s);
    }
    final rf = FrameBuilder.nextRepair(payload, _r);
    _r = rf.nextR;
    return PresentStep(rf.data, true, rf.r);
  }
}
```

Run — pass.

- [ ] **Step 4: Screen controls** `screen_controls.dart`:

```dart
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

abstract class ScreenControls {
  Future<void> keepAwake(bool on);
  Future<void> maxBrightness();
  Future<void> restoreBrightness();
}

/// App-level only: screen_brightness changes this window's brightness, not the
/// system setting, so no WRITE_SETTINGS permission is involved.
class PluginScreenControls implements ScreenControls {
  const PluginScreenControls();
  @override
  Future<void> keepAwake(bool on) => on ? WakelockPlus.enable() : WakelockPlus.disable();
  @override
  Future<void> maxBrightness() => ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
  @override
  Future<void> restoreBrightness() => ScreenBrightness.instance.resetApplicationScreenBrightness();
}
```

(Check the installed `screen_brightness` version's method names in its README — older versions use `ScreenBrightness().setScreenBrightness` / `resetScreenBrightness`; use the app-level ones.)

- [ ] **Step 5: Failing screen test** `app/test/features/present_screen_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/features/send/present_screen.dart';
import 'package:cimbar_scanner/features/send/screen_controls.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';

class FakeControls implements ScreenControls {
  final log = <String>[];
  @override
  Future<void> keepAwake(bool on) async => log.add('awake:$on');
  @override
  Future<void> maxBrightness() async => log.add('max');
  @override
  Future<void> restoreBrightness() async => log.add('restore');
}

void main() {
  final p = PayloadEncoder.encode(name: 'n.txt', bytes: Uint8List(5000), allowCompression: false);

  Future<FakeControls> open(WidgetTester tester) async {
    final c = FakeControls();
    // Real decodeImageFromPixels never completes inside the fake-async test
    // zone; make one tiny image outside it and hand out clones.
    final img = (await tester.runAsync(() => createTestImage(width: 1, height: 1)))!;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (ctx) => TextButton(
        onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => PresentScreen(payload: p, delayMs: 100, controls: c,
                toImage: (_) async => img.clone()))),
        child: const Text('go'))),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    return c;
  }

  testWidgets('keeps the screen awake and bright while shown, restores on back — Review Focus 4', (tester) async {
    final c = await open(tester);
    expect(c.log, containsAll(['awake:true', 'max']));
    expect(find.textContaining('1'), findsWidgets); // frame counter
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(c.log.sublist(c.log.length - 2), containsAll(['awake:false', 'restore']));
  });

  testWidgets('backgrounding pauses and restores; resuming re-applies', (tester) async {
    final c = await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(c.log.last, 'restore');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.log, containsAllInOrder(['restore', 'awake:true', 'max']));
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('advances frames on the delay', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('presentCounter')), findsOneWidget);
    final first = (tester.widget(find.byKey(const Key('presentCounter'))) as Text).data;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 50));
    final second = (tester.widget(find.byKey(const Key('presentCounter'))) as Text).data;
    expect(second, isNot(first));
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
```

(`PresentScreen.toImage` defaults to the real `decodeImageFromPixels`; the tests inject a pre-made image, which is why the parameter exists.)

- [ ] **Step 6: Implement** `present_screen.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/encode/cell_grid.dart';
import '../../core/encode/frame_raster.dart';
import '../../core/encode/payload_encoder.dart';
import '../../core/format/cimbar_spec.dart';
import '../../l10n/generated/app_localizations.dart';
import 'present_sequencer.dart';
import 'screen_controls.dart';

Future<ui.Image> _rgbaToImage(Uint8List rgba) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, CimbarSpec.framePx, CimbarSpec.framePx, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

class PresentScreen extends StatefulWidget {
  final EncodedPayload payload;
  final int delayMs;
  final ScreenControls controls;
  final Future<ui.Image> Function(Uint8List rgba) toImage;
  const PresentScreen({super.key, required this.payload, required this.delayMs,
      ScreenControls? controls, Future<ui.Image> Function(Uint8List rgba)? toImage})
      : controls = controls ?? const PluginScreenControls(),
        toImage = toImage ?? _rgbaToImage;
  @override
  State<PresentScreen> createState() => _PresentScreenState();
}

class _PresentScreenState extends State<PresentScreen> with WidgetsBindingObserver {
  late final PresentSequencer _seq = PresentSequencer(widget.payload);
  ui.Image? _image;
  PresentStep? _step;
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    _running = true;
    await widget.controls.keepAwake(true);
    await widget.controls.maxBrightness();
    _tick();
  }

  void _stop() {
    _running = false;
    _timer?.cancel();
    widget.controls.keepAwake(false);
    widget.controls.restoreBrightness();
  }

  // Build the next frame, show it, schedule the following one. A frame that
  // takes longer than the delay to build simply stays on screen longer.
  Future<void> _tick() async {
    if (!_running) return;
    final sw = Stopwatch()..start();
    final step = _seq.next();
    final img = await widget.toImage(FrameRaster.toRgba(FrameRaster.render(CellGrid.cells(step.data))));
    if (!mounted || !_running) {
      img.dispose();
      return;
    }
    final old = _image;
    setState(() {
      _image = img;
      _step = step;
    });
    old?.dispose();
    final wait = widget.delayMs - sw.elapsedMilliseconds;
    _timer = Timer(Duration(milliseconds: wait > 0 ? wait : 0), _tick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_running) _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_running) _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_running) _stop();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final step = _step;
    final label = step == null
        ? ''
        : step.repair
            ? l10n.presentRepair(step.index)
            : l10n.presentSource(step.index + 1, widget.payload.total);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: _image == null
                    ? const SizedBox.shrink()
                    // FilterQuality.none: nearest-neighbour scaling keeps tile edges hard.
                    : RawImage(image: _image, fit: BoxFit.contain, filterQuality: FilterQuality.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(label, key: const Key('presentCounter'), style: const TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    );
  }
}
```

`presentRepair`/`presentSource` take `int` placeholders — declare them `"type": "int"` in `app_en.arb`.

In `send_screen.dart` replace the temporary `_present` body with the root-navigator push from Task 9 Step 6.

- [ ] **Step 7: Run.** `flutter test test/features/present_sequencer_test.dart test/features/present_screen_test.dart && flutter analyze && sh tests/run_all.sh`.

- [ ] **Step 8: Device smoke test** (Android device or emulator): Send → Text → "hello" → Present → frames animate full-screen at full brightness; second phone's Live Scan decodes it and shows the text with Copy; Back restores brightness. Note results in the commit message; if no device is available, say so there.

- [ ] **Step 9: Commit.**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/features/send app/test/features app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(app): Present screen — source then endless repair frames, screen kept awake and bright"
```

---

### Task 11: Documentation and store text

**Files:**
- Modify: `CLAUDE.md`, `app/CLAUDE.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` (§4.1 note), `docs/superpowers/specs/2026-10-01-text-transfer-and-mobile-encode-design.md` (Status line), `fastlane/metadata/android/{en-US,ru-RU,uk,tr-TR,ka-GE}/full_description.txt`, `web-app/index.html` (About tab), `web-app/i18n.js` (any About keys touched)

- [ ] **Step 1: `CLAUDE.md`.** Encoding pipeline: "File **or typed text (`message-YYYYMMDD-HHMMSS.txt`)** → build container → …". Decoding pipeline: "… → File, **or the text view when `isTextMessage`**". Module list: `cimbar.js` gains `isTextMessage`/`decodeTextMessage`/`textMessageName`. Add an "Interoperability" paragraph: the text convention, `test-data/text-message.json` as the shared contract, `dart_text` golden written by the Dart encoder. Test table: add `tests/test_text_message.js`; update counts ("twenty-one Node tests" → twenty-two in `run_all.sh`'s description and `test_pipeline.py` line; `test_browser_load.js` still loads twenty-one page scripts — unchanged). The Android app is no longer decode-only: update the Architecture `app/` bullet ("decodes … and encodes text and files: Send tab, Present, Share GIF").

- [ ] **Step 2: `app/CLAUDE.md`.** A section on `lib/core/encode/` (unit table from the spec §5, parity tests, `tool/gen_dart_goldens.dart`), the Send tab and Present screen (root navigator, wakelock/brightness, caps 4096 / 500), and the `CryptoService.encrypt` fix (salt/iv only injected by tests).

- [ ] **Step 3: `CHANGELOG.md`** under `## [Unreleased]`:

```markdown
### Added
- Send text, not just files: the web app's Encode tab has a Text mode, and every receiver (web, Android, iOS) shows a received text message with Copy and Save as .txt instead of a bare file.
- Android/iOS can now send: a new Send tab encodes text or a file and shows it full screen (Present) or shares an animated GIF.

### Fixed
- `CryptoService.encrypt` drew its salt and IV from a 256-value seed space; it now uses the platform CSPRNG. Only tests used it before this release.
```

- [ ] **Step 4: Store text.** In each locale's `full_description.txt` add one sentence (≤ 4000 chars total): en "Send text or files from your phone too: type a message or pick a file, then show it on screen for another device to scan, or share it as an animated GIF." ru "Отправляйте текст или файлы и с телефона: введите сообщение или выберите файл, покажите его на экране для сканирования другим устройством или поделитесь анимированным GIF." uk "Надсилайте текст або файли й з телефона: введіть повідомлення або виберіть файл, покажіть його на екрані для сканування іншим пристроєм чи поділіться анімованим GIF." tr "Telefonunuzdan da metin veya dosya gönderin: bir mesaj yazın ya da dosya seçin, başka bir cihazın taraması için ekranda gösterin veya hareketli GIF olarak paylaşın." ka "გააგზავნეთ ტექსტი ან ფაილები ტელეფონიდანაც: შეიყვანეთ შეტყობინება ან აირჩიეთ ფაილი, აჩვენეთ ეკრანზე სხვა მოწყობილობით დასასკანერებლად ან გააზიარეთ ანიმირებული GIF-ის სახით." Then `python3 tools/validate_store_metadata.py` → OK.

- [ ] **Step 5: About tab.** Add one sentence to the web About text (and its five translations in `i18n.js`) that text can be sent from the Encode tab's Text mode and appears as text on the receiving side.

- [ ] **Step 6: Specs.** Format spec §4.1: "A container named `*.txt` holding strict UTF-8 ≤ 1 MiB is presented as a text message — see `2026-10-01-text-transfer-and-mobile-encode-design.md` §3; nothing on the wire changes." Feature spec: `Status: Implemented (plan: docs/superpowers/plans/2026-10-01-text-transfer-and-mobile-encode.md)`.

- [ ] **Step 7: Full verification.** `cd web-app && sh tests/run_all.sh`; `cd app && flutter analyze && sh tests/run_all.sh`; `python3 tools/validate_store_metadata.py`. All green.

- [ ] **Step 8: Commit.**

```bash
git add CLAUDE.md app/CLAUDE.md CHANGELOG.md docs fastlane web-app/index.html web-app/i18n.js
git commit -m "docs: text transfer and mobile encoding"
```

---

## Manual device checklist (after Task 11, before the PR leaves draft)

Phone → phone (Present + Live Scan, text and a small file); phone Share GIF → messenger → Import on the other phone; web Text → Present → phone Live Scan; phone Present → web Live Scan (http(s) page); an encrypted text each way (passphrase typed on the receiver after the "passphrase required" prompt); iOS simulator: Send tab, Present, Share GIF sheet.
