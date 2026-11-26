// Tests for tools/healthcheck.js — the script that decides whether a deploy
// is rolled back. Uses a local http server so the real fetchPage code path
// (no-cache headers, User-Agent, no redirect following) is exercised.
'use strict';
const http = require('http');
const { spawnSync } = require('child_process');
const path = require('path');
const { buildMarker, fetchPage, checkOnce, healthcheck, USER_AGENT } = require('../tools/healthcheck.js');

let passed = 0, failed = 0;
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
function assert(c, msg) { if (!c) throw new Error(msg || 'assert'); }

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

/** Serve a configurable fake site. `routes` maps path -> {status, type, body}. */
function serve(routes) {
  const seen = [];
  const server = http.createServer((req, res) => {
    seen.push({ url: req.url, ua: req.headers['user-agent'], cc: req.headers['cache-control'] });
    const r = routes[req.url] || { status: 404, type: 'text/plain', body: 'nope' };
    res.writeHead(r.status, { 'content-type': r.type, ...(r.headers || {}) });
    res.end(r.body);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => {
    const base = `http://127.0.0.1:${server.address().port}/cimbar/`;
    resolve({ base, seen, close: () => new Promise((r) => server.close(r)) });
  }));
}

const SHA = 'abc1234';
const good = {
  '/cimbar/': { status: 200, type: 'text/html; charset=utf-8', body: `<!doctype html><html><head>${buildMarker(SHA)}</head></html>` },
  '/cimbar/cimbar.js': { status: 200, type: 'text/javascript; charset=utf-8', body: 'window.Cimbar={};' },
  '/cimbar/vendor/libheif/libheif.wasm': { status: 200, type: 'application/wasm', body: Buffer.from([0x00, 0x61, 0x73, 0x6d, 1, 0, 0, 0]) },
};

test('buildMarker is a prefixed HTML comment, never a bare sha', () => {
  assertEq(buildMarker(SHA), '<!-- cimbar-build:abc1234 -->');
});

test('healthy site passes; requests carry no-cache and a User-Agent', async () => {
  const s = await serve(good);
  try {
    const r = await checkOnce(s.base, SHA);
    assertEq(r.ok, true, r.failures.join('; '));
    assertEq(s.seen.length, 3);
    assertEq(s.seen[0].url, '/cimbar/');
    assertEq(s.seen[1].url, '/cimbar/cimbar.js');
    assertEq(s.seen[2].url, '/cimbar/vendor/libheif/libheif.wasm');
    assertEq(s.seen[0].ua, USER_AGENT);
    assertEq(s.seen[0].cc, 'no-cache');
  } finally { await s.close(); }
});

test('stale page (marker for another build) fails with a marker message', async () => {
  const s = await serve({ ...good, '/cimbar/': { ...good['/cimbar/'], body: `<html>${buildMarker('0000000')}</html>` } });
  try {
    const r = await checkOnce(s.base, SHA);
    assertEq(r.ok, false);
    assert(r.failures.some((f) => f.includes('build marker')), r.failures.join('; '));
  } finally { await s.close(); }
});

test('wrong content types and missing script are all reported together', async () => {
  const s = await serve({ '/cimbar/': { status: 200, type: 'application/octet-stream', body: buildMarker(SHA) } });
  try {
    const r = await checkOnce(s.base, SHA);
    assertEq(r.ok, false);
    assert(r.failures.some((f) => f.includes('content-type') && f.includes('text/html')), 'html type');
    assert(r.failures.some((f) => f.includes('cimbar.js') && f.includes('404')), 'script 404');
  } finally { await s.close(); }
});

test('libheif.wasm served as application/wasm is healthy; any other type is not', async () => {
  const wasm = '/cimbar/vendor/libheif/libheif.wasm';
  for (const [type, ok] of [['application/wasm', true], ['application/octet-stream', false], ['binary/octet-stream', false], ['text/html', false]]) {
    const s = await serve({ ...good, [wasm]: { ...good[wasm], type } });
    try {
      const r = await checkOnce(s.base, SHA);
      assertEq(r.ok, ok, `${type}: ${r.failures.join('; ')}`);
      if (!ok) assert(r.failures.some((f) => f.includes('libheif.wasm') && f.includes('application/wasm')), `${type}: ${r.failures.join('; ')}`);
    } finally { await s.close(); }
  }
});

test('a missing libheif.wasm is unhealthy', async () => {
  const routes = { ...good };
  delete routes['/cimbar/vendor/libheif/libheif.wasm'];
  const s = await serve(routes);
  try {
    const r = await checkOnce(s.base, SHA);
    assertEq(r.ok, false);
    assert(r.failures.some((f) => f.includes('libheif.wasm') && f.includes('404')), r.failures.join('; '));
  } finally { await s.close(); }
});

test('CLI exits 0 against a healthy site, wasm included', async () => {
  const cli = path.join(__dirname, '..', 'tools', 'healthcheck.js');
  const s = await serve(good);
  try {
    const { spawn } = require('child_process');
    const code = await new Promise((resolve) => {
      const p = spawn(process.execPath, [cli, s.base, SHA], { env: { ...process.env, HEALTHCHECK_ATTEMPTS: '1' } });
      p.on('exit', resolve);
    });
    assertEq(code, 0, 'healthy');
  } finally { await s.close(); }
});

test('a redirect is a failure, not followed', async () => {
  const s = await serve({ ...good, '/cimbar/': { status: 301, type: 'text/html', body: '', headers: { location: '/cimbar/index.html' } } });
  try {
    const r = await checkOnce(s.base, SHA);
    assertEq(r.ok, false);
    assert(r.failures.some((f) => f.includes('301')), r.failures.join('; '));
  } finally { await s.close(); }
});

test('healthcheck retries with backoff until healthy', async () => {
  let calls = 0;
  const fetcher = async (url) => {
    calls++;
    if (url.endsWith('cimbar.js')) return { status: 200, contentType: 'text/javascript', body: '' };
    if (url.endsWith('.wasm')) return { status: 200, contentType: 'application/wasm', body: '' };
    // page is stale for the first two attempts, then fresh
    const fresh = calls > 6;
    return { status: 200, contentType: 'text/html', body: fresh ? buildMarker(SHA) : buildMarker('old') };
  };
  const delays = [];
  const r = await healthcheck('http://x/cimbar/', SHA, { fetcher, sleep: async (ms) => { delays.push(ms); }, firstDelayMs: 10 });
  assertEq(r.ok, true);
  assertEq(JSON.stringify(delays), JSON.stringify([10, 20]));
});

test('healthcheck gives up after the attempt cap and reports the last failure', async () => {
  const fetcher = async () => { throw new Error('ECONNREFUSED'); };
  const r = await healthcheck('http://x/cimbar/', SHA, { fetcher, sleep: async () => {}, attempts: 3, firstDelayMs: 1 });
  assertEq(r.ok, false);
  assert(r.failures[0].includes('ECONNREFUSED'), r.failures.join('; '));
});

test('CLI exits 2 on bad usage and 1 when unhealthy', async () => {
  const cli = path.join(__dirname, '..', 'tools', 'healthcheck.js');
  const usage = spawnSync(process.execPath, [cli], { encoding: 'utf8' });
  assertEq(usage.status, 2, 'no args');
  const notUrl = spawnSync(process.execPath, [cli, 'nfcarchiver.com/cimbar/', SHA], { encoding: 'utf8' });
  assertEq(notUrl.status, 2, 'base url without scheme');
  const s = await serve({});
  await s.close(); // closed port: every attempt is refused immediately
  const env = { ...process.env, HEALTHCHECK_ATTEMPTS: '2', HEALTHCHECK_FIRST_DELAY_MS: '1' };
  const unhealthy = spawnSync(process.execPath, [cli, s.base, SHA], { encoding: 'utf8', env, timeout: 60000 });
  assertEq(unhealthy.status, 1, 'unhealthy');
  assert(unhealthy.stderr.includes('UNHEALTHY'), unhealthy.stderr);
});

(async () => {
  console.log('\ntest_healthcheck.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
