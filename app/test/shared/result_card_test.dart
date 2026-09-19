import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/core/models/decode_result.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:cimbar_scanner/shared/widgets/result_card.dart';

void main() {
  final result = DecodeResult(filename: 'report.pdf', data: Uint8List(2048));

  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('offers Open, Save to device and Share, each wired to its callback', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(host(ResultCard(
      result: result,
      onOpen: () => calls.add('open'),
      onExport: () => calls.add('export'),
      onShare: () => calls.add('share'),
    )));

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Save to device'), findsOneWidget);
    expect(find.text('Share File'), findsOneWidget);
    expect(find.text('File: report.pdf'), findsOneWidget);
    expect(find.text('Size: 2.0 KB'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.tap(find.text('Save to device'));
    await tester.tap(find.text('Share File'));
    expect(calls, ['open', 'export', 'share']);
  });

  testWidgets('omits a button whose callback is null', (tester) async {
    await tester.pumpWidget(host(ResultCard(result: result, onShare: () {})));
    expect(find.text('Open'), findsNothing);
    expect(find.text('Save to device'), findsNothing);
    expect(find.text('Share File'), findsOneWidget);
  });
}
