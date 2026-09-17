// Tests for i18n.js: dictionary completeness, interpolation, fallback,
// language detection, and that every key index.html references exists.
'use strict';
const fs = require('fs');
const path = require('path');
const I = require('../i18n.js');

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

const LANGS = I.LANGUAGES.map((l) => l.code);
const en = I.STRINGS.en;
const placeholders = (s) => (s.match(/\{[a-z]+\}/g) || []).sort().join(',');

test('five languages, English first, each with a native name', () => {
  assertEq(LANGS.join(','), 'en,ru,uk,tr,ka', 'language codes');
  for (const l of I.LANGUAGES) assert(l.name && l.name.length > 2, `name for ${l.code}`);
});

test('every language defines every English key, non-empty, with the same placeholders', () => {
  const keys = Object.keys(en);
  assert(keys.length > 60, `expected a full dictionary, got ${keys.length} keys`);
  for (const code of LANGS) {
    const table = I.STRINGS[code];
    const missing = keys.filter((k) => !(k in table));
    assertEq(missing.join(','), '', `${code} missing keys`);
    const extra = Object.keys(table).filter((k) => !(k in en));
    assertEq(extra.join(','), '', `${code} has keys not in en`);
    for (const k of keys) {
      assert(typeof table[k] === 'string' && table[k].trim().length > 0, `${code}.${k} empty`);
      assertEq(placeholders(table[k]), placeholders(en[k]), `${code}.${k} placeholders`);
    }
  }
});

test('t() interpolates {params}, falls back to English, returns the key when unknown', () => {
  I.setLang('ru');
  assertEq(I.getLang(), 'ru');
  assertEq(I.t('fileInfo', { name: 'a.txt', size: '1 KB' }), 'Файл: a.txt (1 KB)');
  assertEq(I.t('encodingFrame', { i: 2, n: 5 }), 'Кодирование кадра 2 / 5');
  // temporarily poke a hole to prove the English fallback
  const saved = I.STRINGS.ru.done; delete I.STRINGS.ru.done;
  try { assertEq(I.t('done'), 'Done'); } finally { I.STRINGS.ru.done = saved; }
  assertEq(I.t('noSuchKey'), 'noSuchKey');
  I.setLang('en');
});

test('detect(): stored choice, then browser languages, then English; bad values ignored', () => {
  const store = (v) => ({ getItem: () => v });
  assertEq(I.detect(store('ka'), ['en-US']), 'ka', 'stored wins');
  assertEq(I.detect(store('xx'), ['ru-RU', 'en']), 'ru', 'invalid stored falls to browser');
  assertEq(I.detect(store(null), ['fr', 'uk-UA']), 'uk', 'first supported browser language');
  assertEq(I.detect(store(null), ['fr']), 'en', 'unsupported browser language -> en');
  assertEq(I.detect(null, []), 'en', 'nothing -> en');
  assertEq(I.detect({ getItem: () => { throw new Error('blocked'); } }, ['tr']), 'tr', 'storage error tolerated');
  assertEq(I.normalize('UK_ua'), 'uk');
});

test('every data-i18n* key used by index.html exists in the English table', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const used = [...html.matchAll(/data-i18n(?:-html|-placeholder|-title)?="([^"]+)"/g)].map((m) => m[1]);
  assert(used.length >= 40, `expected the page to be tagged, found ${used.length} attributes`);
  const unknown = used.filter((k) => !(k in en));
  assertEq(unknown.join(','), '', 'unknown keys in index.html');
  const dyn = [...html.matchAll(/\bt\('([A-Za-z0-9]+)'/g)].map((m) => m[1]);
  assert(dyn.length >= 30, `expected dynamic messages to use t(), found ${dyn.length}`);
  const unknownDyn = dyn.filter((k) => !(k in en));
  assertEq(unknownDyn.join(','), '', 'unknown keys in t() calls');
  assert(html.includes('<script src="i18n.js"></script>'), 'i18n.js must be loaded by the page');
  assert(html.indexOf('<script src="i18n.js">') < html.indexOf('CimbarI18n.apply()'), 'i18n.js must load before the page script uses it');
});

test('html-bearing strings keep their markup balanced in every language', () => {
  for (const code of LANGS) {
    for (const [k, v] of Object.entries(I.STRINGS[code])) {
      if (!k.endsWith('Html')) { assert(!/<[a-z]/.test(v), `${code}.${k} contains markup but is not an Html key`); continue; }
      const open = (v.match(/<strong/g) || []).length, close = (v.match(/<\/strong>/g) || []).length;
      assertEq(open, close, `${code}.${k} <strong> balance`);
    }
  }
});

(async () => {
  console.log('\ntest_i18n.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
