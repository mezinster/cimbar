/**
 * heic-worker.js — decodes one HEIF/HEIC photo with the vendored libheif
 * (vendor/libheif/, see its README). Not a page script: image-decode.js
 * creates a fresh worker per decode and terminates it after the reply.
 *
 * Request  { module: WebAssembly.Module, buffer: ArrayBuffer }  (buffer transferred)
 * Reply    { ok: true, width, height, rgba: ArrayBuffer }       (rgba transferred)
 *       or { ok: false, code: 'decode_failed' | 'too_large' }
 *
 * The page compiles libheif.wasm once and posts the module; libheif's
 * instantiateWasm hook instantiates it here, so nothing is fetched or
 * recompiled. libheif applies the HEIF transformations (irot/imir/clap), so
 * width/height and the pixels are as the photo is meant to be displayed.
 */
'use strict';
self.window = self;
importScripts('vendor/libheif/libheif.js');

const MAX_HEIF_PIXELS = 64e6; // keeps the RGBA buffer at or below 256 MB

let replied = false;
function reply(msg, transfer) {
  if (replied) return;
  replied = true;
  self.postMessage(msg, transfer || []);
}
const fail = (code) => reply({ ok: false, code });

/**
 * Instantiates libheif from a compiled module. This build compiles
 * synchronously (its factory reads the wasm exports as soon as
 * instantiateWasm returns), so the hook must instantiate synchronously and
 * return done()'s result; the factory then returns a ready module. A worker
 * may instantiate a large module synchronously (only the main thread may not).
 */
function instantiate(module) {
  return self.libheif({
    instantiateWasm(imports, done) {
      return done(new WebAssembly.Instance(module, imports));
    },
    // Never used while instantiateWasm supplies the module, but libheif.js
    // would otherwise resolve the wasm relative to this worker (web-app/).
    locateFile: (p) => 'vendor/libheif/' + p,
  });
}

// display() decodes inside an async callback; if that throws, no callback
// comes, so answer here instead of leaving the page waiting.
self.onunhandledrejection = () => fail('decode_failed');

self.onmessage = function (e) {
  const { module, buffer } = e.data;
  try {
    const lib = instantiate(module);
    const images = new lib.HeifDecoder().decode(new Uint8Array(buffer));
    const image = images.find((im) => im.is_primary()) || images[0];
    if (!image) return fail('decode_failed');
    const width = image.get_width();
    const height = image.get_height();
    if (!(width > 0 && height > 0)) return fail('decode_failed');
    if (width * height > MAX_HEIF_PIXELS) return fail('too_large');
    const target = { data: new Uint8ClampedArray(width * height * 4) };
    image.display(target, (out) => {
      if (!out) return fail('decode_failed');
      reply({ ok: true, width, height, rgba: target.data.buffer }, [target.data.buffer]);
    });
  } catch (err) {
    fail('decode_failed');
  }
};
