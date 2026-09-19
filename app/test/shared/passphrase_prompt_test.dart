import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:cimbar_scanner/shared/widgets/passphrase_prompt.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('submits the typed passphrase via the button and via the keyboard action', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(host(PassphrasePrompt(onSubmit: submitted.add, onCancel: () {})));

    expect(find.text('This file is encrypted. Enter the passphrase to decrypt it.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text('Decrypt'));
    await tester.pump();
    expect(submitted, ['hunter2']);

    await tester.enterText(find.byType(TextField), 'hunter3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, ['hunter2', 'hunter3']);
  });

  testWidgets('shows the wrong-passphrase error and disables Decrypt while busy', (tester) async {
    await tester.pumpWidget(host(PassphrasePrompt(
      errorText: 'Wrong passphrase. Try again.',
      busy: true,
      onSubmit: (_) {},
      onCancel: () {},
    )));
    expect(find.text('Wrong passphrase. Try again.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Decrypt'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Cancel calls onCancel', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(host(PassphrasePrompt(onSubmit: (_) {}, onCancel: () => cancelled = true)));
    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });
}
