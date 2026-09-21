// Port of app/test/core/services/capture_policy_test.dart, case for case,
// plus the web-only 'tooSmall' status (photo-decoder.js's module floor).
'use strict';
const path = require('path');
const { CapturePolicy, isLocated } = require(path.join(__dirname, '..', 'capture-policy.js'));

let passed = 0, failed = 0;
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

// Mirrors the Dart helper: corners absent only for notLocated.
function outcome(status, opts) {
  const o = Object.assign({ module: 12, ox: 0 }, opts);
  return {
    status,
    corners: status === 'notLocated' ? null
      : [100 + o.ox, 100, 700 + o.ox, 100, 100 + o.ox, 700, 700 + o.ox, 700],
    module: o.module,
  };
}

test('locks after the first located frame, unlocks 2 s after losing it', () => {
  const p = new CapturePolicy();
  assertEq(p.update(outcome('notLocated'), 0).lockAction, 'none', 'not located yet');
  assertEq(p.update(outcome('rsFailed'), 100).lockAction, 'lock', 'first located frame locks');
  assertEq(p.locked, true, 'locked');
  assertEq(p.update(outcome('ok'), 300).lockAction, 'none', 'already locked');
  assertEq(p.update(outcome('notLocated'), 1000).lockAction, 'none', 'lost for 700 ms');
  assertEq(p.update(outcome('notLocated'), 2400).lockAction, 'unlock', 'lost for 2300 ms');
  assertEq(p.locked, false, 'unlocked');
});

test('hints from module size, motion and rsFailed', () => {
  const p = new CapturePolicy();
  assertEq(p.update(outcome('ok', { module: 4 }), 0).hint, 'moveCloser', 'module 4');
  assertEq(p.update(outcome('ok', { module: 50 }), 100).hint, 'moveBack', 'module 50');
  assertEq(p.update(outcome('ok', { module: 12 }), 200).hint, 'none', 'module 12, same corners');
  assertEq(p.update(outcome('ok', { module: 12, ox: 25 }), 300).hint, 'holdStill', 'moved 25 px');
  assertEq(p.update(outcome('rsFailed', { module: 12, ox: 25 }), 400).hint, 'adjustAngle', 'rsFailed, still');
  assertEq(p.update(outcome('notLocated'), 500).hint, 'none', 'not located');
});

test('reset clears lock and stale corner history', () => {
  const p = new CapturePolicy();
  assertEq(p.update(outcome('ok'), 0).lockAction, 'lock', 'lock');
  assertEq(p.locked, true, 'locked');
  p.reset();
  assertEq(p.locked, false, 'reset unlocks');
  const r = p.update(outcome('ok', { ox: 25 }), 100);
  assertEq(r.lockAction, 'lock', 'locks again after reset');
  assertEq(r.hint, 'none', 'no motion hint against pre-reset corners');
});

test('tooSmall with corners is located and asks to move closer (web-only status)', () => {
  const p = new CapturePolicy();
  const r = p.update(outcome('tooSmall', { module: 4 }), 0);
  assertEq(r.lockAction, 'lock', 'tooSmall with corners locks');
  assertEq(r.hint, 'moveCloser', 'tooSmall -> moveCloser via the module rule');
});

test('tooSmall without corners (locator-level floor) is not located', () => {
  const p = new CapturePolicy();
  const o = { status: 'tooSmall', corners: null, module: 0 };
  assertEq(isLocated(o), false, 'isLocated');
  const r = p.update(o, 0);
  assertEq(r.lockAction, 'none', 'no lock');
  assertEq(r.hint, 'none', 'no hint');
});

test('isLocated needs both corners and a located status', () => {
  assertEq(isLocated(outcome('ok')), true, 'ok');
  assertEq(isLocated(outcome('badHeader')), true, 'badHeader');
  assertEq(isLocated(outcome('unsupportedGrid')), true, 'unsupportedGrid');
  assertEq(isLocated(outcome('notLocated')), false, 'notLocated');
  assertEq(isLocated({ status: 'error', corners: [0, 0, 0, 0, 0, 0, 0, 0], module: 1 }), false, 'error status');
});

(async () => {
  console.log('\ntest_capture_policy.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
