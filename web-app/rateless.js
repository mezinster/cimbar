/**
 * rateless.js — CimBar v2.1 coding layer (spec §5, §7): repair-body
 * combination over GF(256) and the RatelessAssembler that recovers the N
 * source bodies from any N independent rows by incremental elimination.
 * Loads after format.js and rs.js; before cimbar.js. IIFE; exposes
 * window.CimbarRateless / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const Fmt = isNode ? require('./format.js') : window.CimbarFormat;
const RS = isNode ? require('./rs.js').ReedSolomon : window.ReedSolomon;
const gfMul = RS.gfMul, gfInv = RS.gfInv;

/** out = Σ coef[j] · bodies[j] over GF(256). */
function combineBodies(bodies, coef) {
  const len = bodies[0].length;
  const out = new Uint8Array(len);
  for (let j = 0; j < coef.length; j++) {
    const c = coef[j];
    if (c === 0) continue;
    const b = bodies[j];
    if (c === 1) { for (let i = 0; i < len; i++) out[i] ^= b[i]; continue; }
    for (let i = 0; i < len; i++) out[i] ^= gfMul(c, b[i]);
  }
  return out;
}

/** row -= c * pivot, over coefficients from column `from` and the whole body. */
function subtractScaled(row, pivot, c, from) {
  const rc = row.coef, pc = pivot.coef, rb = row.body, pb = pivot.body;
  if (c === 1) {
    for (let k = from; k < rc.length; k++) rc[k] ^= pc[k];
    for (let i = 0; i < rb.length; i++) rb[i] ^= pb[i];
  } else {
    for (let k = from; k < rc.length; k++) if (pc[k]) rc[k] ^= gfMul(c, pc[k]);
    for (let i = 0; i < rb.length; i++) if (pb[i]) rb[i] ^= gfMul(c, pb[i]);
  }
}

function scaleRow(row, inv, from) {
  if (inv === 1) return;
  for (let k = from; k < row.coef.length; k++) if (row.coef[k]) row.coef[k] = gfMul(inv, row.coef[k]);
  for (let i = 0; i < row.body.length; i++) if (row.body[i]) row.body[i] = gfMul(inv, row.body[i]);
}

class RatelessAssembler {
  constructor() { this.reset(); }

  reset() {
    this.fileId = null; this.total = 0; this.encrypted = false; this.compressed = false;
    this.rank = 0; this.pivots = []; this.seenSource = new Set(); this.seenRepair = new Set();
    this.counts = { source: 0, repair: 0, duplicate: 0, dependent: 0 };
    this._bodies = null;
  }

  /** data: Uint8Array(dataBytesPerFrame) after RS decode. Reasons: rs, header reasons, total, flags, duplicate, dependent. */
  add(data, blocksFailed = 0) {
    if (blocksFailed > 0) return { accepted: false, reason: 'rs', header: null };
    const h = Fmt.decodeHeader(data);
    if (!h.valid) return { accepted: false, reason: h.reason, header: h };
    if (this.fileId !== null && h.fileId !== this.fileId) this.reset();
    if (this.fileId !== null && h.total !== this.total) return { accepted: false, reason: 'total', header: h };
    if (this.fileId !== null && (h.encrypted !== this.encrypted || h.compressed !== this.compressed)) return { accepted: false, reason: 'flags', header: h };
    if (this.fileId === null) {
      this.fileId = h.fileId; this.total = h.total; this.encrypted = h.encrypted; this.compressed = h.compressed;
      this.pivots = new Array(h.total).fill(null);
    }
    const seen = h.repair ? this.seenRepair : this.seenSource;
    if (seen.has(h.seq)) { this.counts.duplicate++; return { accepted: false, reason: 'duplicate', header: h }; }
    seen.add(h.seq);
    const n = this.total;
    const body = data.slice(Fmt.HEADER_LEN);
    let coef;
    if (h.repair) { coef = Fmt.codingCoefficients(h.fileId, h.seq, n); this.counts.repair++; }
    else { coef = new Uint8Array(n); coef[h.seq] = 1; this.counts.source++; }
    const row = { coef, body };
    if (this.rank >= n) { this.counts.dependent++; return { accepted: false, reason: 'dependent', header: h }; }
    // forward elimination against existing pivots
    for (let c = 0; c < n; c++) {
      const v = row.coef[c];
      if (v === 0 || this.pivots[c] === null) continue;
      subtractScaled(row, this.pivots[c], v, c);
    }
    let p = -1;
    for (let c = 0; c < n; c++) if (row.coef[c] !== 0) { p = c; break; }
    if (p < 0) { this.counts.dependent++; return { accepted: false, reason: 'dependent', header: h }; }
    scaleRow(row, gfInv(row.coef[p]), p);
    this.pivots[p] = row;
    this.rank++;
    this._bodies = null;
    return { accepted: true, reason: '', header: h };
  }

  isComplete() { return this.total > 0 && this.rank === this.total; }

  /** Back-substitute (once) and return the N bodies concatenated (still carries the u32 length prefix + padding). */
  framedData() {
    if (!this.isComplete()) throw new Error(`Incomplete: rank ${this.rank}/${this.total}`);
    if (!this._bodies) {
      const n = this.total;
      for (let c = n - 1; c >= 0; c--) {
        const pr = this.pivots[c];
        for (let k = c + 1; k < n; k++) {
          const v = pr.coef[k];
          if (v !== 0) subtractScaled(pr, this.pivots[k], v, k);
        }
      }
      this._bodies = this.pivots.map(p => p.body);
    }
    const per = Fmt.fileBytesPerFrame();
    const out = new Uint8Array(per * this.total);
    for (let i = 0; i < this.total; i++) out.set(this._bodies[i], i * per);
    return out;
  }
}

const API = { combineBodies, RatelessAssembler };
if (isNode) module.exports = API; else window.CimbarRateless = API;
})();
