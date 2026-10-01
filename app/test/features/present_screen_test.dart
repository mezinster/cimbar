import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/features/send/present_screen.dart';
import 'package:cimbar_scanner/features/send/screen_controls.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';

class FakeControls implements ScreenControls {
  final log = <String>[];
  @override
  Future<void> keepAwake(bool on) async => log.add('awake:$on');
  @override
  Future<void> maxBrightness() async => log.add('max');
  @override
  Future<void> restoreBrightness() async => log.add('restore');
}

// PresentScreen's frame timer re-arms forever, so pumpAndSettle would never
// settle while it runs; route transitions are pumped through explicitly.
// 600 ms covers the test platform's default page transition (450 ms) so a
// popped screen is disposed; opening pumps only 50 ms so the first frame
// ("Frame 1 of N") is still the one showing.
Future<void> pumpTransition(WidgetTester tester,
    [Duration d = const Duration(milliseconds: 600)]) async {
  await tester.pump();
  await tester.pump(d);
}

void main() {
  final p = PayloadEncoder.encode(name: 'n.txt', bytes: Uint8List(5000), allowCompression: false);

  Future<FakeControls> open(WidgetTester tester) async {
    final c = FakeControls();
    // Real decodeImageFromPixels never completes inside the fake-async test
    // zone; make one tiny image outside it and hand out clones.
    final img = (await tester.runAsync(() => createTestImage(width: 1, height: 1)))!;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (ctx) => TextButton(
        onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => PresentScreen(payload: p, delayMs: 100, controls: c,
                toImage: (_) async => img.clone()))),
        child: const Text('go'))),
    ));
    await tester.tap(find.text('go'));
    await pumpTransition(tester, const Duration(milliseconds: 50));
    return c;
  }

  testWidgets('keeps the screen awake and bright while shown, restores on back — Review Focus 4', (tester) async {
    final c = await open(tester);
    expect(c.log, containsAll(['awake:true', 'max']));
    expect(find.textContaining('1'), findsWidgets); // frame counter
    await tester.pageBack();
    await pumpTransition(tester);
    expect(c.log.sublist(c.log.length - 2), containsAll(['awake:false', 'restore']));
  });

  testWidgets('backgrounding pauses and restores; resuming re-applies', (tester) async {
    final c = await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(c.log.last, 'restore');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.log, containsAllInOrder(['restore', 'awake:true', 'max']));
    await tester.pageBack();
    await pumpTransition(tester);
  });

  testWidgets('advances frames on the delay', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('presentCounter')), findsOneWidget);
    final first = (tester.widget(find.byKey(const Key('presentCounter'))) as Text).data;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 50));
    final second = (tester.widget(find.byKey(const Key('presentCounter'))) as Text).data;
    expect(second, isNot(first));
    await tester.pageBack();
    await pumpTransition(tester);
  });
}
