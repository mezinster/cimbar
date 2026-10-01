import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/encode/send_jobs.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';

EncodedPayload fakePayload(int n) => EncodedPayload(fileId: 1, encrypted: false, compressed: false,
    framedLength: n * 2104, bodies: List.generate(n, (_) => Uint8List(2104)));

void main() {
  test('text mode sends message-….txt with the UTF-8 text as typed', () async {
    SendRequest? seen;
    final c = SendController(encoder: (r) { seen = r; return fakePayload(1); }, now: () => DateTime(2026, 10, 1, 12));
    c.setText('a\r\nб');
    final p = await c.encode('', cap: maxSendFrames);
    expect(p, isNotNull);
    expect(seen!.name, 'message-20261001-120000.txt');
    expect(seen!.bytes, [0x61, 0x0d, 0x0a, 0xd0, 0xb1]);
  });

  test('empty text is refused; whitespace is not', () async {
    final c = SendController(encoder: (_) => fakePayload(1));
    expect(await c.encode('', cap: maxSendFrames), isNull);
    expect(c.state.error, 'empty');
    c.setText(' ');
    expect(await c.encode('', cap: maxSendFrames), isNotNull);
  });

  test('file mode sends the file under its own name', () async {
    SendRequest? seen;
    final c = SendController(encoder: (r) { seen = r; return fakePayload(1); })
      ..setMode(SendMode.file)
      ..setFile('photo.jpg', Uint8List.fromList([1, 2]));
    await c.encode('pw', cap: maxSendFrames);
    expect(seen!.name, 'photo.jpg');
    expect(seen!.passphrase, 'pw');
  });

  test('the passphrase is trimmed like the web app; whitespace-only means unencrypted', () async {
    final seen = <SendRequest>[];
    final c = SendController(encoder: (r) { seen.add(r); return fakePayload(1); })..setText('x');
    await c.encode(' pw ', cap: maxSendFrames);
    await c.encode('   ', cap: maxSendFrames);
    expect(seen.map((r) => r.passphrase), ['pw', '']);
  });

  test('shareGif trims the passphrase too', () async {
    SendRequest? seen;
    final c = SendController(encoder: (r) { seen = r; return fakePayload(1); }, shareGifBytes: (_, __) async {})
      ..setText('x');
    await c.shareGif('\tpw\n');
    expect(seen!.passphrase, 'pw');
  });

  test('caps are checked on the encoded frame count', () async {
    final c = SendController(encoder: (_) => fakePayload(501))..setText('x');
    expect(await c.encode('', cap: maxSendFrames), isNotNull);
    expect(await c.encode('', cap: maxGifFrames), isNull);
    expect(c.state.error, 'tooLarge:501:500');
  });

  test('shareGif hands a GIF named after the input to the sharer', () async {
    String? sharedName;
    final c = SendController(encoder: (_) => fakePayload(1), shareGifBytes: (n, g) async { sharedName = n; },
        now: () => DateTime(2026, 10, 1, 12))..setText('hi');
    await c.shareGif('');
    expect(sharedName, 'message-20261001-120000.gif');
    expect(c.state.busy, isFalse);
  });

  test('an encoder exception becomes an error and keeps the input', () async {
    final c = SendController(encoder: (_) => throw StateError('boom'))..setText('keep me');
    expect(await c.encode('', cap: maxSendFrames), isNull);
    expect(c.state.error, startsWith('failed:'));
    expect(c.state.text, 'keep me');
  });
}
