#!/usr/bin/env node
/**
 * e2e_live_scan.js — local end-to-end check of live scan (spec §11.2). Not in CI.
 *
 * Renders a golden GIF's frames (source + repair) into a looping 1280x720
 * .y4m, starts Chromium with that file as a fake camera, serves web-app/,
 * presses "Scan with camera" and asserts the download equals the golden's
 * payload. Proves the plumbing (getUserMedia -> frame callback -> worker ->
 * addFrame -> completion), not camera optics: the frames are pixel-perfect.
 *
 * Usage, from web-app/ (Playwright + Chromium resolvable via NODE_PATH):
 *   NODE_PATH=~/banana_split/node_modules node tools/e2e_live_scan.js [golden]
 * golden defaults to lorem_coded; lorem_coded_enc exercises the passphrase.
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

global.ImageData = global.ImageData || class ImageData {
  constructor(w, h) { this.width = w; this.height = h; this.data = new Uint8ClampedArray(w * h * 4); }
};
const { GifDecoder } = require('../gif-decoder.js');

const root = path.join(__dirname, '..');
const goldens = path.join(root, '..', 'test-data', 'goldens');
const name = process.argv[2] || 'lorem_coded';
const W = 1280, H = 720, FPS = 30, HOLD = 6;           // each barcode frame shown for 200 ms

function clamp(v) { return v < 0 ? 0 : v > 255 ? 255 : Math.round(v); }

/** One RGBA barcode frame centred on black, as planar I420 (BT.601 full range, C420jpeg). */
function toI420(rgba, fw, fh) {
  const Y = Buffer.alloc(W * H), U = Buffer.alloc((W / 2) * (H / 2)), V = Buffer.alloc((W / 2) * (H / 2));
  const ox = (W - fw) >> 1, oy = (H - fh) >> 1;
  const px = (x, y) => {
    const fx = x - ox, fy = y - oy;
    if (fx < 0 || fy < 0 || fx >= fw || fy >= fh) return [0, 0, 0];
    const i = (fy * fw + fx) * 4;
    return [rgba[i], rgba[i + 1], rgba[i + 2]];
  };
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const [r, g, b] = px(x, y);
      Y[y * W + x] = clamp(0.299 * r + 0.587 * g + 0.114 * b);
    }
  }
  for (let y = 0; y < H; y += 2) {
    for (let x = 0; x < W; x += 2) {
      let r = 0, g = 0, b = 0;
      for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { const p = px(x + dx, y + dy); r += p[0]; g += p[1]; b += p[2]; }
      r /= 4; g /= 4; b /= 4;
      const i = (y / 2) * (W / 2) + x / 2;
      U[i] = clamp(128 - 0.168736 * r - 0.331264 * g + 0.5 * b);
      V[i] = clamp(128 + 0.5 * r - 0.418688 * g - 0.081312 * b);
    }
  }
  return Buffer.concat([Y, U, V]);
}

function writeY4m(file, frames) {
  const fd = fs.openSync(file, 'w');
  fs.writeSync(fd, `YUV4MPEG2 W${W} H${H} F${FPS}:1 Ip A1:1 C420jpeg\n`);
  for (const f of frames) {
    const yuv = toI420(f.imageData.data, f.width, f.height);
    for (let k = 0; k < HOLD; k++) { fs.writeSync(fd, 'FRAME\n'); fs.writeSync(fd, yuv); }
  }
  fs.closeSync(fd);
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.png': 'image/png',
                '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' };

function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
      const file = path.join(root, rel);
      if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

(async () => {
  let playwright;
  try { playwright = require('playwright'); } catch (e) {
    console.error('Playwright not found. Run with NODE_PATH=<a node_modules containing playwright> (Chromium installed).');
    process.exit(2);
  }
  const golden = JSON.parse(fs.readFileSync(path.join(goldens, `${name}.json`), 'utf8'));
  const frames = new GifDecoder(new Uint8Array(fs.readFileSync(path.join(goldens, `${name}.gif`)))).decode();
  const y4m = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'cimbar-e2e-')), `${name}.y4m`);
  writeY4m(y4m, frames);
  console.log(`${name}: ${frames.length} frames -> ${y4m}`);

  const server = await serve();
  const url = `http://127.0.0.1:${server.address().port}/index.html?debug=1`;
  const browser = await playwright.chromium.launch({
    args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${y4m}`],
  });
  let ok = false;
  try {
    const context = await browser.newContext({ acceptDownloads: true, permissions: ['camera'] });
    const page = await context.newPage();
    page.on('pageerror', (e) => console.log('[pageerror]', e.message));
    await page.goto(url);
    await page.click('button[onclick*="\'decode\'"]');
    if (golden.passphrase) await page.fill('#passDec', golden.passphrase);
    const download = page.waitForEvent('download', { timeout: 120000 });
    await page.click('#scanBtn');
    const d = await download;
    const got = fs.readFileSync(await d.path());
    const want = Buffer.from(golden.fileBytesBase64, 'base64');
    ok = got.equals(want) && d.suggestedFilename() === golden.fileName;
    console.log(`download ${d.suggestedFilename()} ${got.length} bytes: ${ok ? 'MATCHES' : 'DIFFERS FROM'} the golden`);
    if (!ok) console.log(await page.textContent('#logDec'));
  } catch (e) {
    console.log(`FAILED: ${e.message}`);
  } finally {
    await browser.close();
    server.close();
  }
  process.exit(ok ? 0 : 1);
})();
