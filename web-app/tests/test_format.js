'use strict';
const fs = require('fs');
const path = require('path');
const R = require('../tools/tile_rules.js');
const gen = require('../tools/gen_format_data.js');
const SPEC = require('../../spec/cimbar-v2.json');

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); console.log(`  PASS  ${name}`); passed++; }
  catch (e) { console.log(`  FAIL  ${name}: ${e.message}`); failed++; }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg || 'assertEq'}: expected ${b}, got ${a}`); }
function hex(bytes) { let s = ''; for (const b of bytes) s += b.toString(16).padStart(2, '0'); return s; }

console.log('\ntest_format.js');

test('grid constants are self-consistent', () => {
  const g = SPEC.grid;
  assertEq(g.pitchPx, g.cellPx + g.gapPx);
  assertEq(g.gridPx, g.gridCells * g.pitchPx);
  assertEq(g.framePx, g.gridPx + 2 * g.quietPx);
  assertEq(SPEC.gif.framePx, g.framePx);
});

test('finder constants are self-consistent', () => {
  const f = SPEC.finder, g = SPEC.grid;
  assertEq(f.outerPx, f.cells * g.pitchPx);
  assertEq(f.ringInsetPx, g.pitchPx);
  assertEq(f.coreInsetPx, 2 * g.pitchPx);
  assertEq(f.corePx, 3 * g.pitchPx);
  assertEq(f.dotPx, g.pitchPx);
  assertEq(f.dotInsetPx, 3 * g.pitchPx);
  assertEq(f.cornerCells, f.cells + 1);
  const n = g.gridCells;
  assertEq(f.centers.tl.join(','), '3.5,3.5');
  assertEq(f.centers.tr.join(','), `${n - 3.5},3.5`);
  assertEq(f.centers.bl.join(','), `3.5,${n - 3.5}`);
  assertEq(f.centers.br.join(','), `${n - 3.5},${n - 3.5}`);
  assertEq(f.dotOn.join(','), 'tr,bl,br');
});

test('palette has 4 bright colors', () => {
  assertEq(SPEC.palette.length, 4);
  for (const [r, g, b] of SPEC.palette) {
    const luma = 0.299 * r + 0.587 * g + 0.114 * b;
    assert(luma > 100, `luma ${luma} too dark`);
  }
});

test('tile set satisfies tile rules', () => {
  assertEq(SPEC.tiles.length, 16);
  const tiles = SPEC.tiles.map(R.hexToTile);
  const errs = R.checkSet(tiles);
  assertEq(errs.length, 0, errs.join('; '));
});

test('capacity numbers match derivation', () => {
  const n = SPEC.grid.gridCells, c = SPEC.finder.cornerCells;
  const usable = n * n - 4 * c * c;
  assertEq(SPEC.capacity.usableCells, usable);
  const bits = SPEC.bits.symbolBits + SPEC.bits.colorBits;
  assertEq(SPEC.capacity.rawBytesPerFrame, Math.floor(usable * bits / 8));
  let raw = SPEC.capacity.rawBytesPerFrame, data = 0;
  while (raw > SPEC.rs.eccBytes) { const bt = Math.min(SPEC.rs.blockTotal, raw); data += bt - SPEC.rs.eccBytes; raw -= bt; }
  assertEq(SPEC.capacity.dataBytesPerFrame, data);
  assertEq(SPEC.capacity.fileBytesPerFrame, data - SPEC.header.lengthBytes);
});

test('format-data.js is up to date with the spec', () => {
  const expected = gen.render(fs.readFileSync(gen.specPath, 'utf8'));
  const actual = fs.readFileSync(gen.outPath, 'utf8');
  assertEq(actual, expected, 'run: node tools/gen_format_data.js');
});

const F = require('../format.js');

test('format.js exposes the spec and derived capacities', () => {
  assertEq(F.SPEC.version, 2);
  assertEq(F.usableCells(), 3840);
  assertEq(F.rawBytesPerFrame(), 2880);
  assertEq(F.rsBlockSizes().join(','), '255,255,255,255,255,255,255,255,255,255,255,75');
  assertEq(F.dataBytesPerFrame(), 2112);
  assertEq(F.fileBytesPerFrame(), 2104);
});

test('reserved cells are exactly the four 8x8 corners', () => {
  assert(F.isReservedCell(0, 0) && F.isReservedCell(7, 7) && F.isReservedCell(56, 0) && F.isReservedCell(63, 63) && F.isReservedCell(0, 63));
  assert(!F.isReservedCell(8, 0) && !F.isReservedCell(7, 8) && !F.isReservedCell(55, 63) && !F.isReservedCell(32, 32));
  const pos = F.usableCellPositions();
  assertEq(pos.length, 3840);
  assertEq(pos[0].join(','), '8,0', 'first usable');
  assertEq(pos[pos.length - 1].join(','), '55,63', 'last usable');
});

test('cellOrigin uses quiet zone and pitch', () => {
  assertEq(F.cellOrigin(0, 0).join(','), '16,16');
  assertEq(F.cellOrigin(8, 0).join(','), '88,16');
  assertEq(F.cellOrigin(63, 63).join(','), '583,583');
});

test('tileBits matches spec hex', () => {
  const t = F.tileBits(3);
  assertEq(F.SPEC.tiles[3], R.tileToHex(t));
  let n = 0; for (let i = 0; i < 64; i++) n += t[i];
  assert(n >= 26 && n <= 38, 'fill in range');
});

test('header encode/decode round trip and validation', () => {
  const h = F.encodeHeader({ encrypted: true, fileId: 0xBEEF, seq: 3, total: 12 });
  assertEq(h.length, 8);
  assertEq(h[0], 2); assertEq(h[1], 1);
  assertEq(h[2], 0xBE); assertEq(h[3], 0xEF);
  assertEq(h[4], 0); assertEq(h[5], 3);
  assertEq(h[6], 0); assertEq(h[7], 12);
  const d = F.decodeHeader(h);
  assert(d.valid, 'valid');
  assertEq(d.fileId, 0xBEEF); assertEq(d.seq, 3); assertEq(d.total, 12); assertEq(d.encrypted, true);
  assertEq(F.decodeHeader(new Uint8Array([1, 0, 0, 0, 0, 0, 0, 1])).reason, 'version');
  assertEq(F.decodeHeader(new Uint8Array([2, 8, 0, 0, 0, 0, 0, 1])).reason, 'flags');
  assertEq(F.decodeHeader(new Uint8Array([2, 0, 0, 0, 0, 0, 0, 0])).reason, 'total');
  assertEq(F.decodeHeader(new Uint8Array([2, 0, 0, 0, 0, 5, 0, 5])).reason, 'seq');
  assertEq(F.decodeHeader(new Uint8Array([2, 0, 0])).reason, 'short');
});

test('packCells/unpackCells round trip 2880 bytes MSB-first', () => {
  const raw = new Uint8Array(2880);
  for (let i = 0; i < raw.length; i++) raw[i] = (i * 37 + 11) & 0xFF;
  const cells = F.packCells(raw);
  assertEq(cells.length, 3840);
  // first cell = top 6 bits of raw[0]
  assertEq(cells[0], raw[0] >> 2);
  // second cell = low 2 bits of raw[0] and top 4 bits of raw[1]
  assertEq(cells[1], ((raw[0] & 3) << 4) | (raw[1] >> 4));
  for (const v of cells) assert(v >= 0 && v < 64, '6-bit');
  const back = F.unpackCells(cells);
  assertEq(back.length, 2880);
  for (let i = 0; i < raw.length; i++) if (back[i] !== raw[i]) throw new Error(`byte ${i} differs`);
});

test('cellValue/cellSymbol/cellColor', () => {
  assertEq(F.cellValue(15, 3), 63);
  assertEq(F.cellValue(9, 2), (9 << 2) | 2);
  assertEq(F.cellSymbol(F.cellValue(9, 2)), 9);
  assertEq(F.cellColor(F.cellValue(9, 2)), 2);
});

test('HEADER_LEN/FORMAT_VERSION match spec', () => {
  assertEq(F.HEADER_LEN, F.SPEC.header.lengthBytes);
  assertEq(F.FORMAT_VERSION, F.SPEC.header.version);
});

test('header flags: repair and compressed round trip; reserved bits rejected', () => {
  const b = F.encodeHeader({ encrypted: true, repair: true, compressed: true, fileId: 0x1234, seq: 65535, total: 3 });
  assertEq(b[1], 7, 'flags byte');
  const h = F.decodeHeader(b);
  assert(h.valid, h.reason);
  assert(h.encrypted && h.repair && h.compressed, 'flags decoded');
  assertEq(h.seq, 65535, 'repair id may exceed total');
  const src = F.decodeHeader(F.encodeHeader({ fileId: 1, seq: 3, total: 3 }));
  assertEq(src.reason, 'seq', 'source seq must be < total');
  const reserved = F.encodeHeader({ fileId: 1, seq: 0, total: 1 }); reserved[1] = 8;
  assertEq(F.decodeHeader(reserved).reason, 'flags', 'bit 3 rejected');
  assertEq(F.FLAG_REPAIR, 2); assertEq(F.FLAG_COMPRESSED, 4);
});

test('codingCoefficients matches the spec vectors and is deterministic', () => {
  for (const v of F.SPEC.coding.vectors) {
    const c = F.codingCoefficients(v.fileId, v.r, 12);
    assertEq(Array.from(c).join(','), v.coef.join(','), `vector fileId=${v.fileId} r=${v.r}`);
  }
  const a = F.codingCoefficients(0x1234, 0, 400), b = F.codingCoefficients(0x1234, 0, 400);
  assertEq(hex(a), hex(b), 'deterministic');
  assertEq(a.length, 400);
  assertEq(F.SPEC.coding.maxFrames, 4096); assertEq(F.SPEC.coding.gifRepairRatio, 0.25);
  assertEq(F.SPEC.compression.format, 'zlib'); assertEq(F.SPEC.compression.minSaving, 0.05);
});

test('ReedSolomon exports GF(256) helpers', () => {
  const { ReedSolomon } = require('../rs.js');
  assertEq(ReedSolomon.gfMul(2, 128), 0x1D, 'x * x^7 wraps to 0x11D - 0x100');
  for (let x = 1; x < 256; x++) assertEq(ReedSolomon.gfMul(x, ReedSolomon.gfInv(x)), 1, `inv ${x}`);
});

console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
