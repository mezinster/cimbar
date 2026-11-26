/**
 * photo-fit.js — photo optimiser maths: deterministic fit to a byte budget,
 * the frame budget for a file container, and the optimised file name.
 * Ports of the app's photo_fit.dart, frame_budget.dart and
 * optimised_file_name.dart; test-data/photo-fit.json is the shared contract.
 */
'use strict';

// Private scope: classic scripts share one global lexical scope.
(function () {

const Fmt = (typeof module !== 'undefined' && module.exports)
  ? require('./format.js')
  : window.CimbarFormat;

// ── Fit ──────────────────────────────────────────────────────────────────

/** Longest-side presets in pixels. "Original" is added by candidateSides. */
const PHOTO_PRESETS = [320, 480, 640, 800, 1024, 1280, 1440, 1600, 1920, 2560, 3840];

const QUALITY_HIGH = 95;
const QUALITY_GOOD = 50;
const QUALITY_FLOOR = 30;

/** Descending longest sides to try: the original, then every preset strictly smaller. Never upscales. */
function candidateSides(longest) {
  return [longest, ...[...PHOTO_PRESETS].reverse().filter((p) => p < longest)];
}

/**
 * Largest side reaching quality >= 50, else the largest side fitting at
 * quality >= 30, else the smallest result, unfit.
 * session: {width, height, encode(maxSide, quality) -> Promise<Uint8Array>, close()}
 */
async function fitToBudget(session, budget) {
  const sides = candidateSides(Math.max(session.width, session.height));

  const encodeAt = async (side, q) => {
    const bytes = await session.encode(side, q);
    return { maxSide: side, quality: q, bytes, fits: bytes.length <= budget };
  };

  // Highest quality in (lo, hi] that fits, given `known` (at lo) already fits.
  const best = async (side, lo, hi, known) => {
    let found = known;
    let a = lo + 1;
    let b = hi;
    while (a <= b) {
      const mid = Math.floor((a + b) / 2);
      const r = await encodeAt(side, mid);
      if (r.fits) { found = r; a = mid + 1; } else { b = mid - 1; }
    }
    return found;
  };

  if (budget <= 0) return encodeAt(sides[sides.length - 1], QUALITY_FLOOR);

  for (const side of sides) {
    const r = await encodeAt(side, QUALITY_GOOD);
    if (r.fits) return best(side, QUALITY_GOOD, QUALITY_HIGH, r);
  }
  let last;
  for (const side of sides) {
    const r = await encodeAt(side, QUALITY_FLOOR);
    last = r;
    if (r.fits) return best(side, QUALITY_FLOOR, QUALITY_GOOD - 1, r);
  }
  return last;
}

/** One encode at the user's chosen settings. */
async function encodeManual(session, { maxSide, quality, budget }) {
  const bytes = await session.encode(maxSide, quality);
  return { maxSide, quality, bytes, fits: bytes.length <= budget };
}

// ── Frame budget ─────────────────────────────────────────────────────────

/** AES-GCM envelope: magic 4 + salt 16 + IV 12 + tag 16. */
const ENCRYPTION_OVERHEAD = 48;
/** Source frames the coding layer accepts (coding.maxFrames). */
const MAX_FRAMES = 4096;

function utf8Length(s) { return new TextEncoder().encode(s).length; }

/** Container bytes before compression: length prefix 4 + name-length field 4 + name + data (+ envelope). */
function framedBytes(nameBytes, dataBytes, encrypted) {
  return 4 + 4 + nameBytes + dataBytes + (encrypted ? ENCRYPTION_OVERHEAD : 0);
}

/** Source frame count for a file of dataBytes under name. */
function framesForFile(name, dataBytes, encrypted) {
  const framed = framedBytes(utf8Length(name), dataBytes, encrypted);
  return Math.max(1, Math.ceil(framed / Fmt.fileBytesPerFrame()));
}

/** Largest incompressible file size that still fits `frames` frames when encrypted. May be <= 0. */
function photoByteBudget(frames, name) {
  return frames * Fmt.fileBytesPerFrame() - framedBytes(utf8Length(name), 0, true);
}

// ── Names and eligibility ────────────────────────────────────────────────

const UUID_STEM = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `photo-yyyyMMdd-HHmmss.jpg` when no name or only a UUID, else the base name with `.jpg`. */
function optimisedFileName(original, now) {
  if (original === undefined || original === null || original === '') {
    const two = (n) => String(n).padStart(2, '0');
    const date = String(now.getFullYear()).padStart(4, '0') + two(now.getMonth() + 1) + two(now.getDate());
    const time = two(now.getHours()) + two(now.getMinutes()) + two(now.getSeconds());
    return `photo-${date}-${time}.jpg`;
  }
  const dot = original.lastIndexOf('.');
  const base = dot > 0 ? original.slice(0, dot) : original;
  if (UUID_STEM.test(base)) return optimisedFileName(undefined, now);
  return `${base}.jpg`;
}

const NEVER_TYPES = ['image/gif', 'image/svg+xml', 'image/tiff', 'image/x-icon', 'image/vnd.microsoft.icon'];
const IMAGE_EXTS = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];

/**
 * Whether a picked file should go to the optimiser. `head` is the file's first
 * bytes; `sniff(head)` is the caller's HEIF content check (kept out of here).
 */
function isOptimisable(name, type, head, sniff) {
  const lower = String(name || '').toLowerCase();
  const t = String(type || '').toLowerCase();
  const ext = lower.includes('.') ? lower.slice(lower.lastIndexOf('.') + 1) : '';
  if (NEVER_TYPES.includes(t) || ext === 'gif' || ext === 'svg' || ext === 'tif' || ext === 'tiff' || ext === 'ico') return false;
  if (head && head.length >= 4 && head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38) return false;
  if (t.startsWith('image/')) return true;
  if (IMAGE_EXTS.includes(ext)) return true;
  return !!(sniff && head && sniff(head));
}

const API = {
  PHOTO_PRESETS, candidateSides, fitToBudget, encodeManual,
  ENCRYPTION_OVERHEAD, MAX_FRAMES,
  framedBytes, framesForFile, photoByteBudget,
  optimisedFileName, isOptimisable,
};

if (typeof module !== 'undefined' && module.exports) module.exports = API;
else window.CimbarPhotoFit = API;

})();
