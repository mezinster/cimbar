/**
 * live-scan.js — the live camera scanner (spec §6, §7, §9.3).
 *
 * LiveScan opens the camera, takes one frame at a time (a new frame is
 * requested only after the worker replied — Android's wantsFrame
 * back-pressure), posts its RGBA pixels to scan-worker.js, runs each reply
 * through CapturePolicy, applies focus/exposure lock where the browser
 * supports it, draws the finder overlay, and hands `ok` frames to the page
 * via onFrame. It knows nothing about sessions or i18n: the page owns the
 * assembler and turns hint/error codes into translated text.
 *
 * Every browser surface (camera, worker, frame clock, timers, document) is an
 * option with a real default, so tests/test_live_scan.js can drive it in Node.
 *
 * Loads after capture-policy.js. IIFE; exposes window.CimbarLiveScan /
 * module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const { CapturePolicy, isLocated } = isNode ? require('./capture-policy.js') : window.CimbarCapturePolicy;

const CAMERA_CONSTRAINTS = {
  audio: false,
  video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } },
};

const CAMERA_ERRORS = {
  NotAllowedError: 'camDenied', SecurityError: 'camDenied',
  NotFoundError: 'camNone', OverconstrainedError: 'camNone',
  NotReadableError: 'camBusy', AbortError: 'camBusy',
};

const COLOR_ACCEPTED = '#2ecc71';
const COLOR_LOCATED = '#f39c12';

/** object-fit: cover — scale to fill the box, centre the overflow. */
function coverTransform(srcW, srcH, boxW, boxH) {
  const scale = Math.max(boxW / srcW, boxH / srcH);
  return { scale, dx: (boxW - srcW * scale) / 2, dy: (boxH - srcH * scale) / 2 };
}

/** Clears the overlay; draws the finder quadrilateral when corners and color are given. */
function drawOverlay(canvas, srcW, srcH, corners, color) {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (canvas.width !== w) canvas.width = w;
  if (canvas.height !== h) canvas.height = h;
  const g = canvas.getContext('2d');
  g.clearRect(0, 0, w, h);
  if (!corners || !color) return;
  const t = coverTransform(srcW, srcH, w, h);
  // corners = [tlx, tly, trx, try, blx, bly, brx, bry]; draw tl, tr, br, bl.
  const order = [0, 2, 6, 4];
  g.strokeStyle = color;
  g.lineWidth = 4;
  g.beginPath();
  for (let k = 0; k < order.length; k++) {
    const x = corners[order[k]] * t.scale + t.dx, y = corners[order[k] + 1] * t.scale + t.dy;
    if (k === 0) g.moveTo(x, y); else g.lineTo(x, y);
  }
  g.closePath();
  g.stroke();
}

function supports(list) {
  return Array.isArray(list) && list.indexOf('manual') >= 0 && list.indexOf('continuous') >= 0;
}

/** Which of focus/exposure can be locked, from track.getCapabilities(). */
function lockSupport(caps) {
  const c = caps || {};
  return { focus: supports(c.focusMode), exposure: supports(c.exposureMode) };
}

function lockLabel(s) {
  if (s.focus && s.exposure) return 'focus+exposure';
  if (s.focus) return 'focus';
  if (s.exposure) return 'exposure';
  return 'unsupported';
}

/** advanced[] entries pinning the current values (one entry per concern, satisfied independently). */
function lockConstraints(support, settings) {
  const s = settings || {};
  const out = [];
  if (support.focus) {
    const f = { focusMode: 'manual' };
    if (typeof s.focusDistance === 'number') f.focusDistance = s.focusDistance;
    out.push(f);
  }
  if (support.exposure) {
    const e = { exposureMode: 'manual' };
    if (typeof s.exposureTime === 'number') e.exposureTime = s.exposureTime;
    out.push(e);
  }
  return out;
}

function unlockConstraints(support) {
  const out = [];
  if (support.focus) out.push({ focusMode: 'continuous' });
  if (support.exposure) out.push({ exposureMode: 'continuous' });
  return out;
}

/** One callback per new camera frame: requestVideoFrameCallback, else rAF polling currentTime. */
function defaultNextFrame(video, cb) {
  if (typeof video.requestVideoFrameCallback === 'function') {
    const h = video.requestVideoFrameCallback(() => cb());
    return () => video.cancelVideoFrameCallback(h);
  }
  const last = video.currentTime;
  let h;
  const tick = () => { if (video.currentTime !== last) cb(); else h = requestAnimationFrame(tick); };
  h = requestAnimationFrame(tick);
  return () => cancelAnimationFrame(h);
}

function makeGrabber() {
  let canvas = null, g = null;
  return function grabFrame(video) {
    const w = video.videoWidth, h = video.videoHeight;
    if (!w || !h) return null;                              // metadata not ready yet
    if (!canvas) {
      canvas = document.createElement('canvas');
      g = canvas.getContext('2d', { willReadFrequently: true });
    }
    if (canvas.width !== w) canvas.width = w;
    if (canvas.height !== h) canvas.height = h;
    g.drawImage(video, 0, 0, w, h);
    return g.getImageData(0, 0, w, h);
  };
}

function stopStream(stream) {
  if (stream) stream.getTracks().forEach((t) => t.stop());
}

const noop = () => {};

class LiveScan {
  constructor(opts) {
    this.o = Object.assign({
      overlay: null, debug: false, doc: null, win: null,
      createWorker: () => new Worker('scan-worker.js'),
      nextFrame: defaultNextFrame,
      grabFrame: null,
      now: () => performance.now(),
      setTimeout: (fn, ms) => setTimeout(fn, ms),
      clearTimeout: (t) => clearTimeout(t),
      timeoutMs: 10000, maxFailures: 3, pointAfterMs: 1000, fadeMs: 500,
      onFrame: () => null, onStatus: noop, onDebug: noop, onError: noop, onPaused: noop, onStopped: noop,
    }, opts);
    if (!this.o.grabFrame) this.o.grabFrame = makeGrabber();
    this.policy = new CapturePolicy();
    this.state = 'idle';
    this.stream = null; this.track = null; this.worker = null;
    this.support = { focus: false, exposure: false };
    this.lockEnabled = false;
    this.busy = false; this.inflight = null; this.seq = 0; this.timer = null; this.cancelFrame = null;
    this.failures = 0; this.frames = 0; this.accepted = 0;
    this.lastLocatedMs = 0; this.quadMs = -Infinity;
    // Bumped by pause()/stop()/_fail(): _onReply captures it before its awaits
    // (the lock, then onFrame) and abandons a stale continuation if it moved.
    this._epoch = 0;
    this._pendingPause = false;           // pause() landed while state was 'starting'
    this._lockDisabledPermanently = false; // a rejected applyConstraints disables locking for this LiveScan's life
    this._onVisibility = () => { if (this.o.doc && this.o.doc.visibilityState === 'hidden') this.pause(); };
    this._onPageHide = () => this.pause();
    this._listening = false;
  }

  async start() {
    if (this.state !== 'idle' && this.state !== 'paused') return false;
    this.state = 'starting';
    this._pendingPause = false;
    this._listen(true);
    let stream;
    try {
      stream = await this.o.mediaDevices.getUserMedia(CAMERA_CONSTRAINTS);
    } catch (e) {
      if (this.state === 'starting') {
        this.o.onError(CAMERA_ERRORS[e && e.name] || 'camFailed');
        this.stop('error');
      }
      return false;
    }
    if (this.state !== 'starting') { stopStream(stream); return false; }   // closed during the prompt
    this.stream = stream;
    this.track = stream.getVideoTracks()[0];
    const caps = this.track && typeof this.track.getCapabilities === 'function' ? this.track.getCapabilities() : {};
    this.support = lockSupport(caps);
    this.lockEnabled = !this._lockDisabledPermanently && (this.support.focus || this.support.exposure);
    try {
      this.o.video.srcObject = stream;
      await this.o.video.play();
    } catch (e) {
      if (this.state === 'starting') {
        this.o.onError('camFailed');
        this.stop('error');
      } else {
        stopStream(stream);           // pause()/stop() already landed; just release what we opened
      }
      return false;
    }
    if (this.state !== 'starting') return false;             // closed while play() was resolving
    if (this._pendingPause) {                                 // pause() landed while starting: honor it now
      this._pendingPause = false;
      stopStream(this.stream);
      this.stream = null; this.track = null;
      this.o.video.srcObject = null;
      this.state = 'paused';
      this.o.onPaused();
      return false;
    }
    if (!this.worker) this._spawn();
    this.policy.reset();
    this.lastLocatedMs = this.o.now();
    this.state = 'scanning';
    this._debug(`${this.o.video.videoWidth}x${this.o.video.videoHeight} lock=${lockLabel(this.support)} worker=ok`);
    this._schedule();
    return true;
  }

  resume() { return this.state === 'paused' ? this.start() : Promise.resolve(false); }

  pause() {
    if (this.state === 'starting') { this._pendingPause = true; return; }
    if (this.state !== 'scanning') return;
    this.state = 'paused';
    this._epoch++;
    this._cancelPending();
    stopStream(this.stream);
    this.stream = null; this.track = null;
    this.o.video.srcObject = null;
    this.o.onPaused();
  }

  stop(reason) {
    if (this.state === 'stopped') return;
    this.state = 'stopped';
    this._epoch++;
    this._cancelPending();
    this._listen(false);
    if (this.worker) { this.worker.terminate(); this.worker = null; }
    stopStream(this.stream);
    this.stream = null; this.track = null;
    this.o.video.srcObject = null;
    this.o.onStopped({ reason, frames: this.frames, accepted: this.accepted });
  }

  _listen(on) {
    if (on === this._listening) return;
    this._listening = on;
    const verb = on ? 'addEventListener' : 'removeEventListener';
    if (this.o.doc) this.o.doc[verb]('visibilitychange', this._onVisibility);
    if (this.o.win) this.o.win[verb]('pagehide', this._onPageHide);
  }

  _cancelPending() {
    if (this.cancelFrame) { this.cancelFrame(); this.cancelFrame = null; }
    if (this.timer) { this.o.clearTimeout(this.timer); this.timer = null; }
    this.inflight = null;
    this.busy = false;
  }

  _spawn() {
    const w = this.o.createWorker();
    w.onmessage = (e) => this._onReply(w, e.data);
    w.onerror = (e) => {
      if (e && typeof e.preventDefault === 'function') e.preventDefault();
      if (w === this.worker) this._fail('worker error');
    };
    this.worker = w;
  }

  _schedule() {
    if (this.state !== 'scanning' || this.busy || this.cancelFrame) return;
    this.cancelFrame = this.o.nextFrame(this.o.video, () => { this.cancelFrame = null; this._onVideoFrame(); });
  }

  _onVideoFrame() {
    if (this.state !== 'scanning' || this.busy) return;
    const img = this.o.grabFrame(this.o.video);
    if (!img) { this._schedule(); return; }
    const id = ++this.seq;
    this.inflight = id;
    this.busy = true;
    this.frames++;
    const buffer = img.data.buffer;
    this.worker.postMessage({ id, width: img.width, height: img.height, buffer }, [buffer]);
    this.timer = this.o.setTimeout(() => { if (this.inflight === id) this._fail('timeout'); }, this.o.timeoutMs);
  }

  _fail(reason) {
    this._epoch++;
    if (this.timer) { this.o.clearTimeout(this.timer); this.timer = null; }
    this.inflight = null;
    this.busy = false;
    this.failures++;
    this._debug(`worker failure ${this.failures}: ${reason}`);
    if (this.worker) { this.worker.terminate(); this.worker = null; }
    if (this.failures >= this.o.maxFailures) {
      this.o.onError('scanDecoderFailed');
      this.stop('decoderFailed');
      return;
    }
    if (this.state === 'scanning') { this._spawn(); this._schedule(); }
  }

  async _onReply(w, msg) {
    if (w !== this.worker || !msg || msg.id !== this.inflight) return;   // stale or foreign reply
    this.o.clearTimeout(this.timer);
    this.timer = null;
    this.inflight = null;
    if (msg.status === 'error') { this._fail('error: ' + msg.message); return; }
    this.failures = 0;

    const epoch = this._epoch;
    const now = this.o.now();
    const decision = this.policy.update(msg, now);
    await this._applyLock(decision.lockAction);
    if (this._epoch !== epoch) return;   // pause/stop/failure landed during the lock await: abandon, no onFrame call

    let res = null;
    if (msg.status === 'ok') {
      try {
        res = await this.o.onFrame(msg);
      } catch (e) {
        this._debug(`onFrame failed: ${e && e.message}`);
        res = null;
      }
      if (res && res.kind === 'accepted') this.accepted++;
    }

    if (this._epoch !== epoch) {
      // pause/stop/failure landed during the onFrame await: abandon (no onStatus/overlay, no busy
      // reset, no reschedule) — except a completing frame must still end the scan; stop() is
      // idempotent, so this is a no-op if the scan was already stopped during that same await.
      if (res && res.complete) this.stop('complete');
      return;
    }

    const loc = isLocated(msg);
    if (loc) this.lastLocatedMs = now;
    let hint = decision.hint === 'none' ? null : decision.hint;
    if (!loc && now - this.lastLocatedMs > this.o.pointAfterMs) hint = 'point';
    this.o.onStatus({ hint });
    this._overlay(msg, res, loc, now);
    if (this.o.debug) this._debug(debugLine(this.seq, msg, res));

    this.busy = false;
    if (res && res.complete) { this.stop('complete'); return; }
    this._schedule();
  }

  async _applyLock(action) {
    if (!this.lockEnabled || action === 'none' || !this.track) return;
    const advanced = action === 'lock'
      ? lockConstraints(this.support, this.track.getSettings ? this.track.getSettings() : {})
      : unlockConstraints(this.support);
    if (!advanced.length) return;
    try {
      await this.track.applyConstraints({ advanced });
    } catch (e) {
      this.lockEnabled = false;
      this._lockDisabledPermanently = true;
      this._debug(`lock failed (${action}): ${e && e.message}; locking disabled`);
    }
  }

  _overlay(msg, res, loc, now) {
    if (!this.o.overlay) return;
    const vw = this.o.video.videoWidth, vh = this.o.video.videoHeight;
    if (loc) {
      this.quadMs = now;
      const color = res && res.kind === 'accepted' ? COLOR_ACCEPTED : COLOR_LOCATED;
      drawOverlay(this.o.overlay, vw, vh, msg.corners, color);
    } else if (now - this.quadMs >= this.o.fadeMs) {
      drawOverlay(this.o.overlay, vw, vh, null, null);
    }
  }

  _debug(line) { this.o.onDebug(line); }
}

function debugLine(n, msg, res) {
  const d = msg.diag || {};
  let s = `#${n} ${msg.status} ${d.totalMs}ms loc=${d.locateMs} smp=${d.sampleMs} drf=${d.driftMs} rs=${d.rsMs} mod=${(msg.module || 0).toFixed(1)}`;
  if (res) s += ` ${res.kind} r=${res.rank}/${res.total}`;
  return s;
}

const API = { LiveScan, coverTransform, drawOverlay, lockSupport, lockConstraints, unlockConstraints, CAMERA_CONSTRAINTS, CAMERA_ERRORS };
if (isNode) module.exports = API; else window.CimbarLiveScan = API;
})();
