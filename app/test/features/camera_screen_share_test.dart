import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/core/models/decode_result.dart';
import 'package:cimbar_scanner/features/camera/camera_controller.dart';
import 'package:cimbar_scanner/features/camera/camera_screen.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_provider.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';

import '../support/fake_jpeg_session.dart';

final photoFixture = File('test/fixtures/crop_frame_1.png').absolute.path;

/// A [CameraController] holding a photo whose decode failed.
class _FailedCameraController extends CameraController {
  _FailedCameraController({required bool fromShare}) {
    state = CameraState(
      capturedPhotoBytes: File(photoFixture).readAsBytesSync(),
      capturedPhotoPath: photoFixture,
      fromShare: fromShare,
      errorCode: 'decode_failed',
      progress: const DecodeProgress(state: DecodeState.error, progress: 1, message: 'RS failed'),
    );
  }
}

Future<ProviderContainer> pumpCamera(WidgetTester tester, {required bool fromShare}) async {
  final container = ProviderContainer(overrides: [
    cameraControllerProvider.overrideWith((ref) => _FailedCameraController(fromShare: fromShare)),
    jpegSessionOpenerProvider.overrideWithValue(
        (_) async => FakeJpegSession(4000, 3000, size: (s, q) => s * q ~/ 10)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CameraScreen(),
    ),
  ));
  await tester.pump();
  return container;
}

void main() {
  testWidgets('a shared photo that failed to decode offers "Send this photo instead"', (tester) async {
    final container = await pumpCamera(tester, fromShare: true);

    final button = find.byKey(const Key('sendPhotoInstead'));
    await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(button);
    await tester.pump();
    expect(find.text('Send this photo instead'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(PhotoOptimiserScreen), findsOneWidget);
    final pending = container.read(pendingPhotoProvider)!;
    expect(pending.path, photoFixture);
    expect(pending.name, isNull);
  });

  testWidgets('a photo taken in the app has no "Send this photo instead"', (tester) async {
    await pumpCamera(tester, fromShare: false);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();

    expect(find.byKey(const Key('sendPhotoInstead')), findsNothing);
  });
}
