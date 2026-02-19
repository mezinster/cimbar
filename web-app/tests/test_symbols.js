'use strict';
/**
 * test_symbols.js — Verify drawSymbol/detectSymbol round-trip for all
 * 128 (colorIdx 0..7, symIdx 0..15) combinations.
 *
 * Run: node tests/test_symbols.js
 */

const { MockCanvas } = require('./mock_canvas.js');
const {
  CELL_SIZE, COLORS,
  drawSymbol, detectSymbol, nearestColorIdx,
} = require('../cimbar.js');

const cs = CELL_SIZE; // 8
let pass = 0, fail = 0;
const failures = [];

for (let colorIdx = 0; colorIdx < 8; colorIdx++) {
  for (let symIdx = 0; symIdx < 16; symIdx++) {
    const canvas = new MockCanvas(cs, cs);
    const ctx    = canvas.getContext('2d');

    drawSymbol(ctx, symIdx, COLORS[colorIdx], 0, 0, cs);

    const imageData = canvas.getImageData(0, 0, cs, cs);

    // Color detection: sample center pixel (same logic as decodeFramePixels)
    const cx = Math.floor(cs / 2);
    const cy = Math.floor(cs / 2);
    const pi = (cy * cs + cx) * 4;
    const detectedColor = nearestColorIdx(
      imageData.data[pi],
      imageData.data[pi + 1],
      imageData.data[pi + 2]
    );

    // Symbol detection (W = canvas width = cs for a single-cell canvas)
    const detectedSym = detectSymbol(imageData, 0, 0, cs, cs);

    if (detectedColor === colorIdx && detectedSym === symIdx) {
      pass++;
    } else {
      fail++;
      failures.push({ colorIdx, symIdx, detectedColor, detectedSym });
    }
  }
}

if (failures.length > 0) {
  console.error(`\nFailed cases (${fail} / 128):`);
  console.error('  colorIdx  symIdx  detectedColor  detectedSym');
  for (const f of failures) {
    const colorOk = f.detectedColor === f.colorIdx ? '  OK  ' : `GOT ${f.detectedColor}`;
    const symOk   = f.detectedSym   === f.symIdx   ? '  OK  ' : `GOT ${f.detectedSym}`;
    console.error(
      `  ${String(f.colorIdx).padStart(8)}  ${String(f.symIdx).padStart(6)}` +
      `  ${colorOk.padStart(13)}  ${symOk}`
    );
  }
}

console.log(`Symbol round-trip: ${pass} pass, ${fail} fail out of 128`);
process.exit(fail === 0 ? 0 : 1);
