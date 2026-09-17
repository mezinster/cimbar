// Loads the page's scripts the way a browser does — classic <script> tags in
// index.html order, sharing ONE global lexical scope, with no `module` or
// `require` — and asserts every global the inline page script uses exists.
//
// Node's tests cannot catch this class of bug on their own: each file is its
// own module there, so two files may both declare a top-level `const SPEC`
// and pass every unit test, while in the browser the second declaration is a
// SyntaxError that leaves `Cimbar` undefined. This test caught exactly that.
'use strict';
const vm = require('vm');
const fs = require('fs');
const path = require('path');

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const scripts = [...html.matchAll(/<script src="([^"]+)"><\/script>/g)].map((m) => m[1]).filter((s) => !/^https?:/.test(s));

function loadLikeABrowser() {
  const window = {};
  window.window = window;
  window.self = window;
  // Only what a browser provides that the scripts touch at load time; no
  // `module`, no `require`, no `global`.
  const ctx = vm.createContext(Object.assign(window, {
    console, Math, JSON, Error, TypeError, RangeError, Uint8Array, Uint8ClampedArray, Uint16Array, Uint32Array,
    Int32Array, Float32Array, Float64Array, ArrayBuffer, DataView, TextEncoder, TextDecoder, Promise, Map, Set, Symbol,
  }));
  const loaded = [];
  for (const src of scripts) {
    const code = fs.readFileSync(path.join(root, src), 'utf8');
    try {
      vm.runInContext(code, ctx, { filename: src });
      loaded.push(src);
    } catch (e) {
      throw new Error(`${src} failed to load in browser mode after [${loaded.join(', ')}]: ${e.constructor.name}: ${e.message}`);
    }
  }
  return window;
}

test('index.html lists the eight local scripts in dependency order', () => {
  assert(scripts.length === 8, `expected 8 local scripts, found ${scripts.length}: ${scripts.join(', ')}`);
  assert(scripts.indexOf('format-data.js') < scripts.indexOf('format.js'), 'format-data.js must precede format.js');
  assert(scripts.indexOf('format.js') < scripts.indexOf('cimbar.js'), 'format.js must precede cimbar.js');
  assert(scripts.indexOf('format.js') < scripts.indexOf('gif-encoder.js'), 'format.js must precede gif-encoder.js');
  assert(scripts[scripts.length - 1] === 'i18n.js', 'i18n.js is loaded last, right before the page script');
});

test('every script loads as a classic <script> sharing one global scope', () => {
  loadLikeABrowser();
});

test('the globals the inline page script uses are all defined', () => {
  const w = loadLikeABrowser();
  for (const g of ['ReedSolomon', 'CIMBAR_SPEC', 'CimbarFormat', 'Cimbar', 'CimbarCrypto', 'GifEncoder', 'GifDecoder', 'CimbarI18n']) {
    assert(w[g] !== undefined, `window.${g} is not defined after loading the page scripts`);
  }
  for (const fn of ['renderFrame', 'decodeFrameExact', 'encodeRSFrame', 'decodeRSFrame', 'splitIntoFrames', 'FrameAssembler', 'buildPayload', 'parsePayload']) {
    assert(typeof w.Cimbar[fn] === 'function', `Cimbar.${fn} missing`);
  }
});

(async () => {
  console.log('\ntest_browser_load.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
