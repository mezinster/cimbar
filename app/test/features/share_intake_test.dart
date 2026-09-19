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
import 'package:cimbar_scanner/features/import/import_controller.dart';

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

Future<ProviderContainer> pumpApp(WidgetTester tester, FakeShareSource source) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    shareSourceProvider.overrideWithValue(source),
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
}
