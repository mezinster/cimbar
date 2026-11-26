// Behavioral tests for index.html's inline page script (the photo-decode
// glue: addPhoto/handleDecFile/startDecode/finishDecode/resetPhotoSession).
//
// test_browser_load.js already proves a source-level SHAPE invariant (the
// wrong-file guard exists and runs before add()) by reading the page's text.
// That catches "someone deleted the guard" but not "someone called it too
// late" or "the done flag is set after finishDecode instead of before" —
// both bugs that actually shipped and were caught only by a throwaway
// verification script during review, twice. This file is that script, kept.
//
// Approach: extend test_browser_load.js's pattern (raw script text run in a
// vm.createContext with a stubbed global surface) to the inline <script>
// block too, with a DOM stub just large enough for the functions under test.
// format.js, rateless.js and cimbar.js are the REAL modules (via require) —
// only CimbarPhoto.decode (needs real pixels; has its own test suite) and
// the browser-only APIs (createImageBitmap, canvas, Blob/URL, alert/confirm)
// are stubbed. Each test gets a FRESH vm context: photoSession/decFile are
// module-scoped `let` bindings inside the inline script with no external
// accessor, so the only way to reset them between tests is to re-run the
// script from scratch.
'use strict';
const { freshPage, makeFrame, makeCompletingFrame, makeFrameWithPayload, encryptedPayload, okResult, Fmt, Core, RatelessMod, PhotoFit, ImageDecode } = require('./page_harness');
const PhotoOptimiserMod = require('../photo-optimiser.js');
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');

let passed = 0, failed = 0;
function assert(c, msg) { if (!c) throw new Error(msg); }
function assertEq(a, b, msg) { if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}, want ${JSON.stringify(b)}`); }
const tests = [];
function test(name, fn) { tests.push({ name, fn }); }


test('addPhoto ignores further photos once the session has completed (no repeat download) — I1', async () => {
  const { ctx, elements, calls } = freshPage();
  // total: 1 -> the very first accepted photo completes the file.
  const data = makeCompletingFrame({ fileId: 7, seq: 0, total: 1 });
  let decodeCalls = 0;
  ctx.CimbarPhoto.decode = () => { decodeCalls++; return okResult(data); };
  ctx.toImageData = async () => ({});

  await ctx.addPhoto({});
  await ctx.addPhoto({}); // a would-be duplicate of the now-complete file
  await ctx.addPhoto({}); // and another

  assertEq(calls.fileResults, 1, 'the download anchor must be clicked exactly once across three photos of an already-completed file');
  assertEq(calls.parsePayload, 1, 'finishDecode must not re-run (Cimbar.parsePayload) once the session is done');
  assertEq(decodeCalls, 1, 'a completed session must not even attempt to decode later photos (early return before CimbarPhoto.decode)');
  assert(elements['logDec'].innerHTML.includes('photoAlreadyDone'),
    'a completed session must SAY why it is ignoring further photos (photoAlreadyDone), not swallow them silently');
});

test('startDecode leaves a LIVE INCOMPLETE photo session alone and reports its progress — I1', async () => {
  // The old behaviour (resetPhotoSession() before the !decFile guard) wiped
  // every accumulated frame and then alerted "select a GIF first" — and it
  // did so *always*, because handleDecFile clears decFile the moment a photo
  // is chosen, so a live session implies decFile === null by construction.
  const { ctx, elements, calls } = freshPage();
  const frame0 = makeFrameWithPayload(Core.withLengthPrefix(Core.buildPayload('x.bin', new Uint8Array([1, 2, 3]))),
                                      { fileId: 3, seq: 0, total: 2 });
  const frame1 = makeFrame({ fileId: 3, seq: 1, total: 2 });
  let next = frame0;
  ctx.CimbarPhoto.decode = () => okResult(next);
  ctx.toImageData = async () => ({});

  await ctx.addPhoto({});
  assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'setup: the photo session must be live before this test is meaningful');

  await ctx.startDecode();
  assertEq(calls.alerts.length, 0, 'pressing Decode during a photo session must not show the misleading "select a GIF first" alert');
  assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'pressing Decode must NOT destroy a live photo session (it is the only copy of the accumulated frames)');
  assert(elements['logDec'].innerHTML.includes('photoKeepGoing'), 'pressing Decode mid-session must report rank/total and tell the user to keep photographing');

  // The session is genuinely intact, not merely visually: the next photo completes it.
  next = frame1;
  await ctx.addPhoto({});
  assertEq(calls.fileResults, 1, 'the session must still be usable after the Decode press: the next photo completes the file');
});

test('a completion that failed can be retried by pressing Decode, with no re-photographing — I2', async () => {
  // finishDecode reads the passphrase only at completion time, so a user who
  // photographs an encrypted file and has not typed the passphrase yet hits a
  // throwing completion. The assembler must survive it (done stays false) and
  // the Decode button must run finishDecode against it again.
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 9, seq: 0, total: 1, encrypted: true });
  let decodeCalls = 0;
  ctx.CimbarPhoto.decode = () => { decodeCalls++; return okResult(data); };
  ctx.toImageData = async () => ({});

  await ctx.addPhoto({});   // completes the assembler; finishDecode throws (passDec is empty)
  assert(ctx.location.hash === '#/receive/unlock', 'setup: the completion must have failed for a missing passphrase');
  assertEq(calls.fileResults, 0, 'setup: nothing can have been downloaded yet');
  assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'a failed completion must leave the session alive, not tear it down');

  // done must NOT have been set by the failed attempt: the session is still
  // live, so a photo taken meanwhile is processed rather than ignored.
  await ctx.addPhoto({});
  assertEq(decodeCalls, 2, 'a failed completion must leave done false — a later photo must still be processed, not ignored');
  assert(!elements['logDec'].innerHTML.includes('photoAlreadyDone'), 'a failed completion is not a finished session');

  elements['passDec'].value = '  hunter2  ';   // the user finally types it
  const decodesBeforeRetry = decodeCalls;
  await ctx.startDecode();

  assertEq(calls.decrypt, 1, 'pressing Decode with a complete-but-unfinished session must retry finishDecode against the intact assembler');
  assertEq(calls.fileResults, 1, 'the retry must deliver the file');
  assertEq(decodeCalls, decodesBeforeRetry, 'the retry must reuse the accumulated frames — nothing may be re-photographed');
  assert(elements['decError'].textContent !== 'selectGifFirst', 'the retry must not fall through to the no-file alert');

  // And now that it succeeded, done is set: further photos are ignored again.
  await ctx.addPhoto({});
  assertEq(calls.fileResults, 1, 'once the retry succeeds the session is done and later photos must not re-download');
});

test('a photo taken while a completion is still running is ignored — the finishing flag', async () => {
  // done is only set on success, so the repeat-download protection during the
  // attempt itself (PBKDF2 + decrypt is slow) is the separate finishing flag.
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 5, seq: 0, total: 1, encrypted: true });
  let decodeCalls = 0;
  ctx.CimbarPhoto.decode = () => { decodeCalls++; return okResult(data); };
  ctx.toImageData = async () => ({});
  ctx.document.getElementById('passDec').value = 'pw';

  let release;
  const gate = new Promise((r) => { release = r; });
  ctx.CimbarCrypto = { decryptBytes: async () => { calls.decrypt++; await gate; return new Uint8Array(4); } };

  const inFlight = ctx.addPhoto({});                    // parks inside finishDecode's decrypt
  while (calls.decrypt === 0) await new Promise((r) => setTimeout(r, 0));

  // Raced against a timeout: without the finishing flag the second photo
  // re-enters finishDecode and parks on the same gate, so awaiting it plainly
  // would deadlock the whole suite instead of reporting a failure.
  const second = ctx.addPhoto({});                     // the user shoots another photo meanwhile
  const outcome = await Promise.race([second.then(() => 'returned'),
                                      new Promise((r) => setTimeout(() => r('blocked'), 100))]);
  assertEq(outcome, 'returned', 'a photo taken while a completion is in flight must return immediately, not join the in-flight completion');
  assertEq(decodeCalls, 1, 'a photo taken while a completion is in flight must be ignored before any decode work');
  assertEq(calls.decrypt, 1, 'an in-flight completion must not be started a second time');

  release();
  await inFlight;
  assertEq(calls.fileResults, 1, 'the completion must deliver the file exactly once');
});

test('choosing a GIF asks before discarding a live photo session, and honours "no" — M3', async () => {
  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  const gifFile = { name: 'foo.gif', size: 8, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }), arrayBuffer: async () => gifBytes.buffer };

  {   // declined: the session survives, the GIF is ignored
    const { ctx, elements, calls } = freshPage();
    ctx.CimbarPhoto.decode = () => okResult(makeFrame({ fileId: 3, seq: 0, total: 2 }));
    ctx.toImageData = async () => ({});
    await ctx.addPhoto({});
    calls.confirmResult = false;
    await ctx.handleDecFile(gifFile);
    assertEq(calls.confirmPrompts.length, 1, 'staging a GIF over a live photo session must ask first (a photo of a foreign file already does)');
    assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'declining must keep the accumulated frames');
    assert(!(elements['pillDec'] && elements['pillDec'].classList.contains('show')), 'declining must not stage the GIF either');
    assert(elements['logDec'].innerHTML.includes('photoProgressKept'), 'declining must say the GIF was ignored');
  }

  {   // accepted: the session is dropped and the GIF staged
    const { ctx, elements, calls } = freshPage();
    ctx.CimbarPhoto.decode = () => okResult(makeFrame({ fileId: 3, seq: 0, total: 2 }));
    ctx.toImageData = async () => ({});
    await ctx.addPhoto({});
    calls.confirmResult = true;
    await ctx.handleDecFile(gifFile);
    assertEq(calls.confirmPrompts.length, 1, 'setup: the prompt must still be shown');
    assertEq(elements['photoStartOverBtn'].style.display, 'none', 'accepting must reset the photo session');
    assert(elements['pillDec'].classList.contains('show'), 'accepting must stage the GIF');
  }
});

test("choosing a photo clears a previously staged GIF's decFile and pill — I2 direction 1", async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.CimbarPhoto.decode = () => ({ status: 'notLocated', data: null, blocksFailed: 0, header: null });
  ctx.toImageData = async () => ({});

  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  const gifFile = { name: 'foo.gif', size: 12345, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }) };
  await ctx.handleDecFile(gifFile);
  assert(elements['pillDec'].classList.contains('show'), 'setup: staging a GIF must show its pill');

  const photoBytes = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]); // not GIF magic
  const photoFile = { name: 'photo.jpg', size: 999, slice: () => ({ arrayBuffer: async () => photoBytes.buffer }) };
  await ctx.handleDecFile(photoFile);
  assert(!elements['pillDec'].classList.contains('show'), "choosing a photo must hide the stale GIF pill (still showing it means decFile's UI wasn't cleared)");

  // Prove decFile itself, not just the pill, was cleared: startDecode alerts
  // and returns immediately only when decFile is falsy.
  await ctx.startDecode();
  assertEq(elements['decError'].textContent, 'selectGifFirst', 'choosing a photo must clear decFile itself, not just its pill');
});

test('declining the wrong-file prompt leaves the assembler untouched and never calls add() on the foreign frame', async () => {
  const { ctx, calls } = freshPage();

  // Spy on the REAL RatelessAssembler.prototype.add (shared with the page's
  // Cimbar.RatelessAssembler — same class object, since both come from the
  // one required rateless.js module) so we can assert it is not called for
  // the declined frame, and read .rank off the exact instance the page
  // built, without needing to reach into the page-private `photoSession`.
  const proto = RatelessMod.RatelessAssembler.prototype;
  const originalAdd = proto.add;
  const addCalls = [];
  proto.add = function (...args) { addCalls.push({ instance: this, args }); return originalAdd.apply(this, args); };
  try {
    const frameA = makeFrame({ fileId: 1, seq: 0, total: 2 });
    const frameB = makeFrame({ fileId: 2, seq: 0, total: 3 }); // a different file entirely
    let which = 'A';
    ctx.CimbarPhoto.decode = () => okResult(which === 'A' ? frameA : frameB);
    ctx.toImageData = async () => ({});

    await ctx.addPhoto({}); // accepts frame A -> rank 1, fileId 1
    assertEq(addCalls.length, 1, 'setup: the first photo must reach add()');
    const asm = addCalls[0].instance;
    assertEq(asm.rank, 1, 'setup: the first frame must be accepted');

    calls.confirmResult = false; // user declines "discard progress and start over?"
    which = 'B';
    await ctx.addPhoto({}); // a photo of a DIFFERENT file

    assert(calls.confirmPrompts.length >= 1, 'the wrong-file confirm() prompt must have been shown');
    assertEq(addCalls.length, 1, 'declining the wrong-file prompt must NOT call add() on the foreign frame (this is the guard\'s entire purpose)');
    assertEq(asm.rank, 1, 'declining the wrong-file prompt must leave the original assembler\'s rank unchanged');
    assertEq(asm.fileId, 1, 'declining the wrong-file prompt must leave the original assembler bound to the original fileId');
  } finally {
    proto.add = originalAdd; // restore — RatelessAssembler is a module-cached singleton shared across this file's tests
  }
});

test('addFrame reports what happened without logging or completing — kinds', async () => {
  const { ctx, elements, calls } = freshPage();
  const f0 = makeFrame({ fileId: 4, seq: 0, total: 3 });
  let r = await ctx.addFrame(okResult(f0));
  assertEq(r.kind, 'accepted', 'first frame accepted');
  assertEq(r.rank, 1, 'rank'); assertEq(r.total, 3, 'total'); assertEq(r.complete, false, 'not complete');
  r = await ctx.addFrame(okResult(f0));
  assertEq(r.kind, 'duplicate', 'same frame again');
  r = await ctx.addFrame(okResult(makeFrame({ fileId: 4, seq: 1, total: 3, compressed: true })));   // new seq, so not a duplicate
  assertEq(r.kind, 'rejected', 'flags mismatch is a plain rejection');
  assertEq(elements['logDec'].innerHTML, '', 'addFrame never logs');
  assertEq(elements['progDec'].style.display, 'block', 'progress shown');
  assertEq(elements['photoStartOverBtn'].style.display, 'inline-flex', 'start-over shown');

  calls.confirmResult = false;
  r = await ctx.addFrame(okResult(makeFrame({ fileId: 9, seq: 0, total: 2 })));
  assertEq(r.kind, 'kept', 'foreign file, user keeps the session');
  assertEq(r.fileId, 9, 'foreign fileId reported');
  assertEq(r.rank, 1, 'session untouched');
});

test('addFrame returns complete: true and leaves completion to the caller', async () => {
  const { ctx, calls } = freshPage();
  const r = await ctx.addFrame(okResult(makeCompletingFrame({ fileId: 2, seq: 0, total: 1 })));
  assertEq(r.kind, 'accepted', 'accepted');
  assertEq(r.complete, true, 'complete');
  await new Promise((res) => setTimeout(res, 0));
  assertEq(calls.fileResults, 0, 'addFrame itself must not start finishDecode');
  assertEq(calls.parsePayload, 0, 'no completion attempted');
});

test('addFrame on a finished session returns "done"', async () => {
  const { ctx } = freshPage();
  const data = makeCompletingFrame({ fileId: 7, seq: 0, total: 1 });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});                                  // completes and downloads
  assertEq((await ctx.addFrame(okResult(data))).kind, 'done', 'done');
});

const tick = () => new Promise((r) => setTimeout(r, 0));

test('live-scan frames and photos build ONE session', async () => {
  const { ctx, calls } = freshPage();
  const payload = Core.withLengthPrefix(Core.buildPayload('x.bin', new Uint8Array([1, 2, 3])));
  const f0 = makeFrameWithPayload(payload, { fileId: 6, seq: 0, total: 2 });
  const f1 = makeFrame({ fileId: 6, seq: 1, total: 2 });

  await ctx.openScanner();
  const scan = calls.liveScans[0];
  assert(scan, 'openScanner constructs a LiveScan');
  const r = await scan.o.onFrame(okResult(f0));
  assertEq(r.kind, 'accepted', 'live frame accepted');
  ctx.closeScanner();
  await tick();

  ctx.CimbarPhoto.decode = () => okResult(f1);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});                                   // the photo completes the SAME session
  assertEq(calls.fileResults, 1, 'the photo completed the file started by the live scan');
});

test('a wrong-file live frame prompts once; after "keep" that file is ignored silently', async () => {
  const { ctx, calls } = freshPage();
  await ctx.openScanner();
  const scan = calls.liveScans[0];
  await scan.o.onFrame(okResult(makeFrame({ fileId: 1, seq: 0, total: 3 })));
  calls.confirmResult = false;
  const foreign = okResult(makeFrame({ fileId: 2, seq: 0, total: 4 }));
  assertEq((await scan.o.onFrame(foreign)).kind, 'kept', 'first foreign frame: kept');
  assertEq(calls.confirmPrompts.length, 1, 'prompted once');
  assertEq((await scan.o.onFrame(okResult(makeFrame({ fileId: 2, seq: 1, total: 4 })))).kind, 'kept', 'second foreign frame: kept');
  assertEq(calls.confirmPrompts.length, 1, 'not prompted again for the same foreign file');
});

test('completion during a scan closes the scanner, then completes the session (encrypted retry intact)', async () => {
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 8, seq: 0, total: 1, encrypted: true });
  await ctx.openScanner();
  const scan = calls.liveScans[0];
  const r = await scan.o.onFrame(okResult(data));
  assertEq(r.complete, true, 'complete');
  scan.stop('complete');                                     // what LiveScan does on complete
  await tick();
  assert(!elements['scanner'].classList.contains('open'), 'scanner view closed');
  assert(ctx.location.hash === '#/receive/unlock', 'completion ran after the close (and failed: no passphrase)');

  elements['passDec'].value = 'pw';
  await ctx.startDecode();                                   // the existing recovery route
  assertEq(calls.decrypt, 1, 'retry decrypts from the intact assembler');
  assertEq(calls.fileResults, 1, 'file delivered');
});

test('opening the scanner clears a staged GIF; closing logs a summary and pops the history entry', async () => {
  const { ctx, elements, calls } = freshPage();
  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  await ctx.handleDecFile({ name: 'a.gif', size: 8, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }) });
  assert(elements['pillDec'].classList.contains('show'), 'setup: GIF staged');
  await ctx.openScanner();
  assert(!elements['pillDec'].classList.contains('show'), 'GIF pill cleared');
  assert(elements['scanner'].classList.contains('open'), 'scanner open');
  assertEq(calls.pushes, 1, 'history entry pushed');
  ctx.closeScanner();
  await tick();
  assertEq(calls.backs, 1, 'history entry consumed on close');
  assert(elements['logDec'].innerHTML.includes('scanSummary'), 'summary logged');
  await ctx.startDecode();
  assertEq(elements['decError'].textContent, 'selectGifFirst', 'decFile itself was cleared');
});

test('a "back" stop does not call history.back(): popstate already consumed the entry', async () => {
  const { ctx, calls } = freshPage();
  await ctx.openScanner();
  assertEq(calls.pushes, 1, 'history entry pushed');
  const scan = calls.liveScans[0];
  scan.stop('back');                                        // history.state still carries cimbarScanner (stale entry)
  await tick();
  assertEq(calls.backs || 0, 0, 'history.back() not called for a "back" stop');
});

test('a camera error closes the scanner and explains in the Decode log', async () => {
  const { ctx, elements, calls } = freshPage();
  await ctx.openScanner();
  const scan = calls.liveScans[0];
  scan.o.onError('camDenied');
  scan.stop('error');
  await tick();
  assert(!elements['scanner'].classList.contains('open'), 'closed');
  assert(elements['logDec'].innerHTML.includes('camDenied'), 'error explained');
});

test('a completing frame followed by a non-"complete" close still delivers the file', async () => {
  const { ctx, calls } = freshPage();
  const data = makeCompletingFrame({ fileId: 11, seq: 0, total: 1 });
  await ctx.openScanner();
  const scan = calls.liveScans[0];
  const r = await scan.o.onFrame(okResult(data));
  assertEq(r.complete, true, 'complete');
  scan.stop('closed');                                       // the user closed, not LiveScan noticing completion
  await tick();
  assertEq(calls.fileResults, 1, 'the file is still delivered even though the stop reason was not "complete"');
});

test('text mode: encodeInput builds message-….txt from the textarea, as typed (CRLF kept)', async () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('text');
  elements['textEnc'].value = 'a\r\nб';
  const input = await ctx.encodeInput();
  assert(/^message-\d{8}-\d{6}\.txt$/.test(input.name), 'name: ' + input.name);
  assertEq(Buffer.from(input.bytes).toString('hex'), Buffer.from('a\r\nб', 'utf8').toString('hex'), 'UTF-8 bytes as typed, no BOM');
});

test('text mode: empty text disables Encode; whitespace-only does not', async () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('text');
  elements['textEnc'].value = '';
  ctx.updateTextInfo();
  assertEq(elements['encBtn'].disabled, true, 'empty text disables Encode');
  assertEq(await ctx.encodeInput(), null, 'no input for empty text');
  elements['textEnc'].value = '  \n';
  ctx.updateTextInfo();
  assertEq(elements['encBtn'].disabled, false, 'whitespace-only text is sendable');
});

test('switching modes encodes only the visible input — Review Focus 2', async () => {
  const { ctx, elements } = freshPage();
  await ctx.onFileSelect({ files: [{ name: 'a.bin', size: 3, arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer }] }, 'enc');
  ctx.setEncMode('text');
  elements['textEnc'].value = 'hello';
  ctx.setEncMode('file');
  assertEq(elements['encBtn'].disabled, false, 'file mode never disabled by the text box');
  const input = await ctx.encodeInput();
  assertEq(input.name, 'a.bin', 'file mode encodes the staged file, the typed text is NOT encoded');
  assertEq(Buffer.from(input.bytes).toString('hex'), '010203', 'the staged file\'s bytes, not the text\'s');
  assertEq(elements['encTextField'].style.display, 'none', 'text field hidden in file mode');
  assertEq(elements['textEnc'].value, 'hello', 'switching keeps the typed text');
});

test('updateTextInfo shows bytes and an upper-bound frame count', () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('text');
  elements['textEnc'].value = 'x'.repeat(3000);
  ctx.updateTextInfo();
  assert(elements['textEncInfo'].textContent.includes('textEncInfo'), 'uses the textEncInfo key');
});

test('file mode: a second Encode click while the file is still being read does not start a second encode', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.setEncMode('file');
  let reads = 0, release;
  const gate = new Promise((r) => { release = r; });
  const file = { name: 'a.bin', size: 3, arrayBuffer: async () => { reads++; await gate; return new Uint8Array([1, 2, 3]).buffer; } };
  await ctx.onFileSelect({ files: [file] }, 'enc');
  const first = ctx.startEncode();
  assertEq(elements['encBtn'].disabled, true, 'Encode is disabled before the file read is awaited');
  const second = ctx.startEncode();
  release();
  await Promise.all([first, second]);
  assertEq(reads, 1, 'the file is read once: the second click returned early');
  assertEq(elements['encBtn'].disabled, false, 'Encode is enabled again when the first run ends');
  assertEq(calls.alerts.length, 0, 'no "select a file" alert from the second click');
});

test('file mode with nothing staged: Create code is disabled and a click is a no-op', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.setEncMode('file');
  assertEq(elements['encBtn'].disabled, true, 'disabled until a file is chosen');
  await ctx.startEncode();
  assertEq(calls.alerts.length, 0, 'no alert');
  await ctx.onFileSelect({ files: [{ name: 'a.bin', size: 3, arrayBuffer: async () => new ArrayBuffer(3) }] }, 'enc');
  assertEq(elements['encBtn'].disabled, false, 'enabled once a file is staged');
});

test('a wrong passphrase routes to unlock with the wrong-pass message, session intact', async () => {
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 11, seq: 0, total: 1, encrypted: true });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  ctx.CimbarCrypto = { decryptBytes: async () => { throw new Error('Decryption failed — wrong passphrase or corrupted data'); } };
  elements['passDec'].value = 'nope';
  await ctx.addPhoto({});
  assertEq(ctx.location.hash, '#/receive/unlock', 'routed to unlock');
  assertEq(elements['unlockError'].textContent, 'wrongPass', 'says the passphrase was wrong');
  assertEq(calls.fileResults, 0, 'nothing delivered');
  ctx.CimbarCrypto = { decryptBytes: async () => new Uint8Array(4) };
  await ctx.startDecode();
  assertEq(calls.fileResults, 1, 'Unlock (startDecode) retries the intact session');
});

test('received text is left-aligned (.text-out)', () => {
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const rule = html.match(/\.text-out\s*\{([^}]*)\}/);
  assert(rule, '.text-out rule exists');
  assert(/text-align:\s*left/.test(rule[1]), '.text-out sets text-align: left: ' + rule[1]);
});

async function completeWith(ctx, name, bytes) {
  ctx.Cimbar.parsePayload = () => ({ fileName: name, fileBytes: bytes });
  const data = makeCompletingFrame({ fileId: 21, seq: 0, total: 1 });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});
}

test('a decoded text message is shown as text (textContent), not downloaded', async () => {
  const { ctx, elements, calls } = freshPage();
  const bytes = new Uint8Array(Buffer.from('<b>hi</b>\nthere', 'utf8'));
  await completeWith(ctx, 'message-20261001-120000.txt', bytes);
  assertEq(calls.fileResults, 0, 'no automatic download for a text message');
  assertEq(elements['textOut'].style.display, 'block', 'text panel visible');
  assertEq(elements['textOutBody'].textContent, '<b>hi</b>\nthere', 'text via textContent');
  assertEq(elements['textOutBody'].innerHTML, '', 'never innerHTML');
});

test('a non-text payload still downloads and keeps the text panel hidden', async () => {
  const { ctx, elements, calls } = freshPage();
  await completeWith(ctx, 'photo.jpg', new Uint8Array([0xff, 0xd8]));
  assertEq(calls.fileResults, 1, 'file downloaded');
  assert(elements['textOut'].style.display !== 'block', 'text panel hidden');
});

test('BOM + CRLF: Copy gets the text without BOM, Save writes the exact bytes — Review Focus 1', async () => {
  const { ctx, calls } = freshPage();
  const bytes = new Uint8Array([0xef, 0xbb, 0xbf, 0x61, 0x0d, 0x0a, 0x62]);
  await completeWith(ctx, 'notes.txt', bytes);
  let copied = null;
  ctx.navigator.clipboard = { writeText: async (s) => { copied = s; } };
  await ctx.copyText();
  assertEq(copied, 'a\r\nb', 'clipboard text');
  let blobParts = null;
  ctx.Blob = class { constructor(p) { blobParts = p; } };
  ctx.saveText();
  assertEq(calls.anchorClicks, 1, 'Save downloads');
  assertEq(Buffer.from(blobParts[0]).toString('hex'), 'efbbbf610d0a62', 'exact received bytes');
});

test('a blocked clipboard selects the text and explains', async () => {
  const { ctx, elements } = freshPage();
  await completeWith(ctx, 'n.txt', new Uint8Array([0x61]));
  ctx.navigator.clipboard = { writeText: async () => { throw new Error('denied'); } };
  let selected = false;
  ctx.getSelection = () => ({ selectAllChildren() { selected = true; } });
  await ctx.copyText();
  assert(selected, 'text selected for manual copy');
  assert(elements['logDec'].innerHTML.includes('copyFailedHint'), 'hint logged');
});

test('starting over after a text result hides the old text — Review Focus 3', async () => {
  const { ctx, elements } = freshPage();
  await completeWith(ctx, 'n.txt', new Uint8Array([0x61]));
  ctx.resetPhotoSession();
  assertEq(elements['textOut'].style.display, 'none', 'hidden after reset');
  assertEq(elements['textOutBody'].textContent, '', 'old text cleared');
});

test('choosing a language from the sheet sets it and closes the sheet', () => {
  const { ctx, elements } = freshPage();
  let set = null;
  ctx.CimbarI18n.setLang = (c) => { set = c; };
  ctx.openLanguageSheet();
  assertEq(elements['langSheet'].open, true, 'sheet open');
  ctx.chooseLanguage('ka');
  assertEq(set, 'ka', 'language applied');
  assertEq(elements['langSheet'].open, false, 'sheet closed');
});

test('a finished encode replaces #/send with #/send/ready', async () => {
  const { ctx, elements } = freshPage();
  ctx.encodeToGif = async () => ({ blob: { size: 10 }, state: { frames: [1], bodies: [], fileId: 1, opts: {}, delayMs: 200, repairEnabled: false },
                                    stats: { frames: 1, repair: 0, bytes: 10, compressedPct: null, encrypted: false } });
  ctx.navigate('#/send');
  ctx.setEncMode('text');
  elements['textEnc'].value = 'hi';
  ctx.updateTextInfo();
  await ctx.startEncode();
  assertEq(ctx.location.hash, '#/send/ready', 'on the ready screen');
  assertEq(ctx.routeState().hasGif, true, 'GIF held for the guard');
});

test('Share GIF is hidden when the browser cannot share files', () => {
  const { ctx } = freshPage();
  assertEq(ctx.canShareFiles('image/gif'), false, 'harness navigator has no canShare');
  ctx.navigator.canShare = () => true;
  ctx.File = class { constructor(b, n, o) { this.name = n; this.type = o.type; } };
  assertEq(ctx.canShareFiles('image/gif'), true, 'canShare with files');
});

test('entering #/send with nothing staged disables Create code', () => {
  const { ctx, elements } = freshPage();
  ctx.navigate('#/send');
  assertEq(elements['encBtn'].disabled, true, 'no file staged');
});

const gifResult = () => ({ blob: { size: 10 }, state: { frames: [1], bodies: [], fileId: 1, opts: {}, delayMs: 200, repairEnabled: false },
                           stats: { frames: 1, repair: 0, bytes: 10, compressedPct: null, encrypted: false } });
function stageText(ctx, elements) { ctx.setEncMode('text'); elements['textEnc'].value = 'hi'; ctx.updateTextInfo(); }

test('a failed Share GIF shows its error on the ready screen; a cancelled one shows nothing', async () => {
  const { ctx, elements } = freshPage();
  ctx.encodeToGif = async () => gifResult();
  ctx.navigate('#/send');
  stageText(ctx, elements);
  await ctx.startEncode();
  ctx.navigator.share = async () => { const e = new Error('denied'); e.name = 'NotAllowedError'; throw e; };
  await ctx.shareGif();
  assertEq(elements['readyError'].hidden, false, 'error shown on the ready screen');
  assertEq(elements['readyError'].textContent, 'errorPrefix', 'error text');
  assert(elements['decError'].textContent === '', 'nothing written to the Receive screen');
  ctx.navigator.share = async () => { const e = new Error('cancel'); e.name = 'AbortError'; throw e; };
  await ctx.shareGif();
  assertEq(elements['readyError'].hidden, true, 'a cancelled share clears and shows nothing');
});

test('leaving and returning mid-encode keeps Create code disabled', async () => {
  const { ctx, elements } = freshPage();
  let release;
  ctx.encodeToGif = () => new Promise((r) => { release = () => r(gifResult()); });
  ctx.navigate('#/send');
  stageText(ctx, elements);
  const run = ctx.startEncode();
  await new Promise((r) => setTimeout(r, 0));
  ctx.navigate('#/');
  ctx.navigate('#/send');
  assertEq(elements['encBtn'].disabled, true, 'still disabled while encoding');
  release();
  await run;
  assertEq(elements['encBtn'].disabled, false, 're-enabled after the encode');
});

test('an encode that finishes off the Send screen keeps the GIF without redirecting', async () => {
  const { ctx, elements } = freshPage();
  let release;
  ctx.encodeToGif = () => new Promise((r) => { release = () => r(gifResult()); });
  ctx.navigate('#/send');
  stageText(ctx, elements);
  const run = ctx.startEncode();
  await new Promise((r) => setTimeout(r, 0));
  ctx.navigate('#/');
  release();
  await run;
  assertEq(ctx.location.hash, '#/', 'user left where they were');
  assertEq(ctx.routeState().hasGif, true, 'GIF kept for #/send/ready');
});

test('Present pushes one history entry; closing via the UI pops it exactly once', () => {
  const { ctx, calls } = freshPage();
  ctx.setInterval = () => 1; ctx.clearInterval = () => {};
  ctx.presentDraw = () => {}; ctx.layoutPresent = () => {};   // rendering is covered elsewhere; this test is about history
  ctx.openPresentWith({ frames: [new Uint8Array(1)], bodies: [], fileId: 1, opts: {}, delayMs: 200, repairEnabled: false });
  assertEq(calls.pushes, 1, 'one entry pushed');
  assertEq(ctx.history.state && ctx.history.state.cimbarPresent, true, 'entry marked');
  ctx.requestClosePresent();
  assertEq(calls.backs, 1, 'UI close goes through history.back()');
});

test('Wake Lock: pill shows only while a lock is held, and it is re-acquired on return', async () => {
  const { ctx, elements } = freshPage();
  let requests = 0, sentinel = null;
  ctx.navigator.wakeLock = { request: async () => { requests++; sentinel = { released: false, addEventListener(_e, fn) { this.onrel = fn; }, release: async function () { this.onrel && this.onrel(); } }; return sentinel; } };
  ctx.presentOpenForTest(true);
  await ctx.acquireWakeLock();
  assertEq(elements['wakePill'].hidden, false, 'pill visible with a lock');
  sentinel.onrel();                       // the browser dropped it (tab hidden)
  assertEq(elements['wakePill'].hidden, true, 'pill hidden without a lock');
  await ctx.onVisibilityChange();
  assertEq(requests, 2, 're-acquired when visible again');
});

test('no Wake Lock API: no pill and no error', async () => {
  const { ctx, elements } = freshPage();
  ctx.presentOpenForTest(true);
  await ctx.acquireWakeLock();
  assertEq(elements['wakePill'].hidden, true, 'pill hidden');
});

test('Escape does nothing while a <dialog> is open; closes Present otherwise', () => {
  const { ctx, calls } = freshPage();
  ctx.presentOpenForTest(true);
  ctx.history.state = { cimbarPresent: true };
  const esc = calls.docListeners.keydown[0];
  ctx.document.querySelector = (sel) => (sel === 'dialog[open]' ? {} : null);
  esc({ key: 'Escape' });
  assertEq(calls.backs || 0, 0, 'ignored under an open dialog');
  ctx.document.querySelector = () => null;
  esc({ key: 'Escape' });
  assertEq(calls.backs, 1, 'closes Present');
});

test('Wake Lock: a lock granted after Present closed is released, not kept', async () => {
  const { ctx, elements } = freshPage();
  let release; const gate = new Promise((r) => { release = r; });
  let released = 0;
  const sentinel = { addEventListener() {}, release: async () => { released++; } };
  ctx.navigator.wakeLock = { request: async () => { await gate; return sentinel; } };
  ctx.presentOpenForTest(true);
  const p = ctx.acquireWakeLock();
  ctx.closePresent();
  release(); await p;
  assertEq(released, 1, 'late sentinel released');
  assertEq(elements['wakePill'].hidden, true, 'pill hidden');
});

test('Wake Lock: concurrent acquires issue a single request', async () => {
  const { ctx } = freshPage();
  let requests = 0, release; const gate = new Promise((r) => { release = r; });
  ctx.navigator.wakeLock = { request: async () => { requests++; await gate; return { addEventListener() {}, release: async () => {} }; } };
  ctx.presentOpenForTest(true);
  const a = ctx.acquireWakeLock(), b = ctx.acquireWakeLock();
  release(); await Promise.all([a, b]);
  assertEq(requests, 1, 'one request');
});

test('entering #/receive opens the scanner; closing it without a file returns to the hub', async () => {
  const { ctx, calls } = freshPage();
  ctx.navigate('#/receive');
  await new Promise((r) => setTimeout(r, 0));
  assertEq(calls.liveScans.length, 1, 'scanner started on route entry');
  calls.liveScans[0].stop('closed');
  await new Promise((r) => setTimeout(r, 0));
  assertEq(ctx.location.hash, '#/', 'back to the hub');
});

test('a camera error routes to #/receive/files with the reason shown', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.navigate('#/receive');
  await new Promise((r) => setTimeout(r, 0));
  const scan = calls.liveScans[0];
  scan.o.onError('camDenied');
  scan.stop('error');
  await new Promise((r) => setTimeout(r, 0));
  assertEq(ctx.location.hash, '#/receive/files', 'fallback screen');
  assertEq(elements['decNotice'].textContent, 'camUnavailable', 'explains the fallback');
});

test('no camera API: #/receive lands on files without starting a scan', () => {
  const { ctx, calls } = freshPage({ camera: false });
  ctx.navigate('#/receive');
  assertEq(ctx.location.hash, '#/receive/files', 'guarded');
  assertEq(calls.liveScans.length, 0, 'no scanner');
});

test('a worker failure falls back to files with the decoder message, not the camera one', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.navigate('#/receive');
  await tick();
  const scan = calls.liveScans[0];
  scan.o.onError('scanDecoderFailed');
  scan.stop('decoderFailed');
  await tick();
  assertEq(ctx.location.hash, '#/receive/files', 'fallback screen');
  assertEq(elements['decNotice'].textContent, 'scanDecoderFailed', 'names the decoder failure');
});

test('"Load a GIF or photo instead" stops the scan and lands on #/receive/files, not the hub', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.navigate('#/receive');
  await tick();
  let prevented = false;
  ctx.loadInsteadOfScanning({ preventDefault() { prevented = true; } });
  await tick();
  assert(prevented, 'the link does not navigate by itself');
  assertEq(calls.liveScans[0].state, 'stopped', 'scan stopped');
  assert(!elements['scanner'].classList.contains('open'), 'overlay closed');
  assertEq(ctx.location.hash, '#/receive/files', 'files screen');
});

test('opened from #/receive the scanner adds no history entry of its own; a Back stop leaves routing to the browser', async () => {
  // The #/receive entry is the scanner's Back target. An extra overlay entry
  // would need history.back() on close, which is asynchronous in a browser:
  // it would land on #/receive again after the close routed away, and reopen
  // the scanner.
  const { ctx, calls } = freshPage();
  ctx.navigate('#/receive');
  await tick();
  assertEq(calls.pushes, 1, 'only the route entry');
  calls.liveScans[0].stop('back');
  await tick();
  assertEq(calls.backs || 0, 0, 'no history.back()');
  assertEq(ctx.location.hash, '#/receive', 'the traversal the browser already made is not overridden');
});

test('choosing a GIF decodes it straight away', async () => {
  const { ctx, calls } = freshPage();
  let decoded = 0;
  ctx.GifDecoder = class { decode() { decoded++; throw new Error('stub GIF decoder'); } };
  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  await ctx.handleDecFile({ name: 'a.gif', size: 8, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }), arrayBuffer: async () => gifBytes.buffer });
  assertEq(decoded, 1, 'decoded without a Decode press');
  assert(calls.consoleErrors.some((e) => e && e.message === 'stub GIF decoder'), 'the decode ran into the stub');
});

test('a stale decode error is cleared by Start over, the unlock screen and a result', async () => {
  for (const [what, act] of [
    ['resetPhotoSession', (ctx) => ctx.resetPhotoSession()],
    ['showUnlock', (ctx) => ctx.showUnlock(false)],
    ['showFileResult', (ctx) => ctx.showFileResult('a.bin', new Uint8Array(1))],
    ['showTextResult', (ctx) => ctx.showTextResult('m.txt', new Uint8Array(1), 'hi')],
  ]) {
    const { ctx, elements } = freshPage();
    ctx.showError('dec', 'old failure');
    act(ctx);
    assertEq(elements['decError'].hidden, true, `${what} hides #decError`);
    assertEq(elements['decError'].textContent, '', `${what} empties #decError`);
  }
});

test('a scan whose completion fails (not for a passphrase) lands on the files screen with the error', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.Cimbar.parsePayload = () => { throw new Error('corrupt container'); };
  ctx.navigate('#/receive');
  await tick();
  const scan = calls.liveScans[0];
  const r = await scan.o.onFrame(okResult(makeCompletingFrame({ fileId: 31, seq: 0, total: 1 })));
  assertEq(r.complete, true, 'setup: complete');
  scan.stop('complete');
  await tick();
  assertEq(ctx.location.hash, '#/receive/files', 'not stranded on #/receive');
  assertEq(elements['decError'].hidden, false, 'error shown');
  assertEq(elements['decError'].textContent, 'errorPrefix', 'the failure is explained');
});

test('re-entering #/receive with a complete session whose retry fails lands on the files screen', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.Cimbar.parsePayload = () => { throw new Error('corrupt container'); };
  await ctx.addFrame(okResult(makeCompletingFrame({ fileId: 32, seq: 0, total: 1 })));   // complete, never finished
  ctx.navigate('#/receive');
  await tick();
  assertEq(calls.liveScans.length, 0, 'retried instead of scanning');
  assertEq(ctx.location.hash, '#/receive/files', 'not stranded on #/receive');
  assertEq(elements['decError'].textContent, 'errorPrefix', 'the failure is explained');
});

test('entering #/receive while a completion is in flight lands on the files screen', async () => {
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 33, seq: 0, total: 1, encrypted: true });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  elements['passDec'].value = 'pw';
  let release; const gate = new Promise((r) => { release = r; });
  ctx.CimbarCrypto = { decryptBytes: async () => { calls.decrypt++; await gate; return new Uint8Array(4); } };
  const inFlight = ctx.addPhoto({});
  while (calls.decrypt === 0) await tick();
  ctx.navigate('#/receive');
  await tick();
  assertEq(calls.liveScans.length, 0, 'no scan while busy');
  assertEq(ctx.location.hash, '#/receive/files', 'not stranded on #/receive');
  release(); await inFlight;
  assertEq(ctx.location.hash, '#/receive/done', 'the completion still routes when it lands');
});

test('Open is offered only for types a browser renders safely — never svg or html', () => {
  const { ctx } = freshPage();
  for (const n of ['a.pdf', 'b.PNG', 'c.jpeg', 'd.txt', 'e.mp4', 'f.json']) assertEq(ctx.canOpen(n), true, n);
  for (const n of ['x.svg', 'y.html', 'z.htm', 'w.xhtml', 'noext', 'v.exe', 'u.zip']) assertEq(ctx.canOpen(n), false, n);
  assertEq(ctx.mimeFor('report.PDF'), 'application/pdf', 'case-insensitive');
  assertEq(ctx.mimeFor('a.bin'), 'application/octet-stream', 'fallback');
  for (const n of ['a.constructor', 'b.toString', 'c.hasOwnProperty']) {
    assertEq(ctx.canOpen(n), false, n + ' (Object.prototype key)');
    assertEq(ctx.mimeFor(n), 'application/octet-stream', n + ' mime');
  }
});

test('file result screen: Open hidden for an unsafe type, Share hidden without canShare', async () => {
  const { ctx, elements } = freshPage();
  ctx.showFileResult('evil.svg', new Uint8Array(3));
  assertEq(elements['openFileBtn'].hidden, true, 'svg cannot be opened');
  assertEq(elements['shareFileBtn'].hidden, true, 'no canShare in harness');
  assertEq(elements['fileOutName'].textContent, 'evil.svg', 'name via textContent');
});

test('Unlock reads the passphrase field and retries; Discard resets and rescans', async () => {
  const { ctx, elements, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 12, seq: 0, total: 1, encrypted: true });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});
  assertEq(ctx.location.hash, '#/receive/unlock', 'asked for the passphrase');
  elements['passDec'].value = 'pw';
  await ctx.unlock();
  assertEq(calls.fileResults, 1, 'unlocked');
  ctx.discardAndRescan();
  assertEq(ctx.location.hash, '#/receive', 'rescanning');
  assertEq(ctx.routeState().hasResult, false, 'result cleared');
});

test('a failed Share on the file result shows on the done screen; a cancelled one shows nothing', async () => {
  const { ctx, elements } = freshPage();
  ctx.showFileResult('a.pdf', new Uint8Array(3));
  ctx.navigator.share = async () => { const e = new Error('denied'); e.name = 'NotAllowedError'; throw e; };
  await ctx.shareFile();
  assertEq(elements['doneError'].hidden, false, 'error shown on the done screen');
  assertEq(elements['doneError'].textContent, 'errorPrefix', 'error text');
  assertEq(elements['decError'].textContent, '', 'nothing written to the hidden files screen');
  ctx.navigator.share = async () => { const e = new Error('cancel'); e.name = 'AbortError'; throw e; };
  await ctx.shareFile();
  assertEq(elements['doneError'].hidden, true, 'a cancelled share clears and shows nothing');
});

test('Open opens only an inert type, in a new tab', () => {
  const { ctx } = freshPage();
  const opened = [];
  ctx.open = (...a) => { opened.push(a); };
  ctx.showFileResult('evil.svg', new Uint8Array(3));
  ctx.openFile();
  assertEq(opened.length, 0, 'svg is never opened');
  ctx.showFileResult('doc.pdf', new Uint8Array(3));
  ctx.openFile();
  assertEq(opened.length, 1, 'pdf opened');
  assertEq(opened[0][1], '_blank', 'new tab');
});

test('Copy shows the Copied chip', async () => {
  const { ctx, elements } = freshPage();
  ctx.showTextResult('m.txt', new Uint8Array([0x61]), 'a');
  elements['copiedChip'].hidden = true;
  ctx.navigator.clipboard = { writeText: async () => {} };
  await ctx.copyText();
  assertEq(elements['copiedChip'].hidden, false, 'chip shown');
  assert(!elements['logDec'].innerHTML.includes('copyFailedHint'), 'the copy itself succeeded');
});

test('choosing a GIF over a complete-but-locked session and answering Keep keeps the unlock pending', async () => {
  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  const gifFile = { name: 'foo.gif', size: 8, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }), arrayBuffer: async () => gifBytes.buffer };
  const { ctx, calls } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 13, seq: 0, total: 1, encrypted: true });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  await ctx.addPhoto({});
  assertEq(ctx.routeState().needsUnlock, true, 'setup: locked');
  calls.confirmResult = false;
  await ctx.handleDecFile(gifFile);
  assertEq(calls.confirmPrompts.length, 1, 'asked');
  assertEq(ctx.routeState().needsUnlock, true, 'Keep must not lose the pending unlock');
});

test('a passphrase failure is still logged to the console before routing to unlock', async () => {
  const { ctx, calls } = freshPage();
  const err = new Error('OperationError'); err.needPass = true; err.wrongPass = true;
  ctx.logDecodeError(err);
  assertEq(ctx.location.hash, '#/receive/unlock', 'routed to unlock');
  assert(calls.consoleErrors.includes(err), 'console.error(err) ran');
});

test('a share error from one result does not leak onto the next result', async () => {
  const { ctx, elements } = freshPage();
  ctx.showFileResult('a.pdf', new Uint8Array(3));
  ctx.navigator.share = async () => { const e = new Error('denied'); e.name = 'NotAllowedError'; throw e; };
  await ctx.shareFile();
  assertEq(elements['doneError'].hidden, false, 'setup: share error shown');
  ctx.resetPhotoSession();   // what "Receive another" does
  ctx.showTextResult('m.txt', new Uint8Array([0x61]), 'a');
  assertEq(elements['doneError'].hidden, true, 'old share error gone');
  assertEq(elements['doneError'].textContent, '', 'old share error emptied');
  // and showTextResult clears it on its own too
  ctx.showError('done', 'stale');
  ctx.showTextResult('n.txt', new Uint8Array([0x62]), 'b');
  assertEq(elements['doneError'].hidden, true, 'showTextResult clears #doneError');
});

test('an Unlock retry that fails for another reason explains it on the unlock screen', async () => {
  const { ctx, elements } = freshPage();
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 14, seq: 0, total: 1, encrypted: true });
  ctx.CimbarPhoto.decode = () => okResult(data);
  ctx.toImageData = async () => ({});
  ctx.CimbarCrypto = { decryptBytes: async () => { throw new Error('bad'); } };
  elements['passDec'].value = 'wrong';
  await ctx.addPhoto({});
  assertEq(elements['unlockError'].textContent, 'wrongPass', 'setup: wrong pass shown');
  ctx.CimbarCrypto = { decryptBytes: async () => new Uint8Array(4) };
  ctx.Cimbar.parsePayload = () => { throw new Error('corrupt container'); };
  elements['passDec'].value = 'right';
  await ctx.unlock();
  assertEq(ctx.location.hash, '#/receive/unlock', 'still on the unlock screen');
  assertEq(elements['unlockError'].hidden, false, 'error shown on the unlock screen');
  assertEq(elements['unlockError'].textContent, 'errorPrefix', 'the failure, not the stale wrong-pass message');
  assert(elements['logDec'].innerHTML.includes('errorPrefix'), 'the log line is kept');
});

test('hub demo encodes the deployed icon; a fetch failure falls back to a text frame, never an error', async () => {
  const { ctx, elements } = freshPage();
  const seen = [];
  ctx.encodeToGif = async (input) => { seen.push(input.name); return { blob: {}, state: {}, stats: {} }; };
  ctx.fetch = async () => ({ ok: true, arrayBuffer: async () => new ArrayBuffer(8) });
  await ctx.renderDemo();
  assertEq(seen[0], 'cimbar.png', 'icon payload');
  assertEq(elements['demoGif'].src, 'blob://x', 'image set');
  ctx.fetch = async () => { throw new Error('offline'); };
  await ctx.renderDemo();
  assertEq(seen[1], 'hello.txt', 'fallback payload');
});

// ── Final whole-branch review fixes ──────────────────────────
test('a decompression failure is shown inline, not only logged — final 1', () => {
  for (const [flag, key] of [['tooLarge', 'inflatedTooLarge'], ['unsupported', 'noDecompressionSupport']]) {
    const { ctx, elements } = freshPage();
    ctx.clearError('dec');
    const err = new Error('inflate'); err[flag] = true;
    ctx.logDecodeError(err);
    assertEq(elements['decError'].hidden, false, `${flag}: #decError shown`);
    assertEq(elements['decError'].textContent, key, `${flag}: the translated reason`);
  }
});

test('a staged file that cannot be read shows an error and re-enables Create code — final 2', async () => {
  const { ctx, elements } = freshPage();
  ctx.setEncMode('file');
  const file = { name: 'a.bin', size: 3, arrayBuffer: async () => { const e = new Error('unreadable'); e.name = 'NotReadableError'; throw e; } };
  await ctx.onFileSelect({ files: [file] }, 'enc');
  let threw = null;
  try { await ctx.startEncode(); } catch (e) { threw = e; }
  assertEq(threw, null, 'startEncode does not reject');
  assertEq(elements['encError'].hidden, false, 'error shown');
  assertEq(elements['encError'].textContent, 'errorPrefix', 'the failure is explained');
  assertEq(elements['encBtn'].disabled, false, 'Create code usable again');
  assertEq(elements['progEnc'].style.display, 'none', 'no progress left showing');
});

test('a rejected photo explains itself in #decError; the next accepted photo clears it — final 3', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.toImageData = async () => ({});
  ctx.CimbarPhoto.decode = () => ({ status: 'notLocated' });
  await ctx.addPhoto({});
  assertEq(elements['decError'].hidden, false, 'notLocated shown');
  assertEq(elements['decError'].textContent, 'errNotLocated', 'notLocated reason');
  assert(elements['logDec'].innerHTML.includes('errNotLocated'), 'log line kept');
  ctx.CimbarPhoto.decode = () => okResult(makeFrame({ fileId: 5, seq: 0, total: 3 }));
  await ctx.addPhoto({});
  assertEq(elements['decError'].hidden, true, 'accepted photo clears the error');
  assertEq(elements['decError'].textContent, '', 'emptied');
  // a foreign photo the user chose to keep their session over
  calls.confirmResult = false;
  ctx.CimbarPhoto.decode = () => okResult(makeFrame({ fileId: 6, seq: 0, total: 3 }));
  await ctx.addPhoto({});
  assertEq(elements['decError'].textContent, 'photoWrongFileKept', 'kept-session message shown');
});

test('a photo after the session finished says so in #decError — final 3', async () => {
  const { ctx, elements } = freshPage();
  ctx.toImageData = async () => ({});
  ctx.CimbarPhoto.decode = () => okResult(makeCompletingFrame({ fileId: 7, seq: 0, total: 1 }));
  await ctx.addPhoto({});
  assertEq(ctx.location.hash, '#/receive/done', 'setup: delivered');
  await ctx.addPhoto({});
  assertEq(elements['decError'].hidden, false, 'shown');
  assertEq(elements['decError'].textContent, 'photoAlreadyDone', 'already-done message');
});

test('the scanner closed with ✕ returns to where it was entered from — final 4', async () => {
  for (const [from, want] of [['#/receive/files', '#/receive/files'], ['#/', '#/']]) {
    const { ctx, calls } = freshPage();
    ctx.navigate(from);
    ctx.navigate('#/receive');
    await tick();
    assertEq(calls.liveScans.length, 1, `${from}: scanner started`);
    const pushes = calls.pushes;
    calls.liveScans[0].stop('closed');
    await tick();
    assertEq(ctx.location.hash, want, `entered from ${from}`);
    assertEq(calls.pushes, pushes, `${from}: still no history entry of its own`);
    assertEq(calls.backs || 0, 0, `${from}: no history.back()`);
  }
});

test('Present: a second open is ignored and a double close goes back once — final 5', () => {
  const { ctx, calls } = freshPage();
  ctx.presentDraw = () => {}; ctx.layoutPresent = () => {};
  // A real history.back() is asynchronous: history.state still says
  // cimbarPresent until popstate fires.
  ctx.history.back = function () { calls.backs = (calls.backs || 0) + 1; };
  const state = { frames: [new Uint8Array(1)], bodies: [], fileId: 1, opts: {}, delayMs: 200, repairEnabled: false };
  ctx.openPresentWith(state);
  ctx.openPresentWith(state);
  assertEq(calls.pushes, 1, 're-entry pushes no second entry');
  ctx.requestClosePresent();
  ctx.requestClosePresent();
  assertEq(calls.backs, 1, 'one history.back() per open');
  ctx.closePresent();                                        // popstate lands
  ctx.openPresentWith(state);
  ctx.requestClosePresent();
  assertEq(calls.backs, 2, 'the next open can close again');
});

function stageEncryptedGif(ctx) {
  const data = makeFrameWithPayload(encryptedPayload(), { fileId: 21, seq: 0, total: 1, encrypted: true });
  ctx.GifDecoder = class { decode() { return [{ width: 1, height: 1, imageData: {} }]; } };
  ctx.Cimbar.decodeFrameExact = () => ({ raw: new Uint8Array(1) });
  ctx.Cimbar.decodeRSFrame = () => ({ data, blocksFailed: 0 });
  const gifBytes = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]);
  return ctx.handleDecFile({ name: 'a.gif', size: 8, slice: () => ({ arrayBuffer: async () => gifBytes.buffer }), arrayBuffer: async () => gifBytes.buffer });
}

test('dropping a locked GIF for the scanner drops its pending unlock — final 6', async () => {
  const { ctx } = freshPage();
  await stageEncryptedGif(ctx);
  assertEq(ctx.location.hash, '#/receive/unlock', 'setup: locked GIF asks for the passphrase');
  assertEq(ctx.routeState().needsUnlock, true, 'setup: unlock pending');
  await ctx.openScanner();
  assertEq(ctx.routeState().needsUnlock, false, 'nothing left to unlock');
});

test('"Receive another" clears a staged GIF and its pill — final 7', async () => {
  const { ctx, elements } = freshPage({ camera: false });
  await stageEncryptedGif(ctx);
  assert(elements['pillDec'].classList.contains('show'), 'setup: GIF staged');
  ctx.receiveAnother();
  assert(!elements['pillDec'].classList.contains('show'), 'pill hidden');
  assertEq(ctx.routeState().needsUnlock, false, 'no unlock pending');
  await ctx.startDecode();
  assertEq(elements['decError'].textContent, 'selectGifFirst', 'decFile cleared');
});

// ── Send: Choose photo and the Optimise photo screen (#/send/photo) ──────────
// The real PhotoOptimiser (photo-optimiser.js) and photo-fit.js run; only the
// canvas encoder session is faked. A fake encode embeds its (side, quality) in
// the first three bytes so a test can tell which encode was staged.

const flush = async () => { for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r)); };
const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));
const MB128 = Fmt.SPEC.compression.maxInflatedBytes;
const JPEG_HEAD = [0xFF, 0xD8, 0xFF, 0xE0];
const GIF_HEAD = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
// ftyp box: size 24, major brand heic, minor 0, compatible mif1 heic.
const HEIC_HEAD = [0, 0, 0, 24, ...Buffer.from('ftypheic'), 0, 0, 0, 0, ...Buffer.from('mif1heic')];

function fileOf(name, type, head, size = 300000) {
  const b = new Uint8Array(size);
  for (let i = 0; i < b.length; i++) b[i] = (i * 2654435761) >>> 24;   // incompressible-ish filler
  b.set(head || [], 0);
  return new File([b], name, { type });
}

/** Encoded size model: a function of (side, quality); bytes start with side (u16) and quality. */
function fakeSession({ width = 4000, height = 3000, size = (side, q) => Math.round((side * side * q) / 4000), gate = null } = {}) {
  const s = {
    width, height, closed: 0, encodes: 0,
    async encode(side, q) {
      s.encodes++;
      if (gate) await gate;
      const n = Math.max(3, size(side, q));
      const b = new Uint8Array(n);
      for (let i = 3; i < n; i++) b[i] = (i * 2246822519 + side) >>> 24;
      b[0] = side >> 8; b[1] = side & 255; b[2] = q;
      return b;
    },
    close() { s.closed++; },
  };
  return s;
}
const encodedAs = (bytes) => ({ side: (bytes[0] << 8) | bytes[1], quality: bytes[2] });

/** Hands out the given sessions in order to CanvasJpegSession.open. */
function useSessions(ctx, calls, ...sessions) {
  ctx.CimbarCanvasJpeg.CanvasJpegSession.open = async (blob) => {
    calls.sessionOpens.push(blob);
    const next = sessions.shift();
    if (next instanceof Error) throw next;
    return next;
  };
}

/** t() that shows its params, so a test can read the numbers on screen. */
function showParams(ctx) { ctx.CimbarI18n.t = (k, p) => (p ? `${k} ${JSON.stringify(p)}` : k); }

async function pick(ctx, file, side) {
  await ctx.onFileSelect({ files: [file], value: 'C:\\fakepath\\x' }, side);
  await flush();
}

async function stagedInput(ctx) {
  const input = await ctx.encodeInput();
  return input && { name: input.name, bytes: input.bytes };
}

test('router: entering #/send/photo while a photo is open stays; Back to #/send disposes it', async () => {
  const { ctx, calls } = freshPage();
  const s = fakeSession();
  useSessions(ctx, calls, s);
  ctx.navigate('#/send');
  await pick(ctx, fileOf('IMG_1.jpg', 'image/jpeg', JPEG_HEAD), 'photo');
  assertEq(ctx.location.hash, '#/send/photo', 'Choose photo opens the optimiser screen');
  assertEq(ctx.routeState().hasPendingPhoto, true, 'a photo is pending');
  ctx.location.hash = '#/send'; ctx.renderRoute();   // browser Back
  assertEq(ctx.routeState().hasPendingPhoto, false, 'leaving the screen ends the optimiser');
  assertEq(s.closed, 1, 'its encoder session is closed');
});

test('Choose photo with a JPEG opens the optimiser with that file', async () => {
  const { ctx, calls } = freshPage();
  useSessions(ctx, calls, fakeSession());
  ctx.navigate('#/send');
  const f = fileOf('IMG_1234.jpg', 'image/jpeg', JPEG_HEAD);
  await pick(ctx, f, 'photo');
  assertEq(ctx.location.hash, '#/send/photo', 'route');
  assertEq(calls.sessionOpens.length, 1, 'one encoder session opened');
  assert(calls.sessionOpens[0] === f, 'opened with the picked file itself');
  assertEq(await ctx.encodeInput(), null, 'nothing staged until Continue or Skip');
});

test('Choose photo with GIF bytes stages it as a plain file, no optimiser', async () => {
  const { ctx, elements, calls } = freshPage();
  ctx.navigate('#/send');
  const f = fileOf('anim.jpg', 'image/jpeg', GIF_HEAD, 5000);   // mislabelled: the magic bytes decide
  await pick(ctx, f, 'photo');
  assertEq(calls.sessionOpens.length, 0, 'no optimiser');
  assertEq(ctx.location.hash, '#/send', 'stays on Send');
  assertEq((await stagedInput(ctx)).name, 'anim.jpg', 'staged as picked');
  assertEq(elements['pillEncText'].textContent, 'anim.jpg', 'pill shows it');
});

test('Choose photo: a GIF whose head cannot be read is still never optimised (type or name)', async () => {
  const unreadable = (name, type) => ({
    name, type, size: 5000,
    slice: () => ({ arrayBuffer: async () => { const e = new Error('unreadable'); e.name = 'NotReadableError'; throw e; } }),
    arrayBuffer: async () => new ArrayBuffer(5000),
  });
  for (const f of [unreadable('a.gif', 'image/gif'), unreadable('anim', 'image/gif'), unreadable('b.GIF', '')]) {
    const { ctx, elements, calls } = freshPage();
    useSessions(ctx, calls, fakeSession());
    ctx.navigate('#/send');
    await pick(ctx, f, 'photo');
    assertEq(calls.sessionOpens.length, 0, `${f.name}: no optimiser`);
    assertEq(ctx.location.hash, '#/send', `${f.name}: stays on Send`);
    assertEq(elements['pillEncText'].textContent, f.name, `${f.name}: staged as a plain file`);
  }
});

test('Choose a file and drop: photos open the optimiser, documents and GIFs stage directly', async () => {
  const cases = [
    { f: () => fileOf('photo.png', 'image/png', [0x89, 0x50, 0x4E, 0x47]), optimiser: true },
    { f: () => fileOf('doc.pdf', 'application/pdf', [0x25, 0x50, 0x44, 0x46], 5000), optimiser: false },
    { f: () => fileOf('anim.gif', 'image/gif', GIF_HEAD, 5000), optimiser: false },
  ];
  for (const via of ['choose', 'drop']) {
    for (const c of cases) {
      const { ctx, elements, calls } = freshPage();
      useSessions(ctx, calls, fakeSession());
      ctx.navigate('#/send');
      const f = c.f();
      if (via === 'choose') await pick(ctx, f, 'enc');
      else {
        for (const fn of elements['dropEnc']._listeners.drop) fn({ preventDefault() {}, dataTransfer: { files: [f] } });
        await flush();
      }
      const label = `${via} ${f.name}`;
      assertEq(calls.sessionOpens.length, c.optimiser ? 1 : 0, `${label}: optimiser opened`);
      assertEq(ctx.location.hash, c.optimiser ? '#/send/photo' : '#/send', `${label}: route`);
      const staged = await stagedInput(ctx);
      assertEq(staged ? staged.name : null, c.optimiser ? null : f.name, `${label}: staged`);
    }
  }
});

test('octet-stream .heic via Choose a file opens the optimiser — Review Focus 3', async () => {
  for (const f of [fileOf('IMG_0001.HEIC', 'application/octet-stream', HEIC_HEAD), fileOf('IMG_0002', 'application/octet-stream', HEIC_HEAD)]) {
    const { ctx, calls } = freshPage();
    useSessions(ctx, calls, fakeSession());
    ctx.navigate('#/send');
    await pick(ctx, f, 'enc');
    assertEq(calls.sessionOpens.length, 1, `${f.name}: optimiser opened`);
    assertEq(ctx.location.hash, '#/send/photo', `${f.name}: route`);
  }
  const { ctx, calls } = freshPage();   // the same name with non-HEIF bytes and no extension stays a file
  ctx.navigate('#/send');
  await pick(ctx, fileOf('IMG_0003', 'application/octet-stream', [1, 2, 3, 4], 5000), 'enc');
  assertEq(calls.sessionOpens.length, 0, 'no sniff hit, no optimiser');
});

test('a photo over 128 MB stages directly (Choose a file and Choose photo)', async () => {
  for (const side of ['enc', 'photo']) {
    const { ctx, calls } = freshPage();
    ctx.navigate('#/send');
    const big = { name: 'huge.jpg', type: 'image/jpeg', size: MB128 + 1, slice: () => new Blob([new Uint8Array(JPEG_HEAD)]) };
    await pick(ctx, big, side);
    assertEq(calls.sessionOpens.length, 0, `${side}: no optimiser above 128 MB`);
    assertEq(ctx.location.hash, '#/send', `${side}: stays on Send`);
    const exactly = { name: 'max.jpg', type: 'image/jpeg', size: MB128, slice: () => new Blob([new Uint8Array(JPEG_HEAD)]) };
    useSessions(ctx, calls, fakeSession());
    await pick(ctx, exactly, side);
    assertEq(calls.sessionOpens.length, 1, `${side}: exactly 128 MB still goes to the optimiser`);
  }
});

test('Continue stages the optimised IMG_1234.jpg and returns to #/send in File mode', async () => {
  const { ctx, elements, calls } = freshPage();
  const s = fakeSession();
  useSessions(ctx, calls, s);
  ctx.navigate('#/send');
  ctx.setEncMode('text');
  await pick(ctx, fileOf('IMG_1234.HEIC', 'image/heic', HEIC_HEAD), 'photo');
  assertEq(elements['photoContinueBtn'].disabled, false, 'Continue enabled once the fit is done');
  assertEq(elements['photoContinueBtn'].hidden, false, 'Continue shown');
  assertEq(elements['photoContinueWithBtn'].hidden, true, 'no "Continue with M frames" for a fitting result');
  const frames = Number(elements['photoFrames'].value);
  // The same fit, computed independently: start N from the 640 px / q70 probe.
  const probe = await fakeSession().encode(640, 70);
  assertEq(frames, PhotoFit.framesForFile('IMG_1234.jpg', probe.length, true), 'starting count from the 640/q70 probe');
  const expected = await PhotoFit.fitToBudget(fakeSession(), PhotoFit.photoByteBudget(frames, 'IMG_1234.jpg'));
  ctx.photoContinue();
  assertEq(ctx.location.hash, '#/send', 'back on Send');
  assertEq(elements['encFileField'].style.display, 'block', 'File mode');
  assert(elements['encModeFile'].classList.contains('active'), 'File tab active');
  const staged = await stagedInput(ctx);
  assertEq(staged.name, 'IMG_1234.jpg', 'optimised name');
  assertEq(Buffer.from(staged.bytes).equals(Buffer.from(expected.bytes)), true, 'the fitted JPEG bytes are staged');
  assertEq(s.closed, 1, 'session closed');
  assertEq(ctx.routeState().hasPendingPhoto, false, 'optimiser gone');
});

test('Skip stages the original File untouched', async () => {
  const { ctx, calls } = freshPage();
  useSessions(ctx, calls, fakeSession());
  ctx.navigate('#/send');
  const f = fileOf('IMG_1234.HEIC', 'image/heic', HEIC_HEAD);
  await pick(ctx, f, 'photo');
  ctx.photoSkip();
  assertEq(ctx.location.hash, '#/send', 'back on Send');
  const staged = await stagedInput(ctx);
  assertEq(staged.name, 'IMG_1234.HEIC', 'original name');
  assertEq(Buffer.from(staged.bytes).equals(Buffer.from(await f.arrayBuffer())), true, 'original bytes');
});

test('Back leaves the previously staged file untouched', async () => {
  const { ctx, calls } = freshPage();
  const s = fakeSession();
  useSessions(ctx, calls, s);
  ctx.navigate('#/send');
  await pick(ctx, fileOf('doc.pdf', 'application/pdf', [0x25, 0x50], 5000), 'enc');
  await pick(ctx, fileOf('IMG_1.jpg', 'image/jpeg', JPEG_HEAD), 'photo');
  assertEq(ctx.location.hash, '#/send/photo', 'optimiser open');
  ctx.navigate('#/send');   // the topbar back link
  assertEq((await stagedInput(ctx)).name, 'doc.pdf', 'the earlier file is still staged');
  assertEq(s.closed, 1, 'optimiser disposed');
  ctx.photoContinue(); ctx.photoSkip();   // stray taps after leaving do nothing
  assertEq((await stagedInput(ctx)).name, 'doc.pdf', 'still the earlier file');
});

// Every encode is 30000 bytes except the 640/q70 probe, so N starts at 1 and
// nothing fits until 15 frames: framesForFile('IMG_1234.jpg', 30000, true) = 15.
const unfitSession = () => fakeSession({ size: (side, q) => (side === 640 && q === 70 ? 1000 : 30000) });

test('unfit: "Continue with M frames" re-fits at M through continueAtNeeded, then stages', async () => {
  const { ctx, elements, calls } = freshPage();
  showParams(ctx);
  const s = unfitSession();
  useSessions(ctx, calls, s);
  ctx.navigate('#/send');
  await pick(ctx, fileOf('IMG_1234.jpg', 'image/jpeg', JPEG_HEAD), 'photo');
  assertEq(elements['photoFrames'].value, '1', 'starts at the probe count');
  assertEq(elements['photoNote'].textContent, 'photoDoesNotFit {"frames":1,"needed":15}', 'does-not-fit note');
  assertEq(elements['photoContinueWithBtn'].hidden, false, '"Continue with M frames" shown');
  assertEq(elements['photoContinueWithBtn'].textContent, 'photoContinueWith {"count":15}', 'its label');
  assertEq(elements['photoContinueBtn'].textContent, 'photoContinueAsIs {"count":15}', 'as-is label');
  await ctx.photoContinueAtNeeded();
  assertEq(ctx.location.hash, '#/send', 'back on Send');
  const staged = await stagedInput(ctx);
  assertEq(staged.name, 'IMG_1234.jpg', 'name');
  assertEq(JSON.stringify(encodedAs(staged.bytes)), JSON.stringify({ side: 4000, quality: 95 }), 'the re-fit at 15 frames, not the unfit result');
  assert(elements['pillEncMeta'].textContent.includes('"frames":15'), 'pill estimate shows 15 frames: ' + elements['pillEncMeta'].textContent);
});

test('unfit: "Continue with this image (K frames)" stages the unfit result as it is', async () => {
  const { ctx, calls } = freshPage();
  useSessions(ctx, calls, unfitSession());
  ctx.navigate('#/send');
  await pick(ctx, fileOf('IMG_1234.jpg', 'image/jpeg', JPEG_HEAD), 'photo');
  ctx.photoContinue();
  const staged = await stagedInput(ctx);
  assertEq(JSON.stringify(encodedAs(staged.bytes)), JSON.stringify({ side: 320, quality: 30 }), 'the smallest result, unfit');
  assertEq(staged.bytes.length, 30000, 'its bytes');
});

test('second pick while fitting disposes the first optimiser — Review Focus 2', async () => {
  const { ctx, elements, calls } = freshPage();
  showParams(ctx);
  let release;
  const gate = new Promise((r) => { release = r; });
  const a = fakeSession({ width: 4000, height: 3000, gate });
  const b = fakeSession({ width: 1000, height: 500 });
  useSessions(ctx, calls, a, b);
  ctx.navigate('#/send');
  await pick(ctx, fileOf('first.jpg', 'image/jpeg', JPEG_HEAD), 'photo');
  assertEq(elements['photoContinueBtn'].disabled, true, 'Continue disabled while the first photo is fitting');
  assertEq(a.closed, 0, 'setup: the first session is open, its fit waiting on an encode');
  // No route change in between: only openPhotoOptimiser's own guard can dispose the first.
  ctx.openPhotoOptimiser(fileOf('second.jpg', 'image/jpeg', JPEG_HEAD));
  assertEq(a.closed, 1, 'the first session is closed by the second pick itself');
  assertEq(ctx.location.hash, '#/send/photo', 'still on the optimiser screen');
  await flush();
  const label = elements['photoLabel'].textContent;
  const frames = Number(elements['photoFrames'].value);
  const r = await PhotoFit.fitToBudget(fakeSession({ width: 1000, height: 500 }), PhotoFit.photoByteBudget(frames, 'second.jpg'));
  const d = PhotoOptimiserMod.previewDimensions(1000, 500, r.maxSide);
  assertEq(label, `photoResultLabel ${JSON.stringify({ width: d.width, height: d.height, quality: r.quality, kb: Math.max(1, Math.round(r.bytes.length / 1024)) })}`, 'the second photo\'s result is on screen');
  const encodesBefore = a.encodes;
  release();
  await flush();
  assertEq(elements['photoLabel'].textContent, label, 'the first session\'s late result never reaches the screen');
  assertEq(a.encodes, encodesBefore, 'the stale fit stops at its next encode');
  ctx.photoContinue();
  assertEq((await stagedInput(ctx)).name, 'second.jpg', 'Continue stages the second photo');
});

test('a photo that cannot be read says so; Skip still sends the original — Review Focus 4', async () => {
  for (const [err, key] of [[new ImageDecode.PhotoDecodeError(), 'photoDecodeError'], [new ImageDecode.ImageTooLargeError(), 'photoTooLarge']]) {
    const { ctx, elements, calls } = freshPage();
    useSessions(ctx, calls, err);
    ctx.navigate('#/send');
    await pick(ctx, fileOf('IMG_7.heic', 'image/heic', HEIC_HEAD), 'photo');
    assertEq(elements['photoError'].hidden, false, `${key}: error shown`);
    assertEq(elements['photoError'].textContent, key, `${key}: message`);
    assertEq(elements['photoBusy'].hidden, true, `${key}: no spinner left running`);
    assertEq(elements['photoControls'].hidden, true, `${key}: controls hidden`);
    assertEq(elements['photoContinueBtn'].hidden, true, `${key}: no Continue`);
    ctx.photoSkip();
    assertEq((await stagedInput(ctx)).name, 'IMG_7.heic', `${key}: Skip stages the original`);
  }
});

test('the frame stepper: + steps once on a tap, a typed count re-fits after the debounce', async () => {
  const { ctx, elements, calls } = freshPage();
  showParams(ctx);
  elements['frameDelay'].value = '40';
  useSessions(ctx, calls, fakeSession());
  ctx.navigate('#/send');
  await pick(ctx, fileOf('IMG_1.jpg', 'image/jpeg', JPEG_HEAD), 'photo');
  const n = Number(elements['photoFrames'].value);
  const plus = elements['photoPlus']._listeners;
  plus.pointerdown[0]({ button: 0, pointerId: 1 });
  plus.pointerup[0]({});
  assertEq(elements['photoFrames'].value, String(n + 1), '+ tap');
  assertEq(elements['photoContinueBtn'].disabled, true, 'Continue disabled while the re-fit is pending');
  assertEq(elements['photoTime'].textContent, `photoTransferTime ${JSON.stringify({ frames: n + 1, seconds: ctx.fmtSeconds((n + 1) * 0.4), delay: 400 })}`, 'transfer time at the Send screen\'s frame speed');
  elements['photoFrames'].value = '3';
  ctx.photoFramesTyped();
  assertEq(elements['photoFrames'].value, '3', 'typed count');
  await sleepMs(300); await flush();
  assertEq(elements['photoContinueBtn'].disabled, false, 'fit done');
  ctx.photoContinue();
  const staged = await stagedInput(ctx);
  assert(staged.bytes.length <= PhotoFit.photoByteBudget(3, 'IMG_1.jpg'), 'fits 3 frames');
});

test('the File pill shows "<size> · ≈ <n> frames" with encryption counted', async () => {
  const { ctx, elements } = freshPage();
  showParams(ctx);
  ctx.navigate('#/send');
  // 4160 bytes: 2 frames unencrypted, 3 once the 48-byte envelope is counted.
  await pick(ctx, fileOf('doc.pdf', 'application/pdf', [0x25], 4160), 'enc');
  assertEq(PhotoFit.framesForFile('doc.pdf', 4160, false), 2, 'setup: unencrypted count');
  assertEq(elements['pillEncText'].textContent, 'doc.pdf', 'name');
  assertEq(elements['pillEncMeta'].textContent, `pillEstimate ${JSON.stringify({ size: ctx.fmtBytes(4160), frames: 3 })}`, 'size and encrypted estimate');
  ctx.clearEncFile();
  assertEq(elements['pillEncMeta'].textContent, '', 'cleared with the file');
});

test('frame estimate on pill counts encryption; encoding the optimised file with a passphrase needs ≤ shown frames — Review Focus 5', async () => {
  const NodeCrypto = require('../tools/node_crypto.js');
  const Compress = require('../compress.js');
  const { ctx, elements, calls } = freshPage();
  showParams(ctx);
  useSessions(ctx, calls, fakeSession());
  ctx.navigate('#/send');
  await pick(ctx, fileOf('IMG_1234.jpg', 'image/jpeg', JPEG_HEAD), 'photo');
  const shown = Number(elements['photoFrames'].value);
  ctx.photoContinue();
  const staged = await stagedInput(ctx);
  const estimate = Number(/"frames":(\d+)/.exec(elements['pillEncMeta'].textContent)[1]);
  assert(estimate <= shown, `pill estimate ${estimate} ≤ optimiser's ${shown}`);
  // encodeToGif's framing, with a passphrase typed after Continue.
  const z = await Compress.maybeDeflate(Core.buildPayload(staged.name, staged.bytes));
  const enc = NodeCrypto.encryptBytesNode(z.bytes, 'pass', new Uint8Array(16), new Uint8Array(12));
  const frames = Core.splitIntoFrames(Core.withLengthPrefix(enc), 1, { encrypted: true, compressed: z.compressed }).length;
  assert(frames <= estimate, `encrypted encode needs ${frames} ≤ estimate ${estimate}`);
  assert(frames <= shown, `encrypted encode needs ${frames} ≤ shown ${shown}`);
});

test('updateTextInfo counts with CimbarPhotoFit.framesForFile — same numbers as before', () => {
  const { ctx, elements } = freshPage();
  showParams(ctx);
  const seen = [];
  const real = ctx.CimbarPhotoFit.framesForFile;
  ctx.CimbarPhotoFit.framesForFile = (n, b, e) => { seen.push([n, b, e]); return real(n, b, e); };
  ctx.setEncMode('text');
  for (const len of [1, 2021, 2022, 10000]) {
    elements['textEnc'].value = 'x'.repeat(len);
    ctx.updateTextInfo();
    const old = Math.max(1, Math.ceil((4 + 4 + 27 + len + 48) / Fmt.fileBytesPerFrame()));
    const [name, bytes, encrypted] = seen[seen.length - 1];
    assert(/^message-\d{8}-\d{6}\.txt$/.test(name), 'text message name: ' + name);
    assertEq(bytes, len, 'byte count');
    assertEq(encrypted, true, 'encryption reserved');
    assert(elements['textEncInfo'].textContent.includes(`"frames":${old}`), `${len} bytes: ${elements['textEncInfo'].textContent} (want ${old})`);
  }
});

test('addPhoto decodes through CimbarImageDecode.decodeImage (HEIC in every browser)', async () => {
  const { ctx, elements } = freshPage();
  const seen = [];
  let nativeCalls = 0;
  ctx.CimbarImageDecode.decodeImage = async (blob) => { seen.push(blob); return { width: 20, height: 10, close() {} }; };
  ctx.createImageBitmap = async () => { nativeCalls++; return { width: 20, height: 10, close() {} }; };
  ctx.CimbarPhoto.decode = () => ({ status: 'notLocated' });
  const f = fileOf('shot.heic', 'image/heic', HEIC_HEAD, 100);
  await ctx.addPhoto(f);
  assertEq(seen.length, 1, 'decodeImage called once');
  assert(seen[0] === f, 'with the picked file');
  assertEq(nativeCalls, 0, 'not createImageBitmap directly');
  assertEq(elements['decError'].textContent, 'errNotLocated', 'the decoded pixels went on to the barcode decoder');
  ctx.CimbarImageDecode.decodeImage = async () => { throw new ImageDecode.PhotoDecodeError(); };
  await ctx.addPhoto(f);
  assertEq(elements['decError'].textContent, 'photoCantRead', 'an unreadable photo is explained in the page language');
});

(async () => {
  console.log('\ntest_page_logic.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
