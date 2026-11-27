// The tablet Send screen's live barcode preview: re-encodes 350 ms after the
// last change (text, file or passphrase), loops the source frames at the
// frame delay, never shows a superseded encode, and falls back to the empty
// pane on no input or an encode failure.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/encode/send_jobs.dart';
import 'package:cimbar_scanner/features/send/present_screen.dart';
import 'package:cimbar_scanner/features/send/screen_controls.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';
import 'package:cimbar_scanner/features/send/send_preview.dart';
import 'package:cimbar_scanner/features/send/send_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations_en.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'present_screen_test.dart' show FakeControls;
import 'send_controller_test.dart' show fakePayload;

final l10n = AppLocalizationsEn();

void main() {
  late ui.Image img;

  Future<void> pumpSend(
    WidgetTester tester, {
    Size size = const Size(1032, 1376),
    required Future<EncodedPayload> Function(SendRequest) encode,
    void Function()? onImage,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    img = (await tester.runAsync(() => createTestImage(width: 1, height: 1)))!;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(1))),
        screenControlsProvider.overrideWithValue(FakeControls()),
        sendPreviewIoProvider.overrideWithValue(PreviewIo(encode: encode, toImage: (_) async {
          onImage?.call();
          return img.clone();
        })),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SendScreen(),
      ),
    ));
    await tester.pump();
  }

  /// Past the 350 ms debounce, then lets the encode and image futures land.
  Future<void> settlePreview(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 351));
    await tester.pump();
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('sendText')), text);
    await tester.pump();
  }

  testWidgets('empty input shows the empty pane', (tester) async {
    await pumpSend(tester, encode: (_) async => fakePayload(1));
    expect(find.text(l10n.wideSendEmpty), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('typing shows a preview after the debounce', (tester) async {
    await pumpSend(tester, encode: (_) async => fakePayload(1));
    await type(tester, 'hello');
    await tester.pump(const Duration(milliseconds: 349));
    expect(find.byType(RawImage), findsNothing);
    await settlePreview(tester);
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text(l10n.presentSource(1, 1)), findsOneWidget);
  });

  testWidgets('the frame count matches what Present would send', (tester) async {
    // The real encoder (run inline): an incompressible-enough text that
    // takes several frames, with a passphrase so encryption is counted.
    final text = List.generate(6000, (i) => String.fromCharCode(0x4e00 + (i * 7919) % 20000)).join();
    await pumpSend(tester, encode: (r) async => encodeRequest(r));
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await type(tester, text);
    await settlePreview(tester);
    final real = encodeRequest(SendRequest('message-20000101-000000.txt',
        Uint8List.fromList(const Utf8Encoder().convert(text)), 'pw')).total;
    expect(real, greaterThan(1));
    expect(find.text(l10n.presentSource(1, real)), findsOneWidget);
  });

  testWidgets('passphrase is part of the request, trimmed', (tester) async {
    final seen = <String>[];
    await pumpSend(tester, encode: (r) async {
      seen.add(r.passphrase);
      return fakePayload(1);
    });
    await tester.enterText(find.byType(TextField).at(1), ' pw ');
    await type(tester, 'hello');
    await settlePreview(tester);
    expect(seen.last, 'pw');
  });

  testWidgets('changing the passphrase re-encodes', (tester) async {
    var calls = 0;
    await pumpSend(tester, encode: (r) async {
      calls++;
      return fakePayload(1);
    });
    await type(tester, 'hello');
    await settlePreview(tester);
    final before = calls;
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await settlePreview(tester);
    expect(calls, before + 1);
  });

  testWidgets('stale encode result is dropped', (tester) async {
    final pending = <Completer<EncodedPayload>>[];
    await pumpSend(tester, encode: (_) {
      final c = Completer<EncodedPayload>();
      pending.add(c);
      return c.future;
    });
    await type(tester, 'a');
    await settlePreview(tester);
    await type(tester, 'ab');
    await settlePreview(tester);
    // The first (now stale) encode finishes: it is not shown, and the
    // latest input is encoded next.
    pending[0].complete(fakePayload(5));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.presentSource(1, 5)), findsNothing);
    expect(pending.length, 2);
    pending[1].complete(fakePayload(2));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.presentSource(1, 2)), findsOneWidget);
  });

  testWidgets('superseded encodes run one at a time', (tester) async {
    // A large file must not be copied into several isolates at once.
    final pending = <Completer<EncodedPayload>>[];
    await pumpSend(tester, encode: (_) {
      final c = Completer<EncodedPayload>();
      pending.add(c);
      return c.future;
    });
    for (final t in ['a', 'ab', 'abc', 'abcd']) {
      await type(tester, t);
      await settlePreview(tester);
    }
    expect(pending.length, 1, reason: 'only one encode in flight');
    pending[0].complete(fakePayload(1));
    await tester.pump();
    await tester.pump();
    expect(pending.length, 2, reason: 'one re-run for the latest input, not one per change');
    pending[1].complete(fakePayload(1));
    await tester.pump();
    await tester.pump();
    expect(pending.length, 2);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('over the frame cap shows too large instead of a preview', (tester) async {
    await pumpSend(tester, encode: (_) async => fakePayload(maxSendFrames + 1));
    await type(tester, 'hello');
    await settlePreview(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(find.text(l10n.sendTooLarge(maxSendFrames + 1, maxSendFrames)), findsOneWidget);
  });

  testWidgets('preview pauses under Present', (tester) async {
    var images = 0;
    await pumpSend(tester, encode: (_) async => fakePayload(3), onImage: () => images++);
    await type(tester, 'hello');
    await settlePreview(tester);
    await tester.tap(find.text(l10n.previewFullScreen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PresentScreen), findsOneWidget);
    final before = images;
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(images, before, reason: 'no preview frames rendered while Present covers Send');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clearing input shows the empty pane', (tester) async {
    await pumpSend(tester, encode: (_) async => fakePayload(1));
    await type(tester, 'hello');
    await settlePreview(tester);
    expect(find.byType(RawImage), findsOneWidget);
    await type(tester, '');
    await settlePreview(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(find.text(l10n.wideSendEmpty), findsOneWidget);
  });

  testWidgets('encode failure shows the empty pane', (tester) async {
    await pumpSend(tester, encode: (_) async => throw ArgumentError('too big'));
    await type(tester, 'hello');
    await settlePreview(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(RawImage), findsNothing);
    expect(find.text(l10n.wideSendEmpty), findsOneWidget);
  });

  testWidgets('multi-frame preview loops at the frame delay', (tester) async {
    await pumpSend(tester, encode: (_) async => fakePayload(3));
    await type(tester, 'hello');
    await settlePreview(tester);
    expect(find.text(l10n.presentSource(1, 3)), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text(l10n.presentSource(2, 3)), findsOneWidget);
    // Stop the loop before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the preview opens Present', (tester) async {
    await pumpSend(tester, encode: (_) async => fakePayload(1));
    await type(tester, 'hello');
    await settlePreview(tester);
    await tester.tap(find.byType(RawImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PresentScreen), findsOneWidget);
  });

  testWidgets('dispose mid-encode is quiet', (tester) async {
    final c = Completer<EncodedPayload>();
    await pumpSend(tester, encode: (_) => c.future);
    await type(tester, 'hello');
    await settlePreview(tester);
    await tester.pumpWidget(const SizedBox());
    c.complete(fakePayload(1));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone width has no preview', (tester) async {
    await pumpSend(tester, size: const Size(430, 932), encode: (_) async => fakePayload(1));
    expect(find.byType(SendPreview), findsNothing);
  });
}
