/**
 * white-point.js — white reference from the four finder cores (spec §6.3).
 * Port of app/lib/core/decode/white_point.dart. Loads after format.js.
 * IIFE; exposes window.CimbarWhitePoint / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;

const CORNERS = [[0, 0], [56, 0], [0, 56], [56, 56]];
const OFFSETS = [[0.5, 0.5], [0.25, 0.5], [0.75, 0.5], [0.5, 0.25], [0.5, 0.75]];
const MIN_CHANNEL = 30;

function p90(v) {
  v.sort((a, b) => a - b);
  return v[Math.round((v.length - 1) * 0.9)];
}

class WhitePoint {
  /**
   * Per-channel 90th percentile over the eight core cells around each
   * finder's core, five samples per cell through the grid model, excluding
   * the center dot cell. Null when any channel is below minChannel (30).
   */
  static fromFinders(image, grid) {
    const r = [], g = [], b = [];
    const tmp = new Float32Array(3);
    for (const [ox, oy] of CORNERS) {
      for (let cy = 2; cy <= 4; cy++) {
        for (let cx = 2; cx <= 4; cx++) {
          if (cx === 3 && cy === 3) continue; // dot cell on tr/bl/br
          for (const [fx, fy] of OFFSETS) {
            const [sx, sy] = grid.toSource(ox + cx + fx, oy + cy + fy);
            image.bilinear(sx, sy, tmp, 0);
            r.push(tmp[0]);
            g.push(tmp[1]);
            b.push(tmp[2]);
          }
        }
      }
    }
    const wp = [p90(r), p90(g), p90(b)];
    if (wp.some((v) => v < MIN_CHANNEL)) return null;
    return wp;
  }
}

WhitePoint.minChannel = MIN_CHANNEL;

const API = { WhitePoint };
if (isNode) module.exports = API; else window.CimbarWhitePoint = API;
})();
