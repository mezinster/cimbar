import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_handler/share_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cimbar_scanner/app.dart';
import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/core/services/incoming_share.dart';
import 'package:cimbar_scanner/features/camera/live_scan_screen.dart';
import 'package:cimbar_scanner/features/import/import_controller.dart';
import 'package:cimbar_scanner/features/camera/camera_controller.dart';
import 'package:cimbar_scanner/features/camera/camera_screen.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/share_detection.dart';
import 'package:cimbar_scanner/features/photo/data/photo_temp.dart';
import 'package:cimbar_scanner/features/photo/data/platform_jpeg_session.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_provider.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_screen.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';
import 'package:cimbar_scanner/features/send/send_screen.dart';
import 'package:flutter/services.dart';

import '../support/fake_jpeg_session.dart';
import '../test_utils/synthetic_scene.dart';

class FakeShareSource implements ShareSource {
  final controller = StreamController<SharedMedia>.broadcast();
  SharedMedia? initial;
  var resets = 0;

  @override
  Future<SharedMedia?> initialMedia() async => initial;
  @override
  Stream<SharedMedia> get mediaStream => controller.stream;
  @override
  Future<void> resetInitialMedia() async {
    resets++;
    initial = null;
  }
}

SharedMedia gifShare(String path) =>
    SharedMedia(attachments: [SharedAttachment(path: path, type: SharedAttachmentType.image)]);

/// A CimBar GIF (the v2 golden); `test_hello.gif` is a v1 GIF, which is not.
final fixture = File('../test-data/goldens/hello.gif').absolute.path;
final v1Gif = File('test/fixtures/test_hello.gif').absolute.path;
final photoFixture = File('test/fixtures/crop_frame_1.png').absolute.path;

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

/// A pixel decoder that "finds" the hello golden frame in any photo.
PixelDecoder barcodeDecoder() {
  final frame = pixelsOf(loadGoldenFrame('hello', 0));
  return (path, {int maxPixels = 12000000}) async => frame;
}

/// A pixel decoder for a photo with no barcode in it.
Future<DecodedPixels> blankDecoder(String path, {int maxPixels = 12000000}) async =>
    DecodedPixels(64, 64, Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 128));

SharedMedia photoShare(String path) =>
    SharedMedia(attachments: [SharedAttachment(path: path, type: SharedAttachmentType.image)]);

/// An [ImportController] that starts mid-decode, as a clean seam for tests
/// that must not start a real decode to reach `isDecoding: true`.
class _DecodingImportController extends ImportController {
  _DecodingImportController() {
    state = const ImportState(
      selectedFileName: 'existing.gif',
      isDecoding: true,
    );
  }
}

/// A [CameraController] that starts mid-decode of a photo.
class _DecodingCameraController extends CameraController {
  _DecodingCameraController() {
    // A real image (the Camera tab renders it), distinct from the shared photoFixture.
    state = CameraState(capturedPhotoBytes: File('test/fixtures/crop_frame_2.png').readAsBytesSync(), isDecoding: true);
  }
}

Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  FakeShareSource source, {
  List<Override> extraOverrides = const [],
  PixelDecoder pixels = blankDecoder,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final temp = Directory.systemTemp.createTempSync('share_intake');
  addTearDown(() => temp.deleteSync(recursive: true));
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    shareSourceProvider.overrideWithValue(source),
    pixelDecoderProvider.overrideWithValue(pixels),
    photoTempDirProvider.overrideWithValue(() async => temp),
    jpegSessionOpenerProvider.overrideWithValue((_) async => FakeJpegSession(4000, 3000, size: (s, q) => s * q ~/ 10)),
    ...extraOverrides,
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CimBarApp()));
  await tester.pump();
  return container;
}

/// Lets real file I/O finish (it cannot complete inside the fake-async zone).
/// A single runAsync/pump pair isn't reliably enough real wall-clock time for
/// the file read to land, so this polls in short real-time slices instead of
/// one fixed wait.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// Like [settleIo], but keeps going (up to ~10 s of real time) until [done]:
/// photo detection runs in a real isolate.
Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('a GIF shared while the app runs is selected on the Import tab', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);
    // Start somewhere else to prove the intake navigates to Import.
    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    await tester.pump(const Duration(milliseconds: 300));

    source.controller.add(gifShare(fixture));
    await settleIo(tester);

    expect(container.read(importControllerProvider).selectedFileName, 'hello.gif');
    expect(find.text('hello.gif'), findsOneWidget);
  });

  testWidgets('a GIF shared on a cold start is picked up once and reset', (tester) async {
    final source = FakeShareSource()..initial = gifShare(fixture);
    final container = await pumpApp(tester, source);
    await settleIo(tester);

    expect(container.read(importControllerProvider).selectedFileName, 'hello.gif');
    expect(source.resets, 1);
  });

  testWidgets('an unreadable share shows a message instead of failing silently', (tester) async {
    final source = FakeShareSource();
    await pumpApp(tester, source);

    source.controller.add(gifShare('/nonexistent/x.gif'));
    await settleIo(tester);

    expect(find.text("Couldn't read the shared item."), findsOneWidget);
  });

  testWidgets('a share while a decode is running shows a message and leaves the file unchanged', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(
      tester,
      source,
      extraOverrides: [importControllerProvider.overrideWith((ref) => _DecodingImportController())],
    );

    source.controller.add(gifShare(fixture));
    await settleIo(tester);

    expect(find.text('Finish the current decode first, then share the file again.'), findsOneWidget);
    expect(container.read(importControllerProvider).selectedFileName, 'existing.gif');
    expect(container.read(importControllerProvider).isDecoding, isTrue);
  });

  testWidgets('sharing while Live Scan is open closes it and shows Import', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);

    // Open the Camera tab, then Live Scan — a full-screen route pushed on
    // the root navigator, above the shell.
    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LiveScanScreen), findsOneWidget);

    source.controller.add(gifShare(fixture));
    await settleIo(tester);
    // Let the pop's exit transition finish (settleIo's own 300ms tail pump
    // lands exactly on the default MaterialPageRoute duration and can leave
    // it mid-transition).
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LiveScanScreen), findsNothing);
    expect(container.read(importControllerProvider).selectedFileName, 'hello.gif');
    expect(find.text('hello.gif'), findsOneWidget);
  });

  testWidgets('a shared barcode photo opens on the Camera tab with its decode, not decoded twice', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source, pixels: barcodeDecoder());

    source.controller.add(photoShare(photoFixture));
    await settleUntil(tester, () => container.read(cameraControllerProvider).capturedPhotoBytes != null);

    final camera = container.read(cameraControllerProvider);
    expect(camera.capturedPhotoBytes, File(photoFixture).readAsBytesSync());
    expect(camera.result, isNotNull, reason: 'the detection result is adopted, not decoded again');
    expect(camera.isDecoding, isFalse);
    expect(camera.fromShare, isTrue);
    expect(container.read(importControllerProvider).selectedFileName, isNull,
        reason: 'a photo must not be loaded as a GIF import');
    expect(find.byType(CameraScreen), findsOneWidget, reason: 'the Camera tab is showing');
  });

  testWidgets('a shared photo without a barcode opens the optimiser above the Send tab', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);

    source.controller.add(photoShare(photoFixture));
    await settleUntil(tester, () => container.read(photoOptimiserOpenProvider));

    expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
    final pending = container.read(pendingPhotoProvider)!;
    expect(pending.name, 'crop_frame_1.png');
    expect(pending.path, isNot(photoFixture), reason: 'the optimiser gets the staged copy');
    expect(File(pending.path).readAsBytesSync(), File(photoFixture).readAsBytesSync());
    expect(File(photoFixture).existsSync(), isTrue, reason: 'a file outside the cache is not deleted');
    expect(container.read(cameraControllerProvider).capturedPhotoBytes, isNull);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SendScreen), findsOneWidget, reason: 'closing the optimiser lands on Send');
  });

  testWidgets('detection that fails unexpectedly still opens the optimiser', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source,
        pixels: (p, {int maxPixels = 12000000}) async => throw MissingPluginException('no photo plugin'));

    source.controller.add(photoShare(photoFixture));
    await settleUntil(tester, () => container.read(photoOptimiserOpenProvider));

    expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
  });

  testWidgets('"Checking shared photo…" shows while detection runs', (tester) async {
    final source = FakeShareSource();
    final gate = Completer<DecodedPixels>();
    final container = await pumpApp(tester, source, pixels: (p, {int maxPixels = 12000000}) => gate.future);

    source.controller.add(photoShare(photoFixture));
    await settleIo(tester);
    expect(find.text('Checking shared photo…'), findsOneWidget);

    gate.complete(await blankDecoder(''));
    await settleUntil(tester, () => container.read(photoOptimiserOpenProvider));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Checking shared photo…'), findsNothing);
  });

  testWidgets('shared text on a cold start lands on Send in Text mode', (tester) async {
    final source = FakeShareSource()..initial = SharedMedia(content: 'https://example.org/page');
    final container = await pumpApp(tester, source);
    await settleIo(tester);

    final send = container.read(sendControllerProvider);
    expect(send.mode, SendMode.text);
    expect(send.text, 'https://example.org/page');
    expect(find.byType(SendScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'https://example.org/page'), findsOneWidget);
    expect(source.resets, 1);
  });

  testWidgets('shared text reaches the text box while Send is already showing', (tester) async {
    final source = FakeShareSource();
    await pumpApp(tester, source);
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    source.controller.add(SharedMedia(content: 'hello from another app'));
    await settleIo(tester);

    expect(find.widgetWithText(TextField, 'hello from another app'), findsOneWidget);
  });

  testWidgets('a GIF that is not a CimBar GIF lands on Send in File mode', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);

    source.controller.add(gifShare(v1Gif));
    await settleIo(tester);

    expect(container.read(importControllerProvider).selectedFileName, isNull);
    final send = container.read(sendControllerProvider);
    expect(send.mode, SendMode.file);
    expect(send.fileName, 'test_hello.gif');
    expect(find.byType(SendScreen), findsOneWidget);
  });

  testWidgets('a shared PDF lands on Send in File mode', (tester) async {
    final source = FakeShareSource();
    final temp = Directory.systemTemp.createTempSync('share_pdf');
    addTearDown(() => temp.deleteSync(recursive: true));
    final pdf = File('${temp.path}/report.pdf')..writeAsBytesSync('%PDF-1.4\n1 0 obj\n'.codeUnits);
    final container = await pumpApp(tester, source);

    source.controller.add(SharedMedia(attachments: [SharedAttachment(path: pdf.path, type: SharedAttachmentType.file)]));
    await settleIo(tester);

    final send = container.read(sendControllerProvider);
    expect(send.mode, SendMode.file);
    expect(send.fileName, 'report.pdf');
    expect(send.fileBytes, pdf.readAsBytesSync());
    expect(find.byType(SendScreen), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('several shared items: the first is used and a SnackBar says so', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);

    source.controller.add(SharedMedia(attachments: [
      SharedAttachment(path: fixture, type: SharedAttachmentType.image),
      SharedAttachment(path: photoFixture, type: SharedAttachmentType.image),
    ]));
    await settleIo(tester);

    expect(container.read(importControllerProvider).selectedFileName, 'hello.gif');
    expect(find.text('Only the first of 2 items is sent'), findsOneWidget);
  });

  testWidgets('a too-large share lands on Send with the size message', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);

    source.controller.add(SharedMedia(attachments: [
      SharedAttachment(path: 'cimbar-too-large:1000000000', type: SharedAttachmentType.video),
    ]));
    await settleIo(tester);

    expect(find.byType(SendScreen), findsOneWidget);
    expect(find.text('File too large: 953.7 MB (limit 128.0 MB).'), findsOneWidget);
    expect(container.read(sendControllerProvider).fileBytes, isNull);
  });

  testWidgets('a too-large share of unknown size names only the limit', (tester) async {
    final source = FakeShareSource();
    await pumpApp(tester, source);

    source.controller.add(SharedMedia(attachments: [
      SharedAttachment(path: 'cimbar-too-large:-1', type: SharedAttachmentType.video),
    ]));
    await settleIo(tester);

    expect(find.text('File too large (limit 128.0 MB).'), findsOneWidget);
  });

  testWidgets('a shared photo while a photo decode runs shows a message and keeps the photo', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(
      tester,
      source,
      extraOverrides: [cameraControllerProvider.overrideWith((ref) => _DecodingCameraController())],
      pixels: barcodeDecoder(),
    );

    source.controller.add(photoShare(photoFixture));
    await settleUntil(tester, () => find.text('Finish the current decode first, then share the file again.').evaluate().isNotEmpty);

    expect(find.text('Finish the current decode first, then share the file again.'), findsOneWidget);
    expect(container.read(cameraControllerProvider).capturedPhotoBytes, File('test/fixtures/crop_frame_2.png').readAsBytesSync());
  });
}
