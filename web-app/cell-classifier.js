/**
 * cell-classifier.js — symbol by average hash + Hamming distance to the 16
 * tiles; color by brightness-normalized chroma over the winning tile's lit
 * pixels (spec §6.6-6.7). Port of app/lib/core/decode/cell_classifier.dart.
 * Loads after format.js. IIFE; exposes window.CimbarCellClassifier /
 * module.exports.
 *
 * Note: colorMargin is in normalized-chroma units (palette entries are
 * >=1.41 apart), not RGB units.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const Fmt = isNode ? require('./format.js') : window.CimbarFormat;

function chroma(r, g, b) {
  const m = Math.max(1.0, r, g, b);
  return [(r - g) / m, (g - b) / m, (b - r) / m];
}

class CellClassifier {
  constructor() {
    this._paletteChroma = Fmt.SPEC.palette.map((c) => chroma(c[0], c[1], c[2]));
  }

  /** Symbol-only classification of a 64-entry luma patch: [symbol, hamming]. */
  bestSymbol(luma) {
    let mean = 0.0;
    for (let i = 0; i < 64; i++) mean += luma[i];
    mean /= 64;
    let bestSym = 0, bestDist = 65;
    for (let s = 0; s < 16; s++) {
      const t = Fmt.tileBits(s);
      let d = 0;
      for (let i = 0; i < 64; i++) {
        d += ((luma[i] > mean) ? 1 : 0) ^ t[i];
      }
      if (d < bestDist) {
        bestDist = d;
        bestSym = s;
      }
    }
    return [bestSym, bestDist];
  }

  classify(p, whitePoint) {
    const [bestSym, bestDist] = this.bestSymbol(p.luma);
    const t = Fmt.tileBits(bestSym);
    let r = 0.0, g = 0.0, b = 0.0, n = 0;
    for (let i = 0; i < 64; i++) {
      if (t[i] === 1) {
        r += p.rgb[i * 3];
        g += p.rgb[i * 3 + 1];
        b += p.rgb[i * 3 + 2];
        n++;
      }
    }
    if (n > 0) {
      r /= n;
      g /= n;
      b /= n;
    }
    if (whitePoint != null) {
      r = r * 255 / Math.max(1.0, whitePoint[0]);
      g = g * 255 / Math.max(1.0, whitePoint[1]);
      b = b * 255 / Math.max(1.0, whitePoint[2]);
    }
    const ch = chroma(r, g, b);
    let bestC = 0;
    let bestD = Infinity, secondD = Infinity;
    for (let c = 0; c < this._paletteChroma.length; c++) {
      const pc = this._paletteChroma[c];
      const dd = (ch[0] - pc[0]) * (ch[0] - pc[0]) + (ch[1] - pc[1]) * (ch[1] - pc[1]) + (ch[2] - pc[2]) * (ch[2] - pc[2]);
      if (dd < bestD) {
        secondD = bestD;
        bestD = dd;
        bestC = c;
      } else if (dd < secondD) {
        secondD = dd;
      }
    }
    return { symbol: bestSym, hamming: bestDist, color: bestC, colorMargin: Math.sqrt(secondD) - Math.sqrt(bestD) };
  }
}

const API = { CellClassifier };
if (isNode) module.exports = API; else window.CimbarCellClassifier = API;
})();
