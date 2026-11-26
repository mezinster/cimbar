import 'dart:io';
import 'dart:typed_data';

import 'package:cimbar_scanner/core/encode/frame_budget.dart';
import 'package:cimbar_scanner/features/photo/data/platform_jpeg_session.dart';
import 'package:cimbar_scanner/features/photo/domain/photo_fit.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_provider.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_screen.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_jpeg_session.dart';

/// 640 px / q70 = 44,800 B: 22 frames under `IMG_1.jpg`.
int bySideAndQuality(int side, int q) => side * q;

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('photo_screen_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// Writes an original of [bytes] bytes and returns it as a pending photo.
  PendingPhoto original(int bytes) {
    final path = '${temp.path}/IMG_1.HEIC';
    File(path).writeAsBytesSync(Uint8List(bytes));
    return PendingPhoto(path: path, name: 'IMG_1.HEIC');
  }

  /// A phone-sized portrait view, so the whole screen is laid out.
  void phoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
  }

  /// A host whose only page has an "open" button calling [openPhotoOptimiser].
  Future<ProviderContainer> pumpHost(
    WidgetTester tester,
    PendingPhoto photo, {
    JpegEncoderSession? session,
  }) async {
    phoneView(tester);
    final s = session ?? FakeJpegSession(4000, 3000, size: bySideAndQuality);
    final container = ProviderContainer(
      overrides: [jpegSessionOpenerProvider.overrideWithValue((_) async => s)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => openPhotoOptimiser(context, ref, photo),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  /// Lets real file I/O finish and the optimiser's debounced fits run.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  /// Types [n] into the frame-count dialog.
  Future<void> typeFrames(WidgetTester tester, int n) async {
    await tester.tap(find.byKey(const Key('photoFrameCount')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '$n');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await settle(tester);
  }

  PhotoOptimiserState st(ProviderContainer c) => c.read(photoOptimiserProvider);

  testWidgets('shows the frame count and the transfer time at the Send delay', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
    expect(c.read(photoOptimiserOpenProvider), isTrue);
    final n = st(c).frames;
    expect(n, framesForFile('IMG_1.jpg', 44800, encrypted: true));
    expect(
      find.descendant(
        of: find.byKey(const Key('photoFrameCount')),
        matching: find.text('$n'),
      ),
      findsOneWidget,
    );
    expect(c.read(sendControllerProvider).delayMs, 200);
    final secs = n * 0.2;
    final shown = secs == secs.roundToDouble()
        ? '${secs.round()}'
        : secs.toStringAsFixed(1);
    expect(find.text('$n frames · ≈ $shown s at 200 ms'), findsOneWidget);

    await typeFrames(tester, 50);
    expect(find.text('50 frames · ≈ 10 s at 200 ms'), findsOneWidget);

    c.read(sendControllerProvider.notifier).setDelay(400);
    await tester.pump();
    expect(find.text('50 frames · ≈ 20 s at 400 ms'), findsOneWidget);
  });

  testWidgets('the Share GIF note appears above 500 frames only', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(2000000));
    await open(tester);
    const note = 'Share GIF holds up to 500 frames; Present only';
    await typeFrames(tester, 501);
    expect(st(c).frames, 501);
    expect(find.text(note), findsOneWidget);
    await typeFrames(tester, 500);
    expect(st(c).frames, 500);
    expect(find.text(note), findsNothing);
  });

  testWidgets('the stepper buttons move the count', (tester) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    final n = st(c).frames;
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(st(c).frames, n + 1);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(st(c).frames, n - 1);
    await settle(tester);
  });

  testWidgets('touching quality switches to manual; Back to auto returns', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    expect(st(c).auto, isTrue);
    expect(find.text('Back to auto'), findsNothing);

    await tester.ensureVisible(find.byType(Slider));
    await tester.tap(find.byType(Slider));
    await settle(tester);
    expect(st(c).auto, isFalse);
    expect(find.text('Back to auto'), findsOneWidget);

    await tester.ensureVisible(find.text('Back to auto'));
    await tester.pump();
    await tester.tap(find.text('Back to auto'));
    await settle(tester);
    expect(st(c).auto, isTrue);
    expect(find.text('Back to auto'), findsNothing);
  });

  testWidgets('a preset chip also switches to manual', (tester) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '320'));
    await tester.tap(find.widgetWithText(ChoiceChip, '320'));
    await settle(tester);
    expect(st(c).auto, isFalse);
    expect(st(c).manualSide, 320);
    expect(find.widgetWithText(ChoiceChip, 'Original'), findsOneWidget);
  });

  testWidgets('unfit shows "does not fit" and only Continue with M frames', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    await typeFrames(tester, 1);
    final s = st(c);
    expect(s.result!.fits, isFalse);
    final needed = s.neededFrames!;
    expect(
      find.text("Doesn't fit in 1 frame — needs at least $needed frames"),
      findsOneWidget,
    );
    expect(find.text('Continue with $needed frames'), findsOneWidget);
    // The image shown needs the same M frames; re-fitting at M sends one at
    // least as good, so a second button would only duplicate the first.
    expect(find.byKey(const Key('photoContinue')), findsNothing);
    expect(find.textContaining('Continue with this image'), findsNothing);
  });

  testWidgets('manual and unfit: still one Continue, at the needed count', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '1920'));
    await tester.tap(find.widgetWithText(ChoiceChip, '1920'));
    await settle(tester);
    await typeFrames(tester, 1);
    final s = st(c);
    expect(s.auto, isFalse);
    expect(s.result!.fits, isFalse);
    expect(find.text('Continue with ${s.neededFrames} frames'), findsOneWidget);
    expect(find.byKey(const Key('photoContinue')), findsNothing);
  });

  testWidgets('Continue with M frames re-fits at M and hands the result over', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    await typeFrames(tester, 1);
    final needed = st(c).neededFrames!;
    await tester.tap(find.text('Continue with $needed frames'));
    await settle(tester);
    expect(find.byType(PhotoOptimiserScreen), findsNothing);
    final send = c.read(sendControllerProvider);
    expect(send.mode, SendMode.file);
    expect(send.fileName, 'IMG_1.jpg');
    expect(
      send.fileBytes!.length,
      lessThanOrEqualTo(photoByteBudget(needed, 'IMG_1.jpg')),
    );
  });

  testWidgets('Continue lands in Send File mode with the optimised JPEG', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    final result = st(c).result!;
    expect(result.fits, isTrue);
    await tester.tap(find.byKey(const Key('photoContinue')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(PhotoOptimiserScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
    final send = c.read(sendControllerProvider);
    expect(send.mode, SendMode.file);
    expect(send.fileName, 'IMG_1.jpg');
    expect(send.fileBytes, same(result.bytes));
    expect(c.read(photoOptimiserOpenProvider), isFalse);
  });

  testWidgets('a double tap on Continue delivers and pops once', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    await tester.tap(find.byKey(const Key('photoContinue')));
    await tester.tap(find.byKey(const Key('photoContinue')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(PhotoOptimiserScreen), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: 'the host stays');
    expect(c.read(sendControllerProvider).fileName, 'IMG_1.jpg');
  });

  testWidgets('Skip lands in Send File mode with the original file', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    await tester.tap(find.byKey(const Key('photoSkip')));
    await tester.pump();
    await settle(tester);
    expect(find.byType(PhotoOptimiserScreen), findsNothing);
    final send = c.read(sendControllerProvider);
    expect(send.mode, SendMode.file);
    expect(send.fileName, 'IMG_1.HEIC');
    expect(send.fileBytes!.length, 200000);
  });

  testWidgets('a photo that cannot be read shows the error and keeps Skip', (
    tester,
  ) async {
    phoneView(tester);
    final photo = original(200000);
    final container = ProviderContainer(
      overrides: [
        jpegSessionOpenerProvider.overrideWithValue(
          (_) async => throw const PhotoDecodeException(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openPhotoOptimiser(context, ref, photo),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await open(tester);
    expect(
      find.text(
        "This photo can't be read. Tap Skip to send the original file.",
      ),
      findsOneWidget,
    );
    final cont = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('photoContinue')),
    );
    expect(cont.onPressed, isNull);
    final skip = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('photoSkip')),
    );
    expect(skip.onPressed, isNotNull);
  });

  testWidgets('opening again while open only replaces the pending photo', (
    tester,
  ) async {
    final c = await pumpHost(tester, original(200000));
    await open(tester);
    final context = tester.element(find.byType(PhotoOptimiserScreen));
    final other = '${temp.path}/IMG_2.PNG';
    File(other).writeAsBytesSync(Uint8List(100000));
    final ref =
        tester.element(find.byType(Consumer, skipOffstage: false)) as WidgetRef;
    await openPhotoOptimiser(
      context,
      ref,
      PendingPhoto(path: other, name: 'IMG_2.PNG'),
    );
    await settle(tester);
    expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
    expect(st(c).outputName, 'IMG_2.jpg');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  group('plurals', () {
    AppLocalizations l(String code) => lookupAppLocalizations(Locale(code));

    test('English', () {
      expect(l('en').photoContinueWith(1), 'Continue with 1 frame');
      expect(l('en').photoContinueWith(12), 'Continue with 12 frames');
      expect(
        l('en').photoDoesNotFit(1, 2),
        "Doesn't fit in 1 frame — needs at least 2 frames",
      );
      expect(
        l('en').photoDoesNotFit(3, 1),
        "Doesn't fit in 3 frames — needs at least 1 frame",
      );
      expect(
        l('en').photoTransferTime(1, 0.2, 200),
        '1 frame · ≈ 0.2 s at 200 ms',
      );
    });

    test('Russian: one / few / many', () {
      expect(l('ru').photoContinueWith(1), 'Продолжить с 1 кадром');
      expect(l('ru').photoContinueWith(3), 'Продолжить с 3 кадрами');
      expect(l('ru').photoContinueWith(21), 'Продолжить с 21 кадром');
      expect(
        l('ru').photoDoesNotFit(1, 2),
        'Не помещается в 1 кадр — нужно минимум 2 кадра',
      );
      expect(
        l('ru').photoDoesNotFit(5, 21),
        'Не помещается в 5 кадров — нужен минимум 21 кадр',
      );
      expect(
        l('ru').photoTransferTime(3, 0.6, 200),
        '3 кадра · ≈ 0,6 с при 200 мс',
      );
    });

    test('Ukrainian: one / few / many', () {
      expect(l('uk').photoContinueWith(1), 'Продовжити з 1 кадром');
      expect(l('uk').photoContinueWith(4), 'Продовжити з 4 кадрами');
      expect(
        l('uk').photoDoesNotFit(2, 11),
        'Не вміщується у 2 кадри — потрібно щонайменше 11 кадрів',
      );
    });

    test('Polish and Belarusian: one / few / many', () {
      expect(l('pl').photoContinueWith(1), 'Kontynuuj z 1 klatką');
      expect(
        l('pl').photoContinueAsIs(22),
        'Kontynuuj z tym obrazem (22 klatki)',
      );
      expect(
        l('pl').photoDoesNotFit(5, 21),
        'Nie mieści się w 5 klatkach — potrzeba co najmniej 21 klatek',
      );
      expect(l('be').photoContinueWith(21), 'Працягнуць з 21 кадрам');
      expect(
        l('be').photoContinueAsIs(3),
        'Працягнуць з гэтай выявай (3 кадры)',
      );
      expect(
        l('be').photoDoesNotFit(1, 11),
        'Не змяшчаецца ў 1 кадр — патрэбна мінімум 11 кадраў',
      );
    });

    test('every locale renders the numbers', () {
      for (final loc in AppLocalizations.supportedLocales) {
        final a = lookupAppLocalizations(loc);
        expect(a.photoContinueWith(17), contains('17'));
        expect(a.photoContinueAsIs(17), contains('17'));
        final fit = a.photoDoesNotFit(4, 9);
        expect(fit, contains('4'), reason: loc.languageCode);
        expect(fit, contains('9'), reason: loc.languageCode);
        expect(a.photoTransferTime(50, 10, 200), contains('50'));
        expect(a.photoGifCapNote(500), contains('500'));
      }
    });
  });
}
