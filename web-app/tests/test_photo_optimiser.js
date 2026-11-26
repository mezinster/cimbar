// photo-optimiser.js: the DOM-free optimiser controller under a fake clock and
// fake encoder sessions. Port of NFC Archiver's test/photo-optimiser.test.ts
// (tags → frames of 2104 bytes; tag-type switching and archiveGate dropped),
// plus the app's frame rules (photo_optimiser_test.dart).
'use strict';
const path = require('path');

const M = require(path.join(__dirname, '..', 'photo-optimiser.js'));
const Fit = require(path.join(__dirname, '..', 'photo-fit.js'));
const { SideTooLargeError } = require(path.join(__dirname, '..', 'canvas-jpeg.js'));
const { PhotoDecodeError, ImageTooLargeError } = require(path.join(__dirname, '..', 'image-decode.js'));
const {
  PhotoOptimiser, HoldRepeater, previewDimensions, holdIntervalAfter, holdMultiplierAfter,
  REFIT_DEBOUNCE_MS, HOLD_INITIAL_DELAY_MS,
} = M;
const { photoByteBudget, framesForFile, MAX_FRAMES } = Fit;

let passed = 0, failed = 0;
let unhandled = 0;
process.on('unhandledRejection', () => { unhandled++; });
let chain = Promise.resolve();
function test(name, fn) {
  chain = chain.then(async () => {
    try { await fn(); passed++; console.log(`  PASS  ${name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); }
  });
}
function assert(c, msg) { if (!c) throw new Error(msg); }
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}

const model = (side, q) => Math.floor((side * side * q) / 1000);
const ORIGINAL_SIZE = 3_000_000;
const NAME = 'IMG_1.HEIC';
const OUT = 'IMG_1.jpg';

/** Smallest N whose budget holds `bytes`, by search (independent of the controller's closed form). */
function neededFor(bytes) {
  let n = 1;
  while (photoByteBudget(n, OUT) < bytes) n++;
  return n;
}

/** Timers that only fire when the test advances time. */
class FakeClock {
  constructor() { this.now = 0; this.timers = []; this.next = 1; }
  setTimeout(fn, ms) {
    const id = this.next++;
    this.timers.push({ id, at: this.now + ms, fn });
    return id;
  }
  clearTimeout(h) { this.timers = this.timers.filter((t) => t.id !== h); }
  pending() { return this.timers.length; }
  advance(ms) {
    const end = this.now + ms;
    for (;;) {
      this.timers.sort((a, b) => a.at - b.at || a.id - b.id);
      const t = this.timers[0];
      if (!t || t.at > end) break;
      this.timers.shift();
      this.now = t.at;
      t.fn();
    }
    this.now = end;
  }
}

/** An encoder session whose output length is computed by `size`. */
class FakeJpegSession {
  constructor(width, height, size) {
    this.width = width; this.height = height; this.size = size;
    this.calls = []; this.closed = false;
  }
  async encode(maxSide, quality) {
    this.calls.push({ maxSide, quality });
    return new Uint8Array(this.size(maxSide, quality));
  }
  close() { this.closed = true; }
}

/** Encodes that resolve only when the test releases them. */
class GatedSession {
  constructor() {
    this.width = 4032; this.height = 3024;
    this.gated = false; this.calls = []; this.waiting = []; this.closed = false;
  }
  async encode(maxSide, quality) {
    this.calls.push({ maxSide, quality });
    if (this.gated) await new Promise((r) => this.waiting.push(r));
    return new Uint8Array(model(maxSide, quality));
  }
  releaseAll() {
    const w = this.waiting;
    this.waiting = [];
    for (const r of w) r();
  }
  close() { this.closed = true; }
}

/** An encoder that, like iOS Safari's canvas, cannot produce sides above `limit`. */
function cappedSession(limit) {
  const inner = new FakeJpegSession(8064, 6048, model);
  inner.refused = [];
  const encode = inner.encode.bind(inner);
  inner.encode = async (side, q) => {
    if (side > limit) { inner.refused.push(side); throw new SideTooLargeError(); }
    return encode(side, q);
  };
  return inner;
}

const flush = async () => {
  for (let i = 0; i < 50; i++) await new Promise((r) => setImmediate(r));
};

function setup(opts = {}) {
  const clock = new FakeClock();
  const session = opts.session || new FakeJpegSession(4032, 3024, model);
  const states = [];
  const warnings = [];
  // ctl.throwNext: the next onChange throws once (a buggy listener).
  const ctl = { throwNext: false };
  const io = {
    openSession: opts.open || (async () => session),
    clock,
    onChange: (s) => {
      states.push(s);
      if (ctl.throwNext) { ctl.throwNext = false; throw new Error('listener'); }
    },
    warn: (msg) => warnings.push(msg),
  };
  const opt = new PhotoOptimiser(io, {
    source: {},
    fileName: NAME,
    originalSize: opts.originalSize !== undefined ? opts.originalSize : ORIGINAL_SIZE,
  });
  return { opt, clock, session, states, warnings, ctl };
}

/** Opened and first fit landed. */
async function opened(opts) {
  const h = setup(opts);
  await h.opt.ready;
  await flush();
  return h;
}

// ── Hold schedule ────────────────────────────────────────────────────────

test('constants: 250 ms debounce, first repeat after 400 ms', () => {
  eq(REFIT_DEBOUNCE_MS, 250, 'debounce');
  eq(HOLD_INITIAL_DELAY_MS, 400, 'initial delay');
});

test('hold schedule: 300 ms, then 100 ms after 1 s, 50 ms after 2 s, x10 from 3 s', () => {
  eq(holdIntervalAfter(400), 300, '400');
  eq(holdIntervalAfter(999), 300, '999');
  eq(holdIntervalAfter(1000), 100, '1000');
  eq(holdIntervalAfter(2000), 50, '2000');
  eq(holdMultiplierAfter(2999), 1, '2999');
  eq(holdMultiplierAfter(3000), 10, '3000');
});

test('HoldRepeater: a tap is one step, a hold repeats on the schedule and stops on release', () => {
  const clock = new FakeClock();
  const steps = [];
  const events = [];
  const r = new HoldRepeater(clock, {
    onStep: (d) => steps.push(d),
    onHoldStart: () => events.push('start'),
    onHoldEnd: () => events.push('end'),
  });

  r.press(1);
  clock.advance(100);
  r.release();
  eq(steps, [1], 'tap');
  eq(events, [], 'no hold events for a tap');

  steps.length = 0;
  r.press(-1);
  clock.advance(500); // first repeat at 400
  eq(steps, [-1], 'first repeat');
  eq(events, ['start'], 'hold started');
  clock.advance(1000); // t=1500
  eq(steps.length, 1 + 1 + 1 + 5, '400, 700, 1000, then every 100 ms to 1500');
  clock.advance(2000); // t=3500
  assert(steps.includes(-10), 'steps of 10 after 3 s');
  r.release();
  const n = steps.length;
  clock.advance(5000);
  eq(steps.length, n, 'no steps after release');
  eq(events, ['start', 'end'], 'hold ended');
  eq(clock.pending(), 0, 'no timers left');
});

test('HoldRepeater: cancel stops a hold without a tap step', () => {
  const clock = new FakeClock();
  const steps = [];
  const r = new HoldRepeater(clock, { onStep: (d) => steps.push(d) });
  r.press(1);
  clock.advance(100);
  r.cancel();
  clock.advance(1000);
  eq(steps, [], 'no steps');
});

test('previewDimensions scales the oriented size to the result side, never up', () => {
  eq(previewDimensions(4032, 3024, 640), { width: 640, height: 480 }, 'landscape');
  eq(previewDimensions(3024, 4032, 640), { width: 480, height: 640 }, 'portrait');
  eq(previewDimensions(800, 600, 4032), { width: 800, height: 600 }, 'never up');
});

// ── Opening and the auto fit ─────────────────────────────────────────────

test('auto fit on open: starting frames from the 640/q70 probe, best fit for that budget', async () => {
  const { opt, session, states } = await opened();
  const s = opt.state;
  eq(s.width, 4032, 'width');
  eq(s.height, 3024, 'height');
  // Probe 640²·70/1000 = 28672 B → ceil((8 + 9 + 28672 + 48) / 2104) = 14 frames.
  eq(s.frames, framesForFile(OUT, model(640, 70), true), 'frames of the 640/q70 encode');
  eq(s.frames, 14, 'frames');
  eq(s.cap, Math.ceil((ORIGINAL_SIZE + 8 + NAME.length + 48) / 2104), 'cap = frames of the original');
  eq(s.mode, 'auto', 'mode');
  eq(s.busy, false, 'busy');
  eq(s.error, 'none', 'error');
  assert(s.result, 'result');
  eq(s.result.fits, true, 'fits');
  // Budget 14·2104 − 65 = 29391: 640 px reaches q50, best quality 71.
  eq(s.result.maxSide, 640, 'maxSide');
  eq(s.result.quality, 71, 'quality');
  assert(s.result.bytes.length <= photoByteBudget(14, OUT), 'within budget');
  eq(s.needed, neededFor(s.result.bytes.length), 'needed');
  eq(s.largerThanOriginal, false, 'smaller than original');
  eq(s.continueWithFrames, null, 'no continue-with when it fits');
  eq(s.asIsFrames, null, 'no as-is count when it fits');
  eq(opt.outputName, OUT, 'output name');
  eq(session.calls[0], { maxSide: 640, quality: 70 }, 'first encode is the probe');
  assert(states.length > 0, 'state changes are pushed');
  eq(states[states.length - 1], s, 'last pushed state is the current one');
});

test('the cap never exceeds 4096 frames', async () => {
  const { opt, clock } = setup({ originalSize: 1_000_000_000 });
  eq(opt.state.cap, MAX_FRAMES, 'cap');
  opt.setFrames(1_000_000);
  eq(opt.state.frames, MAX_FRAMES, 'frames');
  clock.advance(REFIT_DEBOUNCE_MS);
  opt.dispose();
});

test('tiny original: cap 1, stepper clamps, largerThanOriginal', async () => {
  const { opt, clock } = await opened({ originalSize: 100 });
  eq(opt.state.cap, 1, 'cap');
  eq(opt.state.frames, 1, 'starting frames clamped to the cap');
  opt.step(5);
  eq(opt.state.frames, 1, 'step up clamped');
  opt.setFrames(0);
  eq(opt.state.frames, 1, 'set below 1 clamped');
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  assert(opt.state.result, 'result');
  eq(opt.state.largerThanOriginal, true, 'the JPEG is larger than a 100 B original');
});

test('+/- re-fit after the debounce, clamped to [1, cap]', async () => {
  const { opt, clock, session } = await opened();
  const before = session.calls.length;

  opt.step(-7);
  eq(opt.state.frames, 7, 'frames');
  eq(opt.state.busy, true, 'busy while the refit is pending');
  await flush();
  eq(session.calls.length, before, 'nothing encodes before the debounce');
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  eq(opt.state.busy, false, 'not busy');
  assert(opt.state.result.bytes.length <= photoByteBudget(7, OUT), 'within the 7-frame budget');
  assert(opt.state.result.maxSide < 640, 'smaller side');

  opt.step(-1000);
  eq(opt.state.frames, 1, 'clamped to 1');
  opt.setFrames(1_000_000);
  eq(opt.state.frames, opt.state.cap, 'clamped to cap');
});

test('a hold fits once, after release', async () => {
  const { opt, clock, session } = await opened();
  opt.beginHold();
  for (let i = 0; i < 10; i++) opt.step(1);
  clock.advance(2000);
  await flush();
  const during = session.calls.length;
  eq(opt.state.frames, 24, 'frames moved');
  eq(opt.state.busy, true, 'busy while held');
  opt.endHold();
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  assert(session.calls.length > during, 'fits after release');
  eq(opt.state.busy, false, 'not busy');
  assert(opt.state.result.bytes.length <= photoByteBudget(24, OUT), 'within the 24-frame budget');
});

test('manual, then back to auto', async () => {
  const { opt, clock } = await opened();
  const auto = opt.state.result;

  opt.setManual({ side: 1024 });
  eq(opt.state.mode, 'manual', 'mode');
  eq(opt.state.manualSide, 1024, 'side');
  eq(opt.state.manualQuality, auto.quality, 'quality starts from the auto result');
  await flush();
  eq(opt.state.result.maxSide, 1024, 'manual side encoded');
  eq(opt.state.result.fits, false, 'does not fit');
  eq(opt.state.needed, neededFor(model(1024, auto.quality)), 'needed');

  opt.setManual({ quality: 30 });
  eq(opt.state.manualSide, 1024, 'side kept');
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  eq(opt.state.result.quality, 30, 'quality');

  opt.backToAuto();
  eq(opt.state.mode, 'auto', 'auto');
  await flush();
  eq(opt.state.result.maxSide, auto.maxSide, 'auto side back');
  eq(opt.state.result.quality, auto.quality, 'auto quality back');
});

test('a count set while opening is kept', async () => {
  let resolve;
  const session = new FakeJpegSession(4032, 3024, model);
  const { opt } = setup({ open: () => new Promise((r) => { resolve = r; }) });
  await flush(); // opening has started
  opt.setFrames(2);
  eq(opt.state.frames, 2, 'frames while opening');
  eq(opt.state.busy, true, 'still busy');
  resolve(session);
  await opt.ready;
  await flush();
  eq(opt.state.frames, 2, 'the probe does not overwrite it');
  assert(opt.state.result, 'fitted');
  assert(opt.state.result.bytes.length <= photoByteBudget(2, OUT), 'fitted for 2 frames');
});

// ── Continue / Skip ──────────────────────────────────────────────────────

test('continueAsShown hands back the optimised bytes under a .jpg name and ends the optimiser', async () => {
  const { opt, session, states } = await opened();
  const bytes = opt.state.result.bytes;
  const choice = opt.continueAsShown();
  assert(choice, 'choice');
  eq(choice.kind, 'optimised', 'kind');
  eq(choice.name, OUT, 'name');
  assert(choice.bytes === bytes, 'the result bytes');
  eq(choice.frames, framesForFile(OUT, bytes.length, true), 'true frame count');
  eq(session.closed, true, 'session closed');
  const n = states.length;
  opt.step(1);
  eq(states.length, n, 'nothing published after it ended');
});

test('continueAsShown is null while busy or without a result', async () => {
  const { opt } = setup();
  eq(opt.continueAsShown(), null, 'before open');
  await opt.ready;
  opt.step(-1);
  eq(opt.state.busy, true, 'busy');
  eq(opt.continueAsShown(), null, 'while busy');
  opt.dispose();
});

test('skip keeps the original and closes the session', async () => {
  const { opt, session } = await opened();
  eq(opt.skip(), { kind: 'original' }, 'choice');
  eq(session.closed, true, 'session closed');
});

// ── Failures ─────────────────────────────────────────────────────────────

test('decode failure: error state, no result, Continue refused, Skip still works', async () => {
  const { opt } = await opened({ open: async () => { throw new PhotoDecodeError(); } });
  eq(opt.state.error, 'decodeFailed', 'error');
  eq(opt.state.busy, false, 'busy');
  eq(opt.state.result, null, 'result');
  eq(opt.continueAsShown(), null, 'continue refused');
  opt.setManual({ side: 640 });
  eq(opt.state.mode, 'auto', 'manual is ignored after a failure');
  eq(opt.skip().kind, 'original', 'skip');
});

test('any other open failure is decodeFailed too', async () => {
  const { opt } = await opened({ open: async () => { throw new Error('boom'); } });
  eq(opt.state.error, 'decodeFailed', 'error');
});

test('an image too large to decode: error tooLarge', async () => {
  const { opt } = await opened({ open: async () => { throw new ImageTooLargeError(); } });
  eq(opt.state.error, 'tooLarge', 'error');
  eq(opt.state.busy, false, 'busy');
  eq(opt.state.result, null, 'result');
  eq(opt.continueAsShown(), null, 'continue refused');
});

test('an encode failure after open is the same decode-failed state', async () => {
  let n = 0;
  const s = new FakeJpegSession(4032, 3024, model);
  const failing = {
    width: s.width, height: s.height,
    encode: async (side, q) => { if (n++ > 0) throw new Error('encode'); return s.encode(side, q); },
    close: () => s.close(),
  };
  const { opt } = await opened({ session: failing });
  eq(opt.state.error, 'decodeFailed', 'error');
});

// ── Staleness and dispose ────────────────────────────────────────────────

test('stale results are dropped: a superseded fit never lands', async () => {
  const session = new GatedSession();
  const { opt, clock, states } = await opened({ session });
  eq(opt.state.result.maxSide, 640, 'first fit');

  session.gated = true;
  opt.setManual({ side: 4032 }); // fit A: blocks inside its encode
  await flush();
  eq(session.calls[session.calls.length - 1].maxSide, 4032, 'fit A encoding');
  opt.backToAuto(); // fit B supersedes A while A is still encoding
  states.length = 0;
  session.gated = false;
  session.releaseAll();
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();

  assert(states.every((s) => !s.result || s.result.maxSide !== 4032), 'the 4032 px manual result was never published');
  eq(opt.state.mode, 'auto', 'mode');
  eq(opt.state.result.maxSide, 640, 'auto result');
  eq(opt.state.busy, false, 'busy');
});

test('dispose mid-fit: no onChange after it, session closed', async () => {
  const session = new GatedSession();
  const { opt, states } = await opened({ session });
  session.gated = true;
  opt.setManual({ side: 2560 });
  await flush();
  assert(session.waiting.length > 0, 'a fit is under way');
  opt.dispose();
  const n = states.length;
  session.gated = false;
  session.releaseAll();
  await flush();
  eq(states.length, n, 'nothing published after dispose');
  eq(session.closed, true, 'session closed');
});

test('a session opened after dispose is closed, and nothing is published', async () => {
  let resolve;
  const session = new FakeJpegSession(4032, 3024, model);
  const { opt, states } = setup({ open: () => new Promise((r) => { resolve = r; }) });
  await flush();
  opt.dispose();
  const count = states.length;
  resolve(session);
  await opt.ready;
  await flush();
  eq(session.closed, true, 'closed');
  eq(states.length, count, 'nothing published');
});

test('dispose before opening starts: no session is opened', async () => {
  let calls = 0;
  const { opt, states } = setup({ open: async () => { calls++; return new FakeJpegSession(10, 10, model); } });
  opt.dispose();
  await opt.ready;
  await flush();
  eq(calls, 0, 'openSession not called');
  eq(states.length, 0, 'nothing published');
});

// ── Sides the browser cannot encode ──────────────────────────────────────

test('a side the browser cannot encode counts as "doesn\'t fit": auto moves on to a smaller side', async () => {
  const session = cappedSession(4000);
  const { opt, clock } = await opened({ session, originalSize: 30_000_000 });
  opt.setFrames(1600); // 3.37 MB: the 8064 px original at q50 (3.25 MB) would fit
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  assert(session.refused.includes(8064), 'the original side was tried and refused');
  eq(opt.state.error, 'none', 'error');
  eq(opt.state.result.maxSide, 3840, 'next side');
  eq(opt.state.result.fits, true, 'fits');
});

test('a side refused once is not asked for again in the same search', async () => {
  const session = cappedSession(1000);
  const { opt, clock } = await opened({ session, originalSize: 30_000_000 });
  session.refused.length = 0;
  // 1–2 frames: nothing reaches q50, so each search goes through the sides a
  // second time at q30, the refused ones included.
  opt.setFrames(2);
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  opt.setFrames(1);
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  assert(session.refused.length > 0, 'sides above the limit were tried');
  for (const side of new Set(session.refused)) {
    eq(session.refused.filter((s) => s === side).length, 2, `side ${side}: once per search`);
  }
});

test('manual Original above the browser limit: error memory, recoverable', async () => {
  const session = cappedSession(4000);
  const { opt } = await opened({ session, originalSize: 30_000_000 });
  opt.setManual({ side: 8064 });
  await flush();
  eq(opt.state.error, 'memory', 'error');
  eq(opt.state.result, null, 'result');
  eq(opt.state.busy, false, 'busy');
  eq(opt.state.continueWithFrames, null, 'no continue-with');
  eq(opt.state.asIsFrames, null, 'no as-is');
  eq(opt.continueAsShown(), null, 'continue refused');

  opt.setManual({ side: 1024 });
  await flush();
  eq(opt.state.error, 'none', 'cleared');
  eq(opt.state.result.maxSide, 1024, 'result');
});

test('every side refused: error memory at one frame, nothing to continue with', async () => {
  const { opt } = await opened({ session: cappedSession(100) });
  eq(opt.state.error, 'memory', 'error');
  eq(opt.state.frames, 1, 'the refused probe starts at one frame');
  eq(opt.state.result, null, 'result');
  eq(opt.state.continueWithFrames, null, 'no continue-with');
  eq(opt.state.asIsFrames, null, 'no as-is');
  opt.dispose();
});

// ── Continue with M frames / Continue with this image ────────────────────

/** Even the smallest side is 100 kB, so nothing fits 5 frames. */
const hugeSession = () => new FakeJpegSession(4032, 3024, () => 100_000);

async function openNothingFits(opts = {}) {
  const h = await opened({ session: hugeSession(), ...opts });
  h.opt.setFrames(5);
  h.clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  return h;
}

test('unfit: continueWithFrames and asIsFrames name the counts; continueAtNeeded fits at needed', async () => {
  const { opt, session } = await openNothingFits();
  const s = opt.state;
  eq(s.result.fits, false, 'unfit');
  eq(s.needed, neededFor(100_000), 'needed');
  assert(s.needed > s.frames, 'needed above the count');
  eq(s.continueWithFrames, s.needed, 'continue with M');
  eq(s.asIsFrames, framesForFile(OUT, 100_000, true), 'as-is K');
  const needed = s.needed;
  const choice = await opt.continueAtNeeded();
  assert(choice, 'choice');
  eq(choice.kind, 'optimised', 'kind');
  eq(choice.name, OUT, 'name');
  eq(choice.bytes.length, 100_000, 'bytes');
  eq(choice.frames, needed, 'frames');
  assert(choice.bytes.length <= photoByteBudget(needed, OUT), 'fits at needed');
  eq(opt.state.frames, needed, 'count raised');
  eq(session.closed, true, 'ended');
});

test('continueAsShown on an unfit result carries its true frame count', async () => {
  const { opt } = await openNothingFits();
  const k = opt.state.asIsFrames;
  const choice = opt.continueAsShown();
  eq(choice.frames, k, 'K frames');
  eq(choice.bytes.length, 100_000, 'the shown result');
});

test('no continue-with when the result fits', async () => {
  const { opt } = await opened();
  eq(opt.state.continueWithFrames, null, 'none');
  eq(await opt.continueAtNeeded(), null, 'refused');
});

test('manual and not fitting: continuing keeps the side and quality', async () => {
  const { opt, clock } = await opened();
  opt.setManual({ side: 2000, quality: 90 });
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  eq(opt.state.result.fits, false, 'unfit');
  const needed = opt.state.needed;
  eq(opt.state.continueWithFrames, needed, 'continue with');
  const choice = await opt.continueAtNeeded();
  assert(choice && choice.kind === 'optimised', 'choice');
  eq(choice.bytes.length, model(2000, 90), 'manual bytes');
  eq(opt.state.frames, needed, 'frames');
  eq(opt.state.manualSide, 2000, 'side kept');
  eq(opt.state.manualQuality, 90, 'quality kept');
});

test('needed above the cap: the count passes the cap, never 4096', async () => {
  // A 20 kB original caps at 10 frames; a manual 4032 / q100 needs hundreds.
  const { opt, clock } = await opened({ originalSize: 20_000 });
  const capAtOpen = opt.state.cap;
  opt.setManual({ side: 4032, quality: 100 });
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  const { cap, needed } = opt.state;
  assert(needed > cap, 'needed above cap');
  eq(opt.state.continueWithFrames, needed, 'continue with');
  const choice = await opt.continueAtNeeded();
  assert(choice, 'choice');
  eq(opt.state.frames, needed, 'frames');
  eq(opt.state.cap, capAtOpen, 'the cap stays the original\'s');
});

test('needed above the cap, continue superseded: the cap stays the original\'s', async () => {
  const { opt, clock } = await opened({ originalSize: 20_000 });
  const capAtOpen = opt.state.cap;
  opt.setManual({ side: 4032, quality: 100 });
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  assert(opt.state.needed > capAtOpen, 'needed above cap');
  const p = opt.continueAtNeeded();
  opt.setManual({ side: 640 }); // supersedes its fit
  eq(await p, null, 'superseded');
  eq(opt.state.cap, capAtOpen, 'cap unchanged');
  opt.dispose();
});

test('frames above the cap: − steps down by one, + and a typed count never go higher', async () => {
  const { opt, clock } = await opened({ originalSize: 20_000 });
  const cap = opt.state.cap;
  opt.setManual({ side: 4032, quality: 100 });
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  const p = opt.continueAtNeeded();
  opt.setManual({ side: 640 }); // supersedes its fit: the count stays above the cap
  eq(await p, null, 'superseded');
  const above = opt.state.frames;
  assert(above > cap + 2, `setup: frames ${above} above cap ${cap}`);
  opt.step(-1);
  eq(opt.state.frames, above - 1, '− from above the cap steps down by one, not to the cap');
  opt.step(1);
  eq(opt.state.frames, above - 1, '+ does not climb back above the cap');
  opt.setFrames(5000);
  eq(opt.state.frames, above - 1, 'a typed count higher than the current one is held');
  opt.setFrames(cap - 1 > 0 ? cap - 1 : 1);
  eq(opt.state.frames, Math.max(cap - 1, 1), 'a typed count within the cap is taken');
  opt.setFrames(5000);
  eq(opt.state.frames, cap, 'once back within the cap, the cap clamps again');
  opt.dispose();
});

test('needed above 4096: continueWithFrames null while asIsFrames is set; continueAtNeeded refused', async () => {
  const { opt } = await opened({ session: new FakeJpegSession(4032, 3024, () => 20_000_000), originalSize: 30_000_000 });
  eq(opt.state.result.fits, false, 'unfit');
  assert(opt.state.needed > MAX_FRAMES, 'needed above 4096');
  eq(opt.state.continueWithFrames, null, 'no continue-with');
  eq(opt.state.asIsFrames, framesForFile(OUT, 20_000_000, true), 'as-is count');
  eq(await opt.continueAtNeeded(), null, 'refused');
  assert(opt.state.frames <= MAX_FRAMES, 'frames within 4096');
  opt.dispose();
});

test('continueAtNeeded is refused while busy', async () => {
  const { opt } = await openNothingFits();
  opt.step(1);
  eq(opt.state.busy, true, 'busy');
  eq(await opt.continueAtNeeded(), null, 'refused');
  opt.dispose();
});

test('continueAtNeeded: a newer change during its fit makes it return null', async () => {
  const { opt } = await openNothingFits();
  const p = opt.continueAtNeeded();
  opt.step(1);
  eq(await p, null, 'superseded');
  opt.dispose();
});

test('continueAtNeeded pushes one state for the new count, already busy', async () => {
  const { opt, states } = await openNothingFits();
  const n = states.length;
  const p = opt.continueAtNeeded();
  eq(states.length, n + 1, 'one push');
  eq(states[n].frames, opt.state.needed, 'new count');
  eq(states[n].busy, true, 'busy');
  await p;
});

test('continueAtNeeded resolves null, not a rejection, when its fit fails', async () => {
  const { opt, ctl, warnings } = await openNothingFits();
  const p = opt.continueAtNeeded();
  ctl.throwNext = true; // the fit's result push throws
  eq(await p, null, 'null');
  eq(warnings.length, 1, 'reported through warn');
  opt.step(1);
  eq(opt.state.busy, true, 'still usable');
  opt.dispose();
});

test('a throwing onChange during a fit does not stop later fits', async () => {
  const { opt, clock, ctl, warnings } = await opened();
  const before = unhandled;
  opt.setFrames(7);
  ctl.throwNext = true; // the 7-frame fit's result push throws
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  eq(warnings.length, 1, 'reported through warn');
  eq(opt.state.error, 'none', 'not a decode failure');
  opt.setFrames(8);
  clock.advance(REFIT_DEBOUNCE_MS);
  await flush();
  eq(opt.state.busy, false, 'the next fit ran');
  eq(opt.state.frames, 8, 'frames');
  assert(opt.state.result.bytes.length <= photoByteBudget(8, OUT), 'fitted for 8 frames');
  eq(unhandled, before, 'no unhandled rejection');
});

test('continueAtNeeded: disposed returns null', async () => {
  const { opt } = await openNothingFits();
  const p = opt.continueAtNeeded();
  opt.dispose();
  eq(await p, null, 'disposed');
});

chain.then(async () => {
  await flush();
  if (unhandled) { failed++; console.log(`  FAIL  ${unhandled} unhandled rejection(s)`); }
  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
});
