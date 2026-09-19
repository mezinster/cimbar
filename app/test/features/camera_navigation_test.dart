// Regression test: Live Scan and Photo Capture are full-screen routes and
// must be pushed on the ROOT navigator. Pushed on the shell's nested
// navigator they float above go_router's pages: tapping a bottom tab then
// switches the route underneath while the scanner keeps covering it — the
// tab highlight moves, nothing else happens (seen on a Pixel 8 Pro after the
// first successful scan).
//
// No camera exists under `flutter test`; both screens catch the plugin
// error and render their error state, which is all this test needs.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cimbar_scanner/app.dart';
import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/features/camera/live_scan_screen.dart';
import 'package:cimbar_scanner/features/camera/photo_capture_screen.dart';

Future<void> pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const CimBarApp(),
  ));
  await tester.pump();
  // Camera tab is the second destination.
  await tester.tap(find.byIcon(Icons.camera_alt_outlined));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('Live Scan opens above the tab shell (root navigator)', (tester) async {
    await pumpApp(tester);
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'camera tab shows the shell');
    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LiveScanScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'a full-screen scanner pushed on the shell navigator would leave the tabs visible and make them dead');
    // Leave the scanner so its isolate and camera teardown run.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LiveScanScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Photo Capture opens above the tab shell (root navigator)', (tester) async {
    await pumpApp(tester);
    // The selected Camera tab also shows camera_alt; target the button.
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.camera_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PhotoCaptureScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PhotoCaptureScreen), findsNothing);
  });
}
