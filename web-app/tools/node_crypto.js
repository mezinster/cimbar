'use strict';
/**
 * node_crypto.js — Node implementation of the crypto.js wire format so goldens
 * can be generated and verified without Web Crypto (Node 14 has none).
 * Wire: [CB 42 01 00][16 salt][12 iv][ciphertext][16 tag], PBKDF2-SHA256 150000 iters.
 */
const crypto = require('crypto');
const MAGIC = Buffer.from([0xCB, 0x42, 0x01, 0x00]);
const ITERATIONS = 150000;

function encryptBytesNode(data, passphrase, salt, iv) {
  if (salt.length !== 16 || iv.length !== 12) throw new Error('salt must be 16 bytes, iv 12 bytes');
  const key = crypto.pbkdf2Sync(passphrase, Buffer.from(salt), ITERATIONS, 32, 'sha256');
  const cipher = crypto.createCipheriv('aes-256-gcm', key, Buffer.from(iv));
  const ct = Buffer.concat([cipher.update(Buffer.from(data)), cipher.final()]);
  const tag = cipher.getAuthTag();
  return new Uint8Array(Buffer.concat([MAGIC, Buffer.from(salt), Buffer.from(iv), ct, tag]));
}

function decryptBytesNode(wire, passphrase) {
  const w = Buffer.from(wire);
  if (w[0] !== 0xCB || w[1] !== 0x42) throw new Error('Invalid file: missing CimBar magic header');
  if (w[2] !== 0x01) throw new Error(`Unsupported format version: ${w[2]}`);
  const salt = w.subarray(4, 20), iv = w.subarray(20, 32);
  const ct = w.subarray(32, w.length - 16), tag = w.subarray(w.length - 16);
  const key = crypto.pbkdf2Sync(passphrase, salt, ITERATIONS, 32, 'sha256');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return new Uint8Array(Buffer.concat([decipher.update(ct), decipher.final()]));
}

module.exports = { encryptBytesNode, decryptBytesNode, ITERATIONS };
