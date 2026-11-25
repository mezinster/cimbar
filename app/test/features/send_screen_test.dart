import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_provider.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_screen.dart';
import 'package:cimbar_scanner/features/send/send_controller.dart';
import 'package:cimbar_scanner/features/send/send_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';

import '../support/fake_file_picker.dart';
import '../support/fake_jpeg_session.dart';
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
    // Tall enough that the list builds the buttons below the File picker.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
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

  group('photos', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('send_screen_photo'));
    tearDown(() => temp.deleteSync(recursive: true));

    Future<ProviderContainer> pumpSend(WidgetTester tester) async {
      final container = ProviderContainer(overrides: [
        sendControllerProvider.overrideWith((ref) => SendController(encoder: (_) => fakePayload(1))),
        jpegSessionOpenerProvider
            .overrideWithValue((_) async => FakeJpegSession(4000, 3000, size: (s, q) => s * q ~/ 10)),
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
      await tester.tap(find.text('File'));
      await tester.pump();
      return container;
    }

    FakePickedFile picked(String name, int bytes) {
      final f = File('${temp.path}/$name')..writeAsBytesSync(Uint8List(bytes));
      return FakePickedFile(f);
    }

    /// Lets real file I/O finish and the screen push settle.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('File mode shows Choose photo, which picks images into the optimiser', (tester) async {
      final picker = installFakeFilePicker();
      final container = await pumpSend(tester);
      expect(find.byKey(const Key('sendChoosePhoto')), findsOneWidget);
      picker.next = [picked('IMG_9.jpg', 5000)];
      await tester.tap(find.byKey(const Key('sendChoosePhoto')));
      await settle(tester);
      expect(picker.types, [FileType.image]);
      expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
      expect(container.read(pendingPhotoProvider)!.name, 'IMG_9.jpg');
    });

    testWidgets('Text mode has no Choose photo', (tester) async {
      await pumpSend(tester);
      await tester.tap(find.text('Text'));
      await tester.pump();
      expect(find.byKey(const Key('sendChoosePhoto')), findsNothing);
    });

    for (final name in ['IMG_1.heic', 'shot.PNG', 'a.jpeg', 'b.webp', 'c.HEIF', 'd.JPG']) {
      testWidgets('Choose file sends $name to the optimiser', (tester) async {
        final picker = installFakeFilePicker();
        await pumpSend(tester);
        picker.next = [picked(name, 5000)];
        await tester.tap(find.text('Select File'));
        await settle(tester);
        expect(picker.types, [FileType.any]);
        expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
      });
    }

    for (final name in ['anim.gif', 'doc.pdf', 'noext']) {
      testWidgets('Choose file keeps $name as a plain file', (tester) async {
        final picker = installFakeFilePicker();
        final container = await pumpSend(tester);
        picker.next = [picked(name, 5000)];
        await tester.tap(find.text('Select File'));
        await settle(tester);
        expect(find.byType(PhotoOptimiserScreen), findsNothing);
        final send = container.read(sendControllerProvider);
        expect(send.fileName, name);
        expect(send.fileBytes!.length, 5000);
      });
    }
  });
}
