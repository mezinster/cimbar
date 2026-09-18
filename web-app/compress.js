/**
 * compress.js — zlib deflate/inflate for the CimBar container (spec §4).
 * Browser: CompressionStream/DecompressionStream('deflate') (zlib framing).
 * Node (tests, tools): the zlib module. Classic-script IIFE; exposes
 * window.CimbarCompress / module.exports.
 *
 * Availability: browsers without CompressionStream still encode (the payload
 * is simply sent uncompressed); a browser without DecompressionStream cannot
 * decode a compressed v2.1 file, so inflateBytes throws an error marked
 * `unsupported` that the page reports through i18n.
 *
 * Inflate is capped at spec compression.maxInflatedBytes (128 MB): a crafted
 * zlib stream a few KB long can otherwise expand to gigabytes. Overflow
 * throws an error marked `tooLarge`.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const SPEC = (isNode ? require('./format.js') : window.CimbarFormat).SPEC;
const MIN_SAVING = SPEC.compression.minSaving;
const MAX_INFLATED = SPEC.compression.maxInflatedBytes;

/**
 * Platform predicates, kept on an object so tests can stub them and exercise
 * the browser-without-streams branches under Node.
 */
const _impl = {
  hasCompression() { return isNode || typeof CompressionStream !== 'undefined'; },
  hasDecompression() { return isNode || typeof DecompressionStream !== 'undefined'; },
};

function unsupportedError() {
  const e = new Error('DecompressionStream is not available in this browser');
  e.unsupported = true;
  return e;
}

function tooLargeError(max) {
  const e = new Error(`inflated size exceeds ${max} bytes`);
  e.tooLarge = true;
  e.maxBytes = max;
  return e;
}

async function deflateBytes(bytes) {
  if (isNode) return new Uint8Array(require('zlib').deflateSync(Buffer.from(bytes)));
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Read a DecompressionStream chunk by chunk, refusing to buffer past `max`. */
async function readCapped(stream, max) {
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > max) { try { await reader.cancel(); } catch (e) { /* ignore */ } throw tooLargeError(max); }
      chunks.push(value);
    }
  } finally {
    try { reader.releaseLock(); } catch (e) { /* ignore */ }
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { out.set(c, off); off += c.length; }
  return out;
}

/**
 * Inflate `bytes`, refusing output above `maxBytes` (default the spec cap).
 * Throws an error with `.unsupported` when the browser has no
 * DecompressionStream, and one with `.tooLarge` past the cap.
 */
async function inflateBytes(bytes, maxBytes) {
  const max = maxBytes === undefined ? MAX_INFLATED : maxBytes;
  if (!_impl.hasDecompression()) throw unsupportedError();
  if (isNode) {
    try {
      return new Uint8Array(require('zlib').inflateSync(Buffer.from(bytes), { maxOutputLength: max }));
    } catch (e) {
      if (e instanceof RangeError || e.code === 'ERR_BUFFER_TOO_LARGE') throw tooLargeError(max);
      throw e;
    }
  }
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
  return readCapped(stream, max);
}

/**
 * Deflate only when it saves at least MIN_SAVING; otherwise return the input
 * untouched. A browser without CompressionStream always returns the input.
 */
async function maybeDeflate(bytes) {
  if (bytes.length === 0) return { bytes, compressed: false };
  if (!_impl.hasCompression()) return { bytes, compressed: false };
  const d = await deflateBytes(bytes);
  if (d.length <= Math.floor(bytes.length * (1 - MIN_SAVING))) return { bytes: d, compressed: true };
  return { bytes, compressed: false };
}

const API = { deflateBytes, inflateBytes, maybeDeflate, MIN_SAVING, MAX_INFLATED, _impl };
if (isNode) module.exports = API; else window.CimbarCompress = API;
})();
