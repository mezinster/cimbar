'use strict';
/**
 * gen_tiles.js — seeded search for a 16-tile set satisfying tile_rules.
 * Tiles are built from a 4x4 grid of 2x2-pixel blocks (7..9 lit blocks),
 * so the smallest feature is 2 px — survives camera blur far better than
 * single-pixel scatter while still meeting the spec's Hamming constraints.
 *
 * Usage: node tools/gen_tiles.js [startSeed]
 * Prints {"seed": n, "tiles": [16 hex strings]} for the first seed that works.
 */
const { checkTile, checkPair, tileToHex } = require('./tile_rules.js');

function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomTile(rnd) {
  const blocks = new Uint8Array(16);
  const target = 7 + Math.floor(rnd() * 3); // 7, 8 or 9 blocks -> 28, 32 or 36 px
  const idx = [];
  for (let i = 0; i < 16; i++) idx.push(i);
  for (let i = 15; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const tmp = idx[i]; idx[i] = idx[j]; idx[j] = tmp;
  }
  for (let k = 0; k < target; k++) blocks[idx[k]] = 1;
  const t = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) t[y * 8 + x] = blocks[(y >> 1) * 4 + (x >> 1)];
  return t;
}

function generate(seed, count = 16, maxTries = 200000) {
  const rnd = mulberry32(seed);
  const tiles = [];
  for (let tries = 0; tries < maxTries && tiles.length < count; tries++) {
    const c = randomTile(rnd);
    if (!checkTile(c)) continue;
    if (tiles.every(t => checkPair(t, c))) tiles.push(c);
  }
  return tiles.length === count ? tiles : null;
}

if (require.main === module) {
  const start = parseInt(process.argv[2] || '1', 10);
  for (let s = start; s < start + 1000; s++) {
    const tiles = generate(s);
    if (tiles) {
      console.log(JSON.stringify({ seed: s, tiles: tiles.map(tileToHex) }, null, 2));
      process.exit(0);
    }
  }
  console.error('no tile set found in 1000 seeds');
  process.exit(1);
}

module.exports = { generate, mulberry32, randomTile };
