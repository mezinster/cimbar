// image-decode.js and heic-worker.js: HEIF sniffing, the vendored libheif's
// checksums, a real decode of a committed HEIC through the vendored files,
// the heic-worker.js protocol run the way a browser runs a worker, and
// decodeImage's native-first / worker-fallback flow behind its _impl seam.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');

const root = path.join(__dirname, '..');
const vendor = path.join(root, 'vendor', 'libheif');
const heicPath = path.join(root, '..', 'test-data', 'photos', 'rotated.heic');
const modPath = path.join(root, 'image-decode.js');

let passed = 0, failed = 0;
const pending = [];
function test(name, fn) {
  pending.push((async () => {
    try { await fn(); passed++; console.log(`  PASS  ${name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); }
  })());
}
function assert(c, msg) { if (!c) throw new Error(msg); }
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
async function rejects(promise, Cls, msg) {
  try { await promise; } catch (e) {
    assert(e instanceof Cls, `${msg}: rejected with ${e && e.name} (${e && e.message}), want ${Cls.name}`);
    return e;
  }
  throw new Error(`${msg}: resolved, want a ${Cls.name}`);
}

/** A fresh copy of image-decode.js, so each test has its own _impl and compile memo. */
function fresh() {
  delete require.cache[require.resolve(modPath)];
  return require(modPath);
}

// Browsers have ImageData; Node does not.
global.ImageData = class ImageData {
  constructor(data, width, height) { this.data = data; this.width = width; this.height = height; }
};

const heic = new Uint8Array(fs.readFileSync(heicPath));

console.log('\ntest_image_decode.js');

// ── sniffHeif ────────────────────────────────────────────────────────────

/** An ftyp box: size, 'ftyp', major brand, minor version 0, compatible brands. */
function ftyp(major, compat = [], minor = 0) {
  const size = 16 + 4 * compat.length;
  const b = new Uint8Array(size);
  new DataView(b.buffer).setUint32(0, size);
  b.set(Buffer.from('ftyp' + major, 'latin1'), 4);
  new DataView(b.buffer).setUint32(12, minor);
  compat.forEach((c, i) => b.set(Buffer.from(c, 'latin1'), 16 + 4 * i));
  return b;
}

test('sniffHeif: heic and mif1 major brands', () => {
  const { sniffHeif } = fresh();
  eq(sniffHeif(ftyp('heic', ['mif1', 'heic'])), true, 'heic');
  eq(sniffHeif(ftyp('mif1', ['heic'])), true, 'mif1');
  for (const b of ['heix', 'heim', 'heis', 'hevc', 'hevx', 'msf1']) eq(sniffHeif(ftyp(b)), true, b);
});
test('sniffHeif: the bytes of rotated.heic, whatever the file type says', () => {
  const { sniffHeif } = fresh();
  eq(sniffHeif(heic.subarray(0, 64)), true, 'rotated.heic head');
});
test('sniffHeif: AVIF is not HEIF', () => {
  const { sniffHeif } = fresh();
  eq(sniffHeif(ftyp('avif', ['mif1', 'avif'])), false, 'major avif');
  eq(sniffHeif(ftyp('mif1', ['miaf', 'avif'])), false, 'mif1 with compatible avif');
  eq(sniffHeif(ftyp('mif1', ['avis'])), false, 'mif1 with compatible avis');
});
test('sniffHeif: JPEG, PNG and GIF heads', () => {
  const { sniffHeif } = fresh();
  eq(sniffHeif(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1])), false, 'JPEG');
  eq(sniffHeif(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])), false, 'PNG');
  eq(sniffHeif(new Uint8Array(Buffer.from('GIF89a\x40\x00\x20\x00\x80\x00\x00\x00\x00\x00', 'latin1'))), false, 'GIF');
});
test('sniffHeif: short and garbage input', () => {
  const { sniffHeif } = fresh();
  eq(sniffHeif(ftyp('heic').subarray(0, 11)), false, '11 bytes');
  eq(sniffHeif(new Uint8Array(0)), false, 'empty');
  eq(sniffHeif(null), false, 'null');
  const junk = new Uint8Array(64);
  for (let i = 0; i < junk.length; i++) junk[i] = (i * 151 + 7) & 0xff;
  eq(sniffHeif(junk), false, 'junk');
  const notFtyp = ftyp('heic'); notFtyp.set(Buffer.from('free', 'latin1'), 4);
  eq(sniffHeif(notFtyp), false, 'free box, not ftyp');
  const tiny = ftyp('heic'); new DataView(tiny.buffer).setUint32(0, 8);
  eq(sniffHeif(tiny), false, 'box size smaller than an ftyp header');
});

// ── the vendored files ───────────────────────────────────────────────────

test('vendored libheif files match the SHA-256 in vendor/libheif/README.md', () => {
  const readme = fs.readFileSync(path.join(vendor, 'README.md'), 'utf8');
  const listed = [...readme.matchAll(/^([0-9a-f]{64}) {2}(\S+)$/gm)].map((m) => ({ sha: m[1], file: m[2] }));
  const names = listed.map((l) => l.file);
  for (const f of ['libheif.js', 'libheif.wasm', 'LICENSE', 'DAV1D-LICENSE']) assert(names.includes(f), `README lists no SHA-256 for ${f}`);
  for (const { sha, file } of listed) {
    const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(vendor, file))).digest('hex');
    eq(actual, sha, `SHA-256 of ${file}`);
  }
  assert(/1\.23\.5/.test(readme), 'README names libheif-js 1.23.5');
});

// ── real decode through the vendored libheif (Node) ──────────────────────

function pixel(rgba, width, x, y) { return Array.from(rgba.slice((y * width + x) * 4, (y * width + x) * 4 + 4)); }
function isRed(p) { return p[0] > 200 && p[1] < 60 && p[2] < 60; }
function isBlue(p) { return p[0] < 60 && p[1] < 60 && p[2] > 200; }

test('rotated.heic decodes through vendor/libheif with its irot applied: 32x64, red on top', async () => {
  const wasmBinary = fs.readFileSync(path.join(vendor, 'libheif.wasm'));
  const lib = require(path.join(vendor, 'libheif.js'))({ wasmBinary });
  const images = new lib.HeifDecoder().decode(heic);
  eq(images.length, 1, 'images');
  const w = images[0].get_width(), h = images[0].get_height();
  eq([w, h], [32, 64], 'size after irot');
  const target = { data: new Uint8ClampedArray(w * h * 4) };
  const out = await new Promise((resolve) => images[0].display(target, resolve));
  assert(out, 'display failed');
  assert(isRed(pixel(target.data, w, 16, 8)), `pixel (16, 8) is ${pixel(target.data, w, 16, 8)}, want red`);
  assert(isBlue(pixel(target.data, w, 16, 56)), `pixel (16, 56) is ${pixel(target.data, w, 16, 56)}, want blue`);
});

// ── heic-worker.js, run like a browser worker ───────────────────────────

/**
 * Runs heic-worker.js in its own global scope with a real importScripts that
 * loads files from web-app/, no `module`/`require`/`process` (so libheif.js
 * takes its worker branch), and resolves with the worker's one reply.
 */
function runHeicWorker(buffer) {
  const imported = [];
  const logs = [];
  const sandbox = {
    console: { log: (...a) => logs.push(a.join(' ')), warn: (...a) => logs.push(a.join(' ')), error: (...a) => logs.push(a.join(' ')) },
    setTimeout, clearTimeout, TextDecoder, URL,
    location: { href: 'http://localhost/heic-worker.js' },
  };
  sandbox.self = sandbox;
  const ctx = vm.createContext(sandbox);
  sandbox.importScripts = (...files) => {
    for (const f of files) {
      imported.push(f);
      vm.runInContext(fs.readFileSync(path.join(root, f), 'utf8'), ctx, { filename: f });
    }
  };
  return new Promise((resolve, reject) => {
    sandbox.postMessage = (msg, transfer) => resolve({ msg, transfer, imported, logs });
    vm.runInContext(fs.readFileSync(path.join(root, 'heic-worker.js'), 'utf8'), ctx, { filename: 'heic-worker.js' });
    const SandboxWasm = vm.runInContext('WebAssembly', ctx);
    SandboxWasm.compile(fs.readFileSync(path.join(vendor, 'libheif.wasm')))
      .then((module) => sandbox.onmessage({ data: { module, buffer } }))
      .catch(reject);
  });
}

test('heic-worker.js decodes rotated.heic from a compiled module: 32x64 RGBA, transferred', async () => {
  const buf = heic.slice().buffer;
  const { msg, transfer, imported } = await runHeicWorker(buf);
  eq(imported, ['vendor/libheif/libheif.js'], 'importScripts');
  eq([msg.ok, msg.width, msg.height], [true, 32, 64], 'reply');
  assert(msg.rgba instanceof ArrayBuffer || Object.prototype.toString.call(msg.rgba) === '[object ArrayBuffer]', 'rgba is an ArrayBuffer');
  eq(msg.rgba.byteLength, 32 * 64 * 4, 'rgba length');
  assert(transfer && transfer[0] === msg.rgba, 'rgba is transferred');
  const rgba = new Uint8Array(msg.rgba);
  assert(isRed(pixel(rgba, 32, 16, 8)), `pixel (16, 8) is ${pixel(rgba, 32, 16, 8)}, want red`);
  assert(isBlue(pixel(rgba, 32, 16, 56)), `pixel (16, 56) is ${pixel(rgba, 32, 16, 56)}, want blue`);
});
test('heic-worker.js replies decode_failed for bytes libheif cannot parse', async () => {
  const junk = new Uint8Array(256);
  junk.set(heic.subarray(0, 32));
  const { msg } = await runHeicWorker(junk.buffer);
  eq(msg, { ok: false, code: 'decode_failed' }, 'reply');
});
test('heic-worker.js replies too_large for a HEIF above 64 MP, without decoding it', async () => {
  // rotated.heic with its ispe/clap headers claiming 10000x8000 (80 MP after
  // the irot): libheif reports the size from the headers alone.
  const b = heic.slice();
  const dv = new DataView(b.buffer);
  const at = (box) => Buffer.from(b).indexOf(box);
  const ispe = at('ispe'), clap = at('clap');
  dv.setUint32(ispe + 8, 10000); dv.setUint32(ispe + 12, 10000);
  dv.setUint32(clap + 4, 10000); dv.setUint32(clap + 12, 8000); dv.setInt32(clap + 28, -2000);
  const { msg } = await runHeicWorker(b.buffer);
  eq(msg, { ok: false, code: 'too_large' }, 'reply');
});
test('heic-worker.js source: imports vendor/libheif/libheif.js and locates the wasm under vendor/libheif/', () => {
  const src = fs.readFileSync(path.join(root, 'heic-worker.js'), 'utf8');
  assert(src.includes("importScripts('vendor/libheif/libheif.js')"), "importScripts('vendor/libheif/libheif.js')");
  assert(/locateFile[^\n]*'vendor\/libheif\/' \+/.test(src), "locateFile returning 'vendor/libheif/' + …");
  assert(/self\.window\s*=\s*self/.test(src), 'self.window = self before importScripts');
});

// ── decodeImage behind the _impl seam ────────────────────────────────────

class FakeWorker {
  constructor(url, behave) {
    this.url = url; this.behave = behave; this.posted = []; this.terminated = false;
    this.onmessage = null; this.onerror = null;
  }
  postMessage(msg, transfer) {
    this.posted.push({ msg, transfer });
    setImmediate(() => this.behave(this, msg));
  }
  terminate() { this.terminated = true; }
}

const okReply = (w, h) => (worker) => worker.onmessage({ data: { ok: true, width: w, height: h, rgba: new ArrayBuffer(w * h * 4) } });

/** A module instance with a stubbed _impl. native: 'ok' | 'fail'. */
function setup({ native = 'fail', behave = okReply(32, 64), compile = async () => ({ fakeModule: true }) } = {}) {
  const M = fresh();
  const log = { bitmaps: [], workers: [], compiles: 0 };
  M._impl.createImageBitmap = async (src, opts) => {
    log.bitmaps.push({ src, opts });
    if (src instanceof Blob && native === 'fail') throw new Error('The source image could not be decoded.');
    return { bitmap: true, src, opts };
  };
  M._impl.createWorker = (url) => { const w = new FakeWorker(url, behave); log.workers.push(w); return w; };
  M._impl.compileWasm = async (url) => { log.compiles++; log.compileUrl = url; return compile(url); };
  // Fake timer: tests fire the timeout by hand; nothing waits 60 s.
  log.timers = [];
  M._impl.setTimeout = (fn, ms) => { const t = { fn, ms, cleared: false }; log.timers.push(t); return t; };
  M._impl.clearTimeout = (t) => { t.cleared = true; };
  return { M, log };
}

const heicBlob = (type = 'image/heic') => new Blob([heic], { type });

test('native decode success returns its bitmap without touching the worker', async () => {
  const { M, log } = setup({ native: 'ok' });
  const blob = new Blob([new Uint8Array([0xff, 0xd8, 0xff])], { type: 'image/jpeg' });
  const bmp = await M.decodeImage(blob);
  assert(bmp.src === blob, 'returns the native bitmap');
  eq(log.bitmaps[0].opts, { imageOrientation: 'from-image' }, 'native options');
  eq([log.workers.length, log.compiles], [0, 0], 'no worker, no compile');
});
test('native failure on a non-HEIF file rejects with PhotoDecodeError', async () => {
  const { M, log } = setup();
  const blob = new Blob([new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])], { type: 'image/png' });
  await rejects(M.decodeImage(blob), M.PhotoDecodeError, 'non-HEIF');
  eq([log.workers.length, log.compiles], [0, 0], 'no worker, no compile');
});
test('native failure on HEIF decodes in heic-worker.js and builds a bitmap from the RGBA', async () => {
  const { M, log } = setup();
  const bmp = await M.decodeImage(heicBlob());
  eq(log.compileUrl, 'vendor/libheif/libheif.wasm', 'compiled wasm URL');
  eq(log.workers.length, 1, 'one worker');
  eq(log.workers[0].url, 'heic-worker.js', 'worker URL');
  const { msg, transfer } = log.workers[0].posted[0];
  eq(msg.module, { fakeModule: true }, 'posts the compiled module');
  eq(msg.buffer.byteLength, heic.length, 'posts the file bytes');
  assert(transfer && transfer[0] === msg.buffer, 'buffer is transferred');
  assert(bmp.src instanceof ImageData, 'bitmap made from an ImageData');
  eq([bmp.src.width, bmp.src.height, bmp.src.data.length], [32, 64, 32 * 64 * 4], 'ImageData shape');
  eq(bmp.opts, undefined, 'no resize below 16 MP');
});
test('octet-stream HEIF still sniffed: a Blob typed application/octet-stream takes the worker path', async () => {
  const { M, log } = setup();
  await M.decodeImage(heicBlob('application/octet-stream'));
  eq(log.workers.length, 1, 'worker used');
});
test('worker error rejects with PhotoDecodeError', async () => {
  const { M } = setup({ behave: (w) => w.onerror({ message: 'importScripts failed' }) });
  await rejects(M.decodeImage(heicBlob()), M.PhotoDecodeError, 'worker error');
});
test('compile failure rejects with PhotoDecodeError', async () => {
  const { M, log } = setup({ compile: async () => { throw new TypeError('Failed to fetch'); } });
  await rejects(M.decodeImage(heicBlob()), M.PhotoDecodeError, 'compile failure');
  eq(log.workers.length, 0, 'no worker without a module');
});
test('decode_failed reply rejects with PhotoDecodeError', async () => {
  const { M } = setup({ behave: (w) => w.onmessage({ data: { ok: false, code: 'decode_failed' } }) });
  await rejects(M.decodeImage(heicBlob()), M.PhotoDecodeError, 'decode_failed');
});
test('too_large reply rejects with ImageTooLargeError', async () => {
  const { M } = setup({ behave: (w) => w.onmessage({ data: { ok: false, code: 'too_large' } }) });
  const e = await rejects(M.decodeImage(heicBlob()), M.ImageTooLargeError, 'too_large');
  assert(!(e instanceof M.PhotoDecodeError), 'too large is its own error, not PhotoDecodeError');
});
test('the worker is terminated after success and after failure', async () => {
  const ok = setup();
  await ok.M.decodeImage(heicBlob());
  eq(ok.log.workers[0].terminated, true, 'terminated after success');
  const bad = setup({ behave: (w) => w.onmessage({ data: { ok: false, code: 'decode_failed' } }) });
  await rejects(bad.M.decodeImage(heicBlob()), bad.M.PhotoDecodeError, 'failure');
  eq(bad.log.workers[0].terminated, true, 'terminated after a failed decode');
  const err = setup({ behave: (w) => w.onerror({ message: 'boom' }) });
  await rejects(err.M.decodeImage(heicBlob()), err.M.PhotoDecodeError, 'error');
  eq(err.log.workers[0].terminated, true, 'terminated after a worker error');
});
test('the wasm is compiled once across two decodes, each with a fresh worker', async () => {
  const { M, log } = setup();
  await M.decodeImage(heicBlob());
  await M.decodeImage(heicBlob());
  eq(log.compiles, 1, 'compiles');
  eq(log.workers.length, 2, 'workers');
  assert(log.workers[0] !== log.workers[1], 'a new worker per decode');
});
/** Resolves once the stub has started a worker and armed its timeout. */
async function armed(log) {
  for (let i = 0; i < 100 && log.timers.length === 0; i++) await new Promise((r) => setImmediate(r));
  assert(log.timers.length === 1, `expected one armed timeout, got ${log.timers.length}`);
  return log.timers[0];
}

test('a worker that never replies is terminated after HEIF_DECODE_TIMEOUT_MS and rejects with PhotoDecodeError', async () => {
  const { M, log } = setup({ behave: () => {} });
  const p = M.decodeImage(heicBlob());
  const timer = await armed(log);
  eq(timer.ms, 60000, 'timeout');
  eq(M.HEIF_DECODE_TIMEOUT_MS, 60000, 'exported timeout');
  eq(log.workers[0].terminated, false, 'still running before the timeout');
  timer.fn();
  await rejects(p, M.PhotoDecodeError, 'timeout');
  eq(log.workers[0].terminated, true, 'terminated on timeout');
});
test('a reply arriving after the timeout is ignored: no second settle, no second terminate', async () => {
  let lateReply = null;
  const { M, log } = setup({ behave: (w) => { lateReply = w.onmessage; } });
  const p = M.decodeImage(heicBlob());
  const timer = await armed(log);
  for (let i = 0; i < 10 && !lateReply; i++) await new Promise((r) => setImmediate(r));
  assert(lateReply, 'the stub captured the reply handler');
  const w = log.workers[0];
  let terminations = 0;
  w.terminate = () => { terminations++; w.terminated = true; };
  timer.fn();
  lateReply({ data: { ok: true, width: 32, height: 64, rgba: new ArrayBuffer(32 * 64 * 4) } });
  await rejects(p, M.PhotoDecodeError, 'still the timeout rejection');
  eq(terminations, 1, 'terminate calls');
  eq(log.bitmaps.length, 1, 'no bitmap built from the late reply (only the native attempt)');
});
test('a reply in time clears the timeout', async () => {
  const { M, log } = setup();
  await M.decodeImage(heicBlob());
  eq(log.timers.length, 1, 'one timeout armed');
  eq(log.timers[0].cleared, true, 'timeout cleared after the reply');
});
test('a 9000x8000 RGBA reply is resized to at most 16 MP', async () => {
  const { M } = setup({ behave: okReply(9000, 8000) });
  const bmp = await M.decodeImage(heicBlob());
  const o = bmp.opts;
  assert(o && o.resizeWidth && o.resizeHeight, 'resize options given');
  assert(o.resizeWidth * o.resizeHeight <= M.MAX_BITMAP_PIXELS, `${o.resizeWidth}x${o.resizeHeight} exceeds 16 MP`);
  assert(o.resizeWidth * o.resizeHeight > 0.99 * M.MAX_BITMAP_PIXELS, `${o.resizeWidth}x${o.resizeHeight} shrank more than needed`);
  assert(Math.abs(o.resizeWidth / o.resizeHeight - 9000 / 8000) < 0.001, 'aspect ratio kept');
  eq(o.resizeQuality, 'high', 'resizeQuality');
});
test('limits are the spec values', () => {
  const M = fresh();
  eq([M.MAX_HEIF_PIXELS, M.MAX_BITMAP_PIXELS], [64000000, 16000000], 'limits');
  const src = fs.readFileSync(path.join(root, 'heic-worker.js'), 'utf8');
  assert(/64e6|64_?000_?000/.test(src), 'heic-worker.js refuses images above 64 MP');
});

Promise.all(pending).then(() => {
  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
});
