import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/features/send/send_controller.dart';
import 'package:cimbar_scanner/features/send/send_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';

import 'send_controller_test.dart' show fakePayload;

void main() {
  Widget host() => ProviderScope(
        overrides: [
          sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(1))),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SendScreen(),
        ),
      );

  bool enabled(WidgetTester t, String label) {
    final b = t.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()));
    return b.onPressed != null;
  }

  testWidgets('buttons follow the input; File mode shows the picker', (tester) async {
    await tester.pumpWidget(host());
    expect(enabled(tester, 'Present on screen'), isFalse);
    expect(enabled(tester, 'Share GIF'), isFalse);

    await tester.enterText(find.byKey(const Key('sendText')), 'hi');
    await tester.pump();
    expect(enabled(tester, 'Present on screen'), isTrue);
    expect(enabled(tester, 'Share GIF'), isTrue);

    await tester.tap(find.text('File'));
    await tester.pump();
    expect(find.byKey(const Key('sendText')), findsNothing);
    expect(enabled(tester, 'Present on screen'), isFalse);
    expect(enabled(tester, 'Share GIF'), isFalse);
  });

  testWidgets('the text box is re-seeded from the controller after a tab switch', (tester) async {
    final container = ProviderContainer(overrides: [
      sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(1))),
    ]);
    addTearDown(container.dispose);
    Widget app(Widget child) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child,
          ),
        );
    await tester.pumpWidget(app(const SendScreen()));
    await tester.enterText(find.byKey(const Key('sendText')), 'keep me');
    await tester.pump();
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpWidget(app(const SendScreen()));
    expect(find.text('keep me'), findsOneWidget);
    expect(enabled(tester, 'Present on screen'), isTrue);
    expect(enabled(tester, 'Share GIF'), isTrue);
  });

  testWidgets('a file over the size cap shows a translated hint', (tester) async {
    final container = ProviderContainer(overrides: [
      sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(1))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SendScreen(),
      ),
    ));
    await container.read(sendControllerProvider.notifier)
        .loadFile('movie.mp4', length: () async => 200 * 1024 * 1024, read: () async => Uint8List(0));
    await tester.pump();
    expect(find.text('File too large: 200.0 MB (limit 128.0 MB).'), findsOneWidget);
  });
}
