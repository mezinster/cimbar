/**
 * photo-optimiser.js — the DOM-free photo optimiser controller behind an IO
 * seam (an encoder-session factory, a clock and a change callback), so Node
 * tests cover it without a DOM. The screen in index.html renders its state and
 * forwards taps to it; the fit itself is photo-fit.js, the encoder
 * canvas-jpeg.js.
 *
 * Port of NFC Archiver's app/ui/photo-optimiser.ts with frames of 2104 bytes
 * for its tags, and the app's frame rules (photo_optimiser_provider.dart): a
 * count set while the photo is still opening is kept, and an unfit result
 * offers both "Continue with M frames" and "Continue with this image".
 */
'use strict';

// Private scope: classic scripts share one global lexical scope.
(function () {

const isNode = typeof module !== 'undefined' && module.exports;
// Resolved at call time so load order in the page does not matter.
const photoFit = () => (isNode ? require('./photo-fit.js') : window.CimbarPhotoFit);
const canvasJpeg = () => (isNode ? require('./canvas-jpeg.js') : window.CimbarCanvasJpeg);
const imageDecode = () => (isNode ? require('./image-decode.js') : window.CimbarImageDecode);

/** Stepper and slider changes wait this long before re-fitting. */
const REFIT_DEBOUNCE_MS = 250;

/** Hold-to-repeat: the first repeat comes this long after the press. */
const HOLD_INITIAL_DELAY_MS = 400;

/** The delay before the next repeat, after `elapsed` ms of holding. */
function holdIntervalAfter(elapsed) {
  if (elapsed < 1000) return 300;
  if (elapsed < 2000) return 100;
  return 50;
}

/** The step multiplier after `elapsed` ms of holding. */
function holdMultiplierAfter(elapsed) {
  return elapsed >= 3000 ? 10 : 1;
}

/** The result's pixel size: the oriented source scaled so its longest side is `maxSide`, never up. */
function previewDimensions(width, height, maxSide) {
  const longest = Math.max(width, height);
  if (maxSide >= longest) return { width, height };
  const scale = (v) => Math.round((v * maxSide) / longest);
  return { width: scale(width), height: scale(height) };
}

/**
 * Steps once per tap and repeats while held: the first repeat after 400 ms,
 * then every 300 ms; every 100 ms after 1 s, every 50 ms after 2 s, and from
 * 3 s on each step is 10. Elapsed time is the sum of the scheduled delays, so
 * the schedule is exact under a fake clock.
 * clock: {setTimeout(fn, ms), clearTimeout(handle)};
 * cb: {onStep(delta), onHoldStart?(), onHoldEnd?()}.
 */
class HoldRepeater {
  constructor(clock, cb) {
    this._clock = clock;
    this._cb = cb;
    this._timer = null;
    this._elapsed = 0;
    this._repeated = false;
    this._step = 0;
  }

  press(step) {
    this._stopTimer();
    this._step = step;
    this._repeated = false;
    this._elapsed = HOLD_INITIAL_DELAY_MS;
    this._timer = this._clock.setTimeout(() => this._repeat(), HOLD_INITIAL_DELAY_MS);
  }

  /** Pointer up: a plain tap steps once; a released hold ends without an extra step. */
  release() {
    if (this._timer === null && !this._repeated) return; // not pressed
    this._stopTimer();
    if (this._repeated) { if (this._cb.onHoldEnd) this._cb.onHoldEnd(); }
    else this._cb.onStep(this._step);
    this._repeated = false;
  }

  /** Pointer cancelled or left: no tap step; a hold that repeated still ends. */
  cancel() {
    this._stopTimer();
    if (this._repeated && this._cb.onHoldEnd) this._cb.onHoldEnd();
    this._repeated = false;
  }

  _repeat() {
    if (!this._repeated) {
      this._repeated = true;
      if (this._cb.onHoldStart) this._cb.onHoldStart();
    }
    this._cb.onStep(this._step * holdMultiplierAfter(this._elapsed));
    const next = holdIntervalAfter(this._elapsed);
    this._elapsed += next;
    this._timer = this._clock.setTimeout(() => this._repeat(), next);
  }

  _stopTimer() {
    if (this._timer !== null) this._clock.clearTimeout(this._timer);
    this._timer = null;
  }
}

/** Thrown inside a fit that a newer request has superseded. */
class Stale extends Error {}

/**
 * The optimiser for one picked photo. It starts opening the photo on its own
 * (`ready` settles when the open and probe are done, success or failure).
 *
 * io = {openSession(blob) → Promise<session>, clock: {setTimeout, clearTimeout},
 *       onChange(state), warn?(msg)}; a session is canvas-jpeg.js's
 *       {width, height, encode(maxSide, quality) → Promise<Uint8Array>, close()}.
 * photo = {source: Blob, fileName, originalSize, now?: Date}.
 *
 * State (pushed to onChange on every change, also `state`):
 *   frames, cap (1 … min(frames of the original as picked, 4096)),
 *   mode 'auto'|'manual', manualSide, manualQuality,
 *   result {maxSide, quality, bytes, fits} | null,
 *   needed (smallest frame count whose budget holds result) | null,
 *   width, height (oriented source; 0 until open), busy,
 *   error 'none' | 'decodeFailed' | 'tooLarge' (both final: Skip is the way on)
 *         | 'memory' (no side of this fit could be encoded here; the next
 *           change re-fits and clears it),
 *   largerThanOriginal, continueWithFrames (M, when unfit and M ≤ 4096),
 *   asIsFrames (K, the unfit result's own frame count).
 *
 * continueAsShown, continueAtNeeded (when it succeeds) and skip end the
 * optimiser: the session is closed and nothing is published afterwards.
 */
class PhotoOptimiser {
  constructor(io, photo) {
    const Fit = photoFit();
    this._io = io;
    this._photo = photo;
    this.outputName = Fit.optimisedFileName(photo.fileName, photo.now || new Date());
    this._session = null;
    this._disposed = false;
    this._debounce = null;
    this._holding = false;
    this._framesChosen = false;
    this._gen = 0;
    this._chain = Promise.resolve();
    this._autoFits = new Map(); // frames → auto fit result
    this._s = {
      frames: 1,
      cap: Math.min(Fit.framesForFile(String(photo.fileName || ''), photo.originalSize, true), Fit.MAX_FRAMES),
      mode: 'auto',
      manualSide: null,
      manualQuality: null,
      result: null,
      needed: null,
      width: 0,
      height: 0,
      busy: true,
      error: 'none',
      largerThanOriginal: false,
      continueWithFrames: null,
      asIsFrames: null,
    };
    // A microtask later, so onChange never runs inside the constructor.
    this.ready = Promise.resolve().then(() => this._open());
  }

  get state() {
    return this._s;
  }

  /** decodeFailed and tooLarge end the optimiser's work; memory does not. */
  _final() {
    return this._s.error === 'decodeFailed' || this._s.error === 'tooLarge';
  }

  _set(patch) {
    if (this._disposed) return;
    const s = Object.assign({}, this._s, patch);
    const r = s.result;
    const unfit = r !== null && !r.fits;
    s.largerThanOriginal = r !== null && r.bytes.length >= this._photo.originalSize;
    s.continueWithFrames = unfit && s.needed !== null && s.needed <= photoFit().MAX_FRAMES ? s.needed : null;
    s.asIsFrames = unfit ? this._framesFor(r.bytes.length) : null;
    this._s = s;
    this._io.onChange(s);
  }

  /**
   * Frames the optimised file needs (encryption reserved). Also the smallest N
   * whose photoByteBudget(N) holds `bytes`: both are ceil(framed / 2104).
   */
  _framesFor(bytes) {
    return photoFit().framesForFile(this.outputName, bytes, true);
  }

  /** Decodes the photo, picks the starting count from a 640 px / q70 probe and runs the first fit. */
  async _open() {
    if (this._disposed) return;
    try {
      const session = await this._io.openSession(this._photo.source);
      if (this._disposed) {
        this._closeQuietly(session);
        return;
      }
      this._session = session;
      const longest = Math.max(session.width, session.height);
      let probeFrames = 1;
      try {
        const probe = await session.encode(Math.min(640, longest), 70);
        probeFrames = this._framesFor(probe.length);
      } catch (e) {
        if (!(e instanceof canvasJpeg().SideTooLargeError)) throw e; // the fit then reports what it can
      }
      if (this._disposed) return;
      // The starting count is a suggestion: a count set while opening stands.
      const frames = this._framesChosen ? this._s.frames : Math.min(Math.max(probeFrames, 1), this._s.cap);
      this._set({ width: session.width, height: session.height, frames });
      this._schedule(true);
    } catch (e) {
      if (!this._disposed) this._fail(e);
    }
  }

  setFrames(n) {
    this._framesChosen = true;
    const frames = Math.min(Math.max(Math.round(n), 1), this._s.cap);
    if (frames === this._s.frames) return;
    this._set({ frames });
    this._schedule();
  }

  step(delta) {
    this.setFrames(this._s.frames + delta);
  }

  /** A held stepper: steps move the count on screen but fit nothing until endHold. */
  beginHold() {
    this._holding = true;
    this._clearDebounce();
    this._gen++; // a fit already under way is stale now
    if (this._session !== null && !this._final()) this._set({ busy: true });
  }

  endHold() {
    if (this._disposed || !this._holding) return;
    this._holding = false;
    this._schedule();
  }

  /** Switches to manual mode, starting from the current result's settings. A side re-fits now, quality after the debounce. */
  setManual(opts = {}) {
    if (this._final() || this._session === null) return;
    const st = this._s;
    const manual = st.mode === 'manual';
    const pick = (...vs) => vs.find((v) => v !== undefined && v !== null);
    this._set({
      mode: 'manual',
      manualSide: pick(opts.side, manual ? st.manualSide : null, st.result && st.result.maxSide, Math.max(st.width, st.height)),
      manualQuality: pick(opts.quality, manual ? st.manualQuality : null, st.result && st.result.quality, 70),
    });
    this._schedule(opts.quality === undefined);
  }

  backToAuto() {
    if (this._s.mode === 'auto') return;
    this._set({ mode: 'auto' });
    this._schedule(true);
  }

  /**
   * The shown result as it is (Continue, or "Continue with this image (K
   * frames)" when unfit); `frames` is its own frame count. Null while busy,
   * failed or without a result. Ends the optimiser.
   */
  continueAsShown() {
    const r = this._s.result;
    if (this._disposed || this._s.busy || this._final() || r === null) return null;
    const choice = { kind: 'optimised', name: this.outputName, bytes: r.bytes, frames: this._framesFor(r.bytes.length) };
    this.dispose();
    return choice;
  }

  /**
   * "Continue with M frames": raises the count to `continueWithFrames` (past
   * the cap if need be, never past 4096), re-fits at once and, if that fits,
   * behaves as continueAsShown. Auto may find a better image that still fits;
   * manual keeps its side and quality. Null when busy, failed, superseded,
   * disposed or still not fitting.
   */
  async continueAtNeeded() {
    const st = this._s;
    const frames = st.continueWithFrames;
    if (this._disposed || st.busy || frames === null || this._session === null) return null;
    this._clearDebounce();
    this._holding = false;
    this._framesChosen = true;
    this._set({ frames, cap: Math.max(st.cap, frames) });
    const gen = ++this._gen;
    this._set({ busy: true });
    const done = (this._chain = this._chain.then(() => this._fit(gen)));
    await done;
    if (!this._isCurrent(gen)) return null;
    const after = this._s;
    if (after.frames !== frames || after.result === null || !after.result.fits) return null;
    return this.continueAsShown();
  }

  /** The original file, untouched. Ends the optimiser. */
  skip() {
    this.dispose();
    return { kind: 'original' };
  }

  /** Closes the session; later callbacks and fits are ignored. Idempotent. */
  dispose() {
    if (this._disposed) return;
    this._disposed = true;
    this._gen++;
    this._clearDebounce();
    const s = this._session;
    this._session = null;
    if (s !== null) this._closeQuietly(s);
  }

  _closeQuietly(session) {
    try { session.close(); } catch (e) { this._warn('encoder session close failed'); }
  }

  _warn(msg) {
    if (this._io.warn) this._io.warn(msg);
  }

  _clearDebounce() {
    if (this._debounce !== null) this._io.clock.clearTimeout(this._debounce);
    this._debounce = null;
  }

  _schedule(now = false) {
    if (this._session === null || this._final() || this._disposed) return;
    const gen = ++this._gen;
    this._clearDebounce();
    this._set({ busy: true });
    if (this._holding) return; // endHold schedules the fit
    const run = () => {
      this._debounce = null;
      this._chain = this._chain.then(() => this._fit(gen));
    };
    if (now) run();
    else this._debounce = this._io.clock.setTimeout(run, REFIT_DEBOUNCE_MS);
  }

  _isCurrent(gen) {
    return gen === this._gen && !this._disposed;
  }

  async _fit(gen) {
    const inner = this._session;
    if (inner === null || !this._isCurrent(gen)) return;
    const Fit = photoFit();
    const { SideTooLargeError } = canvasJpeg();
    const st = this._s;
    const budget = Fit.photoByteBudget(st.frames, this.outputName);
    // A side the encoder can't produce here comes back as a stand-in one byte
    // over the budget, so the fit treats it as "doesn't fit" and moves on.
    // photo-fit.js only compares `.length`, so the stand-in is one zero-filled
    // buffer per fit, made on the first refusal and shared by every later one
    // (engines map zeroed memory lazily, and it is never written). Identity
    // marks it, so it never leaves this method.
    let standIn = null;
    // The search visits each side at up to two qualities; a side refused once
    // is not asked for again (a refusal costs a decode and a canvas).
    const refused = new Set();
    // Aborts a superseded search at its next encode instead of running it to the end.
    const guarded = {
      width: inner.width,
      height: inner.height,
      encode: async (side, q) => {
        if (!this._isCurrent(gen)) throw new Stale();
        let bytes;
        try {
          if (refused.has(side)) throw new SideTooLargeError();
          bytes = await inner.encode(side, q);
        } catch (e) {
          if (!(e instanceof SideTooLargeError)) throw e;
          refused.add(side);
          if (standIn === null) standIn = new Uint8Array(Math.max(budget + 1, 1));
          bytes = standIn;
        }
        if (!this._isCurrent(gen)) throw new Stale();
        return bytes;
      },
      close: () => {},
    };
    try {
      let r;
      if (st.mode === 'auto') {
        r = this._autoFits.get(st.frames);
        if (r === undefined) {
          r = await Fit.fitToBudget(guarded, budget);
          this._autoFits.set(st.frames, r);
        }
      } else {
        r = await Fit.encodeManual(guarded, { maxSide: st.manualSide, quality: st.manualQuality, budget });
      }
      if (!this._isCurrent(gen)) return;
      if (standIn !== null && r.bytes === standIn) {
        this._autoFits.delete(st.frames);
        this._set({ result: null, needed: null, busy: false, error: 'memory' });
        return;
      }
      this._set({ result: r, needed: this._framesFor(r.bytes.length), busy: false, error: 'none' });
    } catch (e) {
      if (e instanceof Stale) return;
      if (this._isCurrent(gen)) this._fail(e);
    }
  }

  _fail(e) {
    this._warn(`photo optimiser failed: ${e instanceof Error ? e.name : typeof e}`);
    const error = e instanceof imageDecode().ImageTooLargeError ? 'tooLarge' : 'decodeFailed';
    this._set({ error, busy: false, result: null, needed: null });
  }
}

const API = {
  REFIT_DEBOUNCE_MS, HOLD_INITIAL_DELAY_MS, holdIntervalAfter, holdMultiplierAfter,
  HoldRepeater, previewDimensions, PhotoOptimiser,
};

if (isNode) module.exports = API;
else window.CimbarPhotoOptimiser = API;

})();
