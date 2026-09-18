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

/**
 * row -= c * pivot, over coefficients from column `from` and the whole body.
 * `row` is always a materialised (dense) row. `pivot.coef === null` means
 * the pivot is the unmaterialised unit vector e_from (a systematic source
 * pivot that has never needed arithmetic): row -= c*e_from only zeroes
 * row.coef[from] (e_from is 1 there and 0 everywhere else), no dense pivot
 * array is read or allocated.
 */
function subtractScaled(row, pivot, c, from) {
  const rb = row.body, pb = pivot.body;
  if (pivot.coef === null) {
    row.coef[from] = 0;
    if (c === 1) { for (let i = 0; i < rb.length; i++) rb[i] ^= pb[i]; }
    else { for (let i = 0; i < rb.length; i++) if (pb[i]) rb[i] ^= gfMul(c, pb[i]); }
    return;
  }
  const rc = row.coef, pc = pivot.coef;
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

/**
 * Recovers the N source bodies from any N independent rows (source and/or
 * repair frames) by incremental Gaussian elimination over GF(256).
 *
 * Memory: an uncoded systematic source frame whose column is still free is
 * stored as `{ coef: null, body }` — the implicit unit vector e_seq — with
 * no O(n) coefficient array allocated. Only a row that needs real
 * arithmetic (a repair frame, or a source frame whose column a repair
 * pivot already occupies) is materialised to a dense `Uint8Array(n)`. This
 * keeps an all-source v2 file (`total` up to 65535) at O(n) memory instead
 * of O(n²): `total > SPEC.coding.maxFrames` additionally rejects repair
 * frames outright (reason `uncoded`) so a crafted large `total` can never
 * force dense elimination at all.
 *
 * `counts` (all four count only ACCEPTED-vs-rejected outcomes, mutually
 * exclusive per frame):
 *  - `source` / `repair`: accepted rows of that kind (pivot stored, rank
 *    increased) — NOT incremented for a row that is rejected as duplicate
 *    or dependent, or for a repair row rejected as `uncoded`.
 *  - `duplicate`: a source seq or repair id already seen for this file.
 *  - `dependent`: a valid, non-duplicate row whose coefficients reduce to
 *    all-zero against the current pivots (no new information).
 */
class RatelessAssembler {
  constructor() { this.reset(); }

  reset() {
    this.fileId = null; this.total = 0; this.encrypted = false; this.compressed = false;
    this.rank = 0; this.pivots = []; this.seenSource = new Set(); this.seenRepair = new Set();
    this.counts = { source: 0, repair: 0, duplicate: 0, dependent: 0 };
    this._bodies = null;
  }

  /** Count of stored pivots that hold a materialised (dense) coefficient array — for tests/diagnostics only. */
  denseRows() { let n = 0; for (const p of this.pivots) if (p !== null && p.coef !== null) n++; return n; }

  /** data: Uint8Array(dataBytesPerFrame) after RS decode. Reasons: rs, header reasons, total, flags, uncoded, duplicate, dependent. */
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
    const n = this.total;
    // Decoder-side guard: an uncoded (all-source) file can claim any total
    // up to 65535 with no coding cost; a repair frame on such a file would
    // force O(n) dense arrays per row (O(n²) total) for a file the encoder
    // never actually protects with repair frames beyond maxFrames.
    if (h.repair && n > Fmt.SPEC.coding.maxFrames) return { accepted: false, reason: 'uncoded', header: h };
    const seen = h.repair ? this.seenRepair : this.seenSource;
    if (seen.has(h.seq)) { this.counts.duplicate++; return { accepted: false, reason: 'duplicate', header: h }; }
    seen.add(h.seq);
    const body = data.slice(Fmt.HEADER_LEN);

    if (!h.repair && this.pivots[h.seq] === null) {
      // Fast path: source frame, free column — store the unit vector e_seq
      // without ever allocating a coefficient array.
      this.pivots[h.seq] = { coef: null, body };
      this.rank++;
      this.counts.source++;
      this._bodies = null;
      return { accepted: true, reason: '', header: h };
    }

    if (this.rank >= n) { this.counts.dependent++; return { accepted: false, reason: 'dependent', header: h }; }
    let coef;
    if (h.repair) coef = Fmt.codingCoefficients(h.fileId, h.seq, n);
    else { coef = new Uint8Array(n); coef[h.seq] = 1; }
    const row = { coef, body };
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
    if (h.repair) this.counts.repair++; else this.counts.source++;
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
        if (pr.coef === null) continue; // already the unit vector e_c — nothing to reduce
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
