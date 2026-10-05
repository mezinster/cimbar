// Shared vm harness for tests of index.html's inline page script.
// See the header of test_page_logic.js for the approach.
'use strict';
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const Fmt = require(path.join(root, 'format.js'));
const RatelessMod = require(path.join(root, 'rateless.js'));
const Core = require(path.join(root, 'cimbar.js'));
const { ReedSolomon } = require(path.join(root, 'rs.js'));

function assert(c, msg) { if (!c) throw new Error(msg); }

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

const REQUIRED_GLOBALS = ['addPhoto', 'addFrame', 'handleDecFile', 'startDecode', 'resetPhotoSession', 'finishDecode', 'isGifBytes', 'openScanner', 'closeScanner', 'setEncMode', 'encodeInput', 'updateTextInfo', 'copyText', 'saveText', 'hideTextResult', 'startEncode', 'onFileSelect'];

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
function freshPage(opts = {}) {
  function makeEl(id) {
    const el = {
      id,
      style: {}, dataset: {}, hidden: false, disabled: false, open: false,
      classList: {
        _set: new Set(),
        add(c) { this._set.add(c); },
        remove(c) { this._set.delete(c); },
        contains(c) { return this._set.has(c); },
      },
      innerHTML: '', textContent: '', value: '', scrollTop: 0,
      // log() builds a <span> and appends it; mirror the text into innerHTML
      // so tests can assert on what the user was actually told.
      appendChild(child) { if (child && child.textContent) el.innerHTML += child.textContent + '\n'; },
      addEventListener() {},
      setAttribute(k, v) { el['attr_' + k] = v; },
      showModal() { el.open = true; }, close() { el.open = false; },
      click() { el._clicked = (el._clicked || 0) + 1; },
    };
    return el;
  }
  const elements = {};
  function getEl(id) { if (!elements[id]) elements[id] = makeEl(id); return elements[id]; }

  const calls = { decrypt: 0, parsePayload: 0, anchorClicks: 0, alerts: [], confirmResult: true, confirmPrompts: [], consoleErrors: [], liveScans: [] };

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
    body: makeEl('body'),
    querySelectorAll: () => [],
    querySelector: () => null,
    documentElement: makeEl('html'),
    visibilityState: 'visible',
  };

  const sandbox = {
    // The page console.error()s every decode failure; several tests provoke
    // one deliberately, so capture instead of printing a stack mid-suite.
    console: Object.assign(Object.create(console), { error: (...a) => { calls.consoleErrors.push(a[0]); } }),
    document: documentStub,
    alert: (msg) => { calls.alerts.push(msg); },
    confirm: (msg) => { calls.confirmPrompts.push(msg); return calls.confirmResult; },
    addEventListener() {},
    Math, JSON, Uint8Array, TextEncoder, TextDecoder, Uint8ClampedArray, Promise, Error, setTimeout,
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
    navigator: opts.camera === false ? {} : { mediaDevices: { getUserMedia: async () => ({}) } },
    location: { search: '', hash: '' },
    history: {
      state: null,
      pushState(s, _t, url) { this.state = s; if (typeof url === 'string' && url[0] === '#') sandbox.location.hash = url; calls.pushes = (calls.pushes || 0) + 1; },
      replaceState(s, _t, url) { this.state = s; if (typeof url === 'string' && url[0] === '#') sandbox.location.hash = url; },
      back() { this.state = null; calls.backs = (calls.backs || 0) + 1; },
    },
    scrollTo() {},
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    Worker: class { constructor(u) { this.url = u; } },
    CimbarLiveScan: {
      LiveScan: class {
        constructor(o) { this.o = o; this.state = 'idle'; calls.liveScans.push(this); }
        async start() { this.state = 'scanning'; return true; }
        stop(reason) { if (this.state === 'stopped') return; this.state = 'stopped'; this.o.onStopped({ reason, frames: 0, accepted: 0 }); }
        async resume() { this.state = 'scanning'; return true; }
      },
    },
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
  // Tests read elements the page under test never touched (e.g. asserting
  // addFrame — unlike addPhoto — leaves 'logDec' untouched: elements['logDec']
  // must read as an untouched default, not throw). Auto-vivify on read the
  // same way getEl() does on the page's own document.getElementById() calls,
  // so a not-yet-touched id reads as a fresh default element instead of
  // undefined; an id the page DID touch is unaffected.
  const elementsView = new Proxy(elements, {
    get(target, prop) {
      if (typeof prop === 'string' && !(prop in target)) return getEl(prop);
      return target[prop];
    },
  });
  return { ctx, elements: elementsView, calls };
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

/** A frame whose body is `payload` (already length-prefixed), padded to the frame body size. */
function makeFrameWithPayload(payload, opts) {
  const bodyLen = Fmt.fileBytesPerFrame();
  assert(payload.length <= bodyLen, 'test payload too large for one frame');
  const body = new Uint8Array(bodyLen);
  body.set(payload, 0);
  const header = Fmt.encodeHeader(Object.assign({ encrypted: false, repair: false, compressed: false }, opts));
  const data = new Uint8Array(header.length + body.length);
  data.set(header, 0); data.set(body, header.length);
  return data;
}

/** A length-prefixed payload that finishDecode will see as encrypted (CB 42 magic). */
function encryptedPayload() {
  const body = new Uint8Array(4 + 16 + 12 + 8);
  body.set([0xCB, 0x42, 0x01, 0x00], 0);         // crypto.js wire magic
  return Core.withLengthPrefix(body);
}

const okResult = (data) => ({ status: 'ok', data, blocksFailed: 0, header: Fmt.decodeHeader(data) });

module.exports = { freshPage, makeFrame, makeCompletingFrame, makeFrameWithPayload, encryptedPayload, okResult, Fmt, Core, RatelessMod, ReedSolomon };
