/**
 * scan-worker.js — the live-scan decode worker (spec §5).
 *
 * Stateless: one message in, one reply out. Request
 *   { id, width, height, buffer }   RGBA ArrayBuffer, transferred
 * reply
 *   { id, status, data, blocksFailed, corners, module, diag }
 * or, if decode threw,
 *   { id, status: 'error', message }.
 * cells and raw are not sent back: the page never uses them.
 *
 * The decode modules are classic scripts that read their dependencies from
 * window.* when `module` is undefined; a worker has no window, so alias it
 * before importScripts. importScripts runs them in one shared global scope,
 * the same situation tests/test_browser_load.js simulates for the page, so
 * none of them changes. Keep the list in index.html's order.
 */
'use strict';
self.window = self;
importScripts(
  'rs.js', 'format-data.js', 'format.js', 'rateless.js', 'cimbar.js',
  'rgb-buffer.js', 'luma-plane.js', 'homography.js', 'finder-locator.js',
  'white-point.js', 'cell-sampler.js', 'cell-classifier.js', 'drift-solver.js',
  'photo-decoder.js'
);

self.onmessage = function (e) {
  const m = e.data;
  let reply;
  try {
    const r = self.CimbarPhoto.decode({ width: m.width, height: m.height, data: new Uint8ClampedArray(m.buffer) });
    reply = {
      id: m.id, status: r.status, data: r.data, blocksFailed: r.blocksFailed,
      corners: r.diag.corners, module: r.diag.module, diag: r.diag,
    };
  } catch (err) {
    reply = { id: m.id, status: 'error', message: String((err && err.message) || err) };
  }
  self.postMessage(reply);
};
