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
const placeholders = (s) => [...new Set(s.match(/\{[a-z]+\}/g) || [])].sort().join(',');

test('seven languages, English first, each with a native name', () => {
  assertEq(LANGS.join(','), 'en,ru,uk,tr,ka,pl,be', 'language codes');
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

test('plural forms: [[param|…]] has one form per category of its language and names a real placeholder', () => {
  const ORDER = { en: 2, ru: 3, uk: 3, pl: 3, be: 3 };
  for (const code of LANGS) {
    for (const [k, v] of Object.entries(I.STRINGS[code])) {
      for (const m of v.matchAll(/\[\[([^|\]]*)\|([^\]]*)\]\]/g)) {
        assert(code in ORDER, `${code}.${k}: ${code} has no plural categories, write the message without [[…]]`);
        assertEq(m[2].split('|').length, ORDER[code], `${code}.${k} number of plural forms`);
        assert(placeholders(en[k]).split(',').includes('{' + m[1] + '}'), `${code}.${k}: [[${m[1]}|…]] is not a placeholder of the message`);
      }
      assert(!/\[\[|\]\]/.test(v.replace(/\[\[[a-zA-Z]+\|[^\]]*\]\]/g, '')), `${code}.${k}: malformed [[…]]`);
      assert(!/\((s|ов|ів)\)/.test(v), `${code}.${k}: use a plural form instead of "(s)"`);
    }
  }
});

test('t() picks the plural form for the count', () => {
  try {
    I.setLang('en');
    assertEq(I.t('assembled', { n: 1 }), 'Assembled 1 frame');
    assertEq(I.t('assembled', { n: 5 }), 'Assembled 5 frames');
    assertEq(I.t('readyFrames', { n: '4 + 1' }), '4 + 1 frames', 'non-numeric count takes the last form');
    assertEq(I.t('textEncInfo', { bytes: '62 B', frames: 1 }), '62 B · at most 1 frame');
    I.setLang('ru');
    assertEq(I.t('textEncInfo', { bytes: '1 KB', frames: 1 }), '1 KB · не более 1 кадра');
    assertEq(I.t('textEncInfo', { bytes: '1 KB', frames: 3 }), '1 KB · не более 3 кадров');
    assertEq(I.t('photoWrongFile', { n: 22 }).includes('(22 кадра)'), true, 'ru few');
    assertEq(I.t('photoWrongFile', { n: 11 }).includes('(11 кадров)'), true, 'ru many');
    assertEq(I.t('photoWrongFile', { n: 21 }).includes('(21 кадр)'), true, 'ru one');
    I.setLang('uk');
    assertEq(I.t('gifDiscardsSession', { n: 3 }).includes('(3 кадри)'), true, 'uk few');
    assertEq(I.t('readyHelp', { n: 1 }).includes('будь-який 1 кадр відновить'), true, 'uk one');
    // A key missing in Russian falls back to English with English plural rules.
    const saved = I.STRINGS.ru.assembled; delete I.STRINGS.ru.assembled;
    I.setLang('ru');
    try { assertEq(I.t('assembled', { n: 3 }), 'Assembled 3 frames'); } finally { I.STRINGS.ru.assembled = saved; }
  } finally { I.setLang('en'); }
});

test('every language translates every message (allow-listed technical strings excepted)', () => {
  // Same in every language: abbreviations and unit-only strings. Anything else
  // equal to English shipped untranslated ("LIVE DEMO" did, in four languages).
  const SAME = new Set(['about2Title', 'chipAes', 'delayNormal', 'sizeB', 'sizeKB', 'sizeMB', 'photoResultLabel']);
  for (const code of LANGS.filter((c) => c !== 'en')) {
    const same = Object.keys(en).filter((k) => !SAME.has(k) && I.STRINGS[code][k] === en[k]);
    assertEq(same.join(','), '', `${code}: messages identical to English`);
  }
});

test('counts agree with the noun in the strings fixed after the 0.13 audit', () => {
  try {
    I.setLang('ru');
    assertEq(I.t('presentRepair', { r: 0, n: 3 }), 'Восстанавливающий кадр 0 — любые 3 кадра собирают файл');
    assertEq(I.t('scanFrames', { rank: 2, total: 21 }), '2 / 21 кадра');
    assertEq(I.t('photoKeepGoing', { rank: 1, total: 3 }), '1 из 3 кадров — сфотографируйте следующий');
    I.setLang('pl');
    assertEq(I.t('presentRepair', { r: 1, n: 2 }), 'Klatka naprawcza 1 — dowolne 2 klatki uzupełniają plik');
    assertEq(I.t('incomplete', { filled: 0, total: 1, rejected: 1 }), 'Niekompletne: zdekodowano 0 z 1 klatki (odrzucone: 1)');
    I.setLang('en');
    assertEq(I.t('scanFrames', { rank: 0, total: 1 }), '0 / 1 frame');
    assert(I.t('readyHelpSingle').includes('one frame'), 'one-frame help text');
    I.setLang('ru');
    assertEq(I.t('sizeKB', { value: '14,8' }), '14,8 КБ');
  } finally { I.setLang('en'); }
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
  const used = [...html.matchAll(/data-i18n(?:-html|-placeholder|-title|-aria-label)?="([^"]+)"/g)].map((m) => m[1]);
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

test('no orphaned keys: every English key is used by index.html or by i18n.js itself', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const self = new Set(['title']);   // apply() sets document.title from t('title')
  const orphans = Object.keys(en).filter((k) => !self.has(k) && !html.includes(`'${k}'`) && !html.includes(`"${k}"`));
  assertEq(orphans.join(','), '', 'unused keys (delete them from all five tables)');
});

test('apply() translates data-i18n-aria-label; the icon-only language button uses it', () => {
  const el = { attrs: { 'data-i18n-aria-label': 'language' }, getAttribute(k) { return this.attrs[k]; }, setAttribute(k, v) { this.attrs[k] = v; } };
  const doc = {
    documentElement: {}, title: '',
    querySelectorAll: (sel) => (sel === '[data-i18n-aria-label]' ? [el] : []),
    getElementById: () => null,
  };
  I.setLang('ru', doc);
  assertEq(el.attrs['aria-label'], I.STRINGS.ru.language, 'aria-label follows the language');
  I.setLang('en', doc);
  const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  const btn = html.match(/<button[^>]*onclick="openLanguageSheet\(\)"[^>]*>/)[0];
  assert(!/\saria-label="/.test(btn), 'no hard-coded English aria-label on the language button');
  assert(btn.includes('data-i18n-aria-label="language"'), 'language button aria-label comes from i18n');
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
