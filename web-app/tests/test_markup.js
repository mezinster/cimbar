// Static guards over index.html for things no behavioural test can see.
// Usage: node tests/test_markup.js [path/to/index.html]
'use strict';
const fs = require('fs');
const path = require('path');
const file = process.argv[2] || path.join(__dirname, '..', 'index.html');
const html = fs.readFileSync(file, 'utf8');
const inline = (html.match(/<script>([\s\S]*?)<\/script>/) || [, ''])[1];
let passed = 0, failed = 0;
const test = (name, fn) => { try { fn(); passed++; console.log(`  PASS  ${name}`); } catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); } };
const assert = (c, m) => { if (!c) throw new Error(m); };

console.log(`\ntest_markup.js (${path.basename(file)})`);
test('no external scripts (no Tailwind/Iconify leaking in from design drafts)', () => {
  const ext = [...html.matchAll(/<script[^>]+src="(https?:)?\/\/[^"]+"/g)].map((m) => m[0]);
  assert(ext.length === 0, ext.join(' '));
});
test('every <use href="#i-…"> has a sprite <symbol>', () => {
  const used = new Set([...html.matchAll(/<use href="#(i-[a-z0-9-]+)"/g)].map((m) => m[1]));
  const defined = new Set([...html.matchAll(/<symbol id="(i-[a-z0-9-]+)"/g)].map((m) => m[1]));
  assert(used.size >= 20, `expected the icon sprite in use, found ${used.size} icons`);
  const missing = [...used].filter((u) => !defined.has(u));
  assert(missing.length === 0, 'missing symbols: ' + missing.join(','));
});
test('a dark theme exists and redefines the core tokens', () => {
  const m = html.match(/@media \(prefers-color-scheme: dark\)\s*{\s*:root\s*{([^}]*)}/);
  assert(m, 'no dark :root block');
  for (const tok of ['--bg', '--surface', '--text', '--accent-fg', '--border']) assert(m[1].includes(tok + ':'), `dark theme lacks ${tok}`);
});
test('no alert() or confirm() in the page script', () => {
  assert(!/\b(alert|confirm)\(/.test(inline), 'native dialog call found');
});
test('no red primary action (btn-danger)', () => {
  assert(!html.includes('btn-danger'), 'btn-danger present');
});
test('every route has exactly one screen (except /receive, which is an overlay)', () => {
  for (const r of ['/', '/send', '/send/ready', '/receive/files', '/receive/unlock', '/receive/done', '/how']) {
    const n = html.split(`data-route="${r}"`).length - 1;
    assert(n === 1, `${r}: ${n} screens`);
  }
});
test('green text uses --accent-fg, never --accent, in color: declarations', () => {
  const bad = [...html.matchAll(/(?<![-\w])color\s*:\s*var\(--accent\)/g)];
  assert(bad.length === 0, `${bad.length} color:var(--accent) (fails AA in dark mode — use --accent-fg)`);
});
console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
