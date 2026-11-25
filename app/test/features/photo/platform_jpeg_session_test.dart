import 'package:cimbar_scanner/features/photo/data/platform_jpeg_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall) h) {
    messenger.setMockMethodCallHandler(photoChannel, (c) {
      calls.add(c);
      return h(c);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(photoChannel, null));

  // SOI, APP1 (EXIF-ish, 4 payload bytes), SOS-less filler, EOI.
  final withApp1 = Uint8List.fromList([
    0xFF, 0xD8, //
    0xFF, 0xE1, 0x00, 0x06, 0x45, 0x78, 0x69, 0x66, //
    0xFF, 0xDB, 0x00, 0x04, 0x00, 0x00, //
    0xFF, 0xD9,
  ]);

  test('open returns the native dimensions', () async {
    mock((c) async => {'id': 3, 'width': 4000, 'height': 3000});
    final s = await PlatformJpegSession.open('/p.jpg');
    expect(s.width, 4000);
    expect(s.height, 3000);
    expect(calls.single.method, 'open');
    expect(calls.single.arguments, {'path': '/p.jpg'});
  });

  test('encode sends id/maxSide/quality and strips metadata', () async {
    mock((c) async {
      if (c.method == 'open') return {'id': 3, 'width': 4000, 'height': 3000};
      return withApp1;
    });
    final s = await PlatformJpegSession.open('/p.jpg');
    final out = await s.encode(maxSide: 640, quality: 70);
    expect(calls.last.arguments, {'id': 3, 'maxSide': 640, 'quality': 70});
    expect(out.length, lessThan(withApp1.length));
    for (var i = 0; i < out.length - 1; i++) {
      expect(out[i] == 0xFF && out[i + 1] == 0xE1, isFalse,
          reason: 'APP1 must be gone');
    }
  });

  test('decode_failed maps to PhotoDecodeException', () async {
    mock((c) async => throw PlatformException(code: 'decode_failed'));
    expect(PlatformJpegSession.open('/x'),
        throwsA(isA<PhotoDecodeException>()));
  });

  test('out_of_memory maps to PhotoMemoryException', () async {
    mock((c) async => throw PlatformException(code: 'out_of_memory'));
    expect(PlatformJpegSession.open('/x'),
        throwsA(isA<PhotoMemoryException>()));
  });

  test('decodePixels sends maxPixels and returns the pixels', () async {
    final rgba = Uint8List.fromList([1, 2, 3, 255]);
    mock((c) async => {'width': 1, 'height': 1, 'rgba': rgba});
    final d = await decodePixels('/x.heic');
    expect(calls.single.method, 'decodePixels');
    expect(calls.single.arguments, {'path': '/x.heic', 'maxPixels': 12000000});
    expect(d.width, 1);
    expect(d.height, 1);
    expect(d.rgba, rgba);
  });

  test('decodePixels maps error codes', () async {
    mock((c) async => throw PlatformException(code: 'decode_failed'));
    expect(decodePixels('/x'), throwsA(isA<PhotoDecodeException>()));
    mock((c) async => throw PlatformException(code: 'out_of_memory'));
    expect(decodePixels('/x'), throwsA(isA<PhotoMemoryException>()));
  });
}
