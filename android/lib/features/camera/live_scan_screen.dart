import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/decode/yuv_frame.dart';
import '../../core/providers/debug_mode_provider.dart';
import '../../core/services/capture_policy.dart';
import '../../core/services/file_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/corners_overlay_painter.dart';
import '../../shared/widgets/result_card.dart';
import 'live_scan_controller.dart';

class LiveScanScreen extends ConsumerStatefulWidget {
  final String passphrase;
  const LiveScanScreen({super.key, this.passphrase = ''});

  @override
  ConsumerState<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends ConsumerState<LiveScanScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _initializing = false;
  bool _disposed = false;
  String? _cameraError;
  bool _finishTriggered = false;
  int _tapCount = 0;
  DateTime _lastTapTime = DateTime(0);
  final ScrollController _debugScrollController = ScrollController();
  // Captured once in initState: `ref` is invalid inside dispose() because
  // flutter_riverpod's StatefulElement.unmount runs before State.dispose.
  late final LiveScanController _scan;

  @override
  void initState() {
    super.initState();
    _scan = ref.read(liveScanControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    _initCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scan.startScan();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    _debugScrollController.dispose();
    _scan.disposeIsolate();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.inactive) {
      final cam = _cameraController;
      if (cam == null) return;
      _cameraController = null;
      cam.stopImageStream().catchError((_) {});
      cam.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null) _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing || _disposed) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'no_camera');
        return;
      }
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(camera, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      _cameraController = controller;
      setState(() {});
      await controller.startImageStream(_onCameraImage);
    } catch (e) {
      if (mounted) setState(() => _cameraError = e.toString());
    } finally {
      _initializing = false;
    }
  }

  void _onCameraImage(CameraImage image) {
    if (_disposed || image.planes.length < 3) return;
    final controller = ref.read(liveScanControllerProvider.notifier);
    if (!controller.wantsFrame) return; // drop before copying anything
    final frame = YuvFrame(
      yPlane: Uint8List.fromList(image.planes[0].bytes),
      uPlane: Uint8List.fromList(image.planes[1].bytes),
      vPlane: Uint8List.fromList(image.planes[2].bytes),
      width: image.width,
      height: image.height,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
    controller.onCameraFrame(frame);
  }

  Future<void> _applyLock(LockAction action) async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      if (action == LockAction.lock) {
        await cam.setFocusMode(FocusMode.locked);
        await cam.setExposureMode(ExposureMode.locked);
      } else if (action == LockAction.unlock) {
        await cam.setFocusMode(FocusMode.auto);
        await cam.setExposureMode(ExposureMode.auto);
      }
    } catch (_) {
      // Some devices reject lock modes; scanning continues without them.
    }
  }

  void _onStatusTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds > 500) _tapCount = 0;
    _lastTapTime = now;
    _tapCount++;
    if (_tapCount >= 3) {
      _tapCount = 0;
      ref.read(liveScanControllerProvider.notifier).toggleDebug();
    }
  }

  String _hintText(AppLocalizations l10n, ScanHint hint) => switch (hint) {
        ScanHint.moveCloser => l10n.hintMoveCloser,
        ScanHint.moveBack => l10n.hintMoveBack,
        ScanHint.holdStill => l10n.hintHoldStill,
        ScanHint.adjustAngle => l10n.hintAdjustAngle,
        ScanHint.none => '',
      };

  /// Maps the controller's error code ('passphrase_required' or
  /// 'decoder_failed:<detail>') to a localized message.
  String _errorText(AppLocalizations l10n, String code) {
    if (code == 'passphrase_required') return l10n.errorPassphraseRequired;
    if (code.startsWith('decoder_failed:')) {
      return l10n.errorDecoderFailed(code.substring('decoder_failed:'.length));
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scanState = ref.watch(liveScanControllerProvider);
    final controller = ref.read(liveScanControllerProvider.notifier);
    controller.updateDebugMode(ref.watch(debugModeProvider));

    if (scanState.pendingLock != LockAction.none) {
      final action = scanState.pendingLock;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.consumeLockAction();
        _applyLock(action);
      });
    }
    if (scanState.debugEnabled && scanState.debugLog.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_debugScrollController.hasClients) {
          _debugScrollController.jumpTo(_debugScrollController.position.maxScrollExtent);
        }
      });
    }
    if (scanState.captureStatus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final saved = scanState.captureStatus == 'saved';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved ? l10n.captureSaved : l10n.captureFailed),
          backgroundColor: saved ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ));
        controller.clearCaptureStatus();
      });
    }
    if (scanState.isComplete && !_finishTriggered && !scanState.isDecrypting && scanState.result == null && scanState.errorMessage == null) {
      _finishTriggered = true;
      _cameraController?.stopImageStream().catchError((_) {});
      Future.microtask(() => controller.finish(widget.passphrase));
    }

    final cam = _cameraController;
    final previewReady = !_disposed && cam != null && cam.value.isInitialized;
    final previewSwapped = previewReady && CornersOverlayPainter.isRotated(cam.description.sensorOrientation);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cameraController?.stopImageStream().catchError((_) {});
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (previewReady)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    // Swap only when the sensor turns the axes — the same rule
                    // CornersOverlayPainter maps with, so the overlay and the
                    // preview always agree.
                    width: previewSwapped ? cam.value.previewSize!.height : cam.value.previewSize!.width,
                    height: previewSwapped ? cam.value.previewSize!.width : cam.value.previewSize!.height,
                    child: CameraPreview(cam),
                  ),
                ),
              )
            else if (_cameraError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _cameraError == 'no_camera' ? l10n.noCameraAvailable : l10n.cameraPermissionDenied,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            // Aiming square + located corners
            if (previewReady)
              Positioned.fill(
                child: CustomPaint(
                  painter: CornersOverlayPainter(
                    corners: scanState.isScanning ? scanState.corners : null,
                    sourceImageWidth: scanState.imageWidth ?? cam.value.previewSize!.width.toInt(),
                    sourceImageHeight: scanState.imageHeight ?? cam.value.previewSize!.height.toInt(),
                    sensorOrientation: cam.description.sensorOrientation,
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
            if (scanState.debugEnabled && scanState.isScanning)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  onPressed: controller.captureDebugFrame,
                  icon: const Icon(Icons.camera, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            if (scanState.debugEnabled && scanState.debugLog.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 180,
                child: Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                  color: Colors.black.withValues(alpha: 0.8),
                  padding: const EdgeInsets.all(8),
                  child: ListView(
                    controller: _debugScrollController,
                    shrinkWrap: true,
                    children: [
                      for (final line in scanState.debugLog)
                        Text(line, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _onStatusTap,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                  child: _buildStatusPanel(l10n, scanState, controller),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel(AppLocalizations l10n, LiveScanState s, LiveScanController controller) {
    if (s.result != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        ResultCard(
          result: s.result!,
          onSave: () async {
            final path = await controller.saveResult();
            if (path != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.fileSaved)));
            }
          },
          onShare: () => FileService.shareResult(s.result!),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel, style: const TextStyle(color: Colors.white70))),
      ]);
    }
    if (s.errorMessage != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, color: Colors.red.shade300, size: 40),
        const SizedBox(height: 8),
        Text(_errorText(l10n, s.errorMessage!), style: TextStyle(color: Colors.red.shade300, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel, style: const TextStyle(color: Colors.white70))),
      ]);
    }
    if (s.isDecrypting) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 12),
        Text(l10n.progressDecrypting, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ]);
    }
    final hint = _hintText(l10n, s.hint);
    if (s.total > 0) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(value: s.filled / s.total, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.greenAccent)),
        const SizedBox(height: 12),
        Text(s.isComplete ? l10n.liveScanComplete : l10n.liveScanProgress(s.filled, s.total), style: const TextStyle(color: Colors.white, fontSize: 16)),
        if (hint.isNotEmpty) ...[const SizedBox(height: 4), Text(hint, style: const TextStyle(color: Colors.amberAccent, fontSize: 14))],
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: Colors.white54),
      const SizedBox(height: 12),
      Text(s.corners == null ? l10n.liveScanAim : l10n.liveScanSearching, style: const TextStyle(color: Colors.white70, fontSize: 16)),
      if (hint.isNotEmpty) ...[const SizedBox(height: 4), Text(hint, style: const TextStyle(color: Colors.amberAccent, fontSize: 14))],
      if (s.framesAnalyzed > 0) ...[
        const SizedBox(height: 4),
        Text(l10n.liveScanFramesAnalyzed(s.framesAnalyzed), style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    ]);
  }
}
