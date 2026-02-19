/**
 * crypto.js — AES-256-GCM encryption/decryption using Web Crypto API
 *
 * Wire format: [4 magic bytes][16 salt][12 iv][ciphertext + 16 auth tag]
 * Magic: 0xCB 0x42 0x01 0x00  ("CB" = CimBar, 0x01 = version 1)
 */

'use strict';

const MAGIC = new Uint8Array([0xCB, 0x42, 0x01, 0x00]);
const ITERATIONS = 150000;

async function deriveKey(passphrase, salt) {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw', enc.encode(passphrase), 'PBKDF2', false, ['deriveKey']
  );
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations: ITERATIONS, hash: 'SHA-256' },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

/**
 * Encrypt arbitrary bytes with a passphrase.
 * Returns Uint8Array containing the full wire format.
 */
async function encryptBytes(data, passphrase) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv   = crypto.getRandomValues(new Uint8Array(12));
  const key  = await deriveKey(passphrase, salt);

  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, data)
  );

  const result = new Uint8Array(4 + 16 + 12 + ciphertext.length);
  result.set(MAGIC,      0);
  result.set(salt,       4);
  result.set(iv,         20);
  result.set(ciphertext, 32);
  return result;
}

/**
 * Decrypt a wire-format payload produced by encryptBytes.
 * Returns the original plaintext Uint8Array.
 * Throws on bad magic, wrong passphrase or tampered data.
 */
async function decryptBytes(data, passphrase) {
  if (data[0] !== MAGIC[0] || data[1] !== MAGIC[1]) {
    throw new Error('Invalid file: missing CimBar magic header');
  }
  if (data[2] !== 0x01) {
    throw new Error(`Unsupported format version: ${data[2]}`);
  }

  const salt       = data.slice(4,  20);
  const iv         = data.slice(20, 32);
  const ciphertext = data.slice(32);
  const key        = await deriveKey(passphrase, salt);

  let plaintext;
  try {
    plaintext = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertext);
  } catch {
    throw new Error('Decryption failed — wrong passphrase or corrupted data');
  }
  return new Uint8Array(plaintext);
}

/**
 * Score passphrase strength, returns 0-100.
 */
function passphraseStrength(pass) {
  let score = 0;
  if (pass.length >= 8)  score += 20;
  if (pass.length >= 14) score += 20;
  if (pass.length >= 20) score += 10;
  if (/[A-Z]/.test(pass))           score += 15;
  if (/[a-z]/.test(pass))           score += 10;
  if (/[0-9]/.test(pass))           score += 10;
  if (/[^A-Za-z0-9]/.test(pass))    score += 15;
  return Math.min(100, score);
}

if (typeof module !== 'undefined') {
  module.exports = { encryptBytes, decryptBytes, passphraseStrength };
} else {
  window.CimbarCrypto = { encryptBytes, decryptBytes, passphraseStrength };
}
