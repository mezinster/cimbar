import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen still capture; pops with the JPEG bytes (or null on cancel).
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  CameraController? _controller;
  String? _error;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'no_camera');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final c = CameraController(camera, ResolutionPreset.max, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final c = _controller;
    if (c == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _taking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (c != null && c.value.isInitialized)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: c.value.previewSize!.height,
                height: c.value.previewSize!.width,
                child: CameraPreview(c),
              ),
            ),
          )
        else if (_error != null)
          Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: Center(
            child: FloatingActionButton.large(
              onPressed: c == null || _taking ? null : _take,
              backgroundColor: Colors.white,
              child: _taking
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.camera_alt, color: Colors.black, size: 36),
            ),
          ),
        ),
      ]),
    );
  }
}
