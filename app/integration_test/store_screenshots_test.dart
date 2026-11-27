// App Store screenshots: drives the app through its own providers and asks the
// host to take each screenshot with `xcrun simctl io <device> screenshot`, so
// the captures carry the real status bar at full device resolution.
//
// Run through store-screens/capture.sh, which boots the simulators, passes
// SHOT_DIR and takes the screenshots. Run alone, the test still walks every
// screen but takes no pictures.
//
// The app and the host share SHOT_DIR (a simulator app can see the Mac's
// file system): the test writes `req-<name>`, the host takes the screenshot
// and writes `done-<name>`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cimbar_scanner/app.dart';
import 'package:cimbar_scanner/core/encode/gif_writer.dart';
import 'package:cimbar_scanner/core/encode/send_jobs.dart';
import 'package:cimbar_scanner/core/providers/locale_provider.dart';
import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/features/camera/camera_controller.dart';
import 'package:cimbar_scanner/features/send/present_screen.dart';
import 'package:cimbar_scanner/features/send/screen_controls.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shotDir = String.fromEnvironment('SHOT_DIR');
const _locales = String.fromEnvironment('LOCALES', defaultValue: 'en,ru,uk,pl,tr');

/// The demo message shown on Send, encoded, decoded and listed in Files.
const _messages = {
  'en': 'Meet at the north entrance at 18:30. The door code is 4 7 1 9.',
  'ru': 'Встречаемся у северного входа в 18:30. Код двери: 4 7 1 9.',
  'uk': 'Зустрічаємося біля північного входу о 18:30. Код дверей: 4 7 1 9.',
  'pl': 'Spotkajmy się przy północnym wejściu o 18:30. Kod do drzwi: 4 7 1 9.',
  'tr': "18:30'da kuzey girişinde buluşalım. Kapı kodu: 4 7 1 9.",
};

/// A second received file, so the Files list is not a single row.
const _packingList = 'Passport\nCharger\nRain jacket\nTrail snacks\n';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('App Store screenshots', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CimBarApp()));
    await _wait(tester, 1500);

    final router = container.read(routerProvider);
    final send = container.read(sendControllerProvider.notifier);
    final camera = container.read(cameraControllerProvider.notifier);

    for (final code in _locales.split(',')) {
      final message = _messages[code];
      if (message == null) throw ArgumentError('No demo message for locale "$code"');
      final l10n = lookupAppLocalizations(Locale(code));

      container.read(localeProvider.notifier).setLocale(Locale(code));
      await _clearReceivedFiles();
      await _wait(tester, 500);

      // Send: the demo message typed in.
      router.go('/send');
      await _wait(tester, 600);
      send.setMode(SendMode.text);
      await tester.enterText(find.byKey(const Key('sendText')), message);
      FocusManager.instance.primaryFocus?.unfocus();
      await _wait(tester, 900); // keyboard animates away
      await _shot(tester, code, 'send');

      // Present: the barcode full screen, pushed the same way the Send screen does.
      final payload = await send.encode('', cap: maxSendFrames);
      if (payload == null) throw StateError('Encoding the demo message failed');
      final delayMs = container.read(sendControllerProvider).delayMs;
      rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => PresentScreen(
              payload: payload, delayMs: delayMs, controls: container.read(screenControlsProvider))));
      await _wait(tester, 1500);
      await _shot(tester, code, 'present');
      rootNavigatorKey.currentState!.pop();
      await _wait(tester, 800);

      // Decode a second file first, so Files shows two rows.
      send.setMode(SendMode.file);
      send.setFile('packing-list.txt', Uint8List.fromList(utf8.encode(_packingList)));
      final packing = await send.encode('', cap: maxSendFrames);
      camera.setPhoto(buildGif(packing!, 200));
      await camera.decode('');
      send.setMode(SendMode.text);
      send.setText(message);

      // Camera: the empty scanner.
      camera.reset();
      router.go('/camera');
      await _wait(tester, 800);
      await _shot(tester, code, 'camera');

      // Received: the demo message decoded from its barcode GIF.
      camera.setPhoto(buildGif(payload, delayMs));
      await _wait(tester, 300);
      await camera.decode('');
      await _wait(tester, 800);
      final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(position.maxScrollExtent);
      await _wait(tester, 600);
      expect(find.text(l10n.shareFile), findsOneWidget, reason: 'result card should be on screen');
      await _shot(tester, code, 'received');

      // Files: both files, with the newest one's actions menu open.
      router.go('/files');
      await _wait(tester, 1000);
      tester.state<PopupMenuButtonState<String>>(find.byType(PopupMenuButton<String>).first).showButtonMenu();
      await _wait(tester, 800);
      await _shot(tester, code, 'files');
      Navigator.of(tester.element(find.byType(PopupMenuItem<String>).first)).pop();
      await _wait(tester, 600);
    }
  });
}

/// Lets real time pass while frames keep rendering (the framePolicy is fully live).
Future<void> _wait(WidgetTester tester, int ms) async {
  await tester.pump();
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String locale, String screen) async {
  final name = '${locale}__$screen';
  // ignore: avoid_print
  print('STORE_SHOT $name');
  if (_shotDir.isEmpty) return;
  final done = File('$_shotDir/done-$name');
  if (done.existsSync()) done.deleteSync();
  File('$_shotDir/req-$name').writeAsStringSync(name);
  final clock = Stopwatch()..start();
  while (!done.existsSync()) {
    if (clock.elapsed > const Duration(seconds: 30)) {
      throw StateError('The host took no screenshot for $name; is store-screens/capture.sh running?');
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

/// Decoded files are saved in the app's Documents folder: start each language empty.
Future<void> _clearReceivedFiles() async {
  final dir = await getApplicationDocumentsDirectory();
  for (final entry in dir.listSync()) {
    if (entry is File) entry.deleteSync();
  }
}
