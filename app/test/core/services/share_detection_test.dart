import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';
import 'package:cimbar_scanner/core/services/photo_decoder.dart';
import 'package:cimbar_scanner/core/services/share_detection.dart';
import 'package:cimbar_scanner/features/photo/data/platform_jpeg_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../test_utils/synthetic_scene.dart';

Uint8List noiseGif(int size) {
  final r = Random(1);
  final im = img.Image(width: size, height: size);
  for (final p in im) {
    p.setRgb(r.nextInt(256), r.nextInt(256), r.nextInt(256));
  }
  return img.encodeGif(im);
}

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

Uint8List bytes(List<int> head, [int pad = 16]) =>
    Uint8List.fromList([...head, ...List.filled(pad, 0)]);

void main() {
  group('isCimbarGif', () {
    test('true for a golden', () {
      expect(GifParser.isCimbarGif(File('../test-data/goldens/hello.gif').readAsBytesSync()), isTrue);
    });
    test('false for 608x608 noise', () => expect(GifParser.isCimbarGif(noiseGif(608)), isFalse));
    test('false for 100x100', () => expect(GifParser.isCimbarGif(noiseGif(100)), isFalse));
    test('false for garbage', () => expect(GifParser.isCimbarGif(bytes([1, 2, 3])), isFalse));
  });

  test('sniffKind table', () {
    expect(sniffKind(bytes([0xFF, 0xD8, 0xFF])), ShareKind.image);
    expect(sniffKind(bytes([0x89, 0x50, 0x4E, 0x47])), ShareKind.image);
    expect(sniffKind(bytes('RIFF'.codeUnits + [0, 0, 0, 0] + 'WEBP'.codeUnits)), ShareKind.image);
    expect(sniffKind(bytes('RIFF'.codeUnits + [0, 0, 0, 0] + 'WAVE'.codeUnits)), ShareKind.other);
    for (final b in ['heic', 'heix', 'hevc', 'heim', 'heis', 'mif1', 'msf1']) {
      expect(sniffKind(bytes([0, 0, 0, 24] + 'ftyp'.codeUnits + b.codeUnits)), ShareKind.image, reason: b);
    }
    expect(sniffKind(bytes([0, 0, 0, 24] + 'ftyp'.codeUnits + 'mp42'.codeUnits)), ShareKind.other);
    expect(sniffKind(bytes('GIF89a'.codeUnits)), ShareKind.gif);
    expect(sniffKind(bytes('GIF87a'.codeUnits)), ShareKind.gif);
    expect(sniffKind(bytes([1, 2, 3])), ShareKind.other);
    expect(sniffKind(Uint8List(0)), ShareKind.other);
  });

  group('detectSharedPhoto', () {
    test('PhotoDecodeException -> unreadable_image, not a barcode outcome', () async {
      final r = await detectSharedPhoto('x', (p, {int maxPixels = 12000000}) async => throw const PhotoDecodeException());
      expect(r.errorCode, 'unreadable_image');
      expect(isBarcodeOutcome(r), isFalse);
    });
    test('PhotoMemoryException -> unreadable_image', () async {
      final r = await detectSharedPhoto('x', (p, {int maxPixels = 12000000}) async => throw const PhotoMemoryException());
      expect(r.errorCode, 'unreadable_image');
    });
    test('golden scene decodes; maxPixels is 12 MP', () async {
      int? seen;
      final scene = renderScene(loadGoldenFrame('hello', 0), 1000, 1000, SceneSpec()..scale = 1.3..rotationDeg = 5..centerX = 500..centerY = 500);
      final r = await detectSharedPhoto('x', (p, {int maxPixels = 12000000}) async {
        seen = maxPixels;
        return pixelsOf(scene.image);
      });
      expect(seen, 12000000);
      expect(r.result, isNotNull, reason: '${r.error}');
      expect(isBarcodeOutcome(r), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
    test('blank image -> not_located, not a barcode outcome', () async {
      final r = await detectSharedPhoto('x', (p, {int maxPixels = 12000000}) async =>
          DecodedPixels(200, 200, Uint8List(200 * 200 * 4)..fillRange(0, 200 * 200 * 4, 128)));
      expect(r.errorCode, 'not_located');
      expect(isBarcodeOutcome(r), isFalse);
    });
    test('multi_frame and passphrase_required are barcode outcomes', () {
      expect(isBarcodeOutcome(const PhotoDecodeResult(errorCode: 'multi_frame')), isTrue);
      expect(isBarcodeOutcome(const PhotoDecodeResult(errorCode: 'passphrase_required')), isTrue);
      expect(isBarcodeOutcome(const PhotoDecodeResult(errorCode: 'unsupported_grid')), isFalse);
    });
  });
}
