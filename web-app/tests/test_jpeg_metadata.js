'use strict';
// Port of nfcarchiver webapp/test/jpeg-metadata.test.ts.
const M = require('../jpeg-metadata.js');

let passed = 0, failed = 0;
const pending = [];
function test(name, fn) {
  pending.push((async () => {
    try { await fn(); passed++; console.log(`  PASS  ${name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); }
  })());
}
function eqBytes(a, b, msg) {
  const x = Array.from(a), y = Array.from(b);
  if (x.length !== y.length || x.some((v, i) => v !== y[i])) {
    throw new Error(`${msg}: got [${x.join(',')}], want [${y.join(',')}]`);
  }
}
function eq(a, b, msg) {
  if (a !== b) throw new Error(`${msg}: got ${a}, want ${b}`);
}
function throws(fn, msg) {
  try { fn(); } catch (e) { return; }
  throw new Error(`${msg}: expected a throw`);
}

const ascii = (s) => [...s].map((c) => c.charCodeAt(0));
const seg = (marker, body) => [0xff, marker, (body.length + 2) >> 8, (body.length + 2) & 0xff, ...body];
const filled = (n, v) => new Array(n).fill(v);
const latin1 = (b) => String.fromCharCode(...b);
const u8 = (...parts) => Uint8Array.from(parts.flat());

const soi = [0xff, 0xd8];
const app0 = seg(0xe0, [...ascii('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]);
const app1 = seg(0xe1, [...ascii('Exif'), 0, 0, ...ascii('GPS')]);
const com = seg(0xfe, ascii('hello'));
const dqt = seg(0xdb, filled(65, 3));
const sof = seg(0xc0, [8, 0, 1, 0, 1, 1, 1, 0x11, 0]);
const dht = seg(0xc4, filled(20, 1));
const sos = seg(0xda, [1, 1, 0, 0, 0x3f, 0]);
const data = [0x12, 0xff, 0x00, 0x34, 0xff, 0xd0, 0x56];
const eoi = [0xff, 0xd9];

console.log('\ntest_jpeg_metadata.js');

test('strips APP1 and COM, keeps the rest byte-identical', () => {
  const out = M.stripJpegMetadata(u8(soi, app0, app1, com, dqt, sof, dht, sos, data, eoi));
  eqBytes(out, u8(soi, app0, dqt, sof, dht, sos, data, eoi), 'output');
  eq(latin1(out).includes('Exif'), false, 'Exif gone');
});

test('JPEG without metadata is unchanged', () => {
  const input = u8(soi, app0, dqt, sof, dht, sos, data, eoi);
  eqBytes(M.stripJpegMetadata(input), input, 'unchanged');
});

test('PNG throws', () => {
  const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
  throws(() => M.stripJpegMetadata(png), 'png');
});

test('drops everything after the first EOI, appended gain map included', () => {
  const xmp = seg(0xe1, ascii('http://ns.adobe.com/xap/1.0/\x00GainMap'));
  const gainMap = [...soi, ...app1, ...xmp, ...dqt, ...sof, ...dht, ...sos, ...data, ...eoi];
  const out = M.stripJpegMetadata(u8(soi, app0, dqt, sof, dht, sos, data, eoi, gainMap, [0x00, 0x42]));
  eqBytes(out, u8(soi, app0, dqt, sof, dht, sos, data, eoi), 'output');
  eqBytes(out.subarray(out.length - 2), [0xff, 0xd9], 'tail');
  eq(latin1(out).includes('Exif'), false, 'Exif gone');
  eq(latin1(out).includes('GainMap'), false, 'GainMap gone');
});

test('progressive layout (several scans with tables between) is kept intact', () => {
  const sof2 = seg(0xc2, [8, 0, 1, 0, 1, 1, 1, 0x11, 0]);
  const dht2 = seg(0xc4, filled(18, 2));
  const data2 = [0x77, 0xff, 0x00, 0xff, 0xd3, 0x88];
  const input = u8(soi, app0, app1, dqt, sof2, dht, sos, data, dht2, sos, data2, eoi);
  eqBytes(
    M.stripJpegMetadata(input),
    u8(soi, app0, dqt, sof2, dht, sos, data, dht2, sos, data2, eoi),
    'progressive',
  );
});

test('every APP1-APP15 segment is dropped; APP0 stays', () => {
  for (let marker = 0xe1; marker <= 0xef; marker++) {
    const appN = seg(marker, ascii('ICC_PROFILE or MPF or anything'));
    eqBytes(
      M.stripJpegMetadata(u8(soi, app0, appN, dqt, sof, dht, sos, data, eoi)),
      u8(soi, app0, dqt, sof, dht, sos, data, eoi),
      `marker 0x${marker.toString(16)}`,
    );
  }
});

test('fill bytes before a marker are skipped, kept or dropped segment alike', () => {
  const out = M.stripJpegMetadata(
    u8(soi, [0xff], app0, [0xff, 0xff], app1, [0xff, 0xff, 0xff], dqt, sof, dht, sos, data, eoi),
  );
  eqBytes(out, u8(soi, app0, dqt, sof, dht, sos, data, eoi), 'fill');
});

test('truncated input throws rather than returning a partial file', () => {
  const whole = [...soi, ...app0, ...app1, ...dqt, ...sof, ...dht, ...sos, ...data, ...eoi];
  const cases = [
    ['nothing after SOI', soi],
    ['inside a segment that is kept', whole.slice(0, soi.length + 6)],
    ['inside a segment that is dropped', whole.slice(0, soi.length + app0.length + 5)],
    ['after a marker, before its length', [...soi, ...app0, 0xff, 0xdb]],
    ['inside the entropy data, no EOI', whole.slice(0, whole.length - eoi.length - 2)],
    ['a lone FF where EOI should be', whole.slice(0, whole.length - 1)],
  ];
  for (const [what, bytes] of cases) {
    throws(() => M.stripJpegMetadata(Uint8Array.from(bytes)), what);
  }
});

Promise.all(pending).then(() => {
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
});
