/**
 * compress.js — zlib deflate/inflate for the CimBar container (spec §4).
 * Browser: CompressionStream/DecompressionStream('deflate') (zlib framing).
 * Node (tests, tools): the zlib module. Classic-script IIFE; exposes
 * window.CimbarCompress / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const MIN_SAVING = (isNode ? require('./format.js') : window.CimbarFormat).SPEC.compression.minSaving;

async function deflateBytes(bytes) {
  if (isNode) return new Uint8Array(require('zlib').deflateSync(Buffer.from(bytes)));
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function inflateBytes(bytes) {
  if (isNode) return new Uint8Array(require('zlib').inflateSync(Buffer.from(bytes)));
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Deflate only when it saves at least MIN_SAVING; otherwise return the input untouched. */
async function maybeDeflate(bytes) {
  if (bytes.length === 0) return { bytes, compressed: false };
  const d = await deflateBytes(bytes);
  if (d.length <= Math.floor(bytes.length * (1 - MIN_SAVING))) return { bytes: d, compressed: true };
  return { bytes, compressed: false };
}

const API = { deflateBytes, inflateBytes, maybeDeflate, MIN_SAVING };
if (isNode) module.exports = API; else window.CimbarCompress = API;
})();
