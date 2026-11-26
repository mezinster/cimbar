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
  assert(/<meta name="theme-color" content="#f5f3ef"(?: media="\(prefers-color-scheme: light\)")?>/.test(html), 'no light <meta name="theme-color" content="#f5f3ef">');
});

test('every local <link href> exists in web-app/', () => {
  assert(localLinks.length >= 4, `expected the icon/manifest links, found ${localLinks.join(', ')}`);
  for (const href of localLinks) assert(fs.existsSync(path.join(root, href)), `index.html links ${href}, which does not exist`);
});

test('the deploy workflow stages every local file the page links to', () => {
  const staged = stagedFiles();
  for (const href of localLinks) assert(staged.includes(href), `deploy-webapp.yml does not stage ${href}`);
});

test('the deploy workflow stages every worker, the scripts it imports and the wasm it fetches', () => {
  // The workflow's verify step checks <script src> and <link href> only; a
  // worker is created from JS (new Worker('…'), or createWorker(WORKER_URL))
  // and pulls its own files with importScripts / fetch, so a missing one would
  // 404 only once someone scans or opens a HEIC photo.
  const staged = stagedFiles();
  const read = (f) => fs.readFileSync(path.join(root, f), 'utf8');
  const sources = ['live-scan.js', 'index.html', 'image-decode.js'].map(read).join('\n');
  const workers = [...sources.matchAll(/new Worker\('([^']+)'\)/g)].map((m) => m[1]);
  const heicWorker = read('image-decode.js').match(/const WORKER_URL = '([^']+)'/);
  assert(heicWorker, "image-decode.js has no `const WORKER_URL = '…'`");
  workers.push(heicWorker[1]);
  assert(workers.includes('scan-worker.js'), `expected new Worker('scan-worker.js'), found ${workers.join(', ') || 'none'}`);
  assert(workers.includes('heic-worker.js'), `expected the HEIC worker heic-worker.js, found ${workers.join(', ')}`);
  const minImports = { 'scan-worker.js': 10, 'heic-worker.js': 1 };
  for (const w of workers) {
    assert(staged.includes(w), `deploy-webapp.yml does not stage the worker ${w}`);
    const src = read(w);
    const call = src.match(/importScripts\(([\s\S]*?)\);/);
    assert(call, `${w} has no importScripts(...) call`);
    const files = [...call[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
    assert(files.length >= (minImports[w] || 1), `${w} imports only ${files.length} files`);
    for (const f of files) {
      assert(fs.existsSync(path.join(root, f)), `${w} imports ${f}, which does not exist`);
      assert(staged.includes(f), `deploy-webapp.yml does not stage ${f}, which ${w} imports`);
    }
  }
  assert(workers.includes('heic-worker.js') && read('heic-worker.js').includes("importScripts('vendor/libheif/libheif.js')"),
    'heic-worker.js must import vendor/libheif/libheif.js');
  const wasm = read('image-decode.js').match(/const WASM_URL = '([^']+)'/);
  assert(wasm, "image-decode.js has no `const WASM_URL = '…'`");
  for (const f of [wasm[1], 'vendor/libheif/libheif.js', 'vendor/libheif/LICENSE', 'vendor/libheif/DAV1D-LICENSE']) {
    assert(fs.existsSync(path.join(root, f)), `${f} does not exist`);
    assert(staged.includes(f), `deploy-webapp.yml does not stage ${f}`);
  }
  assert(wasm[1] === 'vendor/libheif/libheif.wasm', `unexpected WASM_URL ${wasm[1]}`);
});

/** Published (site/) name of a staged source file: the licences get a .txt suffix. */
function publishedName(f) { return /^vendor\/libheif\/(DAV1D-)?LICENSE$/.test(f) ? f + '.txt' : f; }

test('the libheif licences are published as .txt (extensionless keys are served as folders), typed in both tables, and nothing else is .txt', () => {
  const rename = workflow.match(/case "\$f" in\s+vendor\/libheif\/LICENSE\|vendor\/libheif\/DAV1D-LICENSE\) dest="\$f\.txt"/);
  assert(rename, 'the staging loop must rename the two licences to <name>.txt');
  const published = stagedFiles().map(publishedName);
  for (const f of ['vendor/libheif/LICENSE.txt', 'vendor/libheif/DAV1D-LICENSE.txt']) {
    assert(published.includes(f), `${f} is not published`);
    assert(workflow.split('Verify the staged bundle')[1].split('Verify the healthcheck')[0].includes(f), `the verify allow-list does not accept ${f}`);
  }
  assert(published.filter((f) => f.endsWith('.txt')).length === 2, 'only the two licences may be .txt (the *.txt type is text/plain)');
  assert(!workflow.includes('*LICENSE'), 'no extensionless *LICENSE pattern may remain');
  assert((workflow.match(/^\s*\*\.txt\s+text\/plain; charset=utf-8\s*$/gm) || []).length === 2, '*.txt text/plain must be in both type tables');
});

test('the staging loop keeps subdirectories', () => {
  assert(/mkdir -p "\$\(dirname "..\/site\/\$dest"\)"/.test(workflow), 'the staging loop must mkdir -p the destination directory of each file');
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
    '*.wasm': 'application/wasm',
    '*.txt': 'text/plain; charset=utf-8',
  };
  for (const [pattern, type] of Object.entries(want)) {
    const line = new RegExp(`^\\s*${pattern.replace(/[.*]/g, '\\$&')}\\s+${type.replace(/[+.]/g, '\\$&')}\\s*$`, 'gm');
    const n = (workflow.match(line) || []).length;
    assert(n === 2, `expected "${pattern} ${type}" in both the upload and the rollback type tables, found ${n}`);
  }
  assert(/find \. -type f/.test(workflow.split('Verify the staged bundle')[1] || ''), 'the verify step must walk subdirectories (find), not just *');
  assert(!/--content-type 'text\/javascript[^']*'\s*\\?\s*\n\s*--cache-control/.test(workflow),
    'a sync still forces text/javascript on every file');
  for (const f of stagedFiles().map(publishedName)) {
    if (f === 'index.html') continue;
    const key = Object.keys(want).find((p) => (p.startsWith('*.') ? f.endsWith(p.slice(1)) : f.endsWith(p.slice(1))));
    assert(key, `staged file ${f} has no Content-Type entry`);
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
