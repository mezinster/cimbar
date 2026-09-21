// Behavioral tests for index.html's inline page script (the photo-decode
// glue: addPhoto/handleDecFile/startDecode/finishDecode/resetPhotoSession).
//
// test_browser_load.js already proves a source-level SHAPE invariant (the
// wrong-file guard exists and runs before add()) by reading the page's text.
// That catches "someone deleted the guard" but not "someone called it too
// late" or "the done flag is set after finishDecode instead of before" —
// both bugs that actually shipped and were caught only by a throwaway
// verification script during review, twice. This file is that script, kept.
//
// Approach: extend test_browser_load.js's pattern (raw script text run in a
// vm.createContext with a stubbed global surface) to the inline <script>
// block too, with a DOM stub just large enough for the functions under test.
// format.js, rateless.js and cimbar.js are the REAL modules (via require) —
// only CimbarPhoto.decode (needs real pixels; has its own test suite) and
// the browser-only APIs (createImageBitmap, canvas, Blob/URL, alert/confirm)
// are stubbed. Each test gets a FRESH vm context: photoSession/decFile are
// module-scoped `let` bindings inside the inline script with no external
// accessor, so the only way to reset them between tests is to re-run the
// script from scratch.
'use strict';
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const Fmt = require(path.join(root, 'format.js'));
const RatelessMod = require(path.join(root, 'rateless.js'));
const Core = require(path.join(root, 'cimbar.js'));
const { ReedSolomon } = require(path.join(root, 'rs.js'));

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

const INLINE_SCRIPT = (() => {
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  if (blocks.length !== 1) {
    throw new Error(
      `expected exactly one inline <script> block in index.html, found ${blocks.length} — ` +
      `this test's page-script extraction needs updating (see INLINE_SCRIPT at the top of ` +
      `test_page_logic.js), this is not a bug in the page itself`,
    );
  }
  return blocks[0][1];
})();

const REQUIRED_GLOBALS = ['addPhoto', 'handleDecFile', 'startDecode', 'resetPhotoSession', 'finishDecode', 'isGifBytes'];

/**
 * Runs the inline page script fresh in its own vm context, with a minimal
 * DOM/browser stub, and returns { ctx, elements, calls }. `ctx` is the
 * context object the script ran in: its own top-level `function` and `var`
 * declarations (addPhoto, startDecode, ...) are reachable as ctx.<name> —
 * exactly the vm behavior test_browser_load.js's loadLikeABrowser() already
 * relies on for <script src> files, extended here to the inline block.
 * `let`/`const` bindings (photoSession, decFile, t, ...) are NOT reachable
 * from outside, by design — tests observe their effects through the DOM
 * stub and through spies on the real Cimbar/RatelessAssembler collaborators
 * instead of reaching into page-private state.
 */
function freshPage() {
  function makeEl(id) {
    const el = {
      id,
      style: {},
      classList: {
        _set: new Set(),
        add(c) { this._set.add(c); },
        remove(c) { this._set.delete(c); },
        contains(c) { return this._set.has(c); },
      },
      innerHTML: '', textContent: '', value: '', scrollTop: 0,
      appendChild() {}, addEventListener() {},
      click() { el._clicked = (el._clicked || 0) + 1; },
    };
    return el;
  }
  const elements = {};
  function getEl(id) { if (!elements[id]) elements[id] = makeEl(id); return elements[id]; }

  const calls = { decrypt: 0, parsePayload: 0, anchorClicks: 0, alerts: [], confirmResult: true, confirmPrompts: [] };

  const documentStub = {
    getElementById: getEl,
    createElement(tag) {
      if (tag === 'a') {
        const a = makeEl('anchor');
        const origClick = a.click.bind(a);
        a.click = () => { calls.anchorClicks++; origClick(); };
        return a;
      }
      if (tag === 'canvas') {
        return { width: 0, height: 0, getContext: () => ({ drawImage() {}, getImageData: () => ({ width: 1, height: 1, data: new Uint8Array(4) }) }) };
      }
      return makeEl(tag);
    },
    createTextNode: () => ({}),
    addEventListener() {},
  };

  const sandbox = {
    console,
    document: documentStub,
    alert: (msg) => { calls.alerts.push(msg); },
    confirm: (msg) => { calls.confirmPrompts.push(msg); return calls.confirmResult; },
    addEventListener() {},
    Math, JSON, Uint8Array, Uint8ClampedArray, Promise, Error, setTimeout,
    Blob: class { constructor() {} },
    URL: { createObjectURL: () => 'blob://x' },
    CimbarFormat: Fmt,
    Cimbar: Object.assign({}, Core, {
      RatelessAssembler: RatelessMod.RatelessAssembler,
      parsePayload: (bytes) => { calls.parsePayload++; return { fileName: 'x.bin', fileBytes: new Uint8Array(1) }; },
    }),
    ReedSolomon,
    GifDecoder: class {},
    CimbarCrypto: { decryptBytes: async () => { calls.decrypt++; return new Uint8Array(4); } },
    CimbarCompress: { inflateBytes: async (b) => b, MAX_INFLATED: 128 * 1024 * 1024 },
    CimbarI18n: { t: (k) => k, apply: () => {} },
    CimbarPhoto: { decode: () => { throw new Error('CimbarPhoto.decode was not stubbed for this test'); } },
    createImageBitmap: async () => ({ width: 10, height: 10, close() {} }),
    innerWidth: 800, innerHeight: 600,
  };
  sandbox.window = sandbox;
  sandbox.self = sandbox;

  const ctx = vm.createContext(sandbox);
  try {
    vm.runInContext(INLINE_SCRIPT, ctx, { filename: 'index.html-inline' });
  } catch (e) {
    throw new Error(
      `the inline page script threw while loading in the test harness (${e.constructor.name}: ${e.message}) — ` +
      `either index.html's inline script structure changed in a way this stub doesn't cover (check what new ` +
      `global it touches at load time) or the page itself is genuinely broken; run ` +
      `'node tests/test_browser_load.js' first to rule out the latter`,
    );
  }
  for (const g of REQUIRED_GLOBALS) {
    if (typeof ctx[g] !== 'function') {
      throw new Error(
        `expected the inline page script to define a top-level function '${g}' (index.html) but it is ` +
        `${typeof ctx[g]} after loading — this test's extraction is stale (the function was renamed or is no ` +
        `longer a plain top-level 'function' declaration), not necessarily a bug in the page`,
      );
    }
  }
  return { ctx, elements, calls };
}

/** A syntactically valid frame: HEADER_LEN + fileBytesPerFrame() bytes, header only meaningful part. */
function makeFrame(opts) {
  const header = Fmt.encodeHeader(Object.assign({ encrypted: false, repair: false, compressed: false }, opts));
  const body = new Uint8Array(Fmt.fileBytesPerFrame());
  const data = new Uint8Array(header.length + body.length);
  data.set(header, 0); data.set(body, header.length);
  return data;
}

/** A frame whose body is a real length-prefixed payload, so finishDecode can actually complete. */
function makeCompletingFrame(opts) {
  const payload = Core.withLengthPrefix(Core.buildPayload('x.bin', new Uint8Array([1, 2, 3])));
  const bodyLen = Fmt.fileBytesPerFrame();
  assert(payload.length <= bodyLen, 'test payload too large for one frame');
  const body = new Uint8Array(bodyLen);
  body.set(payload, 0);
  const header = Fmt.encodeHeader(Object.assign({ encrypted: false, repair: false, compressed: false }, opts));
  const data = new Uint8Array(header.length + body.length);
  data.set(header, 0); data.set(body, header.length);
  return data;
}

const okResult = (data) => ({ status: 'ok', data, blocksFailed: 0, header: Fmt.decodeHeader(data) });

test('addPhoto ignores further photos once the session has completed (no repeat download) — I1', async () => {
  const { ctx, calls } = freshPage();
  // total: 1 -> the very first accepted photo completes the file.
  const data = makeCompletingFrame({ fileId: 7, seq: 0, total: 1 });
  let decodeCalls = 0;
  ctx.CimbarPhoto.decode = () => { decodeCalls++; return okResult(data); };
  ctx.toImageData = async () => ({});

  await ctx.addPhoto({});
  await ctx.addPhoto({}); // a would-be duplicate of the now-complete file
  await ctx.addPhoto({}); // and another

  assertEq(calls.anchorClicks, 1, 'the download anchor must be clicked exactly once across three photos of an already-completed file');
  assertEq(calls.parsePayload, 1, 'finishDecode must not re-run (Cimbar.parsePayload) once the session is done');
  assertEq(decodeCalls, 1, 'a completed session must not even attempt to decode later photos (early return before CimbarPhoto.decode)');
});

test('startDecode resets a live photo session before doing anything else, even with no GIF staged — I2 direction 2', async () => {
  // Sub-case A: no GIF ever staged (decFile stays null) — this is the exact
  // ordering bug: an early "if (!decFile) return" placed before
  // resetPhotoSession() would never reach the reset.
  {
    const { ctx, elements, calls } = freshPage();
    const data = makeFrame({ fileId: 3, seq: 0, total: 2 }); // total:2 -> stays live after one frame
    ctx.CimbarPhoto.decode = () => okResult(data);
    ctx.toImageData = async () => ({});

    await ctx.addPhoto({});
    assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'setup: the photo session must be live before this test is meaningful');

    await ctx.startDecode();
    assertEq(calls.alerts[0], 'selectGifFirst', 'setup: startDecode must still hit its own no-file guard in this sub-case');
    assertEq(elements['photoStartOverBtn'].style.display, 'none', 'startDecode must reset a live photo session even when it has no GIF to decode');
  }

  // Sub-case B: a real GIF gets staged afterward and startDecode actually
  // proceeds — the reset must have already happened by the time decoding starts.
  {
    const { ctx, elements } = freshPage();
    const data = makeFrame({ fileId: 3, seq: 0, total: 2 });
    ctx.CimbarPhoto.decode = () => okResult(data);
    ctx.toImageData = async () => ({});
    await ctx.addPhoto({});
    assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'setup: the photo session must be live before this test is meaningful');

    const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
    const gifFile = { name: 'foo.gif', size: 8, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }), arrayBuffer: async () => gifBytes.buffer };
    await ctx.handleDecFile(gifFile); // stages decFile via the GIF branch
    assertEq(elements['photoStartOverBtn'].style.display, 'none', 'staging a GIF must already have reset the photo session');
  }
});

test("choosing a photo clears a previously staged GIF's decFile and pill — I2 direction 1", async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.CimbarPhoto.decode = () => ({ status: 'notLocated', data: null, blocksFailed: 0, header: null });
  ctx.toImageData = async () => ({});

  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  const gifFile = { name: 'foo.gif', size: 12345, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }) };
  await ctx.handleDecFile(gifFile);
  assert(elements['pillDec'].classList.contains('show'), 'setup: staging a GIF must show its pill');

  const photoBytes = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]); // not GIF magic
  const photoFile = { name: 'photo.jpg', size: 999, slice: () => ({ arrayBuffer: async () => photoBytes.buffer }) };
  await ctx.handleDecFile(photoFile);
  assert(!elements['pillDec'].classList.contains('show'), "choosing a photo must hide the stale GIF pill (still showing it means decFile's UI wasn't cleared)");

  // Prove decFile itself, not just the pill, was cleared: startDecode alerts
  // and returns immediately only when decFile is falsy.
  await ctx.startDecode();
  assertEq(calls.alerts[calls.alerts.length - 1], 'selectGifFirst', 'choosing a photo must clear decFile itself, not just its pill');
});

test('declining the wrong-file prompt leaves the assembler untouched and never calls add() on the foreign frame', async () => {
  const { ctx, calls } = freshPage();

  // Spy on the REAL RatelessAssembler.prototype.add (shared with the page's
  // Cimbar.RatelessAssembler — same class object, since both come from the
  // one required rateless.js module) so we can assert it is not called for
  // the declined frame, and read .rank off the exact instance the page
  // built, without needing to reach into the page-private `photoSession`.
  const proto = RatelessMod.RatelessAssembler.prototype;
  const originalAdd = proto.add;
  const addCalls = [];
  proto.add = function (...args) { addCalls.push({ instance: this, args }); return originalAdd.apply(this, args); };
  try {
    const frameA = makeFrame({ fileId: 1, seq: 0, total: 2 });
    const frameB = makeFrame({ fileId: 2, seq: 0, total: 3 }); // a different file entirely
    let which = 'A';
    ctx.CimbarPhoto.decode = () => okResult(which === 'A' ? frameA : frameB);
    ctx.toImageData = async () => ({});

    await ctx.addPhoto({}); // accepts frame A -> rank 1, fileId 1
    assertEq(addCalls.length, 1, 'setup: the first photo must reach add()');
    const asm = addCalls[0].instance;
    assertEq(asm.rank, 1, 'setup: the first frame must be accepted');

    calls.confirmResult = false; // user declines "discard progress and start over?"
    which = 'B';
    await ctx.addPhoto({}); // a photo of a DIFFERENT file

    assert(calls.confirmPrompts.length >= 1, 'the wrong-file confirm() prompt must have been shown');
    assertEq(addCalls.length, 1, 'declining the wrong-file prompt must NOT call add() on the foreign frame (this is the guard\'s entire purpose)');
    assertEq(asm.rank, 1, 'declining the wrong-file prompt must leave the original assembler\'s rank unchanged');
    assertEq(asm.fileId, 1, 'declining the wrong-file prompt must leave the original assembler bound to the original fileId');
  } finally {
    proto.add = originalAdd; // restore — RatelessAssembler is a module-cached singleton shared across this file's tests
  }
});

(async () => {
  console.log('\ntest_page_logic.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
