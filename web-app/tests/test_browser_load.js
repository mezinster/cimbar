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

// Crude source-level extraction of one top-level function's body from the
// inline page script, by brace counting from its first `{`. Good enough for
// our own controlled source (no braces inside string/template literals in
// the functions this is used on); not a general JS parser.
function extractFunctionBody(src, name) {
  const m = src.match(new RegExp('(?:async\\s+)?function\\s+' + name + '\\s*\\('));
  if (!m) return null;
  const start = src.indexOf('{', m.index);
  if (start < 0) return null;
  let depth = 0;
  for (let j = start; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (depth === 0) return src.slice(start, j + 1); }
  }
  return null;
}

function loadLikeABrowser() {
  const window = {};
  window.window = window;
  window.self = window;
  // Only what a browser provides that the scripts touch at load time; no
  // `module`, no `require`, no `global`.
  const ctx = vm.createContext(Object.assign(window, {
    console, Math, JSON, Error, TypeError, RangeError, Uint8Array, Uint8ClampedArray, Uint16Array, Uint32Array,
    Int32Array, Float32Array, Float64Array, ArrayBuffer, DataView, TextEncoder, TextDecoder, Promise, Map, Set, Symbol,
    Blob: undefined, Response: undefined, CompressionStream: undefined, DecompressionStream: undefined,
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

test('index.html lists the nineteen local scripts in dependency order', () => {
  assert(scripts.length === 19, `expected 19 local scripts, found ${scripts.length}: ${scripts.join(', ')}`);
  assert(scripts.indexOf('format-data.js') < scripts.indexOf('format.js'), 'format-data.js must precede format.js');
  assert(scripts.indexOf('format.js') < scripts.indexOf('cimbar.js'), 'format.js must precede cimbar.js');
  assert(scripts.indexOf('format.js') < scripts.indexOf('gif-encoder.js'), 'format.js must precede gif-encoder.js');
  assert(scripts.indexOf('rateless.js') < scripts.indexOf('cimbar.js'), 'rateless.js must precede cimbar.js');
  // photo decode chain (Task 8): each of the eight support modules loads
  // after format.js (they all consume CimbarFormat) and before
  // photo-decoder.js, which composes all eight plus rs.js/cimbar.js.
  for (const mod of ['rgb-buffer.js', 'luma-plane.js', 'homography.js', 'finder-locator.js',
                      'white-point.js', 'cell-sampler.js', 'cell-classifier.js', 'drift-solver.js']) {
    assert(scripts.indexOf('format.js') < scripts.indexOf(mod), `format.js must precede ${mod}`);
    assert(scripts.indexOf(mod) < scripts.indexOf('photo-decoder.js'), `${mod} must precede photo-decoder.js`);
  }
  assert(scripts.indexOf('rs.js') < scripts.indexOf('photo-decoder.js'), 'rs.js must precede photo-decoder.js');
  assert(scripts.indexOf('cimbar.js') < scripts.indexOf('photo-decoder.js'), 'cimbar.js must precede photo-decoder.js');
  assert(scripts.indexOf('photo-decoder.js') < scripts.indexOf('i18n.js'), 'photo-decoder.js must precede i18n.js');
  assert(scripts[scripts.length - 1] === 'i18n.js', 'i18n.js is loaded last, right before the page script');
});

test('every script loads as a classic <script> sharing one global scope', () => {
  loadLikeABrowser();
});

test('the globals the inline page script uses are all defined', () => {
  const w = loadLikeABrowser();
  for (const g of ['ReedSolomon', 'CIMBAR_SPEC', 'CimbarFormat', 'CimbarRateless', 'Cimbar', 'CimbarCrypto', 'CimbarCompress', 'GifEncoder', 'GifDecoder',
                    'CimbarRgbBuffer', 'CimbarLumaPlane', 'CimbarHomography', 'CimbarFinderLocator', 'CimbarWhitePoint', 'CimbarCellSampler', 'CimbarCellClassifier', 'CimbarDriftSolver', 'CimbarPhoto',
                    'CimbarI18n']) {
    assert(w[g] !== undefined, `window.${g} is not defined after loading the page scripts`);
  }
  for (const fn of ['renderFrame', 'decodeFrameExact', 'encodeRSFrame', 'decodeRSFrame', 'splitIntoFrames', 'repairFrame', 'frameBodies', 'gifRepairCount', 'RatelessAssembler', 'buildPayload', 'parsePayload']) {
    assert(typeof w.Cimbar[fn] === 'function', `Cimbar.${fn} missing`);
  }
  // CimbarPhoto is deliberately exported as the class itself (call shape
  // CimbarPhoto.decode(...)), unlike every sibling module which exports an
  // API object — do not normalise this asymmetry away.
  assert(typeof w.CimbarPhoto.decode === 'function', 'CimbarPhoto.decode missing');
});

test('addPhoto compares a decoded fileId against the assembler before add() (wrong-file guard)', () => {
  // This is a source-level invariant, not a behavioral one: there is no DOM
  // harness in this repo for index.html's inline script, so this reads the
  // page's own source rather than executing it. It is crude (brace-counted
  // function extraction, regex over the body) and will need updating if
  // addPhoto is refactored — that is the right trade for an invariant whose
  // silent failure destroys a user's accumulated photo progress with no
  // error message at all (see rateless.js:104 and CLAUDE.md's rateless.js
  // description: "resets the entire collection when a frame carries a
  // different fileId" — harmless for a GIF, one file, one fileId, but
  // destructive across a multi-photo session).
  const body = extractFunctionBody(html, 'addPhoto');
  assert(body, 'addPhoto() not found in index.html — this test (and the wrong-file guard it checks for) needs updating if the photo path was renamed or restructured');

  const decodeIdx = body.search(/CimbarFormat\.decodeHeader\(/);
  assert(decodeIdx >= 0,
    'addPhoto must decode the frame header itself (CimbarFormat.decodeHeader) before handing the frame ' +
    'to the assembler. Without this, there is no way to detect a foreign fileId before rateless.js\'s ' +
    'add() silently RESETS the whole collection — discarding every photo the user has taken so far — ' +
    'the moment a stray or wrong photo is added.');

  // Looks for two DIFFERENT `.fileId` reads compared with !==, e.g.
  // `photoSession.asm.fileId !== null && h.fileId !== photoSession.asm.fileId`.
  const guardIdx = body.search(/\.fileId\s*!==\s*null\s*&&[\s\S]{0,120}?\.fileId\s*!==[\s\S]{0,120}?\.fileId/);
  assert(guardIdx >= 0,
    'addPhoto must compare the newly decoded header\'s fileId against the in-progress assembler\'s ' +
    'fileId (something like `photoSession.asm.fileId !== null && h.fileId !== photoSession.asm.fileId`) ' +
    'before calling add(). This is the ONLY thing standing between a wrong photo and rateless.js ' +
    'silently wiping a user\'s accumulated frames (rateless.js:104) — deleting the guard breaks no other ' +
    'test in this suite, which is exactly why this assertion exists.');

  const addIdx = body.search(/\.asm\.add\(/);
  assert(addIdx >= 0, 'addPhoto must call <assembler>.add(...) on the photo session');
  assert(decodeIdx < addIdx, 'addPhoto must decode the header before calling add() — deciding after add() has already run is too late');
  assert(guardIdx < addIdx, 'addPhoto must compare fileId BEFORE calling add() — rateless.js\'s add() will have already reset the collection on a foreign fileId by the time a post-hoc check could run');
});

test('the About tab declares the app version and matches the newest CHANGELOG release', () => {
  const m = html.match(/<span id="appVersion" data-version="(\d+\.\d+\.\d+)">/);
  assert(m, 'index.html must carry <span id="appVersion" data-version="x.y.z">');
  const changelog = fs.readFileSync(path.join(root, '..', 'CHANGELOG.md'), 'utf8');
  const newest = changelog.match(/^## \[(\d+\.\d+\.\d+)\]/m)[1];
  assert(m[1] === newest, `index.html data-version ${m[1]} but the newest CHANGELOG release is ${newest}`);
  assert(/<span id="buildSha">dev<\/span>/.test(html), 'index.html must carry <span id="buildSha">dev</span> for the deploy workflow to stamp');
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
