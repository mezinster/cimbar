'use strict';
const fs = require('fs');
const path = require('path');
const C = require('../cimbar.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log(`  PASS  ${name}`); }
  catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); }
}
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }

function caseBytes(c) {
  const one = Buffer.from(c.hex, 'hex');
  const n = c.repeat || 1;
  const out = new Uint8Array(one.length * n);
  for (let i = 0; i < n; i++) out.set(one, i * one.length);
  return out;
}

console.log('\ntest_text_message.js');
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'test-data', 'text-message.json'), 'utf8'));

for (const c of fixture.cases) {
  test(`fixture: ${c.name} (${c.note})`, () => {
    const bytes = caseBytes(c);
    assertEq(C.isTextMessage(c.name, bytes), c.expected, 'isTextMessage');
    const s = C.decodeTextMessage(c.name, bytes);
    if (c.expected) { if (c.text !== undefined) assertEq(s, c.text, 'decoded text'); }
    else assertEq(s, null, 'decodeTextMessage on a non-text payload');
  });
}

test('textMessageName formats local time, zero-padded', () => {
  assertEq(C.textMessageName(new Date(2026, 0, 2, 3, 4, 5)), 'message-20260102-030405.txt', 'name');
});

test('the hello golden (hello.txt) is a text message', () => {
  const side = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'test-data', 'goldens', 'hello.json'), 'utf8'));
  const bytes = new Uint8Array(Buffer.from(side.fileBytesBase64, 'base64'));
  assertEq(C.decodeTextMessage(side.fileName, bytes), 'Hello, CimBar v2!\n', 'decoded');
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
