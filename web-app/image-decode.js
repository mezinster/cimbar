/**
 * image-decode.js — turns a picked photo into an ImageBitmap in every browser.
 * The browser's own decoder first (createImageBitmap, orientation from the
 * image); if that fails and the file is HEIF (sniffed from its bytes, not its
 * type or name), the vendored libheif decodes it in heic-worker.js.
 *
 * The wasm is compiled once and the WebAssembly.Module posted to a fresh
 * worker per decode; the worker is terminated after its reply, because
 * libheif's memory grows to the peak of a large decode and never shrinks.
 * Any failure is a PhotoDecodeError; a HEIF above 64 MP is ImageTooLargeError.
 */
'use strict';

// Private scope: classic scripts share one global lexical scope.
(function () {

const MAX_HEIF_PIXELS = 64_000_000;   // enforced in heic-worker.js
const MAX_BITMAP_PIXELS = 16_000_000; // the encoder session's canvas cap
const SNIFF_BYTES = 64;
// A worker that never answers (a crafted file looping in libheif) is
// terminated; a legitimate 48 MP decode on a phone takes seconds, not a minute.
const HEIF_DECODE_TIMEOUT_MS = 60_000;
const WASM_URL = 'vendor/libheif/libheif.wasm';
const WORKER_URL = 'heic-worker.js';

const HEIF_BRANDS = ['heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'mif1', 'msf1'];
const AVIF_BRANDS = ['avif', 'avis'];

class PhotoDecodeError extends Error {
  constructor(message = 'This photo can\'t be read', options) {
    super(message, options);
    this.name = 'PhotoDecodeError';
  }
}

class ImageTooLargeError extends Error {
  constructor(message = 'This photo is too large to optimise', options) {
    super(message, options);
    this.name = 'ImageTooLargeError';
  }
}

function fourcc(b, at) {
  return String.fromCharCode(b[at], b[at + 1], b[at + 2], b[at + 3]);
}

/**
 * Whether `head` (a file's first bytes) starts with an ISO-BMFF ftyp box whose
 * major brand is a HEIF brand and whose compatible brands name no AVIF brand
 * (AVIF lists mif1 too). Box: size u32, 'ftyp', major brand, minor version,
 * compatible brands; only the brands within `head` are checked.
 */
function sniffHeif(head) {
  if (!head || head.length < 12) return false;
  if (fourcc(head, 4) !== 'ftyp') return false;
  const size = ((head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3]) >>> 0;
  if (size < 16) return false;
  if (!HEIF_BRANDS.includes(fourcc(head, 8))) return false;
  const end = Math.min(size, head.length);
  for (let at = 16; at + 4 <= end; at += 4) {
    if (AVIF_BRANDS.includes(fourcc(head, at))) return false;
  }
  return true;
}

/** Browser surfaces, replaceable by tests. */
const _impl = {
  createImageBitmap: (source, options) =>
    (options === undefined ? createImageBitmap(source) : createImageBitmap(source, options)),
  createWorker: (url) => new Worker(url),
  compileWasm: (url) => WebAssembly.compileStreaming(fetch(url)),
  setTimeout: (fn, ms) => setTimeout(fn, ms),
  clearTimeout: (id) => clearTimeout(id),
};

let libheifModule = null; // Promise<WebAssembly.Module>, memoised

function compiledLibheif() {
  if (!libheifModule) {
    const compiling = Promise.resolve().then(() => _impl.compileWasm(WASM_URL));
    libheifModule = compiling;
    // A failed fetch/compile is not cached: a later pick tries again.
    compiling.catch(() => { if (libheifModule === compiling) libheifModule = null; });
  }
  return libheifModule;
}

/** Posts the module and file bytes to a fresh worker; resolves with its reply. */
function runWorker(wasm, buffer) {
  return new Promise((resolve, reject) => {
    let worker;
    try {
      worker = _impl.createWorker(WORKER_URL);
    } catch (e) {
      reject(new PhotoDecodeError(undefined, { cause: e }));
      return;
    }
    let settled = false;
    let timer = null;
    const done = (settle) => {
      if (settled) return;
      settled = true;
      if (timer !== null) _impl.clearTimeout(timer);
      worker.onmessage = worker.onerror = worker.onmessageerror = null;
      worker.terminate();
      settle();
    };
    worker.onmessage = (e) => done(() => resolve(e.data));
    worker.onerror = (e) => done(() => reject(new PhotoDecodeError(undefined, { cause: e })));
    worker.onmessageerror = (e) => done(() => reject(new PhotoDecodeError(undefined, { cause: e })));
    try {
      worker.postMessage({ module: wasm, buffer }, [buffer]);
    } catch (e) {
      done(() => reject(new PhotoDecodeError(undefined, { cause: e })));
      return;
    }
    timer = _impl.setTimeout(
      () => done(() => reject(new PhotoDecodeError('HEIC decode timed out'))),
      HEIF_DECODE_TIMEOUT_MS);
  });
}

async function decodeHeif(blob) {
  let wasm, buffer;
  try {
    wasm = await compiledLibheif();
    buffer = await blob.arrayBuffer();
  } catch (e) {
    throw new PhotoDecodeError(undefined, { cause: e });
  }
  const reply = await runWorker(wasm, buffer);
  if (!reply || reply.ok !== true) {
    if (reply && reply.code === 'too_large') throw new ImageTooLargeError();
    throw new PhotoDecodeError();
  }
  const { width, height, rgba } = reply;
  try {
    const imageData = new ImageData(new Uint8ClampedArray(rgba), width, height);
    const pixels = width * height;
    if (pixels <= MAX_BITMAP_PIXELS) return await _impl.createImageBitmap(imageData);
    const scale = Math.sqrt(MAX_BITMAP_PIXELS / pixels);
    return await _impl.createImageBitmap(imageData, {
      resizeWidth: Math.max(1, Math.floor(width * scale)),
      resizeHeight: Math.max(1, Math.floor(height * scale)),
      resizeQuality: 'high',
    });
  } catch (e) {
    throw new PhotoDecodeError(undefined, { cause: e });
  }
}

/** Blob → ImageBitmap with orientation applied, or PhotoDecodeError / ImageTooLargeError. */
async function decodeImage(blob) {
  let nativeError;
  try {
    return await _impl.createImageBitmap(blob, { imageOrientation: 'from-image' });
  } catch (e) {
    nativeError = e;
  }
  let head;
  try {
    head = new Uint8Array(await blob.slice(0, SNIFF_BYTES).arrayBuffer());
  } catch (e) {
    throw new PhotoDecodeError(undefined, { cause: e });
  }
  if (!sniffHeif(head)) throw new PhotoDecodeError(undefined, { cause: nativeError });
  return decodeHeif(blob);
}

const API = {
  sniffHeif, decodeImage, PhotoDecodeError, ImageTooLargeError,
  MAX_HEIF_PIXELS, MAX_BITMAP_PIXELS, HEIF_DECODE_TIMEOUT_MS, _impl,
};

if (typeof module !== 'undefined' && module.exports) module.exports = API;
else window.CimbarImageDecode = API;

})();
