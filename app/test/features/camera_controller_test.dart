import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:cimbar_scanner/core/services/photo_decoder.dart';
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
}
