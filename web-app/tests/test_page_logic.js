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
const { freshPage, makeFrame, makeCompletingFrame, makeFrameWithPayload, encryptedPayload, okResult, Fmt, Core, RatelessMod } = require('./page_harness');
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
  ctx.onFileSelect({ files: [{ name: 'a.bin', size: 3, arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer }] }, 'enc');
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
  ctx.onFileSelect({ files: [file] }, 'enc');
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
  ctx.onFileSelect({ files: [{ name: 'a.bin', size: 3, arrayBuffer: async () => new ArrayBuffer(3) }] }, 'enc');
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

test('received text is left-aligned (.text-out overrides .output-section centering)', () => {
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

(async () => {
  console.log('\ntest_page_logic.js');
  for (const t of tests) {
    try { await t.fn(); passed++; console.log(`  PASS  ${t.name}`); }
    catch (e) { failed++; console.log(`  FAIL  ${t.name}: ${e.message}`); }
  }
  console.log(`Results: ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
