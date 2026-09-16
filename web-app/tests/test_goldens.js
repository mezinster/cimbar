'use strict';
const fs = require('fs');
const path = require('path');
global.ImageData = global.ImageData || class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
const { GifDecoder } = require('../gif-decoder.js');
const { ReedSolomon } = require('../rs.js');
const F = require('../format.js');
const C = require('../cimbar.js');
const { decryptBytesNode } = require('../tools/node_crypto.js');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function hex(bytes) { let s = ''; for (const b of bytes) s += b.toString(16).padStart(2, '0'); return s; }

const dir = path.join(__dirname, '..', '..', 'test-data', 'goldens');
const names = fs.readdirSync(dir).filter(f => f.endsWith('.json')).map(f => f.replace(/\.json$/, '')).sort();

console.log('\ntest_goldens.js');
assert(names.length >= 5, `expected at least 5 goldens, found ${names.length}`);

for (const name of names) {
  test(`golden ${name}: frames, cells, headers and payload match sidecar`, () => {
    const side = JSON.parse(fs.readFileSync(path.join(dir, name + '.json'), 'utf8'));
    const gif = new Uint8Array(fs.readFileSync(path.join(dir, name + '.gif')));
    const frames = new GifDecoder(gif).decode();
    assertEq(frames.length, side.total, 'frame count');
    assertEq(frames[0].width, F.SPEC.grid.framePx, 'frame width');
    const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
    const asm = new C.FrameAssembler();
    for (let i = 0; i < frames.length; i++) {
      const r = C.decodeFrameExact(frames[i].imageData);
      assertEq(r.diag.hammingMax, 0, `frame ${i} exact hashes`);
      assertEq(hex(r.raw), side.frames[i].rawHex, `frame ${i} raw`);
      assertEq(Array.from(r.cells).join(','), side.frames[i].cells.join(','), `frame ${i} cells`);
      const d = C.decodeRSFrame(r.raw, rs);
      assertEq(d.blocksFailed, 0, `frame ${i} RS`);
      assertEq(hex(d.data), side.frames[i].dataHex, `frame ${i} data`);
      const h = F.decodeHeader(d.data);
      assertEq(JSON.stringify({ version: h.version, encrypted: h.encrypted, fileId: h.fileId, seq: h.seq, total: h.total }),
        JSON.stringify(side.frames[i].header), `frame ${i} header`);
      assert(asm.add(d.data, d.blocksFailed).accepted, `frame ${i} accepted`);
    }
    assert(asm.isComplete(), 'complete');
    let payload = C.stripLengthPrefix(asm.framedData());
    if (side.passphrase !== null) {
      assert(payload[0] === 0xCB && payload[1] === 0x42, 'encrypted magic');
      payload = decryptBytesNode(payload, side.passphrase);
    }
    const parsed = C.parsePayload(payload);
    assertEq(parsed.fileName, side.fileName, 'file name');
    const expected = Buffer.from(side.fileBytesBase64, 'base64');
    assertEq(parsed.fileBytes.length, expected.length, 'file length');
    for (let i = 0; i < expected.length; i++) if (parsed.fileBytes[i] !== expected[i]) throw new Error(`file byte ${i} differs`);
  });
}

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
