'use strict';
/**
 * tile_rules.js — tile representation and the constraints from spec §3.4.
 * A tile is a Uint8Array(64) of 0/1, row-major, index = row*8 + col.
 * Hex form: 16 hex digits, MSB of the first digit = top-left pixel.
 */

const RULES = { minFill: 26, maxFill: 38, minHamming: 24, minShiftedHamming: 16 };
const SHIFTS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

function hexToTile(hex) {
  if (typeof hex !== 'string' || hex.length !== 16) throw new Error('tile hex must be 16 chars');
  const t = new Uint8Array(64);
  for (let i = 0; i < 16; i++) {
    const nib = parseInt(hex[i], 16);
    if (Number.isNaN(nib)) throw new Error('bad hex digit in tile');
    for (let b = 0; b < 4; b++) t[i * 4 + b] = (nib >> (3 - b)) & 1;
  }
  return t;
}

function tileToHex(t) {
  let s = '';
  for (let i = 0; i < 16; i++) {
    let nib = 0;
    for (let b = 0; b < 4; b++) nib = (nib << 1) | t[i * 4 + b];
    s += nib.toString(16);
  }
  return s;
}

function popcount(t) { let n = 0; for (let i = 0; i < 64; i++) n += t[i]; return n; }
function hamming(a, b) { let n = 0; for (let i = 0; i < 64; i++) n += a[i] ^ b[i]; return n; }

function shift(t, dx, dy) {
  const o = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const sx = x - dx, sy = y - dy;
    if (sx >= 0 && sx < 8 && sy >= 0 && sy < 8) o[y * 8 + x] = t[sy * 8 + sx];
  }
  return o;
}

function rot90(t) {
  const o = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) o[x * 8 + (7 - y)] = t[y * 8 + x];
  return o;
}

function mirror(t) {
  const o = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) o[y * 8 + (7 - x)] = t[y * 8 + x];
  return o;
}

function variants(t) {
  const r1 = rot90(t), r2 = rot90(r1), r3 = rot90(r2);
  return [r1, r3, mirror(t), mirror(r1), mirror(r3)];
}

function checkTile(t) {
  const f = popcount(t);
  return f >= RULES.minFill && f <= RULES.maxFill;
}

function checkPair(a, b) {
  if (hamming(a, b) < RULES.minHamming) return false;
  for (const [dx, dy] of SHIFTS) {
    if (hamming(shift(a, dx, dy), b) < RULES.minShiftedHamming) return false;
    if (hamming(shift(b, dx, dy), a) < RULES.minShiftedHamming) return false;
  }
  for (const v of variants(a)) if (hamming(v, b) === 0) return false;
  return true;
}

function checkSet(tiles) {
  const errors = [];
  tiles.forEach((t, i) => {
    if (!checkTile(t)) errors.push(`tile ${i}: fill ${popcount(t)} outside ${RULES.minFill}-${RULES.maxFill}`);
  });
  for (let i = 0; i < tiles.length; i++) {
    for (let j = i + 1; j < tiles.length; j++) {
      if (!checkPair(tiles[i], tiles[j])) {
        errors.push(`tiles ${i},${j}: pair rule violated (hamming ${hamming(tiles[i], tiles[j])})`);
      }
    }
  }
  return errors;
}

module.exports = { RULES, SHIFTS, hexToTile, tileToHex, popcount, hamming, shift, rot90, mirror, variants, checkTile, checkPair, checkSet };
