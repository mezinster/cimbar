import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:cimbar_scanner/core/encode/cell_grid.dart';
import 'package:cimbar_scanner/core/encode/frame_builder.dart';
import 'package:cimbar_scanner/core/encode/frame_raster.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/photo_decoder.dart';
import 'package:cimbar_scanner/core/services/share_detection.dart';
import 'package:cimbar_scanner/features/photo/data/platform_jpeg_session.dart';
import 'package:cimbar_scanner/features/camera/camera_controller.dart';

import '../test_utils/synthetic_scene.dart';

Uint8List goldenPng() {
  final f = loadGoldenFrame('hello', 0);
  final im = img.Image(width: f.width, height: f.height);
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      final i = (y * f.width + x) * 3;
      im.setPixelRgb(x, y, f.rgb[i], f.rgb[i + 1], f.rgb[i + 2]);
    }
  }
  return img.encodePng(im);
}

/// RGBA of a single-frame barcode encrypted with [passphrase], rendered by
/// the app's own encoder.
DecodedPixels encryptedFramePixels(String passphrase) {
  final p = PayloadEncoder.encode(name: 'secret.txt', bytes: Uint8List.fromList('top secret'.codeUnits), passphrase: passphrase);
  expect(p.total, 1);
  final idx = FrameRaster.render(CellGrid.cells(FrameBuilder.sourceFrame(p, 0)));
  const colors = [...CimbarSpec.palette, [0, 0, 0], [255, 255, 255]];
  final rgba = Uint8List(idx.length * 4);
  for (var i = 0; i < idx.length; i++) {
    final c = colors[idx[i]];
    rgba[i * 4] = c[0];
    rgba[i * 4 + 1] = c[1];
    rgba[i * 4 + 2] = c[2];
    rgba[i * 4 + 3] = 255;
  }
  return DecodedPixels(CimbarSpec.framePx, CimbarSpec.framePx, rgba);
}

Uint8List blankPng() => img.encodePng(img.Image(width: 200, height: 200)..clear(img.ColorRgb8(128, 128, 128)));

/// The fields `decode()` sets, for comparing two controllers.
Map<String, Object?> decodeFields(CameraState s) => {
      'isDecoding': s.isDecoding,
      'filename': s.result?.filename,
      'data': s.result?.data,
      'errorCode': s.errorCode,
      'errorTotal': s.errorTotal,
      'progressState': s.progress?.state,
      'progress': s.progress?.progress,
      'message': s.progress?.message,
      'bytes': s.capturedPhotoBytes,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    docs = Directory.systemTemp.createTempSync('camera_docs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => docs.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    docs.deleteSync(recursive: true);
  });

  test('adoptDetected leaves the state decode() would, and auto-saves the file', () async {
    final png = goldenPng();
    final decoded = CameraController()..setPhoto(png);
    await decoded.decode('');
    expect(decoded.state.result, isNotNull, reason: '${decoded.state.progress?.message}');
    final saved = File('${docs.path}/${decoded.state.result!.filename}');
    expect(saved.existsSync(), isTrue);
    saved.deleteSync();

    final adopted = CameraController();
    await adopted.adoptDetected(png, '/staged/IMG_1.png', await decodePhotoBytes(png, ''));
    expect(decodeFields(adopted.state), decodeFields(decoded.state));
    expect(adopted.state.capturedPhotoPath, '/staged/IMG_1.png');
    expect(adopted.state.fromShare, isTrue);
    expect(decoded.state.fromShare, isFalse);
    expect(saved.readAsBytesSync(), adopted.state.result!.data, reason: 'auto-saved like decode()');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('adoptDetected carries an error outcome like decode()', () async {
    final png = blankPng();
    final decoded = CameraController()..setPhoto(png);
    await decoded.decode('');
    expect(decoded.state.errorCode, 'not_located');

    final adopted = CameraController();
    await adopted.adoptDetected(png, '/staged/x.png', await decodePhotoBytes(png, ''));
    expect(decodeFields(adopted.state), decodeFields(decoded.state));
    expect(docs.listSync(), isEmpty);
  });

  test('a multi_frame outcome keeps its total', () async {
    final c = CameraController();
    await c.adoptDetected(blankPng(), '/p', const PhotoDecodeResult(error: 'spans 5', errorCode: 'multi_frame', total: 5));
    expect(c.state.errorCode, 'multi_frame');
    expect(c.state.errorTotal, 5);
    expect(c.state.result, isNull);
  });

  test('fromShare survives a re-decode and is cleared by a new photo', () async {
    final png = blankPng();
    final c = CameraController();
    await c.adoptDetected(png, '/p', await decodePhotoBytes(png, ''));
    await c.decode('pw');
    expect(c.state.fromShare, isTrue, reason: 'the same shared photo, decoded again with a passphrase');
    c.setPhoto(png);
    expect(c.state.fromShare, isFalse);
    await c.adoptDetected(png, '/p', await decodePhotoBytes(png, ''));
    c.reset();
    expect(c.state.fromShare, isFalse);
  });

  test('a shared photo is re-decoded with the passphrase from native pixels (HEIC), not the image package', () async {
    final px = encryptedFramePixels('pw1');
    final seen = <String>[];
    Future<DecodedPixels> fake(String path, {int maxPixels = 12000000}) async {
      seen.add('$path@$maxPixels');
      return px;
    }

    final detected = await detectSharedPhoto('/staged/IMG_9.heic', fake);
    expect(detected.errorCode, 'passphrase_required');

    // The bytes are HEIC: decodePhotoBytes (the image package) can't read them.
    final heic = Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits, ...List.filled(32, 0)]);
    final c = CameraController(decodePixels: fake);
    await c.adoptDetected(heic, '/staged/IMG_9.heic', detected);
    expect(c.state.errorCode, 'passphrase_required');

    await c.decode('pw1');
    expect(c.state.result, isNotNull, reason: '${c.state.progress?.message}');
    expect(String.fromCharCodes(c.state.result!.data), 'top secret');
    expect(c.state.fromShare, isTrue);
    expect(seen.last, '/staged/IMG_9.heic@12000000');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a shared photo whose native decode throws ends in the generic error state', () async {
    final c = CameraController(
        decodePixels: (p, {int maxPixels = 12000000}) async => throw PlatformException(code: 'weird'));
    await c.adoptDetected(blankPng(), '/staged/x.heic',
        const PhotoDecodeResult(error: 'encrypted', errorCode: 'passphrase_required'));
    await c.decode('pw');
    expect(c.state.isDecoding, isFalse);
    expect(c.state.result, isNull);
    expect(c.state.errorCode, 'unreadable_image');
    expect(c.state.progress?.message, isNotEmpty);
  });

  test('a photo that is not from a share still decodes from its bytes', () async {
    var calls = 0;
    final c = CameraController(decodePixels: (p, {int maxPixels = 12000000}) async {
      calls++;
      throw StateError('must not be called');
    })
      ..setPhoto(goldenPng(), path: '/gallery/x.png');
    await c.decode('');
    expect(c.state.result, isNotNull);
    expect(calls, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the provider wires the pixel decoder from pixelDecoderProvider', () async {
    var calls = 0;
    final container = ProviderContainer(overrides: [
      pixelDecoderProvider.overrideWithValue((p, {int maxPixels = 12000000}) async {
        calls++;
        throw const PhotoDecodeException();
      }),
    ]);
    addTearDown(container.dispose);
    final c = container.read(cameraControllerProvider.notifier);
    await c.adoptDetected(blankPng(), '/staged/y.heic',
        const PhotoDecodeResult(error: 'encrypted', errorCode: 'passphrase_required'));
    await c.decode('pw');
    expect(calls, 1);
    expect(c.state.errorCode, 'unreadable_image');
  });
}
