import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/encode/frame_budget.dart';
import '../../../core/encode/send_jobs.dart';
import '../data/platform_jpeg_session.dart';
import '../domain/optimised_file_name.dart';
import '../domain/photo_fit.dart';

/// A photo waiting for the optimiser. [name] is null when the source gave none.
class PendingPhoto {
  const PendingPhoto({required this.path, this.name});

  final String path;
  final String? name;
}

/// Set by whoever hands a photo to the optimiser, before it opens the screen.
final pendingPhotoProvider = StateProvider<PendingPhoto?>((_) => null);

/// Opens an encoder session for a file; overridable in tests.
final jpegSessionOpenerProvider =
    Provider<Future<JpegEncoderSession> Function(String path)>(
      (_) => PlatformJpegSession.open,
    );

/// Stepper and slider changes wait this long before re-fitting.
const photoRefitDebounce = Duration(milliseconds: 250);

class PhotoOptimiserState {
  const PhotoOptimiserState({
    required this.outputName,
    this.opening = true,
    this.fitting = false,
    this.frames = 1,
    this.maxFrames = maxSendFrames,
    this.auto = true,
    this.manualSide,
    this.manualQuality,
    this.result,
    this.neededFrames,
    this.width = 0,
    this.height = 0,
    this.originalBytes = 0,
    this.error,
    this.handingOver = false,
  });

  /// True until the photo is decoded and the starting count is known.
  final bool opening;

  /// True while a re-fit is pending or running.
  final bool fitting;

  /// The frame count the photo is fitted into.
  final int frames;

  /// The stepper's upper bound: the original's frame count, held to
  /// [maxSendFrames].
  final int maxFrames;
  final bool auto;
  final int? manualSide;
  final int? manualQuality;
  final PhotoFitResult? result;

  /// Smallest frame count whose budget fits [result]; set only when it does
  /// not fit at [frames].
  final int? neededFrames;

  /// Name the optimised file is sent under.
  final String outputName;

  /// Source dimensions after orientation; 0 until the session is open.
  final int width;
  final int height;

  /// Size of the original file in bytes; 0 until it has been read.
  final int originalBytes;

  /// `'decode'`, `'memory'`, `'failed'` or null.
  final String? error;

  /// True while the result is being handed over; Continue is disabled.
  final bool handingOver;

  int get longestSide => math.max(width, height);

  bool get canContinue =>
      !opening && !fitting && !handingOver && error == null && result != null;

  PhotoOptimiserState copyWith({
    bool? opening,
    bool? fitting,
    int? frames,
    int? maxFrames,
    bool? auto,
    int? manualSide,
    int? manualQuality,
    PhotoFitResult? result,
    int? neededFrames,
    bool clearResult = false,
    bool clearNeeded = false,
    int? width,
    int? height,
    int? originalBytes,
    String? error,
    bool? handingOver,
  }) => PhotoOptimiserState(
    outputName: outputName,
    opening: opening ?? this.opening,
    fitting: fitting ?? this.fitting,
    frames: frames ?? this.frames,
    maxFrames: maxFrames ?? this.maxFrames,
    auto: auto ?? this.auto,
    manualSide: manualSide ?? this.manualSide,
    manualQuality: manualQuality ?? this.manualQuality,
    result: clearResult ? null : result ?? this.result,
    neededFrames: clearResult || clearNeeded
        ? null
        : neededFrames ?? this.neededFrames,
    width: width ?? this.width,
    height: height ?? this.height,
    originalBytes: originalBytes ?? this.originalBytes,
    error: error ?? this.error,
    handingOver: handingOver ?? this.handingOver,
  );
}

/// Thrown inside a fit that a newer request has superseded.
class _Stale implements Exception {
  const _Stale();
}

/// Aborts a running fit as soon as it is no longer the latest request, so a
/// superseded search stops at its next encode instead of running to the end.
class _GuardedSession implements JpegEncoderSession {
  _GuardedSession(this._inner, this._current);

  final JpegEncoderSession _inner;
  final bool Function() _current;

  @override
  int get width => _inner.width;
  @override
  int get height => _inner.height;

  @override
  Future<Uint8List> encode({required int maxSide, required int quality}) async {
    if (!_current()) throw const _Stale();
    final bytes = await _inner.encode(maxSide: maxSide, quality: quality);
    if (!_current()) throw const _Stale();
    return bytes;
  }

  @override
  Future<void> close() async {} // the notifier owns the real session
}

String _basename(String path) {
  final i = math.max(path.lastIndexOf('/'), path.lastIndexOf(r'\'));
  return i < 0 ? path : path.substring(i + 1);
}

class PhotoOptimiserNotifier extends StateNotifier<PhotoOptimiserState> {
  PhotoOptimiserNotifier(this._ref, this._photo)
    : super(
        PhotoOptimiserState(
          outputName: optimisedFileName(
            _photo.name == null ? null : _basename(_photo.name!),
            DateTime.now(),
          ),
        ),
      ) {
    _open();
  }

  final Ref _ref;
  final PendingPhoto _photo;

  JpegEncoderSession? _session;
  bool _disposed = false;
  Timer? _debounce;
  bool _holding = false;
  bool _framesChosen = false;
  int _gen = 0;
  Future<void> _chain = Future<void>.value();
  final Map<int, PhotoFitResult> _autoFits = {};

  String get _originalName => _photo.name ?? _basename(_photo.path);

  int _framesFor(int bytes) =>
      framesForFile(state.outputName, bytes, encrypted: true);

  Future<void> _open() async {
    try {
      final open = _ref.read(jpegSessionOpenerProvider);
      final length = await File(_photo.path).length();
      if (_disposed) return;
      final maxFrames = math.min(
        framesForFile(_originalName, length, encrypted: true),
        maxSendFrames,
      );
      state = state.copyWith(
        originalBytes: length,
        maxFrames: maxFrames,
        frames: state.frames.clamp(1, maxFrames),
      );
      final s = await open(_photo.path);
      if (_disposed) {
        _closeQuietly(s);
        return;
      }
      _session = s;
      final longest = math.max(s.width, s.height);
      final probe = await s.encode(
        maxSide: math.min(640, longest),
        quality: 70,
      );
      if (_disposed) return;
      state = state.copyWith(
        opening: false,
        width: s.width,
        height: s.height,
        // The starting count is a suggestion: a count the user already set
        // while the photo was opening stands.
        frames: _framesChosen
            ? null
            : _framesFor(probe.length).clamp(1, state.maxFrames),
      );
      _schedule(now: true);
    } catch (e) {
      if (!_disposed) _fail(e);
    }
  }

  void setFrames(int n) {
    _framesChosen = true;
    final frames = n.clamp(1, state.maxFrames);
    if (frames == state.frames) return;
    state = state.copyWith(frames: frames);
    _schedule();
  }

  /// A held stepper: [setFrames] moves the count on screen but fits nothing
  /// until [endHold], so a long hold costs one fit, not one per step.
  void beginHold() {
    _holding = true;
    _debounce?.cancel();
    _gen++; // a fit already under way is stale now
    if (_session != null && state.error == null) {
      state = state.copyWith(fitting: true);
    }
  }

  /// Safe after dispose: a repeat button may call it from a microtask that
  /// lands after the screen (and this notifier) went away.
  void endHold() {
    if (_disposed || !_holding) return;
    _holding = false;
    _schedule();
  }

  /// Switches to manual mode, starting from the current result's settings.
  void setManual({int? side, int? quality}) {
    if (state.error != null || _session == null) return;
    state = state.copyWith(
      auto: false,
      manualSide:
          side ??
          (!state.auto ? state.manualSide : null) ??
          state.result?.maxSide ??
          state.longestSide,
      manualQuality:
          quality ??
          (!state.auto ? state.manualQuality : null) ??
          state.result?.quality ??
          70,
    );
    _schedule(now: quality == null);
  }

  void backToAuto() {
    if (state.auto) return;
    state = state.copyWith(auto: true);
    _schedule(now: true);
  }

  /// Hands the optimised JPEG over in memory. Null when Continue is not
  /// available (still fitting, failed, or a hand-over already running).
  Future<({String name, Uint8List bytes})?> continueWithResult() async {
    final r = state.result;
    if (!state.canContinue || r == null) return null;
    // Disabled while handing over, so a second tap cannot deliver twice.
    state = state.copyWith(handingOver: true);
    await Future<void>.delayed(Duration.zero);
    if (_disposed) return null;
    state = state.copyWith(handingOver: false);
    return (name: state.outputName, bytes: r.bytes);
  }

  /// "Continue with N frames", offered when the result does not fit: moves the
  /// count to [PhotoOptimiserState.neededFrames], re-fits at once (auto may
  /// find a better image that still fits; manual keeps its side and quality)
  /// and, if that fits, hands it over. The count may pass [maxFrames] for
  /// this, never [maxSendFrames]. Null when it could not continue.
  Future<({String name, Uint8List bytes})?> continueAtNeeded() async {
    final st = state;
    final needed = st.neededFrames;
    final r = st.result;
    if (_disposed ||
        !st.canContinue ||
        r == null ||
        r.fits ||
        needed == null ||
        _session == null) {
      return null;
    }
    final frames = math.max(1, math.min(needed, maxSendFrames));
    _framesChosen = true;
    final gen = ++_gen;
    _debounce?.cancel();
    state = state.copyWith(frames: frames, fitting: true);
    await (_chain = _chain.then((_) => _fit(gen)));
    if (!_isCurrent(gen)) return null;
    final after = state;
    if (!after.canContinue || after.frames != frames || !after.result!.fits) {
      return null;
    }
    return continueWithResult();
  }

  /// The original file, untouched.
  ({String path, String name}) skip() =>
      (path: _photo.path, name: _originalName);

  void _schedule({bool now = false}) {
    if (_session == null || state.error != null) return;
    final gen = ++_gen;
    _debounce?.cancel();
    state = state.copyWith(fitting: true);
    if (_holding) return; // endHold schedules the fit
    void run() => _chain = _chain.then((_) => _fit(gen));
    if (now) {
      run();
    } else {
      _debounce = Timer(photoRefitDebounce, run);
    }
  }

  bool _isCurrent(int gen) => gen == _gen && !_disposed;

  Future<void> _fit(int gen) async {
    final s = _session;
    if (s == null || !_isCurrent(gen)) return;
    final st = state;
    final budget = photoByteBudget(st.frames, st.outputName);
    final guarded = _GuardedSession(s, () => _isCurrent(gen));
    try {
      final PhotoFitResult r;
      if (st.auto) {
        r = _autoFits[st.frames] ??= await fitToBudget(guarded, budget);
      } else {
        r = await encodeManual(
          guarded,
          maxSide: st.manualSide!,
          quality: st.manualQuality!,
          budgetBytes: budget,
        );
      }
      if (!_isCurrent(gen)) return;
      state = state.copyWith(
        result: r,
        neededFrames: r.fits ? null : _framesFor(r.bytes.length),
        clearNeeded: r.fits,
        fitting: false,
      );
    } on _Stale {
      return;
    } catch (e) {
      if (_isCurrent(gen)) _fail(e);
    }
  }

  void _fail(Object e) {
    state = state.copyWith(
      error: e is PhotoMemoryException
          ? 'memory'
          : e is PhotoDecodeException
          ? 'decode'
          : 'failed',
      opening: false,
      fitting: false,
      clearResult: true,
    );
  }

  void _closeQuietly(JpegEncoderSession s) {
    s.close().catchError((Object _) {});
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    final s = _session;
    if (s != null) _closeQuietly(s);
    super.dispose();
  }
}

/// Watches [pendingPhotoProvider]: a different photo disposes this notifier
/// (closing its session, even one still opening) and builds a fresh one.
final photoOptimiserProvider =
    StateNotifierProvider.autoDispose<
      PhotoOptimiserNotifier,
      PhotoOptimiserState
    >((ref) {
      final photo = ref.watch(pendingPhotoProvider);
      if (photo == null) throw StateError('no pending photo');
      return PhotoOptimiserNotifier(ref, photo);
    });
