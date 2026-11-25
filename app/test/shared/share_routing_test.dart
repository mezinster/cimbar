import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/incoming_share.dart';
import 'package:cimbar_scanner/features/photo/data/platform_jpeg_session.dart';
import 'package:cimbar_scanner/shared/widgets/share_routing.dart';

import '../test_utils/synthetic_scene.dart';

DecodedPixels pixelsOf(RgbBuffer b) {
  final out = Uint8List(b.width * b.height * 4);
  for (var i = 0, j = 0; i < b.rgb.length; i += 3, j += 4) {
    out[j] = b.rgb[i];
    out[j + 1] = b.rgb[i + 1];
    out[j + 2] = b.rgb[i + 2];
    out[j + 3] = 255;
  }
  return DecodedPixels(b.width, b.height, out);
}

Uint8List noiseGif(int size) {
  final r = Random(1);
  final im = img.Image(width: size, height: size);
  for (final p in im) {
    p.setRgb(r.nextInt(256), r.nextInt(256), r.nextInt(256));
  }
  return img.encodeGif(im);
}

void main() {
  late Directory tmp;
  late List<String> staged;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('share_routing');
    staged = [];
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  SharedFileItem file(String name, List<int> bytes) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return SharedFileItem(name: name, path: f.path, length: bytes.length);
  }

  /// Copies like the real stager does, recording each call.
  Future<String> stage(SharedFileItem f) async {
    final dest = '${tmp.path}/staged_${staged.length}_${f.name}';
    await File(f.path).copy(dest);
    staged.add(dest);
    return dest;
  }

  Future<DecodedPixels> neverDecode(String path, {int maxPixels = 12000000}) async =>
      fail('the pixel decoder must not run for this item');

  Future<DecodedPixels> blank(String path, {int maxPixels = 12000000}) async =>
      DecodedPixels(200, 200, Uint8List(200 * 200 * 4)..fillRange(0, 200 * 200 * 4, 128));

  final png = File('test/fixtures/crop_frame_1.png').readAsBytesSync();

  test('text goes to Send text mode', () async {
    final r = await routeShare(const SharedText('hello there'), decodePixels: neverDecode, stage: stage);
    expect(r, isA<ToSendText>().having((t) => t.text, 'text', 'hello there'));
    expect(staged, isEmpty);
  });

  test('a CimBar GIF goes to Import', () async {
    final gif = File('../test-data/goldens/hello.gif').readAsBytesSync();
    final r = await routeShare(file('hello.gif', gif), decodePixels: neverDecode, stage: stage);
    expect(r, isA<ToImport>().having((t) => t.name, 'name', 'hello.gif').having((t) => t.bytes, 'bytes', gif));
    expect(staged, isEmpty);
  });

  test('any other GIF is sent as a file', () async {
    final gif = noiseGif(608);
    final r = await routeShare(file('cat.gif', gif), decodePixels: neverDecode, stage: stage);
    expect(r, isA<ToSendFile>().having((t) => t.name, 'name', 'cat.gif').having((t) => t.bytes, 'bytes', gif));
  });

  test('a photo with no barcode goes to the optimiser with the staged copy', () async {
    final r = await routeShare(file('IMG_1.png', png), decodePixels: blank, stage: stage);
    expect(staged, hasLength(1));
    expect(r, isA<ToOptimiser>());
    final photo = (r as ToOptimiser).photo;
    expect(photo.path, staged.single);
    expect(photo.name, 'IMG_1.png');
  });

  test('a photo of a barcode goes to the Camera tab with the decode result', () async {
    final frame = pixelsOf(loadGoldenFrame('hello', 0));
    String? seenPath;
    final r = await routeShare(file('IMG_2.png', png), decodePixels: (p, {int maxPixels = 12000000}) async {
      seenPath = p;
      return frame;
    }, stage: stage);
    expect(seenPath, staged.single, reason: 'detection reads the staged copy');
    expect(r, isA<ToCamera>());
    final c = r as ToCamera;
    expect(c.result.result, isNotNull, reason: '${c.result.error}');
    expect(c.path, staged.single);
    expect(c.bytes, png);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a photo the platform cannot decode goes to the optimiser', () async {
    // JPEG magic and nothing else: a corrupt .jpg.
    final r = await routeShare(file('broken.jpg', [0xFF, 0xD8, 0xFF]),
        decodePixels: (p, {int maxPixels = 12000000}) async => throw const PhotoDecodeException(), stage: stage);
    expect(r, isA<ToOptimiser>().having((t) => t.photo.path, 'path', staged.single));
  });

  test('any other detection failure counts as not a barcode', () async {
    for (final error in <Object>[
      PlatformException(code: 'weird'),
      MissingPluginException('no plugin'),
      StateError('boom'),
    ]) {
      final r = await routeShare(file('IMG_3.png', png),
          decodePixels: (p, {int maxPixels = 12000000}) async => throw error, stage: stage);
      expect(r, isA<ToOptimiser>(), reason: '$error');
    }
  });

  test('a PDF is sent as a file', () async {
    final pdf = '%PDF-1.4\n%âãÏÓ\n1 0 obj\n'.codeUnits;
    final r = await routeShare(file('report.pdf', pdf), decodePixels: neverDecode, stage: stage);
    expect(r, isA<ToSendFile>().having((t) => t.name, 'name', 'report.pdf').having((t) => t.bytes, 'bytes', pdf));
    expect(staged, isEmpty);
  });

  test('a too-large share is reported with its length', () async {
    final r = await routeShare(const ShareTooLarge(length: 999999999), decodePixels: neverDecode, stage: stage);
    expect(r, isA<ShowTooLarge>().having((t) => t.length, 'length', 999999999));
    final unknown = await routeShare(const ShareTooLarge(), decodePixels: neverDecode, stage: stage);
    expect(unknown, isA<ShowTooLarge>().having((t) => t.length, 'length', isNull));
  });

  test('an unreadable share is reported', () async {
    final r = await routeShare(const ShareUnreadable(), decodePixels: neverDecode, stage: stage);
    expect(r, isA<ShowUnreadable>());
  });

  test('a file that vanished before routing is unreadable', () async {
    final r = await routeShare(SharedFileItem(name: 'gone.pdf', path: '${tmp.path}/gone.pdf', length: 10),
        decodePixels: neverDecode, stage: stage);
    expect(r, isA<ShowUnreadable>());
  });

  test('onDetecting fires only for photos', () async {
    var detecting = 0;
    await routeShare(const SharedText('x'), decodePixels: neverDecode, stage: stage, onDetecting: () => detecting++);
    await routeShare(file('a.pdf', '%PDF-1.4'.codeUnits),
        decodePixels: neverDecode, stage: stage, onDetecting: () => detecting++);
    expect(detecting, 0);
    await routeShare(file('IMG_4.png', png), decodePixels: blank, stage: stage, onDetecting: () => detecting++);
    expect(detecting, 1);
  });
}
