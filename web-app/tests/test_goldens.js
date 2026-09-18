'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
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
assert(names.length >= 7, `expected at least 7 goldens, found ${names.length}`);

/** Assemble frame data via a RatelessAssembler, decode the full payload and check it matches the sidecar's expected file. */
function verifyAssembled(asm, side, label) {
  assert(asm.isComplete(), `${label}: complete`);
  let payload = C.stripLengthPrefix(asm.framedData());
  if (side.passphrase !== null) {
    assert(payload[0] === 0xCB && payload[1] === 0x42, `${label}: encrypted magic`);
    payload = decryptBytesNode(payload, side.passphrase);
  }
  if (side.compressed) payload = new Uint8Array(zlib.inflateSync(Buffer.from(payload)));
  const parsed = C.parsePayload(payload);
  assertEq(parsed.fileName, side.fileName, `${label}: file name`);
  const expected = Buffer.from(side.fileBytesBase64, 'base64');
  assertEq(parsed.fileBytes.length, expected.length, `${label}: file length`);
  for (let i = 0; i < expected.length; i++) if (parsed.fileBytes[i] !== expected[i]) throw new Error(`${label}: file byte ${i} differs`);
}

for (const name of names) {
  test(`golden ${name}: frames, cells, headers and payload match sidecar`, () => {
    const side = JSON.parse(fs.readFileSync(path.join(dir, name + '.json'), 'utf8'));
    const gif = new Uint8Array(fs.readFileSync(path.join(dir, name + '.gif')));
    const frames = new GifDecoder(gif).decode();
    assertEq(frames.length, side.frameCount ?? side.total, 'frame count');
    assertEq(frames[0].width, F.SPEC.grid.framePx, 'frame width');
    const rs = new ReedSolomon(F.SPEC.rs.eccBytes);
    const asm = new C.RatelessAssembler();
    const decoded = [];
    for (let i = 0; i < frames.length; i++) {
      const r = C.decodeFrameExact(frames[i].imageData);
      assertEq(r.diag.hammingMax, 0, `frame ${i} exact hashes`);
      assertEq(hex(r.raw), side.frames[i].rawHex, `frame ${i} raw`);
      assertEq(Array.from(r.cells).join(','), side.frames[i].cells.join(','), `frame ${i} cells`);
      const d = C.decodeRSFrame(r.raw, rs);
      assertEq(d.blocksFailed, 0, `frame ${i} RS`);
      assertEq(hex(d.data), side.frames[i].dataHex, `frame ${i} data`);
      const h = F.decodeHeader(d.data);
      const sideHeader = side.frames[i].header;
      assertEq(
        JSON.stringify({ version: h.version, encrypted: h.encrypted, repair: h.repair, compressed: h.compressed, fileId: h.fileId, seq: h.seq, total: h.total }),
        JSON.stringify({ version: sideHeader.version, encrypted: sideHeader.encrypted, repair: sideHeader.repair ?? false, compressed: sideHeader.compressed ?? false, fileId: sideHeader.fileId, seq: sideHeader.seq, total: sideHeader.total }),
        `frame ${i} header`);
      decoded.push({ data: d.data, blocksFailed: d.blocksFailed });
      const addResult = asm.add(d.data, d.blocksFailed);
      // Source frames always add new information. A repair frame received after the
      // assembler is already complete is legitimately redundant ('dependent') — that is
      // the point of shipping extra repair frames, not a bug.
      if (!h.repair) assert(addResult.accepted, `frame ${i} accepted`);
    }
    verifyAssembled(asm, side, 'all frames');

    const repairFrames = side.repairFrames ?? 0;
    if (repairFrames > 0) {
      const sourceFrames = side.sourceFrames ?? side.total;

      // (a) source frames only.
      const asmSource = new C.RatelessAssembler();
      for (let i = 0; i < sourceFrames; i++) asmSource.add(decoded[i].data, decoded[i].blocksFailed);
      verifyAssembled(asmSource, side, 'source-only');

      // (b) drop every k-th frame (1-indexed), k = floor(total frames / repairFrames).
      const k = Math.floor(decoded.length / repairFrames);
      const asmDropped = new C.RatelessAssembler();
      let dropped = 0;
      for (let i = 0; i < decoded.length; i++) {
        if ((i + 1) % k === 0) { dropped++; continue; }
        asmDropped.add(decoded[i].data, decoded[i].blocksFailed);
      }
      assert(dropped > 0 && dropped <= repairFrames, `dropped ${dropped} frames should be in (0, ${repairFrames}]`);
      verifyAssembled(asmDropped, side, 'dropped frames');
    }
  });
}

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
