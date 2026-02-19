/**
 * rs.js — Reed-Solomon error correction over GF(256)
 * Primitive polynomial: x^8 + x^4 + x^3 + x^2 + 1 (0x11D)
 *
 * API:
 *   const rs = new ReedSolomon(eccBytes);
 *   const encoded = rs.encode(dataBytes);   // Uint8Array, length = data.length + eccBytes
 *   const decoded = rs.decode(received);    // Uint8Array (original data) or throws
 */

'use strict';

const GF_PRIM = 0x11D; // x^8 + x^4 + x^3 + x^2 + 1

// Build GF(256) log/exp tables
const GF_EXP = new Uint8Array(512);
const GF_LOG = new Uint8Array(256);

(function buildTables() {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    GF_EXP[i] = x;
    GF_LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= GF_PRIM;
  }
  for (let i = 255; i < 512; i++) GF_EXP[i] = GF_EXP[i - 255];
})();

function gfMul(a, b) {
  if (a === 0 || b === 0) return 0;
  return GF_EXP[GF_LOG[a] + GF_LOG[b]];
}

function gfDiv(a, b) {
  if (b === 0) throw new Error('GF division by zero');
  if (a === 0) return 0;
  return GF_EXP[(GF_LOG[a] - GF_LOG[b] + 255) % 255];
}

function gfPow(x, power) {
  return GF_EXP[(GF_LOG[x] * power) % 255];
}

function gfInv(x) {
  return GF_EXP[255 - GF_LOG[x]];
}

// Polynomial operations (arrays, index 0 = highest degree)
function polyScale(p, x) {
  return p.map(c => gfMul(c, x));
}

function polyAdd(p, q) {
  const result = new Uint8Array(Math.max(p.length, q.length));
  for (let i = 0; i < p.length; i++) result[i + result.length - p.length] ^= p[i];
  for (let i = 0; i < q.length; i++) result[i + result.length - q.length] ^= q[i];
  return result;
}

function polyMul(p, q) {
  const result = new Uint8Array(p.length + q.length - 1);
  for (let i = 0; i < p.length; i++)
    for (let j = 0; j < q.length; j++)
      result[i + j] ^= gfMul(p[i], q[j]);
  return result;
}

function polyEval(p, x) {
  let y = p[0];
  for (let i = 1; i < p.length; i++) y = gfMul(y, x) ^ p[i];
  return y;
}

// Generate generator polynomial for RS(n, k) with `eccLen` check symbols
function rsGeneratorPoly(eccLen) {
  let g = new Uint8Array([1]);
  for (let i = 0; i < eccLen; i++) {
    g = polyMul(g, new Uint8Array([1, gfPow(2, i)]));
  }
  return g;
}

class ReedSolomon {
  constructor(eccLen = 8) {
    this.eccLen = eccLen;
    this.gen = rsGeneratorPoly(eccLen);
  }

  /**
   * Encode data bytes, returns Uint8Array of length data.length + eccLen
   */
  encode(data) {
    const msg = new Uint8Array(data.length + this.eccLen);
    msg.set(data);

    // Polynomial long division
    for (let i = 0; i < data.length; i++) {
      const coef = msg[i];
      if (coef !== 0) {
        for (let j = 1; j < this.gen.length; j++) {
          msg[i + j] ^= gfMul(this.gen[j], coef);
        }
      }
    }

    // Restore data (overwritten by division), append ECC
    const result = new Uint8Array(data.length + this.eccLen);
    result.set(data);
    result.set(msg.slice(data.length), data.length);
    return result;
  }

  /**
   * Decode received codeword. Returns original data Uint8Array.
   * Throws if uncorrectable.
   */
  decode(received) {
    const msg = new Uint8Array(received);
    const eccLen = this.eccLen;

    // 1. Compute syndromes
    const syndromes = new Uint8Array(eccLen);
    let hasError = false;
    for (let i = 0; i < eccLen; i++) {
      syndromes[i] = polyEval(msg, gfPow(2, i));
      if (syndromes[i] !== 0) hasError = true;
    }

    if (!hasError) return msg.slice(0, msg.length - eccLen);

    // 2. Berlekamp-Massey to find error locator polynomial
    let C = new Uint8Array([1]);
    let B = new Uint8Array([1]);
    let L = 0, m = 1, b = 1;

    for (let n = 0; n < eccLen; n++) {
      let d = syndromes[n];
      for (let i = 1; i <= L; i++) {
        if (i < C.length) d ^= gfMul(C[C.length - 1 - i], syndromes[n - i]);
      }

      if (d === 0) {
        m++;
      } else if (2 * L <= n) {
        const T = new Uint8Array(C);
        const shift = new Uint8Array(m + B.length);
        shift.set(B, 0);
        // scale B by d/b and shift by m
        const scaled = polyScale(shift, gfMul(d, gfInv(b)));
        // pad C to match
        const Cpad = new Uint8Array(Math.max(C.length, scaled.length));
        Cpad.set(C, Cpad.length - C.length);
        C = polyAdd(Cpad, scaled);
        L = n + 1 - L;
        B = T;
        b = d;
        m = 1;
      } else {
        const shift = new Uint8Array(m + B.length);
        shift.set(B, 0);
        const scaled = polyScale(shift, gfMul(d, gfInv(b)));
        const Cpad = new Uint8Array(Math.max(C.length, scaled.length));
        Cpad.set(C, Cpad.length - C.length);
        C = polyAdd(Cpad, scaled);
        m++;
      }
    }

    if (L === 0) return msg.slice(0, msg.length - eccLen);

    // 3. Find roots of error locator polynomial (Chien search).
    // Must search all 255 non-zero GF(256) elements — not just msg.length of
    // them — because for n < 255 the roots can fall at alpha^i with i >= n.
    // Root at alpha^i means error locator X = alpha^i^{-1} = alpha^{255-i},
    // which corresponds to reverse-position k = (255-i) % 255 and byte-index
    // b = msg.length - 1 - k.
    const errPos = [];
    for (let i = 0; i < 255; i++) {
      if (polyEval(C, gfPow(2, i)) === 0) {
        const pos = (255 - i) % 255;   // reverse-position (0 = last byte)
        if (pos < msg.length) errPos.push(pos);
      }
    }

    if (errPos.length !== L) throw new Error(`RS: uncorrectable errors (found ${errPos.length}, expected ${L})`);

    // 4. Forney algorithm to find error magnitudes
    const E = new Uint8Array(msg.length);
    // Omega = S(x) * sigma(x) mod x^t.
    // S(x) must be in ascending-powers form: S_0 + S_1*x + ... + S_{t-1}*x^{t-1}.
    // In our "index 0 = highest degree" convention that is [S_{t-1}, ..., S_0]
    // (the reversed syndromes array).
    // "mod x^t" keeps the t lowest-degree terms, which are at the END of the
    // product array in "high degree first" convention → .slice(-t).
    const syndromesAsc = new Uint8Array(eccLen);
    for (let i = 0; i < eccLen; i++) syndromesAsc[i] = syndromes[eccLen - 1 - i];
    const Omega = polyMul(syndromesAsc, C).slice(-eccLen);

    for (const pos of errPos) {
      const Xi = gfPow(2, pos);
      const XiInv = gfInv(Xi);

      // Formal derivative of C
      let denom = 0;
      for (let i = 1; i < C.length; i += 2) {
        // Only odd-indexed terms survive formal derivative in GF(2^m)
        denom ^= gfMul(C[C.length - 1 - i], gfPow(XiInv, i - 1));
      }

      const num = polyEval(
        Omega.length > 0 ? Omega : new Uint8Array([0]),
        XiInv
      );

      // Full Forney formula: e_k = X_k * Omega(X_k^{-1}) / Lambda'(X_k^{-1})
      // The X_k factor (Xi) is required because Lambda = prod(1 - X_k*z)
      // contributes an X_k in the denominator when expanded at the root.
      E[msg.length - 1 - pos] = gfMul(Xi, gfDiv(num, denom));
    }

    // 5. Correct
    const corrected = new Uint8Array(msg.length);
    for (let i = 0; i < msg.length; i++) corrected[i] = msg[i] ^ E[i];

    // 6. Verify
    for (let i = 0; i < eccLen; i++) {
      if (polyEval(corrected, gfPow(2, i)) !== 0) {
        throw new Error('RS: correction failed verification');
      }
    }

    return corrected.slice(0, corrected.length - eccLen);
  }
}

// Export
if (typeof module !== 'undefined') module.exports = { ReedSolomon };
else window.ReedSolomon = ReedSolomon;
