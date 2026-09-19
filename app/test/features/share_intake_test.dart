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

final fixture = File('test/fixtures/test_hello.gif').absolute.path;
final photoFixture = File('test/fixtures/crop_frame_1.png').absolute.path;

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
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    shareSourceProvider.overrideWithValue(source),
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

void main() {
  test('firstSharedFile reads a plain path and a file:// path', () async {
    for (final p in [fixture, Uri.file(fixture).toString()]) {
      final r = await firstSharedFile(gifShare(p));
      expect(r.file!.name, 'test_hello.gif');
      expect(r.file!.bytes, File(fixture).readAsBytesSync());
      expect(r.unreadable, isFalse);
    }
  });

  test('firstSharedFile: no attachments is neither a file nor unreadable', () async {
    final r = await firstSharedFile(SharedMedia(attachments: []));
    expect(r.file, isNull);
    expect(r.unreadable, isFalse);
  });

  test('firstSharedFile skips unreadable attachments and reports them', () async {
    final r = await firstSharedFile(gifShare('/nonexistent/x.gif'));
    expect(r.file, isNull);
    expect(r.unreadable, isTrue);
  });

  test('firstSharedFile reports an empty path as unreadable, not a throw', () async {
    final r = await firstSharedFile(gifShare(''));
    expect(r.file, isNull);
    expect(r.unreadable, isTrue);
  });

  test('firstSharedFile reports a malformed file:// URI (authority component) as unreadable, not a throw', () async {
    // Uri.parse(...).toFilePath() throws UnsupportedError for a non-Windows
    // file URI with an authority component.
    final r = await firstSharedFile(gifShare('file://example.com/some/path.gif'));
    expect(r.file, isNull);
    expect(r.unreadable, isTrue);
  });

  testWidgets('a GIF shared while the app runs is selected on the Import tab', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);
    // Start somewhere else to prove the intake navigates to Import.
    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    await tester.pump(const Duration(milliseconds: 300));

    source.controller.add(gifShare(fixture));
    await settleIo(tester);

    expect(container.read(importControllerProvider).selectedFileName, 'test_hello.gif');
    expect(find.text('test_hello.gif'), findsOneWidget);
  });

  testWidgets('a GIF shared on a cold start is picked up once and reset', (tester) async {
    final source = FakeShareSource()..initial = gifShare(fixture);
    final container = await pumpApp(tester, source);
    await settleIo(tester);

    expect(container.read(importControllerProvider).selectedFileName, 'test_hello.gif');
    expect(source.resets, 1);
  });

  testWidgets('an unreadable share shows a message instead of failing silently', (tester) async {
    final source = FakeShareSource();
    await pumpApp(tester, source);

    source.controller.add(gifShare('/nonexistent/x.gif'));
    await settleIo(tester);

    expect(find.text("Couldn't read the shared file. Open it with Import GIF instead."), findsOneWidget);
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
    expect(container.read(importControllerProvider).selectedFileName, 'test_hello.gif');
    expect(find.text('test_hello.gif'), findsOneWidget);
  });

  testWidgets('a shared photo (not a GIF) opens on the Camera tab, ready to decode', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(tester, source);

    source.controller.add(SharedMedia(attachments: [SharedAttachment(path: photoFixture, type: SharedAttachmentType.image)]));
    await settleIo(tester);

    final camera = container.read(cameraControllerProvider);
    expect(camera.capturedPhotoBytes, File(photoFixture).readAsBytesSync());
    expect(container.read(importControllerProvider).selectedFileName, isNull,
        reason: 'a photo must not be loaded as a GIF import');
    expect(find.byType(CameraScreen), findsOneWidget, reason: 'the Camera tab is showing');
    expect(find.byType(Image), findsWidgets, reason: 'with the shared photo previewed');
  });

  testWidgets('a shared photo while a photo decode runs shows a message and keeps the photo', (tester) async {
    final source = FakeShareSource();
    final container = await pumpApp(
      tester,
      source,
      extraOverrides: [cameraControllerProvider.overrideWith((ref) => _DecodingCameraController())],
    );

    source.controller.add(SharedMedia(attachments: [SharedAttachment(path: photoFixture, type: SharedAttachmentType.image)]));
    await settleIo(tester);

    expect(find.text('Finish the current decode first, then share the file again.'), findsOneWidget);
    expect(container.read(cameraControllerProvider).capturedPhotoBytes, File('test/fixtures/crop_frame_2.png').readAsBytesSync());
  });
}
