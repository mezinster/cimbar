/**
 * capture-policy.js — camera acquisition policy for live scan (spec §8).
 *
 * Transliteration of app/lib/core/services/capture_policy.dart: lock focus
 * and exposure once a barcode is located, unlock after unlockAfterMs without
 * one, and derive a user hint from the finder module size, corner motion and
 * the decode status. Constants are Android's, verbatim.
 *
 * One web-only addition: 'tooSmall' counts as located. It is the photo
 * decoder's module floor, which runs after the locator filled corners and
 * module, so a small barcode yields moveCloser through the module rule.
 *
 * Pure logic, no DOM. IIFE; exposes window.CimbarCapturePolicy / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;

const LOCATED_STATUSES = ['ok', 'rsFailed', 'badHeader', 'unsupportedGrid', 'tooSmall'];

function isLocated(o) {
  return !!(o && o.corners) && LOCATED_STATUSES.indexOf(o.status) >= 0;
}

function motion(a, b) {
  let worst = 0;
  for (let i = 0; i < 8; i += 2) {
    const dx = a[i] - b[i], dy = a[i + 1] - b[i + 1];
    const d = dx * dx + dy * dy;
    if (d > worst) worst = d;
  }
  return worst === 0 ? 0 : Math.sqrt(worst);
}

class CapturePolicy {
  constructor(opts) {
    const p = opts || {};
    this.minModulePx = p.minModulePx !== undefined ? p.minModulePx : 6;
    this.maxModulePx = p.maxModulePx !== undefined ? p.maxModulePx : 40;
    this.motionPx = p.motionPx !== undefined ? p.motionPx : 10;
    this.unlockAfterMs = p.unlockAfterMs !== undefined ? p.unlockAfterMs : 2000;
    this.reset();
  }

  get locked() { return this._locked; }

  reset() {
    this._locked = false;
    this._lastLocatedMs = null;
    this._lastCorners = null;
  }

  update(o, nowMs) {
    let lockAction = 'none';
    let hint = 'none';
    if (isLocated(o)) {
      this._lastLocatedMs = nowMs;
      if (!this._locked) {
        this._locked = true;
        lockAction = 'lock';
      }
      if (o.module < this.minModulePx) {
        hint = 'moveCloser';
      } else if (o.module > this.maxModulePx) {
        hint = 'moveBack';
      } else if (this._lastCorners !== null && motion(this._lastCorners, o.corners) > this.motionPx) {
        hint = 'holdStill';
      } else if (o.status === 'rsFailed') {
        hint = 'adjustAngle';
      }
      this._lastCorners = o.corners;
    } else {
      this._lastCorners = null;
      if (this._locked && this._lastLocatedMs !== null && nowMs - this._lastLocatedMs >= this.unlockAfterMs) {
        this._locked = false;
        lockAction = 'unlock';
      }
    }
    return { hint, lockAction };
  }
}

const API = { CapturePolicy, isLocated, LOCATED_STATUSES };
if (isNode) module.exports = API; else window.CimbarCapturePolicy = API;
})();
