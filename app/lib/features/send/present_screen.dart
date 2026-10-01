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

  /// Run generation: bumped by every start and stop (and dispose). An async
  /// step that resumes under a different generation is stale and must neither
  /// tick nor leave the screen awake/bright — so there is at most one frame
  /// chain, and every exit ends with the screen restored.
  int _run = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  /// Screen settings are best-effort: a plugin that throws (synchronously or
  /// asynchronously) must never stop the frames or skip a restore.
  static Future<void> _safe(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      debugPrint('PresentScreen: screen control failed: $e');
    }
  }

  Future<void> _restoreScreen() => Future.wait([
        _safe(() => widget.controls.keepAwake(false)),
        _safe(widget.controls.restoreBrightness),
      ]);

  Future<void> _start() async {
    final gen = ++_run;
    _running = true;
    for (final apply in [() => widget.controls.keepAwake(true), widget.controls.maxBrightness]) {
      await _safe(apply);
      if (gen != _run) {
        // Stopped while this call was in flight: it may have landed after the
        // stop's restore, so restore again — unless a newer start now owns the screen.
        if (!_running) await _restoreScreen();
        return;
      }
    }
    _tick();
  }

  void _stop() {
    _run++;
    _running = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_restoreScreen());
  }

  // Build the next frame, show it, schedule the following one. A frame that
  // takes longer than the delay to build simply stays on screen longer.
  Future<void> _tick() async {
    if (!_running) return;
    final gen = _run;
    final sw = Stopwatch()..start();
    final step = _seq.next();
    final img = await widget.toImage(FrameRaster.toRgba(FrameRaster.render(CellGrid.cells(step.data))));
    if (!mounted || gen != _run) {
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
    if (_running) {
      _stop();
    } else {
      _run++;
    }
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
