#!/usr/bin/env node
/**
 * Post-deploy verification for the CimBar web app. Fetches the live site
 * through its PUBLIC url — so DNS, CloudFront and S3 are all exercised, not
 * just the origin — and asserts it is serving the build this run produced.
 *
 *   node tools/healthcheck.js https://nfcarchiver.com/cimbar/ <short-sha>
 *
 * A 200 only proves S3 holds something. The build-marker match is the
 * load-bearing check: it proves the page is THIS build and that no edge is
 * still serving the previous one. The page carries the marker as an HTML
 * comment stamped by the deploy workflow's build job; one script is fetched
 * too, because index.html references its scripts by relative URL and a
 * stale or missing script would break the app while the page itself looks
 * fine.
 *
 * Exit codes: 0 healthy, 1 unhealthy, 2 bad usage. Exit 2 is asserted by the
 * workflow before the credentialed job depends on this file.
 *
 * Uses Node's http/https modules rather than global fetch so the same code
 * path runs under the Node 14 that `sh tests/run_all.sh` may use locally and
 * the Node 20 the workflow uses. No dependencies.
 */
'use strict';
const http = require('http');
const https = require('https');
const { URL } = require('url');

const REQUEST_TIMEOUT_MS = 30000;

/** Node's http/https send NO User-Agent by default; common WAF rulesets block
 *  such requests with 403, which would make this check fail on every deploy
 *  and roll back good ones. Identify ourselves. */
const USER_AGENT = 'cimbar-deploy-healthcheck/1 (+https://github.com/mezinster/cimbar)';

/** The marker the workflow stamps into index.html. Prefixed so a bare short
 *  SHA (7 hex chars) cannot match an unrelated hex run in the page. */
function buildMarker(sha) {
  return `<!-- cimbar-build:${sha} -->`;
}

/** Redirects are deliberately NOT followed: the deploy target is a directory
 *  URL that must resolve to index.html at the edge, so a 301 here is a real
 *  finding about the CDN configuration, not something to paper over. */
function fetchPage(url) {
  return new Promise((resolve, reject) => {
    const target = new URL(url);
    const client = target.protocol === 'https:' ? https : http;
    const req = client.get(
      {
        protocol: target.protocol,
        hostname: target.hostname,
        port: target.port,
        path: target.pathname + target.search,
        headers: { 'cache-control': 'no-cache', pragma: 'no-cache', 'user-agent': USER_AGENT },
      },
      (res) => {
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => { body += chunk; });
        res.on('end', () => resolve({
          status: res.statusCode || 0,
          contentType: String(res.headers['content-type'] || ''),
          body,
        }));
      },
    );
    req.setTimeout(REQUEST_TIMEOUT_MS, () => req.destroy(new Error(`timeout after ${REQUEST_TIMEOUT_MS} ms`)));
    req.on('error', reject);
  });
}

/** One full pass. Collects every failure rather than stopping at the first,
 *  so a failing deploy reports everything wrong with it in one log. */
async function checkOnce(baseUrl, expectedSha, fetcher = fetchPage) {
  const failures = [];
  const base = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`;
  const scriptUrl = `${base}cimbar.js`;

  const page = await fetcher(base);
  if (page.status !== 200) failures.push(`GET ${base} -> ${page.status} (want 200)`);
  if (!page.contentType.includes('text/html')) failures.push(`GET ${base} content-type "${page.contentType}" (want text/html)`);
  if (page.status === 200 && !page.body.includes(buildMarker(expectedSha))) {
    failures.push(`served page does not carry the build marker ${buildMarker(expectedSha)} — an older version is still live`);
  }

  const js = await fetcher(scriptUrl);
  if (js.status !== 200) failures.push(`GET ${scriptUrl} -> ${js.status} (want 200)`);
  if (!js.contentType.includes('javascript')) failures.push(`GET ${scriptUrl} content-type "${js.contentType}" (want javascript)`);

  return { ok: failures.length === 0, failures };
}

/** Retry with exponential backoff to absorb residual CDN propagation.
 *  Defaults: 6 attempts, 2 s first delay, ~62 s total. */
async function healthcheck(baseUrl, expectedSha, opts = {}) {
  const attempts = opts.attempts || 6;
  const fetcher = opts.fetcher || fetchPage;
  const sleep = opts.sleep || ((ms) => new Promise((r) => setTimeout(r, ms)));
  const log = opts.log || (() => {});
  let delay = opts.firstDelayMs === undefined ? 2000 : opts.firstDelayMs;
  let last = { ok: false, failures: ['no attempt was made'] };
  for (let i = 1; i <= attempts; i++) {
    try {
      last = await checkOnce(baseUrl, expectedSha, fetcher);
    } catch (e) {
      last = { ok: false, failures: [`request failed: ${e.message}`] };
    }
    if (last.ok) return last;
    log(`attempt ${i}/${attempts} unhealthy: ${last.failures.join('; ')}`);
    if (i < attempts) { await sleep(delay); delay *= 2; }
  }
  return last;
}

async function main(argv) {
  const [baseUrl, sha] = argv;
  if (!baseUrl || !sha || !/^https?:\/\//.test(baseUrl)) {
    console.error('usage: node tools/healthcheck.js <https://base-url/> <build-sha>');
    return 2;
  }
  // Test hooks only: the workflow never sets these, so production runs use
  // the full ~62 s schedule.
  const attempts = process.env.HEALTHCHECK_ATTEMPTS ? Number(process.env.HEALTHCHECK_ATTEMPTS) : undefined;
  const firstDelayMs = process.env.HEALTHCHECK_FIRST_DELAY_MS ? Number(process.env.HEALTHCHECK_FIRST_DELAY_MS) : undefined;
  const result = await healthcheck(baseUrl, sha, { log: (m) => console.log(m), attempts, firstDelayMs });
  if (result.ok) {
    console.log(`HEALTHY: ${baseUrl} serves build ${sha}`);
    return 0;
  }
  console.error(`UNHEALTHY: ${baseUrl}`);
  for (const f of result.failures) console.error(`  - ${f}`);
  return 1;
}

module.exports = { buildMarker, fetchPage, checkOnce, healthcheck, USER_AGENT };

if (require.main === module) {
  main(process.argv.slice(2)).then((code) => process.exit(code), (e) => {
    console.error(`healthcheck crashed: ${e && e.stack ? e.stack : e}`);
    process.exit(1);
  });
}
