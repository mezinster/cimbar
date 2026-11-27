// Tablet layout of the decode screens: Import and Camera put the decoded
// result in the right pane (an empty pane until there is one) on a wide
// window, and under the form on a phone; Files and About sit in a centred
// column at most 680 pt wide.

import 'dart:convert';

import 'package:cimbar_scanner/core/models/decode_result.dart';
import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/features/camera/camera_controller.dart';
import 'package:cimbar_scanner/features/camera/camera_screen.dart';
import 'package:cimbar_scanner/features/files/files_controller.dart';
import 'package:cimbar_scanner/features/files/files_screen.dart';
import 'package:cimbar_scanner/features/import/import_controller.dart';
import 'package:cimbar_scanner/features/import/import_screen.dart';
import 'package:cimbar_scanner/features/settings/settings_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations_en.dart';
import 'package:cimbar_scanner/shared/widgets/result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final l10n = AppLocalizationsEn();
const ipad13 = Size(1032, 1376);
const phone = Size(430, 932);
// Narrow but wider than a phone: ResultCard's button row overflows a 430-pt
// window in the test font (wider glyphs than iOS/Android), unrelated to layout.
const narrow = Size(700, 1000);
final result = DecodeResult(filename: 'note.txt', data: utf8.encode('hello'));

class _ImportWithResult extends ImportController {
  _ImportWithResult(DecodeResult? r) {
    state = ImportState(selectedFileName: 'hello.gif', result: r);
  }
}

class _CameraWithResult extends CameraController {
  _CameraWithResult(DecodeResult? r) {
    state = CameraState(result: r);
  }
}

class _StaticFiles extends FilesController {
  _StaticFiles() {
    state = FilesState(files: [
      StoredFile(name: 'note.txt', path: '/tmp/note.txt', sizeBytes: 5, modified: DateTime(2026, 11, 27)),
    ]);
  }
  @override
  Future<void> loadFiles() async {}
}

Future<void> pumpScreen(WidgetTester tester, Size size, Widget screen, List<Override> overrides) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs), ...overrides],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  ));
  await tester.pump();
}

void main() {
  final decodeButton = find.widgetWithText(FilledButton, 'Decode');

  for (final (name, screen, override) in [
    ('import', const ImportScreen(), (DecodeResult? r) => importControllerProvider.overrideWith((ref) => _ImportWithResult(r))),
    ('camera', const CameraScreen(), (DecodeResult? r) => cameraControllerProvider.overrideWith((ref) => _CameraWithResult(r))),
  ]) {
    testWidgets('$name: result in the right pane on a tablet', (tester) async {
      await pumpScreen(tester, ipad13, screen, [override(result)]);
      expect(find.byType(ResultCard), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ResultCard)).dx, greaterThan(440));
      expect(find.text(l10n.wideResultEmpty), findsNothing);
    });

    testWidgets('$name: empty pane on a tablet before a result', (tester) async {
      await pumpScreen(tester, ipad13, screen, [override(null)]);
      expect(find.byType(ResultCard), findsNothing);
      expect(find.text(l10n.wideResultEmpty), findsOneWidget);
    });

    testWidgets('$name: result under the form on a narrow window', (tester) async {
      await pumpScreen(tester, narrow, screen, [override(result)]);
      expect(find.text(l10n.wideResultEmpty), findsNothing);
      expect(tester.getTopLeft(find.byType(ResultCard)).dy, greaterThan(tester.getTopLeft(decodeButton).dy));
      expect(tester.getTopLeft(find.byType(ResultCard)).dx, lessThan(40));
    });
  }

  testWidgets('files list is centred on a tablet', (tester) async {
    await pumpScreen(tester, ipad13, const FilesScreen(), [filesControllerProvider.overrideWith((ref) => _StaticFiles())]);
    expect(tester.getSize(find.byType(ListView)).width, lessThanOrEqualTo(680));
  });

  testWidgets('about is centred on a tablet', (tester) async {
    await pumpScreen(tester, ipad13, const SettingsScreen(), []);
    expect(tester.getSize(find.byType(ListView)).width, lessThanOrEqualTo(680));
  });

  testWidgets('about fills a phone', (tester) async {
    await pumpScreen(tester, phone, const SettingsScreen(), []);
    expect(tester.getSize(find.byType(ListView)).width, phone.width);
  });
}
