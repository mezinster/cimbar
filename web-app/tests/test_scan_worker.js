// scan-worker.js run the way a browser runs a worker: one global scope
// (`self`), no `window` until the worker's own shim, no module/require, and
// importScripts loading the real page files from disk into that scope.
// The worker must add nothing to and lose nothing from CimbarPhoto.decode:
// for every scene fixture its reply equals a direct decode of the same pixels.
'use strict';
const vm = require('vm');
const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');
const { PNG } = require('./png.js');

const root = path.join(__dirname, '..');
const scenes = path.join(root, '..', 'test-data', 'scenes');
const { CimbarPhoto } = require(path.join(root, 'photo-decoder.js'));

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

function loadWorker() {
  const posted = [];
  const imported = [];
  const sandbox = { console, performance };
  sandbox.self = sandbox;
  sandbox.postMessage = (m) => posted.push(m);
  const ctx = vm.createContext(sandbox);
  sandbox.importScripts = (...files) => {
    for (const f of files) {
      imported.push(f);
      vm.runInContext(fs.readFileSync(path.join(root, f), 'utf8'), ctx, { filename: f });
    }
  };
  vm.runInContext(fs.readFileSync(path.join(root, 'scan-worker.js'), 'utf8'), ctx, { filename: 'scan-worker.js' });
  return { ctx, posted, imported };
}

function post(w, msg) {
  w.ctx.onmessage({ data: msg });
  assertEq(w.posted.length > 0, true, 'the worker must reply synchronously to each message');
  return w.posted.pop();
}

test('loads the decode chain in index.html order and installs onmessage', () => {
  const w = loadWorker();
  assertEq(typeof w.ctx.onmessage, 'function', 'self.onmessage');
  assertEq(typeof w.ctx.CimbarPhoto.decode, 'function', 'CimbarPhoto reachable after importScripts');
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const pageOrder = [...html.matchAll(/<script src="([^"]+)"><\/script>/g)].map((m) => m[1]);
  let last = -1;
  for (const f of w.imported) {
    const i = pageOrder.indexOf(f);
    assert(i >= 0, `${f} is imported by the worker but is not a page script`);
    assert(i > last, `${f} is imported out of index.html order`);
    last = i;
  }
  assert(w.imported.includes('photo-decoder.js'), 'photo-decoder.js imported');
});

for (const name of fs.readdirSync(scenes).filter((f) => f.endsWith('.png')).sort()) {
  test(`reply equals a direct CimbarPhoto.decode — ${name}`, () => {
    const img = PNG.decode(fs.readFileSync(path.join(scenes, name)));
    const direct = CimbarPhoto.decode(img);
    const w = loadWorker();
    const buffer = new Uint8ClampedArray(img.data).buffer;       // a copy, as getImageData would give
    const r = post(w, { id: 7, width: img.width, height: img.height, buffer });
    assertEq(r.id, 7, 'id echoed');
    assertEq(r.status, direct.status, 'status');
    assertEq(r.blocksFailed, direct.blocksFailed, 'blocksFailed');
    assertEq(JSON.stringify(r.corners), JSON.stringify(direct.diag.corners), 'corners');
    assertEq(r.module, direct.diag.module, 'module');
    if (direct.data) {
      assert(r.data, 'data present');
      assertEq(Buffer.from(r.data).equals(Buffer.from(direct.data)), true, 'data bytes');
    } else {
      assertEq(r.data, null, 'data null');
    }
    assertEq(r.cells, undefined, 'cells are not sent back');
    assertEq(r.raw, undefined, 'raw is not sent back');
  });
}

test('a blank frame replies notLocated rather than throwing', () => {
  const w = loadWorker();
  const width = 200, height = 200;
  const px = new Uint8ClampedArray(width * height * 4).fill(128);
  const r = post(w, { id: 1, width, height, buffer: px.buffer });
  assertEq(r.status, 'notLocated', 'status');
  assertEq(r.corners, null, 'no corners');
});

test('an exception inside decode becomes status "error" with the message', () => {
  const w = loadWorker();
  w.ctx.CimbarPhoto.decode = () => { throw new Error('boom'); };
  const r = post(w, { id: 3, width: 1, height: 1, buffer: new ArrayBuffer(4) });
  assertEq(r.id, 3, 'id echoed');
  assertEq(r.status, 'error', 'status');
  assertEq(r.message, 'boom', 'message');
});

(async () => {
  console.log('\ntest_scan_worker.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
