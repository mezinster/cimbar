import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/decode/diagnostics.dart';
import '../../core/decode/frame_assembler.dart';
import '../../core/decode/yuv_frame.dart';
import '../../core/format/file_container.dart';
import '../../core/models/decode_result.dart';
import '../../core/services/capture_policy.dart';
import '../../core/services/crypto_service.dart';
import '../../core/services/decode_isolate.dart';

final liveScanControllerProvider =
    StateNotifierProvider<LiveScanController, LiveScanState>((ref) => LiveScanController());

class LiveScanState {
  final bool isScanning;
  final int framesAnalyzed;
  final int filled;
  final int total;
  final ScanHint hint;
  final Float64List? corners;
  final int? imageWidth;
  final int? imageHeight;
  final LockAction pendingLock;
  final bool isDecrypting;
  final DecodeResult? result;
  final String? errorMessage;
  final bool debugEnabled;
  final List<String> debugLog;
  final String? captureStatus;
  final int lastFrameMs;

  const LiveScanState({
    this.isScanning = false,
    this.framesAnalyzed = 0,
    this.filled = 0,
    this.total = 0,
    this.hint = ScanHint.none,
    this.corners,
    this.imageWidth,
    this.imageHeight,
    this.pendingLock = LockAction.none,
    this.isDecrypting = false,
    this.result,
    this.errorMessage,
    this.debugEnabled = false,
    this.debugLog = const [],
    this.captureStatus,
    this.lastFrameMs = 0,
  });

  bool get isComplete => total > 0 && filled >= total;

  LiveScanState copyWith({
    bool? isScanning,
    int? framesAnalyzed,
    int? filled,
    int? total,
    ScanHint? hint,
    Float64List? corners,
    bool clearCorners = false,
    int? imageWidth,
    int? imageHeight,
    LockAction? pendingLock,
    bool? isDecrypting,
    DecodeResult? result,
    String? errorMessage,
    bool? debugEnabled,
    List<String>? debugLog,
    String? captureStatus,
    bool clearCaptureStatus = false,
    int? lastFrameMs,
  }) {
    return LiveScanState(
      isScanning: isScanning ?? this.isScanning,
      framesAnalyzed: framesAnalyzed ?? this.framesAnalyzed,
      filled: filled ?? this.filled,
      total: total ?? this.total,
      hint: hint ?? this.hint,
      corners: clearCorners ? null : (corners ?? this.corners),
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      pendingLock: pendingLock ?? this.pendingLock,
      isDecrypting: isDecrypting ?? this.isDecrypting,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      debugEnabled: debugEnabled ?? this.debugEnabled,
      debugLog: debugLog ?? this.debugLog,
      captureStatus: clearCaptureStatus ? null : (captureStatus ?? this.captureStatus),
      lastFrameMs: lastFrameMs ?? this.lastFrameMs,
    );
  }
}

class LiveScanController extends StateNotifier<LiveScanState> {
  LiveScanController() : super(const LiveScanState());

  final FrameAssembler _assembler = FrameAssembler();
  final CapturePolicy _policy = CapturePolicy();
  DecodeIsolate? _isolate;
  Future<DecodeIsolate>? _spawning;
  RoiHint? _hint;
  bool _debugMode = false;
  bool _captureNext = false;
  int _frameNum = 0;
  static const _maxDebugEntries = 50;

  void updateDebugMode(bool enabled) => _debugMode = enabled;

  /// True when a frame can be processed right now (no copy should be made otherwise).
  bool get wantsFrame => state.isScanning && _isolate != null && !_isolate!.busy;

  Future<void> startScan() async {
    _assembler.reset();
    _policy.reset();
    _hint = null;
    _frameNum = 0;
    state = LiveScanState(isScanning: true, debugEnabled: state.debugEnabled);
    _spawning ??= DecodeIsolate.spawn();
    _isolate ??= await _spawning;
  }

  void stopScan() => state = state.copyWith(isScanning: false);

  void disposeIsolate() {
    _isolate?.dispose();
    _isolate = null;
    _spawning = null;
  }

  @override
  void dispose() {
    disposeIsolate();
    super.dispose();
  }

  void toggleDebug() {
    if (!_debugMode) return;
    state = state.copyWith(debugEnabled: !state.debugEnabled);
  }

  void captureDebugFrame() => _captureNext = true;
  void clearCaptureStatus() => state = state.copyWith(clearCaptureStatus: true);
  void consumeLockAction() => state = state.copyWith(pendingLock: LockAction.none);

  void onCameraFrame(YuvFrame frame) {
    if (!wantsFrame) return;
    final capture = _captureNext;
    _captureNext = false;
    final job = FrameJob(frame: frame, useDrift: true, hint: _hint, capture: capture);
    final n = ++_frameNum;
    _isolate!.decode(job).then((o) => _onOutcome(n, o), onError: (e) => _log('frame=$n isolate error: $e'));
  }

  void _onOutcome(int n, FrameOutcome o) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final (hint, lock) = _policy.update(o, now);
    _hint = o.roi == null ? null : RoiHint(o.roi![0], o.roi![1], o.roi![2], o.roi![3]);
    var rejected = '';
    if (o.status == DecodeStatus.ok && o.data != null) {
      final added = _assembler.add(o.data!, blocksFailed: o.blocksFailed);
      if (!added.accepted) rejected = added.reason;
    }
    if (_debugMode) {
      final d = o.diag.entries.map((e) => '${e.key}=${e.value}').join(' ');
      _log('frame=$n status=${o.status.name} ms=${o.totalMs} filled=${_assembler.filled}/${_assembler.total}${rejected.isEmpty ? '' : ' rejected=$rejected'} $d');
      _overlay('#$n ${o.status.name} ${o.totalMs}ms f=${_assembler.filled}/${_assembler.total}');
    }
    if (o.capturePng != null) _saveCapture(o);
    if (!mounted) return;
    state = state.copyWith(
      framesAnalyzed: n,
      filled: _assembler.filled,
      total: _assembler.total,
      hint: hint,
      corners: o.corners,
      clearCorners: o.corners == null,
      imageWidth: o.width,
      imageHeight: o.height,
      pendingLock: lock == LockAction.none ? state.pendingLock : lock,
      lastFrameMs: o.totalMs,
    );
  }

  void _log(String msg) {
    if (!_debugMode) return;
    for (final line in msg.split('\n')) {
      if (line.isNotEmpty) debugPrint('[cimbar_scan] $line');
    }
  }

  void _overlay(String msg) {
    if (!mounted) return;
    final log = [...state.debugLog, msg];
    if (log.length > _maxDebugEntries) log.removeRange(0, log.length - _maxDebugEntries);
    state = state.copyWith(debugLog: log);
  }

  Future<void> _saveCapture(FrameOutcome o) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      await File('${dir.path}/capture_$ts.png').writeAsBytes(o.capturePng!);
      final lines = o.diag.entries.map((e) => '${e.key}=${e.value}').join('\n');
      await File('${dir.path}/capture_$ts.txt').writeAsString('status=${o.status.name}\n$lines\n');
      if (mounted) state = state.copyWith(captureStatus: 'saved');
    } catch (_) {
      if (mounted) state = state.copyWith(captureStatus: 'failed');
    }
  }

  /// Assemble, strip the length prefix, decrypt if needed, parse the file.
  Future<void> finish(String passphrase) async {
    if (!_assembler.isComplete) return;
    state = state.copyWith(isScanning: false, isDecrypting: true);
    try {
      final payload = FileContainer.stripLengthPrefix(_assembler.framedData());
      Uint8List plain;
      if (FileContainer.isEncrypted(payload)) {
        if (passphrase.isEmpty) {
          state = state.copyWith(isDecrypting: false, errorMessage: 'This file is encrypted: a passphrase is required');
          return;
        }
        plain = CryptoService.decrypt(payload, passphrase);
      } else {
        plain = payload;
      }
      final file = FileContainer.parsePayload(plain);
      final result = DecodeResult(filename: file.fileName, data: file.fileBytes);
      await _autoSave(result);
      state = state.copyWith(isDecrypting: false, result: result);
    } catch (e) {
      state = state.copyWith(isDecrypting: false, errorMessage: '$e');
    }
  }

  Future<String?> _autoSave(DecodeResult result) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${result.filename}');
      await file.writeAsBytes(result.data);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> saveResult() async {
    final r = state.result;
    return r == null ? null : _autoSave(r);
  }

  List<int> get missingSeqs => _assembler.missingSeqs();
}
