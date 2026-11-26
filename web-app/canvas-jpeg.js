/**
 * canvas-jpeg.js — the browser's JPEG encoder session: the only DOM-touching
 * part of the photo optimiser. Decodes once (image-decode.js: the browser's
 * decoder, libheif for HEIC), orientation baked in, then encodes per
 * (maxSide, quality) on a white background. Canvas output carries no EXIF/GPS;
 * stripJpegMetadata runs as a second safeguard.
 *
 * Memory: iOS Safari caps one canvas at ~16.7 MP and limits canvas memory in
 * total, while a fit walks from the original side down through the presets.
 * So at most MAX_LIVE_CANVASES scaled canvases are alive, none is created
 * above MAX_CANVAS_PIXELS, and a canvas that can't be made or encoded throws
 * SideTooLargeError — "doesn't fit" for that side, not "can't be read".
 * Only a failed decode is a PhotoDecodeError.
 * Port of NFC Archiver's app/ui/canvas-jpeg.ts.
 */
'use strict';

// Private scope: classic scripts share one global lexical scope.
(function () {

const isNode = typeof module !== 'undefined' && module.exports;
// Resolved at call time so load order in the page does not matter.
const imageDecode = () => (isNode ? require('./image-decode.js') : window.CimbarImageDecode);
const jpegMeta = () => (isNode ? require('./jpeg-metadata.js') : window.CimbarJpegMeta);

/** Below iOS Safari's 16,777,216-pixel limit for one canvas. */
const MAX_CANVAS_PIXELS = 16_000_000;

/** The fit walks sides in order, so the current and the previous side suffice. */
const MAX_LIVE_CANVASES = 2;

/** A side too big to render or encode in this browser. */
class SideTooLargeError extends Error {
  constructor(message = 'This size is too large for the browser', options) {
    super(message, options);
    this.name = 'SideTooLargeError';
  }
}

/** Least-recently-used cache that releases what it drops. DOM-free. */
class BoundedCache {
  constructor(limit, release) {
    this._limit = limit;
    this._release = release;
    this._map = new Map();
  }

  get(key) {
    const v = this._map.get(key);
    if (v !== undefined) { this._map.delete(key); this._map.set(key, v); } // most recent last
    return v;
  }

  set(key, value) {
    const old = this._map.get(key);
    if (old !== undefined && old !== value) this._release(old);
    this._map.delete(key);
    this._map.set(key, value);
    while (this._map.size > this._limit) this._dropOldest();
  }

  /** Makes room for one more entry before an allocation. */
  reserve() {
    while (this._map.size >= this._limit) this._dropOldest();
  }

  get size() { return this._map.size; }

  clear() {
    for (const v of this._map.values()) this._release(v);
    this._map.clear();
  }

  _dropOldest() {
    const [k, v] = this._map.entries().next().value;
    this._map.delete(k);
    this._release(v);
  }
}

/** Pixel size of width×height scaled so its longest side is maxSide (never up). */
function scaledSize(width, height, maxSide) {
  const longest = Math.max(width, height);
  const side = Math.min(maxSide, longest);
  return {
    w: Math.max(1, Math.round((width * side) / longest)),
    h: Math.max(1, Math.round((height * side) / longest)),
  };
}

// Browser surface, replaceable by tests.
const _impl = {
  makeCanvas(w, h) {
    if (typeof OffscreenCanvas !== 'undefined') return new OffscreenCanvas(w, h);
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    return c;
  },
  async toJpeg(canvas, quality) {
    if ('convertToBlob' in canvas) return canvas.convertToBlob({ type: 'image/jpeg', quality });
    return new Promise((resolve, reject) => {
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('JPEG encoding failed'))), 'image/jpeg', quality);
    });
  },
  decodeImage(blob) { return imageDecode().decodeImage(blob); },
};

/** Zero-sized canvases give their backing store back at once (Safari counts it until GC otherwise). */
function releaseCanvas(c) {
  c.width = 0;
  c.height = 0;
}

class CanvasJpegSession {
  constructor(bitmap) {
    this._scaled = new BoundedCache(MAX_LIVE_CANVASES, releaseCanvas);
    this._bitmap = bitmap;
    this.width = bitmap.width;
    this.height = bitmap.height;
  }

  static async open(blob) {
    const { PhotoDecodeError, ImageTooLargeError } = imageDecode();
    let bitmap;
    try {
      bitmap = await _impl.decodeImage(blob);
    } catch (e) {
      if (e instanceof PhotoDecodeError || e instanceof ImageTooLargeError) throw e;
      throw new PhotoDecodeError(undefined, { cause: e });
    }
    if (!bitmap || bitmap.width === 0 || bitmap.height === 0) {
      if (bitmap && bitmap.close) bitmap.close();
      throw new PhotoDecodeError();
    }
    return new CanvasJpegSession(bitmap);
  }

  /** The source drawn at maxSide (never upscaled) on white, kept while among the last two sides. */
  _canvasFor(maxSide) {
    const { w, h } = scaledSize(this.width, this.height, maxSide);
    const key = Math.max(w, h);
    const hit = this._scaled.get(key);
    if (hit) return hit;
    const bitmap = this._bitmap;
    if (!bitmap) throw new Error('Session closed');
    if (w * h > MAX_CANVAS_PIXELS) throw new SideTooLargeError();
    this._scaled.reserve(); // free the oldest canvas before allocating a new one
    let canvas = null;
    try {
      canvas = _impl.makeCanvas(w, h);
      const ctx = canvas.getContext('2d');
      if (!ctx) throw new Error('No 2D context'); // what Safari does when canvas memory runs out
      ctx.fillStyle = '#ffffff'; // JPEG has no alpha: flatten transparency onto white
      ctx.fillRect(0, 0, w, h);
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(bitmap, 0, 0, w, h);
    } catch (e) {
      if (canvas) releaseCanvas(canvas);
      throw new SideTooLargeError(undefined, { cause: e });
    }
    this._scaled.set(key, canvas);
    return canvas;
  }

  async encode(maxSide, quality) {
    const canvas = this._canvasFor(maxSide);
    let blob;
    try {
      blob = await _impl.toJpeg(canvas, Math.min(Math.max(quality, 1), 100) / 100);
    } catch (e) {
      throw new SideTooLargeError(undefined, { cause: e }); // encoder out of memory for this size
    }
    return jpegMeta().stripJpegMetadata(new Uint8Array(await blob.arrayBuffer()));
  }

  close() {
    if (this._bitmap && this._bitmap.close) this._bitmap.close();
    this._bitmap = null;
    this._scaled.clear();
  }
}

const API = {
  MAX_CANVAS_PIXELS, MAX_LIVE_CANVASES, SideTooLargeError, BoundedCache,
  scaledSize, CanvasJpegSession, _impl,
};

if (isNode) module.exports = API;
else window.CimbarCanvasJpeg = API;

})();
