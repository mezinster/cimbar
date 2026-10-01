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
}
