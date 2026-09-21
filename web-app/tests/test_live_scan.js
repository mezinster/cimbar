// LiveScan against fake camera, track, worker, frame clock and timers.
// Nothing here touches a real DOM: the controller takes every browser
// surface as an option precisely so these rules can be pinned in Node.
'use strict';
const path = require('path');
const { LiveScan, coverTransform, drawOverlay } = require(path.join(__dirname, '..', 'live-scan.js'));

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
function assertJson(a, b, msg) { assertEq(JSON.stringify(a), JSON.stringify(b), msg); }
function near(a, b, msg) { if (Math.abs(a - b) > 1e-6) throw new Error(`${msg}: got ${a}, want ${b}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }
const flush = () => new Promise((r) => setImmediate(r));

function eventTarget(extra) {
  const listeners = {};
  return Object.assign({
    addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
    removeEventListener(type, fn) { listeners[type] = (listeners[type] || []).filter((f) => f !== fn); },
    fire(type) { (listeners[type] || []).slice().forEach((fn) => fn({ type })); },
    count(type) { return (listeners[type] || []).length; },
  }, extra);
}

function diag() { return { totalMs: 5, locateMs: 1, sampleMs: 2, driftMs: 1, rsMs: 1 }; }
function located(status, opts) {
  const o = Object.assign({ ox: 0, module: 12 }, opts);
  return { status: status || 'ok', corners: [100 + o.ox, 100, 700 + o.ox, 100, 100 + o.ox, 700, 700 + o.ox, 700],
           module: o.module, blocksFailed: 0, data: new Uint8Array(8), diag: diag() };
}
function notLocated() { return { status: 'notLocated', corners: null, module: 0, blocksFailed: 0, data: null, diag: diag() }; }

function rig(opts) {
  const o = opts || {};
  const log = { posts: [], transfers: [], applied: [], errors: [], debug: [], stopped: [], paused: 0, statuses: [], workers: [], frames: [], gum: 0 };
  const track = {
    stopped: false,
    stop() { this.stopped = true; },
    getCapabilities: () => o.caps || {},
    getSettings: () => o.settings || {},
    applyConstraints: async (c) => { log.applied.push(c); if (o.rejectLock) throw new Error('not allowed'); },
  };
  const stream = { getVideoTracks: () => [track], getTracks: () => [track] };
  const mediaDevices = {
    getUserMedia: async (c) => {
      log.gum++; log.constraints = c;
      if (o.gumError) { const e = new Error('x'); e.name = o.gumError; throw e; }
      track.stopped = false;
      return stream;
    },
  };
  let pending = null;
  const nextFrame = (video, cb) => { pending = cb; return () => { pending = null; }; };
  const fireFrame = () => { const cb = pending; pending = null; if (cb) cb(); return !!cb; };
  const timers = [];
  const setT = (fn, ms) => { const t = { fn, ms, cleared: false, fired: false }; timers.push(t); return t; };
  const clearT = (t) => { if (t) t.cleared = true; };
  const fireTimeouts = () => timers.filter((t) => !t.cleared && !t.fired).forEach((t) => { t.fired = true; t.fn(); });
  class FakeWorker {
    constructor() { this.posted = []; this.terminated = false; log.workers.push(this); }
    postMessage(m, transfer) { this.posted.push(m); log.posts.push(m); log.transfers.push(transfer); }
    terminate() { this.terminated = true; }
  }
  let clock = 0;
  const doc = eventTarget({ visibilityState: 'visible' });
  const win = eventTarget();
  const video = { videoWidth: 1280, videoHeight: 720, srcObject: null, play: async () => {} };
  const scan = new LiveScan({
    video, overlay: null, mediaDevices, doc, win, debug: true,
    createWorker: () => new FakeWorker(), nextFrame,
    grabFrame: () => ({ width: 2, height: 2, data: new Uint8ClampedArray(16) }),
    now: () => clock, setTimeout: setT, clearTimeout: clearT,
    onFrame: o.onFrame || (async (r) => { log.frames.push(r); return { kind: 'accepted', complete: false, rank: 1, total: 5 }; }),
    onStatus: (s) => log.statuses.push(s), onDebug: (l) => log.debug.push(l), onError: (c) => log.errors.push(c),
    onPaused: () => { log.paused++; }, onStopped: (i) => log.stopped.push(i),
  });
  const worker = () => log.workers[log.workers.length - 1];
  const reply = async (msg, w) => {
    const target = w || worker();
    const last = target.posted[target.posted.length - 1];
    target.onmessage({ data: Object.assign({ id: last.id }, msg) });
    await flush();
  };
  return { scan, track, video, log, fireFrame, fireTimeouts, reply, worker, doc, win, setClock: (v) => { clock = v; } };
}

test('start requests the rear camera at ideal 1080p, no audio, and reports resolution and lock support', async () => {
  const r = rig();
  assertEq(await r.scan.start(), true, 'start resolves true');
  assertJson(r.log.constraints, { audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } } }, 'constraints');
  assertEq(r.video.srcObject !== null, true, 'stream attached to the video');
  assertEq(r.scan.state, 'scanning', 'state');
  assert(r.log.debug[0].includes('1280x720') && r.log.debug[0].includes('lock=unsupported'), `debug header: ${r.log.debug[0]}`);
});

test('one frame in flight: no second post until the worker replies', async () => {
  const r = rig();
  await r.scan.start();
  assertEq(r.fireFrame(), true, 'a frame callback is registered after start');
  assertEq(r.log.posts.length, 1, 'first frame posted');
  assertEq(r.fireFrame(), false, 'no frame callback while a decode is in flight');
  assertEq(r.log.posts.length, 1, 'still one post');
  await r.reply(notLocated());
  assertEq(r.fireFrame(), true, 'the next frame is requested after the reply');
  assertEq(r.log.posts.length, 2, 'second post');
});

test('the pixel buffer is transferred, not copied', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame();
  const m = r.log.posts[0];
  assertEq(m.width, 2, 'width'); assertEq(m.height, 2, 'height');
  assert(r.log.transfers[0] && r.log.transfers[0][0] === m.buffer, 'transfer list holds the buffer');
});

test('lock pins the current focus distance and exposure time; unlock restores continuous', async () => {
  const r = rig({
    caps: { focusMode: ['manual', 'single-shot', 'continuous'], exposureMode: ['continuous', 'manual'] },
    settings: { focusDistance: 0.3, exposureTime: 20 },
  });
  await r.scan.start();
  assert(r.log.debug[0].includes('lock=focus+exposure'), r.log.debug[0]);
  r.fireFrame(); await r.reply(located());
  assertJson(r.log.applied[0], { advanced: [{ focusMode: 'manual', focusDistance: 0.3 }, { exposureMode: 'manual', exposureTime: 20 }] }, 'lock');
  r.setClock(2500);
  r.fireFrame(); await r.reply(notLocated());
  assertJson(r.log.applied[1], { advanced: [{ focusMode: 'continuous' }, { exposureMode: 'continuous' }] }, 'unlock');
});

test('focus-only support locks focus only; a setting that is not a number is left out', async () => {
  const r = rig({ caps: { focusMode: ['manual', 'continuous'] }, settings: { focusDistance: 0.5, exposureTime: 20 } });
  await r.scan.start();
  assert(r.log.debug[0].includes('lock=focus '), r.log.debug[0]);
  r.fireFrame(); await r.reply(located());
  assertJson(r.log.applied[0], { advanced: [{ focusMode: 'manual', focusDistance: 0.5 }] }, 'focus only');

  const r2 = rig({ caps: { focusMode: ['manual', 'continuous'] }, settings: {} });
  await r2.scan.start();
  r2.fireFrame(); await r2.reply(located());
  assertJson(r2.log.applied[0], { advanced: [{ focusMode: 'manual' }] }, 'no focusDistance setting -> mode only');
});

test('no lock support means no applyConstraints calls at all', async () => {
  const r = rig({ caps: { focusMode: ['continuous'] } });
  await r.scan.start();
  r.fireFrame(); await r.reply(located());
  r.setClock(3000);
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.applied.length, 0, 'applyConstraints never called');
});

test('a rejected applyConstraints disables locking and scanning continues', async () => {
  const r = rig({ caps: { focusMode: ['manual', 'continuous'] }, settings: { focusDistance: 1 }, rejectLock: true });
  await r.scan.start();
  r.fireFrame(); await r.reply(located());
  assertEq(r.log.applied.length, 1, 'lock attempted once');
  assert(r.log.debug.some((l) => l.includes('lock failed')), 'the failure is in the debug log');
  r.setClock(3000);
  r.fireFrame(); await r.reply(notLocated());
  r.setClock(3100);
  r.fireFrame(); await r.reply(located());
  assertEq(r.log.applied.length, 1, 'no further lock/unlock attempts');
  assertEq(r.fireFrame(), true, 'still scanning');
});

test('only ok frames reach onFrame', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply(located('rsFailed'));
  r.fireFrame(); await r.reply(located('badHeader'));
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.frames.length, 0, 'no non-ok frame reaches the session');
  r.fireFrame(); await r.reply(located('ok'));
  assertEq(r.log.frames.length, 1, 'ok frame delivered');
});

test('hints: policy hints pass through; "point" only after 1 s without a located frame', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply(located('ok', { module: 4 }));
  assertEq(r.log.statuses[r.log.statuses.length - 1].hint, 'moveCloser', 'module 4');
  r.setClock(500);
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.statuses[r.log.statuses.length - 1].hint, null, 'lost for 500 ms: no hint yet');
  r.setClock(1200);
  r.fireFrame(); await r.reply(notLocated());
  assertEq(r.log.statuses[r.log.statuses.length - 1].hint, 'point', 'lost for 1200 ms');
});

test('worker failures respawn; three in a row stop the scan; a success resets the count', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply({ status: 'error', message: 'boom' });
  assertEq(r.log.workers.length, 2, 'error reply -> respawn');
  assertEq(r.log.workers[0].terminated, true, 'old worker terminated');
  r.fireFrame(); r.worker().onerror({ preventDefault() {} }); await flush();
  assertEq(r.log.workers.length, 3, 'error event -> respawn');
  r.fireFrame(); await r.reply(notLocated());                 // success resets the count
  r.fireFrame(); r.fireTimeouts(); await flush();
  assertEq(r.log.workers.length, 4, 'timeout -> respawn');
  r.fireFrame(); await r.reply({ status: 'error', message: 'x' });
  assertEq(r.scan.state, 'scanning', 'two in a row since the success: still scanning');
  r.fireFrame(); await r.reply({ status: 'error', message: 'y' });
  assertEq(r.scan.state, 'stopped', 'third in a row stops');
  assertJson(r.log.errors, ['scanDecoderFailed'], 'error reported');
  assertEq(r.log.stopped[0].reason, 'decoderFailed', 'stop reason');
  assertEq(r.track.stopped, true, 'camera released');
});

test('a late reply from a timed-out request is ignored', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame();
  const old = r.worker();
  const oldId = old.posted[0].id;
  r.fireTimeouts(); await flush();
  old.onmessage({ data: Object.assign(located('ok'), { id: oldId }) });
  await flush();
  assertEq(r.log.frames.length, 0, 'the stale reply did not reach onFrame');
});

test('camera errors map to translated codes and stop', async () => {
  for (const [name, code] of [['NotAllowedError', 'camDenied'], ['SecurityError', 'camDenied'], ['NotFoundError', 'camNone'],
                              ['OverconstrainedError', 'camNone'], ['NotReadableError', 'camBusy'], ['AbortError', 'camBusy'], ['TypeError', 'camFailed']]) {
    const r = rig({ gumError: name });
    assertEq(await r.scan.start(), false, `${name}: start resolves false`);
    assertJson(r.log.errors, [code], name);
    assertEq(r.log.stopped[0].reason, 'error', `${name}: stop reason`);
  }
});

test('stop releases the camera and the worker and reports counts', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame(); await r.reply(located('ok'));
  r.scan.stop('closed');
  assertEq(r.track.stopped, true, 'track stopped');
  assertEq(r.worker().terminated, true, 'worker terminated');
  assertJson(r.log.stopped, [{ reason: 'closed', frames: 1, accepted: 1 }], 'onStopped');
  assertEq(r.doc.count('visibilitychange'), 0, 'visibility listener removed');
  assertEq(r.win.count('pagehide'), 0, 'pagehide listener removed');
  r.scan.stop('closed');
  assertEq(r.log.stopped.length, 1, 'stop is idempotent');
});

test('hidden tab and pagehide pause (camera released); resume reopens the camera', async () => {
  const r = rig();
  await r.scan.start();
  r.fireFrame();                                   // a decode in flight while hidden
  r.doc.visibilityState = 'hidden';
  r.doc.fire('visibilitychange');
  assertEq(r.scan.state, 'paused', 'paused');
  assertEq(r.track.stopped, true, 'camera released');
  assertEq(r.log.paused, 1, 'onPaused');
  assertEq(await r.scan.resume(), true, 'resume');
  assertEq(r.log.gum, 2, 'camera reopened');
  assertEq(r.scan.state, 'scanning', 'scanning again');
  assertEq(r.fireFrame(), true, 'frames flow again');

  r.win.fire('pagehide');
  assertEq(r.scan.state, 'paused', 'pagehide pauses');
});

test('a completing frame stops the scan with reason "complete"', async () => {
  const r = rig({ onFrame: async () => ({ kind: 'accepted', complete: true, rank: 5, total: 5 }) });
  await r.scan.start();
  r.fireFrame(); await r.reply(located('ok'));
  assertEq(r.scan.state, 'stopped', 'stopped');
  assertJson(r.log.stopped, [{ reason: 'complete', frames: 1, accepted: 1 }], 'onStopped');
});

test('stop during the permission prompt releases the late stream', async () => {
  const r = rig();
  const p = r.scan.start();
  r.scan.stop('closed');
  assertEq(await p, false, 'start resolves false');
  assertEq(r.track.stopped, true, 'the stream granted after close is released');
});

test('coverTransform scales to fill and centres the overflow', () => {
  let t = coverTransform(1280, 720, 640, 360);
  near(t.scale, 0.5, 'same aspect scale'); near(t.dx, 0, 'dx'); near(t.dy, 0, 'dy');
  t = coverTransform(1280, 720, 400, 800);                       // portrait phone, landscape video
  near(t.scale, 800 / 720, 'tall box scale'); near(t.dx, (400 - 1280 * 800 / 720) / 2, 'dx'); near(t.dy, 0, 'dy');
  t = coverTransform(640, 480, 1000, 500);                       // wide box
  near(t.scale, 1000 / 640, 'wide box scale'); near(t.dx, 0, 'dx'); near(t.dy, (500 - 480 * 1000 / 640) / 2, 'dy');
});

test('drawOverlay maps corners through the cover transform in tl-tr-br-bl order', () => {
  const ops = [];
  const g = {
    clearRect: (...a) => ops.push(['clear', ...a]), beginPath: () => ops.push(['begin']),
    moveTo: (x, y) => ops.push(['move', x, y]), lineTo: (x, y) => ops.push(['line', x, y]),
    closePath: () => ops.push(['close']), stroke: () => ops.push(['stroke']),
  };
  const canvas = { clientWidth: 640, clientHeight: 360, width: 0, height: 0, getContext: () => g };
  drawOverlay(canvas, 1280, 720, [0, 0, 1280, 0, 0, 720, 1280, 720], '#0f0');
  assertEq(canvas.width, 640, 'canvas sized to its box');
  assertJson(ops.filter((o) => o[0] === 'move' || o[0] === 'line'),
    [['move', 0, 0], ['line', 640, 0], ['line', 640, 360], ['line', 0, 360]], 'path');
  ops.length = 0;
  drawOverlay(canvas, 1280, 720, null, null);
  assertJson(ops, [['clear', 0, 0, 640, 360]], 'no corners -> cleared only');
});

(async () => {
  console.log('\ntest_live_scan.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
