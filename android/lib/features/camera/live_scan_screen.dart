import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/decode_tuning_provider.dart';
import '../../core/services/file_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/barcode_overlay_painter.dart';
import '../../shared/widgets/result_card.dart';
import 'live_scan_controller.dart';

/// Full-screen camera preview for live multi-frame CimBar scanning.
class LiveScanScreen extends ConsumerStatefulWidget {
  final String passphrase;

  const LiveScanScreen({super.key, required this.passphrase});

  @override
  ConsumerState<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends ConsumerState<LiveScanScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _initializing = false;
  bool _disposed = false;
  String? _cameraError;
  bool _decryptTriggered = false;
  int _tapCount = 0;
  DateTime _lastTapTime = DateTime(0);
  final ScrollController _debugScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Lock to portrait — camera preview dimensions don't survive rotation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _initCamera();
    // Defer startScan — initState runs during the widget tree build and
    // Riverpod forbids synchronous provider modifications at that point.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveScanControllerProvider.notifier).startScan();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    _debugScrollController.dispose();
    // Restore all orientations
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.stopImageStream().catchError((_) {});
      _cameraController?.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing || _disposed) return;
    _initializing = true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'no_camera');
        }
        return;
      }

      // Prefer back camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      _cameraController = controller;
      setState(() {});

      // Start image stream for live scanning
      await controller.startImageStream(_onCameraImage);
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = e.toString());
      }
    } finally {
      _initializing = false;
    }
  }

  void _onCameraImage(CameraImage image) {
    if (_disposed || image.planes.length < 3) return;

    // Copy plane bytes — they're only valid during this callback
    final yPlane = Uint8List.fromList(image.planes[0].bytes);
    final uPlane = Uint8List.fromList(image.planes[1].bytes);
    final vPlane = Uint8List.fromList(image.planes[2].bytes);

    ref.read(liveScanControllerProvider.notifier).onCameraFrame(
          width: image.width,
          height: image.height,
          yPlane: yPlane,
          uPlane: uPlane,
          vPlane: vPlane,
          yRowStride: image.planes[0].bytesPerRow,
          uvRowStride: image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        );
  }

  void _onStatusTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds > 500) {
      _tapCount = 0;
    }
    _lastTapTime = now;
    _tapCount++;
    if (_tapCount >= 3) {
      _tapCount = 0;
      ref.read(liveScanControllerProvider.notifier).toggleDebug();
    }
  }

  void _scrollDebugToBottom() {
    if (_debugScrollController.hasClients) {
      _debugScrollController.jumpTo(
        _debugScrollController.position.maxScrollExtent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scanState = ref.watch(liveScanControllerProvider);
    final controller = ref.read(liveScanControllerProvider.notifier);
    final tuningConfig = ref.watch(decodeTuningProvider);
    controller.updateTuningConfig(tuningConfig);
    controller.updateDebugMode(tuningConfig.debugModeEnabled);

    // Auto-scroll debug log when new entries arrive
    if (scanState.debugEnabled && scanState.debugLog.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollDebugToBottom();
      });
    }

    // Auto-decrypt when scan is complete
    if (controller.scanComplete &&
        !_decryptTriggered &&
        !scanState.isDecrypting &&
        scanState.result == null &&
        scanState.errorMessage == null) {
      _decryptTriggered = true;
      // Stop the image stream before decrypting
      _cameraController?.stopImageStream().catchError((_) {});
      Future.microtask(() => controller.decrypt(widget.passphrase));
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _cameraController?.stopImageStream().catchError((_) {});
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
        children: [
          // Camera preview
          if (!_disposed &&
              _cameraController != null &&
              _cameraController!.value.isInitialized)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            )
          else if (_cameraError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _cameraError == 'no_camera'
                      ? l10n.noCameraAvailable
                      : l10n.cameraPermissionDenied,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // AR overlay: barcode bounding box
          if (scanState.barcodeRect != null &&
              scanState.isScanning &&
              scanState.sourceImageWidth != null &&
              scanState.sourceImageHeight != null &&
              _cameraController != null)
            Positioned.fill(
              child: CustomPaint(
                painter: BarcodeOverlayPainter(
                  barcodeRect: scanState.barcodeRect!,
                  sourceImageWidth: scanState.sourceImageWidth!,
                  sourceImageHeight: scanState.sourceImageHeight!,
                  sensorOrientation:
                      _cameraController!.description.sensorOrientation,
                ),
              ),
            ),

          // Top: cancel button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
              ),
            ),
          ),

          // Debug overlay (above status panel)
          if (scanState.debugEnabled && scanState.debugLog.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 160,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                color: Colors.black.withOpacity(0.8),
                child: ListView.builder(
                  controller: _debugScrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: scanState.debugLog.length,
                  itemBuilder: (_, i) => Text(
                    scanState.debugLog[i],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),

          // Bottom: status panel (triple-tap to toggle debug)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _onStatusTap,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: _buildStatusPanel(l10n, scanState, controller),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildStatusPanel(
    AppLocalizations l10n,
    LiveScanState scanState,
    LiveScanController controller,
  ) {
    // Result state
    if (scanState.result != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ResultCard(
            result: scanState.result!,
            onSave: () async {
              final path = await controller.saveResult();
              if (path != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.fileSaved)),
                );
              }
            },
            onShare: () => FileService.shareResult(scanState.result!),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white70)),
          ),
        ],
      );
    }

    // Error state
    if (scanState.errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 40),
          const SizedBox(height: 8),
          Text(
            scanState.errorMessage!,
            style: TextStyle(color: Colors.red.shade300, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white70)),
          ),
        ],
      );
    }

    // Decrypting state
    if (scanState.isDecrypting) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 12),
          Text(l10n.progressDecrypting,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      );
    }

    // Scanning state
    if (scanState.totalFrames > 0) {
      final progress = scanState.uniqueFrames / scanState.totalFrames;
      final statusText = scanState.uniqueFrames >= scanState.totalFrames
          ? l10n.liveScanComplete
          : l10n.liveScanProgress(scanState.uniqueFrames, scanState.totalFrames);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
          ),
          const SizedBox(height: 12),
          Text(statusText,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          if (scanState.detectedFrameSize != null) ...[
            const SizedBox(height: 4),
            Text(
              '${scanState.detectedFrameSize}px',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      );
    }

    // Searching state
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: Colors.white54),
        const SizedBox(height: 12),
        Text(l10n.liveScanSearching,
            style: const TextStyle(color: Colors.white70, fontSize: 16)),
        if (scanState.framesAnalyzed > 0) ...[
          const SizedBox(height: 4),
          Text(
            l10n.liveScanFramesAnalyzed(scanState.framesAnalyzed),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
