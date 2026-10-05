'use strict';
const { freshPage } = require('./page_harness');
let passed = 0, failed = 0;
function assertEq(a, b, msg) { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = []; const test = (name, fn) => tests.push({ name, fn });

const all = { hasGif: true, hasCamera: true, needsUnlock: true, hasResult: true };
const none = { hasGif: false, hasCamera: false, needsUnlock: false, hasResult: false };

test('empty and root hashes are the hub, no redirect', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('', none), { route: '/', redirect: null }, 'empty');
  assertEq(ctx.resolveRoute('#', none), { route: '/', redirect: null }, 'bare #');
  assertEq(ctx.resolveRoute('#/', none), { route: '/', redirect: null }, '#/');
});
test('every known route resolves to itself when its state exists', () => {
  const { ctx } = freshPage();
  for (const r of ctx.ROUTES) assertEq(ctx.resolveRoute('#' + r, all), { route: r, redirect: null }, r);
});
test('unknown hashes go to the hub', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/nope', all), { route: '/', redirect: '#/' }, 'unknown');
  assertEq(ctx.resolveRoute('#send', all), { route: '/', redirect: '#/' }, 'missing slash');
});
test('reload on #/send/ready with no GIF goes back to compose', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/send/ready', none), { route: '/send', redirect: '#/send' }, 'ready guard');
});
test('#/receive without a camera API falls back to files', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/receive', none), { route: '/receive/files', redirect: '#/receive/files' }, 'camera guard');
});
test('#/receive/unlock with nothing to unlock chains through #/receive', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/receive/unlock', { ...none, hasCamera: true }), { route: '/receive', redirect: '#/receive' }, 'with camera');
  assertEq(ctx.resolveRoute('#/receive/unlock', none), { route: '/receive/files', redirect: '#/receive/files' }, 'chained to files');
});
test('#/receive/done with no result goes to the hub', () => {
  const { ctx } = freshPage();
  assertEq(ctx.resolveRoute('#/receive/done', none), { route: '/', redirect: '#/' }, 'done guard');
});
test('navigate replace vs push, and routeState reflects the page', () => {
  const { ctx, calls } = freshPage();
  ctx.navigate('#/how');
  assertEq(ctx.location.hash, '#/how', 'pushed hash');
  assertEq(calls.pushes, 1, 'one push');
  ctx.navigate('#/send', { replace: true });
  assertEq(ctx.location.hash, '#/send', 'replaced hash');
  assertEq(calls.pushes, 1, 'replace does not push');
  assertEq(ctx.routeState().hasGif, false, 'no GIF yet');
  assertEq(ctx.routeState().hasCamera, true, 'harness has getUserMedia');
});
test('navigating to a guarded route lands on the redirect', () => {
  const { ctx } = freshPage();
  ctx.navigate('#/send/ready');
  assertEq(ctx.location.hash, '#/send', 'redirect applied to the URL');
});

(async () => {
  console.log('\ntest_router.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
