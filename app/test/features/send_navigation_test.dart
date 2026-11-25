// Regression test: the Present screen is full-screen and must be pushed on the
// ROOT navigator, like Live Scan and Photo Capture (camera_navigation_test.dart).
// Pushed on the shell's nested navigator it would float above go_router's
// pages, leaving the tabs visible and dead underneath it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cimbar_scanner/app.dart';
import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/features/import/import_screen.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_provider.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_screen.dart';
import 'package:cimbar_scanner/features/send/present_screen.dart';
import 'package:cimbar_scanner/features/send/screen_controls.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';

import '../support/fake_file_picker.dart';
import '../support/fake_jpeg_session.dart';
import 'present_screen_test.dart' show FakeControls;
import 'send_controller_test.dart' show fakePayload;

void main() {
  testWidgets('Present opens above the tab shell (root navigator)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controls = FakeControls();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(2))),
        screenControlsProvider.overrideWithValue(controls),
      ],
      child: const CimBarApp(),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byKey(const Key('sendText')), 'hello');
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'the Send tab shows the shell');
    await tester.tap(find.text('Present on screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PresentScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'a full-screen Present pushed on the shell navigator would leave the tabs visible and make them dead');
    expect(controls.log, contains('awake:true'), reason: 'the injected screen controls are used');

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PresentScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(controls.log, contains('awake:false'));
  });

  testWidgets('the photo optimiser opens above the tab shell; tabs switch after it closes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final temp = Directory.systemTemp.createTempSync('send_nav_photo');
    addTearDown(() => temp.deleteSync(recursive: true));
    final photo = File('${temp.path}/IMG_5.jpg')..writeAsBytesSync(Uint8List(5000));
    final picker = installFakeFilePicker()..next = [FakePickedFile(photo)];
    // runAsync below lets real platform calls fail; ShareIntake's stream
    // listen would otherwise surface a MissingPluginException.
    const shareStream = EventChannel('com.shoutsocial.share_handler/sharedMediaStream');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(shareStream, MockStreamHandler.inline(onListen: (_, _) {}));
    addTearDown(() => messenger.setMockStreamHandler(shareStream, null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(2))),
        jpegSessionOpenerProvider
            .overrideWithValue((_) async => FakeJpegSession(4000, 3000, size: (s, q) => s * q ~/ 10)),
      ],
      child: const CimBarApp(),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('File'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('sendChoosePhoto')));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(picker.types, isNotEmpty);
    expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'pushed on the shell navigator the optimiser would leave the tabs visible and dead');

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PhotoOptimiserScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byIcon(Icons.gif_box_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ImportScreen), findsOneWidget, reason: 'the tab bar still switches tabs');
  });
}
