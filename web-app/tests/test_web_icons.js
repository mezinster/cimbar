// The page's icons and web manifest: every local file index.html links to
// must exist and be staged by the deploy workflow (which copies an explicit
// list), and the manifest's icons must be the sizes they declare.
'use strict';
const fs = require('fs');
const path = require('path');

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg || 'assert'); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const workflow = fs.readFileSync(path.join(root, '..', '.github', 'workflows', 'deploy-webapp.yml'), 'utf8');

/** href values of <link> tags that point at local files (not https://…). */
const localLinks = [...html.matchAll(/<link\b[^>]*\bhref="([^"]+)"/g)]
  .map((m) => m[1])
  .filter((h) => !/^(https?:)?\/\//.test(h));

/** The files the deploy workflow's "Stage the deployable files" loop copies. */
function stagedFiles() {
  const m = workflow.match(/for f in ([^;]+); do/);
  assert(m, 'deploy-webapp.yml has no "for f in …; do" staging loop');
  return m[1].trim().split(/\s+/);
}

/** [width, height, colour type] from a PNG's IHDR. */
function pngInfo(file) {
  const b = fs.readFileSync(file);
  assert(b.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), `${file} is not a PNG`);
  return [b.readUInt32BE(16), b.readUInt32BE(20), b[25]];
}

test('index.html links a favicon, an Apple touch icon and a web manifest', () => {
  for (const rel of ['icon', 'apple-touch-icon', 'manifest']) {
    assert(new RegExp(`<link\\b[^>]*\\brel="${rel}"`).test(html), `no <link rel="${rel}">`);
  }
  assert(/<meta name="theme-color" content="#[0-9a-fA-F]{6}">/.test(html), 'no <meta name="theme-color">');
});

test('every local <link href> exists in web-app/', () => {
  assert(localLinks.length >= 4, `expected the icon/manifest links, found ${localLinks.join(', ')}`);
  for (const href of localLinks) assert(fs.existsSync(path.join(root, href)), `index.html links ${href}, which does not exist`);
});

test('the deploy workflow stages every local file the page links to', () => {
  const staged = stagedFiles();
  for (const href of localLinks) assert(staged.includes(href), `deploy-webapp.yml does not stage ${href}`);
});

test('the deploy workflow stages the live-scan worker and every script it imports', () => {
  // The workflow's verify step checks <script src> and <link href> only; a
  // worker is created from JS (new Worker('…')) and pulls its own files with
  // importScripts, so a missing one would 404 only once someone scans.
  const staged = stagedFiles();
  const sources = ['live-scan.js', 'index.html'].map((f) => fs.readFileSync(path.join(root, f), 'utf8')).join('\n');
  const workers = [...sources.matchAll(/new Worker\('([^']+)'\)/g)].map((m) => m[1]);
  assert(workers.includes('scan-worker.js'), `expected new Worker('scan-worker.js'), found ${workers.join(', ') || 'none'}`);
  for (const w of workers) {
    assert(staged.includes(w), `deploy-webapp.yml does not stage the worker ${w}`);
    const src = fs.readFileSync(path.join(root, w), 'utf8');
    const call = src.match(/importScripts\(([\s\S]*?)\);/);
    assert(call, `${w} has no importScripts(...) call`);
    const files = [...call[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
    assert(files.length >= 10, `${w} imports only ${files.length} files`);
    for (const f of files) {
      assert(fs.existsSync(path.join(root, f)), `${w} imports ${f}, which does not exist`);
      assert(staged.includes(f), `deploy-webapp.yml does not stage ${f}, which ${w} imports`);
    }
  }
});

test('the deploy verify step checks <link href> as well as <script src>', () => {
  assert(/<link\b[^\n]*href/.test(workflow.split('Verify the staged bundle')[1] || ''),
    'the "Verify the staged bundle" step must check local <link href> files');
});

test('upload and rollback give every staged file type its own Content-Type', () => {
  // S3 serves whatever Content-Type the upload set; the non-HTML sync used to
  // force text/javascript on everything, which would make browsers reject icons.
  const want = {
    '*.js': 'text/javascript; charset=utf-8',
    '*.png': 'image/png',
    '*.svg': 'image/svg+xml',
    '*.webmanifest': 'application/manifest+json',
  };
  for (const [pattern, type] of Object.entries(want)) {
    const line = new RegExp(`^\\s*${pattern.replace(/[.*]/g, '\\$&')}\\s+${type.replace(/[+.]/g, '\\$&')}\\s*$`, 'gm');
    const n = (workflow.match(line) || []).length;
    assert(n === 2, `expected "${pattern} ${type}" in both the upload and the rollback type tables, found ${n}`);
  }
  assert(!/--content-type 'text\/javascript[^']*'\s*\\?\s*\n\s*--cache-control/.test(workflow),
    'a sync still forces text/javascript on every file');
  for (const f of stagedFiles()) {
    if (f === 'index.html') continue;
    const ext = '*' + path.extname(f);
    assert(want[ext], `staged file ${f} has no Content-Type entry`);
  }
});

test('manifest icons exist, are listed for deploy, and match their declared sizes', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.webmanifest'), 'utf8'));
  assert(manifest.name && manifest.short_name, 'manifest needs name and short_name');
  assert(manifest.icons && manifest.icons.length >= 2, 'manifest needs icons');
  const staged = stagedFiles();
  for (const icon of manifest.icons) {
    const [w, h] = pngInfo(path.join(root, icon.src));
    assert(icon.sizes === `${w}x${h}`, `${icon.src} is ${w}x${h} but the manifest says ${icon.sizes}`);
    assert(staged.includes(icon.src), `deploy-webapp.yml does not stage ${icon.src}`);
  }
});

test('the Apple touch icon is 180x180 and opaque (iOS fills transparency with black)', () => {
  const href = html.match(/<link\b[^>]*\brel="apple-touch-icon"[^>]*\bhref="([^"]+)"/)[1];
  const [w, h, colour] = pngInfo(path.join(root, href));
  assert(w === 180 && h === 180, `apple-touch-icon is ${w}x${h}`);
  assert(colour === 2, `apple-touch-icon has PNG colour type ${colour}; want 2 (RGB, no alpha)`);
});

(async () => {
  console.log('\ntest_web_icons.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
