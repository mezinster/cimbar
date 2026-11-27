// Tablet layout: the shell swaps its bottom bar for a side rail, and screens
// put their form and result side by side, only on a wide window (at least
// 840 pt across with a shorter side of at least 600 pt). Phones, including a
// Pro Max on its side, keep the phone layout.

import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:cimbar_scanner/shared/widgets/app_shell.dart';
import 'package:cimbar_scanner/shared/widgets/wide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const ipad13 = Size(1032, 1376);
const phone = Size(430, 932);
const phoneLandscape = Size(956, 440);
const ipadMini = Size(744, 1133);

void setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> pumpShell(WidgetTester tester, Size size) async {
  setWindow(tester, size);
  const tabs = ['/send', '/import', '/camera', '/files', '/settings'];
  final router = GoRouter(initialLocation: '/send', routes: [
    ShellRoute(
      builder: (_, _, child) => AppShell(child: child),
      routes: [
        for (final t in tabs) GoRoute(path: t, builder: (_, _) => Text('page $t')),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpBody(WidgetTester tester, Size size) async {
  setWindow(tester, size);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => adaptiveBody(context, right: const Text('right'), children: const [Text('left')]),
      ),
    ),
  ));
}

void main() {
  testWidgets('ipad portrait uses the rail', (tester) async {
    await pumpShell(tester, ipad13);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.text('page /camera'), findsOneWidget);
  });

  testWidgets('phone portrait uses the bottom bar', (tester) async {
    await pumpShell(tester, phone);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('phone landscape stays narrow', (tester) async {
    await pumpShell(tester, phoneLandscape);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('small tablet portrait is narrow', (tester) async {
    await pumpShell(tester, ipadMini);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('adaptiveBody puts two panes side by side on a tablet', (tester) async {
    await pumpBody(tester, ipad13);
    expect(find.byType(TwoPane), findsOneWidget);
    expect(tester.getTopLeft(find.text('right')).dx, greaterThan(tester.getTopLeft(find.text('left')).dx + 400));
  });

  testWidgets('adaptiveBody is one column on a phone', (tester) async {
    await pumpBody(tester, phone);
    expect(find.byType(TwoPane), findsNothing);
    expect(find.text('right'), findsNothing);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.keyboardDismissBehavior, ScrollViewKeyboardDismissBehavior.onDrag);
  });

  testWidgets('rail fits with the keyboard up on a short wide window', (tester) async {
    // iPad mini in landscape counts as wide; a 400-pt keyboard must not
    // squeeze the five labelled rail destinations.
    setWindow(tester, const Size(1133, 744));
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    tester.view.padding = const FakeViewPadding(top: 24);
    const tabs = ['/send', '/import', '/camera', '/files', '/settings'];
    final router = GoRouter(initialLocation: '/send', routes: [
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [for (final t in tabs) GoRoute(path: t, builder: (_, _) => Text('page $t'))],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('left pane narrows at the narrowest wide window', (tester) async {
    // At 840 pt a fixed 440-pt form would leave the result pane narrower
    // than any phone; the right pane must keep at least the form's width.
    await pumpBody(tester, const Size(840, 1000));
    final left = tester.getSize(find.byType(ListView));
    final right = tester.getTopLeft(find.text('right')).dx;
    expect(840 - right, greaterThanOrEqualTo(left.width - 40));
  });

  testWidgets('left pane is 440 pt on a 13-inch iPad', (tester) async {
    await pumpBody(tester, ipad13);
    expect(tester.getSize(find.byType(ListView)).width, 440);
  });
}
