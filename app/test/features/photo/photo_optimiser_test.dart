import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cimbar_scanner/core/encode/frame_budget.dart';
import 'package:cimbar_scanner/features/photo/data/platform_jpeg_session.dart';
import 'package:cimbar_scanner/features/photo/domain/photo_fit.dart';
import 'package:cimbar_scanner/features/photo/presentation/photo_optimiser_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_jpeg_session.dart';

int linear(int side, int q) => side * q ~/ 10; // 640 px / q70 = 4,480 B

void main() {
  late Directory temp;
  late String photoPath;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('photo_opt_test');
    photoPath = '${temp.path}/IMG_1.HEIC';
    File(photoPath).writeAsBytesSync(Uint8List(20000));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  PendingPhoto photo() => PendingPhoto(path: photoPath, name: 'IMG_1.HEIC');

  ProviderContainer container({
    Future<JpegEncoderSession> Function(String path)? opener,
    JpegEncoderSession? session,
    PendingPhoto? pending,
  }) {
    final s = session ?? FakeJpegSession(4000, 3000, size: linear);
    final c = ProviderContainer(
      overrides: [
        pendingPhotoProvider.overrideWith((ref) => pending ?? photo()),
        jpegSessionOpenerProvider.overrideWithValue(opener ?? (_) async => s),
      ],
    );
    addTearDown(c.dispose);
    c.listen(photoOptimiserProvider, (_, __) {}); // keeps it alive
    return c;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  PhotoOptimiserNotifier notifier(ProviderContainer c) =>
      c.read(photoOptimiserProvider.notifier);
  PhotoOptimiserState st(ProviderContainer c) => c.read(photoOptimiserProvider);

  test('starting frames match the 640 px / q70 encode, in auto mode', () async {
    final s = FakeJpegSession(4000, 3000, size: linear);
    final c = container(session: s);
    await settle();
    final state = st(c);
    expect(s.calls.first, (maxSide: 640, quality: 70));
    expect(state.outputName, 'IMG_1.jpg');
    expect(
      state.frames,
      framesForFile(state.outputName, linear(640, 70), encrypted: true),
    );
    expect(state.auto, isTrue);
    expect(state.opening, isFalse);
    expect(state.originalBytes, 20000);
    expect(
      state.maxFrames,
      framesForFile('IMG_1.HEIC', 20000, encrypted: true),
    );
    expect(state.result, isNotNull);
    expect(state.canContinue, isTrue);
  });

  test('setFrames clamps to 1 … maxFrames', () async {
    final c = container();
    await settle();
    final max = st(c).maxFrames;
    notifier(c).setFrames(0);
    expect(st(c).frames, 1);
    notifier(c).setFrames(-3);
    expect(st(c).frames, 1);
    notifier(c).setFrames(max + 10);
    expect(st(c).frames, max);
  });

  test(
    'auto result fits the budget; setFrames refits after the debounce',
    () async {
      final c = container();
      await settle();
      notifier(c).setFrames(st(c).maxFrames);
      expect(st(c).fitting, isTrue);
      await settle();
      final state = st(c);
      expect(state.fitting, isFalse);
      expect(state.result!.fits, isTrue);
      expect(
        state.result!.bytes.length,
        lessThanOrEqualTo(photoByteBudget(state.frames, state.outputName)),
      );
      expect(state.neededFrames, isNull);
    },
  );

  test('stepper changes are debounced', () async {
    final s = FakeJpegSession(4000, 3000, size: linear);
    final c = container(session: s);
    await settle();
    final before = s.calls.length;
    final max = st(c).maxFrames;
    notifier(c).setFrames(max);
    notifier(c).setFrames(max - 1);
    notifier(c).setFrames(max);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.calls.length, before, reason: 'nothing fitted yet');
    await settle();
    expect(s.calls.length, greaterThan(before));
  });

  test('hold fits once, on release', () async {
    final s = FakeJpegSession(4000, 3000, size: linear);
    final c = container(session: s);
    await settle();
    final before = s.calls.length;
    notifier(c).beginHold();
    for (var i = 1; i <= 3; i++) {
      notifier(c).setFrames(i + 4);
    }
    await settle();
    expect(s.calls.length, before, reason: 'no fit while held');
    expect(st(c).canContinue, isFalse);
    notifier(c).endHold();
    await settle();
    expect(s.calls.length, greaterThan(before));
    expect(st(c).canContinue, isTrue);
  });

  test(
    'manual mode encodes once at the chosen settings; backToAuto restores',
    () async {
      final c = container();
      await settle();
      notifier(c).setManual(side: 1024, quality: 40);
      await settle();
      expect(st(c).auto, isFalse);
      expect(st(c).result!.maxSide, 1024);
      expect(st(c).result!.quality, 40);
      notifier(c).backToAuto();
      await settle();
      expect(st(c).auto, isTrue);
      expect(st(c).result!.quality, isNot(40));
    },
  );

  test(
    'unfit: neededFrames is M, continueAtNeeded refits and returns bytes',
    () async {
      final big = File(photoPath)..writeAsBytesSync(Uint8List(50000));
      expect(big.lengthSync(), 50000);
      final c = container(
        session: FakeJpegSession(4000, 3000, size: (_, __) => 100000),
      );
      await settle();
      final m = framesForFile(st(c).outputName, 100000, encrypted: true);
      expect(st(c).result!.fits, isFalse);
      expect(st(c).neededFrames, m);
      expect(st(c).frames, st(c).maxFrames);

      final out = await notifier(c).continueAtNeeded();
      expect(out, isNotNull);
      expect(out!.name, 'IMG_1.jpg');
      expect(st(c).frames, m);
      expect(st(c).result!.fits, isTrue);
      expect(
        out.bytes.length,
        lessThanOrEqualTo(photoByteBudget(m, st(c).outputName)),
      );
    },
  );

  test('continueAtNeeded does nothing when the result fits', () async {
    final c = container();
    await settle();
    expect(st(c).result!.fits, isTrue);
    expect(await notifier(c).continueAtNeeded(), isNull);
  });

  test('a count set while opening is kept after open', () async {
    final opened = Completer<JpegEncoderSession>();
    final c = container(opener: (_) => opened.future);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    notifier(c).setFrames(2);
    opened.complete(FakeJpegSession(4000, 3000, size: linear));
    await settle();
    expect(st(c).frames, 2);
    expect(st(c).result, isNotNull, reason: 'fitted for that count');
  });

  test(
    'handingOver is true during continueWithResult; a second call is null',
    () async {
      final c = container();
      await settle();
      final first = notifier(c).continueWithResult();
      expect(st(c).handingOver, isTrue);
      expect(st(c).canContinue, isFalse);
      expect(await notifier(c).continueWithResult(), isNull);
      final out = await first;
      expect(out!.name, 'IMG_1.jpg');
      expect(out.bytes, st(c).result!.bytes);
      expect(st(c).handingOver, isFalse);
    },
  );

  test('a decode failure sets error decode; memory sets memory', () async {
    var c = container(opener: (_) async => throw const PhotoDecodeException());
    await settle();
    expect(st(c).error, 'decode');
    expect(st(c).canContinue, isFalse);
    c = container(opener: (_) async => throw const PhotoMemoryException());
    await settle();
    expect(st(c).error, 'memory');
  });

  test('any other failure sets error failed', () async {
    final c = container(opener: (_) async => throw StateError('boom'));
    await settle();
    expect(st(c).error, 'failed');
  });

  test('skip returns the original path and name', () async {
    final c = container();
    await settle();
    expect(notifier(c).skip(), (path: photoPath, name: 'IMG_1.HEIC'));
  });

  test(
    'replacing the pending photo mid-open closes the first session',
    () async {
      final first = Completer<JpegEncoderSession>();
      final second = FakeJpegSession(4000, 3000, size: linear);
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          jpegSessionOpenerProvider.overrideWithValue(
            (_) => calls++ == 0 ? first.future : Future.value(second),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(pendingPhotoProvider.notifier).state = photo();
      c.listen(photoOptimiserProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      c.read(pendingPhotoProvider.notifier).state = PendingPhoto(
        path: photoPath,
        name: 'other.png',
      );
      await settle();
      expect(st(c).outputName, 'other.jpg');
      expect(st(c).result, isNotNull);

      final stale = FakeJpegSession(4000, 3000, size: linear);
      first.complete(stale);
      await settle();
      expect(stale.closed, isTrue);
      expect(stale.calls, isEmpty, reason: 'never encoded');
      expect(st(c).outputName, 'other.jpg');
    },
  );

  test('closing the provider closes the session', () async {
    final s = FakeJpegSession(4000, 3000, size: linear);
    final c = ProviderContainer(
      overrides: [
        pendingPhotoProvider.overrideWith((ref) => photo()),
        jpegSessionOpenerProvider.overrideWithValue((_) async => s),
      ],
    );
    final sub = c.listen(photoOptimiserProvider, (_, __) {});
    await settle();
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(s.closed, isTrue);
    c.dispose();
  });
}
