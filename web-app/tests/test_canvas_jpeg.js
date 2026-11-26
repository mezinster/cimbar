// canvas-jpeg.js: BoundedCache and scaledSize (ported from NFC Archiver) and
// CanvasJpegSession against fake canvases injected through its _impl seam.
'use strict';
const path = require('path');

const M = require(path.join(__dirname, '..', 'canvas-jpeg.js'));
const ID = require(path.join(__dirname, '..', 'image-decode.js'));
const { BoundedCache, scaledSize, CanvasJpegSession, SideTooLargeError, MAX_CANVAS_PIXELS, MAX_LIVE_CANVASES } = M;

let passed = 0, failed = 0;
// Serial: the tests share the module's _impl seam.
let chain = Promise.resolve();
function test(name, fn) {
  chain = chain.then(async () => {
    try { await fn(); passed++; console.log(`  PASS  ${name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${name}: ${e.message}`); }
  });
}
function assert(c, msg) { if (!c) throw new Error(msg); }
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`);
}
async function rejects(promise, Cls, msg) {
  try { await promise; } catch (e) {
    assert(e instanceof Cls, `${msg}: rejected with ${e && e.name} (${e && e.message}), want ${Cls.name}`);
    return e;
  }
  throw new Error(`${msg}: resolved, want a ${Cls.name}`);
}

// A fake canvas world: counts live canvases (width/height > 0) and logs ctx calls.
function world(opts = {}) {
  const w = { live: 0, maxLive: 0, made: [], log: [], jpegCalls: 0 };
  M._impl.makeCanvas = (cw, ch) => {
    const canvas = {
      _w: cw, _h: ch,
      get width() { return this._w; },
      set width(v) { if (this._w > 0 && v === 0) w.live--; this._w = v; },
      get height() { return this._h; },
      set height(v) { this._h = v; },
      getContext() {
        if (opts.nullContext) return null;
        return {
          set fillStyle(v) { w.log.push(['fillStyle', v]); },
          fillRect() { w.log.push(['fillRect']); },
          drawImage() { w.log.push(['drawImage']); },
        };
      },
    };
    w.live++; w.maxLive = Math.max(w.maxLive, w.live);
    w.made.push(canvas);
    return canvas;
  };
  M._impl.toJpeg = async (canvas, q) => {
    w.jpegCalls++;
    w.lastQuality = q;
    const bytes = opts.jpeg || new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
    return { arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) };
  };
  return w;
}
function fakeBitmap(width, height) {
  return { width, height, closed: false, close() { this.closed = true; } };
}
async function open(width, height) {
  M._impl.decodeImage = async () => fakeBitmap(width, height);
  return CanvasJpegSession.open({});
}

console.log('\ntest_canvas_jpeg.js');

test('BoundedCache keeps at most the limit alive and releases what it drops', () => {
  eq(MAX_LIVE_CANVASES, 2, 'limit');
  const released = [];
  const c = new BoundedCache(MAX_LIVE_CANVASES, (v) => released.push(v));
  c.set(4032, 'a'); c.set(3840, 'b'); c.set(2560, 'c');
  eq(c.size, 2, 'size');
  eq(released, ['a'], 'released after overflow');
  eq(c.get(3840), 'b', 'get');
  c.reserve();
  eq(released, ['a', 'c'], 'reserve drops the least recent');
  eq(c.size, 1, 'size after reserve');
  c.set(1920, 'd'); c.set(1600, 'e');
  eq(released, ['a', 'c', 'b'], 'released');
  c.clear();
  eq(released.sort(), ['a', 'b', 'c', 'd', 'e'], 'clear releases all');
  eq(c.size, 0, 'empty');
});

test('a 48 MP original exceeds the canvas pixel cap; 12 MP does not', () => {
  const big = scaledSize(8064, 6048, 8064);
  assert(big.w * big.h > MAX_CANVAS_PIXELS, '48 MP over cap');
  const twelve = scaledSize(4032, 3024, 4032);
  assert(twelve.w * twelve.h <= MAX_CANVAS_PIXELS, '12 MP under cap');
  eq(scaledSize(8064, 6048, 3840), { w: 3840, h: 2880 }, 'scaled');
  eq(scaledSize(800, 600, 3840), { w: 800, h: 600 }, 'never up');
});

test('never more than 2 live canvases across a descending walk of 12 sides', async () => {
  const w = world();
  const s = await open(4000, 3000);
  const sides = [4000, 3840, 2560, 1920, 1600, 1440, 1280, 1024, 800, 640, 480, 320];
  for (const side of sides) await s.encode(side, 80);
  assert(w.maxLive <= 2, `max live ${w.maxLive}`);
  eq(w.jpegCalls, 12, 'encodes');
  s.close();
  eq(w.live, 0, 'all released on close');
});

test('a side above 16 MP throws SideTooLargeError without allocating', async () => {
  const w = world();
  const s = await open(8064, 6048);
  await rejects(s.encode(8064, 80), SideTooLargeError, 'too large');
  eq(w.made.length, 0, 'no canvas made');
});

test('a null 2D context is SideTooLargeError and the canvas is released', async () => {
  const w = world({ nullContext: true });
  const s = await open(800, 600);
  await rejects(s.encode(800, 80), SideTooLargeError, 'null ctx');
  eq(w.live, 0, 'released');
});

test('encode output passes through stripJpegMetadata', async () => {
  // SOI, APP1 (EXIF), EOI: the APP1 segment must be gone.
  const withExif = new Uint8Array([0xff, 0xd8, 0xff, 0xe1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, 0xff, 0xd9]);
  world({ jpeg: withExif });
  const s = await open(100, 100);
  const out = await s.encode(100, 80);
  assert(out instanceof Uint8Array, 'Uint8Array');
  assert(!Array.from(out).includes(0xe1), 'APP1 stripped');
  eq([out[0], out[1], out[out.length - 2], out[out.length - 1]], [0xff, 0xd8, 0xff, 0xd9], 'still a JPEG');
});

test('white is filled before the bitmap is drawn; quality is clamped to 0..1', async () => {
  const w = world();
  const s = await open(100, 100);
  await s.encode(100, 250);
  eq(w.log.map((l) => l[0]), ['fillStyle', 'fillRect', 'drawImage'], 'order');
  eq(w.log[0][1], '#ffffff', 'white');
  eq(w.lastQuality, 1, 'clamped');
});

test('open maps a decode failure to PhotoDecodeError and passes typed errors through', async () => {
  world();
  M._impl.decodeImage = async () => { throw new Error('boom'); };
  await rejects(CanvasJpegSession.open({}), ID.PhotoDecodeError, 'generic');
  const tooBig = new ID.ImageTooLargeError();
  M._impl.decodeImage = async () => { throw tooBig; };
  const e = await rejects(CanvasJpegSession.open({}), ID.ImageTooLargeError, 'typed');
  assert(e === tooBig, 'same instance');
  const zero = fakeBitmap(0, 10);
  M._impl.decodeImage = async () => zero;
  await rejects(CanvasJpegSession.open({}), ID.PhotoDecodeError, 'zero size');
  assert(zero.closed, 'zero bitmap closed');
});

test('close closes the bitmap and a later encode fails', async () => {
  world();
  const bmp = fakeBitmap(100, 100);
  M._impl.decodeImage = async () => bmp;
  const s = await CanvasJpegSession.open({});
  s.close();
  assert(bmp.closed, 'bitmap closed');
  let threw = false;
  try { await s.encode(100, 80); } catch { threw = true; }
  assert(threw, 'encode after close throws');
});

chain.then(() => {
  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed) process.exit(1);
});
