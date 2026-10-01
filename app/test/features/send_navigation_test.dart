// Regression test: the Present screen is full-screen and must be pushed on the
// ROOT navigator, like Live Scan and Photo Capture (camera_navigation_test.dart).
// Pushed on the shell's nested navigator it would float above go_router's
// pages, leaving the tabs visible and dead underneath it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cimbar_scanner/app.dart';
import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/features/send/present_screen.dart';
import 'package:cimbar_scanner/features/send/screen_controls.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';

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
}
