import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/encode/cell_grid.dart';
import '../../core/encode/frame_raster.dart';
import '../../core/encode/payload_encoder.dart';
import '../../core/format/cimbar_spec.dart';
import '../../l10n/generated/app_localizations.dart';
import 'present_sequencer.dart';
import 'screen_controls.dart';

Future<ui.Image> _rgbaToImage(Uint8List rgba) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, CimbarSpec.framePx, CimbarSpec.framePx, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

class PresentScreen extends StatefulWidget {
  final EncodedPayload payload;
  final int delayMs;
  final ScreenControls controls;

  /// Turns one frame's RGBA pixels into an image; defaults to
  /// decodeImageFromPixels. Tests inject a ready-made image, since the real
  /// call never completes inside the fake-async test zone.
  final Future<ui.Image> Function(Uint8List rgba) toImage;
  const PresentScreen({super.key, required this.payload, required this.delayMs,
      ScreenControls? controls, Future<ui.Image> Function(Uint8List rgba)? toImage})
      : controls = controls ?? const PluginScreenControls(),
        toImage = toImage ?? _rgbaToImage;
  @override
  State<PresentScreen> createState() => _PresentScreenState();
}

class _PresentScreenState extends State<PresentScreen> with WidgetsBindingObserver {
  late final PresentSequencer _seq = PresentSequencer(widget.payload);
  ui.Image? _image;
  PresentStep? _step;
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    _running = true;
    await widget.controls.keepAwake(true);
    await widget.controls.maxBrightness();
    _tick();
  }

  void _stop() {
    _running = false;
    _timer?.cancel();
    widget.controls.keepAwake(false);
    widget.controls.restoreBrightness();
  }

  // Build the next frame, show it, schedule the following one. A frame that
  // takes longer than the delay to build simply stays on screen longer.
  Future<void> _tick() async {
    if (!_running) return;
    final sw = Stopwatch()..start();
    final step = _seq.next();
    final img = await widget.toImage(FrameRaster.toRgba(FrameRaster.render(CellGrid.cells(step.data))));
    if (!mounted || !_running) {
      img.dispose();
      return;
    }
    final old = _image;
    setState(() {
      _image = img;
      _step = step;
    });
    old?.dispose();
    final wait = widget.delayMs - sw.elapsedMilliseconds;
    _timer = Timer(Duration(milliseconds: wait > 0 ? wait : 0), _tick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_running) _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_running) _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_running) _stop();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final step = _step;
    final label = step == null
        ? ''
        : step.repair
            ? l10n.presentRepair(step.index)
            : l10n.presentSource(step.index + 1, widget.payload.total);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: _image == null
                    ? const SizedBox.shrink()
                    // FilterQuality.none: nearest-neighbour scaling keeps tile edges hard.
                    : RawImage(image: _image, fit: BoxFit.contain, filterQuality: FilterQuality.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(label, key: const Key('presentCounter'), style: const TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    );
  }
}
