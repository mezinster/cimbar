import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/core/format/text_message.dart';
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

  testWidgets('a text message shows its text, Copy and Share text', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final shared = <String>[];
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('line 1\r\nстрока 2')]);
    await tester.pumpWidget(host(ResultCard(
      result: DecodeResult(filename: 'message-20261001-120000.txt', data: bytes),
      onShareText: shared.add,
    )));
    expect(find.text('line 1\r\nстрока 2'), findsOneWidget);
    expect(find.textContaining('Showing the first'), findsNothing);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, ['line 1\r\nстрока 2'], reason: 'BOM dropped, CRLF kept — Review Focus 1');
    expect(find.text('Copied to clipboard'), findsOneWidget);
    await tester.tap(find.text('Share text'));
    expect(shared, ['line 1\r\nстрока 2']);
  });

  testWidgets('a binary file shows no text view', (tester) async {
    await tester.pumpWidget(host(ResultCard(result: result, onShareText: (_) {})));
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('1 MiB of one long line stays bounded and scrollable — Review Focus 5', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final big = Uint8List(TextMessage.maxBytes)..fillRange(0, TextMessage.maxBytes, 0x41);
    await tester.pumpWidget(host(SingleChildScrollView(child: ResultCard(
      result: DecodeResult(filename: 'big.txt', data: big)))));
    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.byKey(const Key('textResultBody')));
    expect(box.height, lessThanOrEqualTo(320));
    expect(find.textContaining('Showing the first 100000 characters'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied.single.length, TextMessage.maxBytes);
  });

  testWidgets('the text is decoded once per result, not on every rebuild', (tester) async {
    final r = DecodeResult(filename: TextMessage.fileName(DateTime(2026, 10, 1)), data: utf8.encode('hello there'));
    String shown() => tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    await tester.pumpWidget(host(ResultCard(result: r, onShare: () {})));
    final first = shown();
    // A parent rebuild (e.g. a passphrase keystroke) makes a new ResultCard for the same result.
    await tester.pumpWidget(host(ResultCard(result: r, onShare: () {})));
    expect(identical(shown(), first), isTrue, reason: 'decoded again on rebuild');
    // A new result is decoded afresh.
    final r2 = DecodeResult(filename: r.filename, data: utf8.encode('something else'));
    await tester.pumpWidget(host(ResultCard(result: r2, onShare: () {})));
    expect(shown(), 'something else');
  });
}
