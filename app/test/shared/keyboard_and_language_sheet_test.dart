// Three iPhone glitches from TestFlight build 196: the language sheet slid
// under the bottom tab bar, the keyboard could not be put away after pasting
// into Send's multi-line text box, and the language sheet opened behind the
// keyboard.

import 'package:cimbar_scanner/core/providers/locale_provider.dart';
import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';
import 'package:cimbar_scanner/features/send/send_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/send_controller_test.dart' show fakePayload;

void main() {
  final rootKey = GlobalKey<NavigatorState>();

  /// SendScreen inside a nested navigator under a bottom bar, as AppShell
  /// puts every tab.
  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sendControllerProvider.overrideWith(
            (ref) => SendController(encoder: (_) => fakePayload(1)),
          ),
        ],
        child: MaterialApp(
          navigatorKey: rootKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Navigator(
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => const SendScreen()),
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.send), label: 'Tab A'),
                NavigationDestination(icon: Icon(Icons.info), label: 'Tab B'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool textBoxFocused(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('sendText')),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  testWidgets('the language sheet opens above the tab bar', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    final lastRow = find.text('Українська');
    expect(lastRow, findsOneWidget);
    // On the root navigator, so the shell's bottom bar sits below the sheet.
    expect(Navigator.of(tester.element(lastRow)), same(rootKey.currentState));
    // The last row takes the tap: under the bar it would hit the bar instead.
    await tester.tap(lastRow);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SendScreen)),
    );
    expect(container.read(localeProvider), const Locale('uk'));
    expect(find.text('Українська'), findsNothing, reason: 'a pick closes it');
  });

  testWidgets('opening the language sheet puts the keyboard away', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('sendText')));
    await tester.pump();
    expect(textBoxFocused(tester), isTrue);
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    expect(textBoxFocused(tester), isFalse);
  });

  testWidgets('a tap outside the text box puts the keyboard away', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.enterText(find.byKey(const Key('sendText')), 'pasted\ntext');
    await tester.pump();
    expect(textBoxFocused(tester), isTrue);
    await tester.tapAt(tester.getCenter(find.text('Frame delay')));
    await tester.pump();
    expect(textBoxFocused(tester), isFalse);
  });

  testWidgets('dragging the form puts the keyboard away', (tester) async {
    await pumpShell(tester);
    await tester.enterText(find.byKey(const Key('sendText')), 'pasted');
    await tester.pump();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(
      list.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
  });
}
