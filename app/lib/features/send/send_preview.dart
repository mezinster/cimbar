import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/encode/cell_grid.dart';
import '../../core/encode/frame_builder.dart';
import '../../core/encode/frame_raster.dart';
import '../../core/encode/payload_encoder.dart';
import '../../core/encode/send_jobs.dart';
import '../../core/format/cimbar_spec.dart';
import '../../core/format/text_message.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/wide_layout.dart';
import 'send_controller.dart';

Future<ui.Image> _rgbaToImage(Uint8List rgba) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, CimbarSpec.framePx, CimbarSpec.framePx, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// The preview's two slow steps, swappable in tests: the real ones run an
/// isolate and decodeImageFromPixels, neither of which completes inside the
/// fake-async test zone.
class PreviewIo {
  final Future<EncodedPayload> Function(SendRequest) encode;
  final Future<ui.Image> Function(Uint8List rgba) toImage;
  const PreviewIo({this.encode = encodeInIsolate, this.toImage = _rgbaToImage});
}

final sendPreviewIoProvider = Provider<PreviewIo>((ref) => const PreviewIo());

/// Live barcode preview on the tablet Send screen (right pane). Re-encodes
/// 350 ms after the last change to the text, file or [passphrase] — the same
/// request Present sends, so the frame count matches — and loops the source
/// frames at the chosen frame delay. Tapping it calls [onPresent].
class SendPreview extends ConsumerStatefulWidget {
  final TextEditingController passphrase;
  final VoidCallback? onPresent;

  const SendPreview({super.key, required this.passphrase, this.onPresent});

  @override
  ConsumerState<SendPreview> createState() => _SendPreviewState();
}

class _SendPreviewState extends ConsumerState<SendPreview> {
  static const _debounce = Duration(milliseconds: 350);

  Timer? _wait;
  Timer? _tick;
  EncodedPayload? _payload;
  ui.Image? _image;
  int _frame = 0;

  /// Bumped by every new encode and by dispose: work resuming under an older
  /// generation is stale and is dropped.
  int _gen = 0;
  late String _lastPass;

  /// At most one encode runs at a time: a change during it only marks the
  /// result stale, and the latest input is encoded once it finishes. A large
  /// file is copied into the isolate, so overlapping encodes would stack.
  bool _inFlight = false;
  bool _dirty = false;

  /// Source-frame count of an input over the Present cap, shown instead of a
  /// preview nobody could send.
  int? _tooLarge;

  /// False while another route covers Send (Present, pushed on the root
  /// navigator): the loop stops rendering so it doesn't compete with
  /// Present's own frames, and resumes when Send is visible again.
  bool _active = true;
  bool _stalled = false;

  @override
  void initState() {
    super.initState();
    _lastPass = widget.passphrase.text.trim();
    widget.passphrase.addListener(_onPassphrase);
    _wait = Timer(Duration.zero, _encode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active == _active) return;
    _active = active;
    if (active && _stalled) {
      _stalled = false;
      _advance(_gen);
    }
  }

  @override
  void dispose() {
    widget.passphrase.removeListener(_onPassphrase);
    _gen++;
    _wait?.cancel();
    _tick?.cancel();
    _image?.dispose();
    super.dispose();
  }

  void _onPassphrase() {
    final p = widget.passphrase.text.trim();
    if (p == _lastPass) return;
    _lastPass = p;
    _schedule();
  }

  void _schedule() {
    _wait?.cancel();
    _wait = Timer(_debounce, _encode);
  }

  void _clear() {
    final old = _image;
    setState(() {
      _payload = null;
      _image = null;
      _tooLarge = null;
    });
    old?.dispose();
  }

  Future<void> _encode() async {
    final s = ref.read(sendControllerProvider);
    if (!s.hasInput) {
      _gen++;
      _dirty = false;
      _tick?.cancel();
      _clear();
      return;
    }
    if (_inFlight) {
      _dirty = true;
      return;
    }
    final gen = ++_gen;
    _tick?.cancel();
    // The text-message name has a fixed length, so any date gives Present's N.
    final req = s.mode == SendMode.text
        ? SendRequest(TextMessage.fileName(DateTime(2000)), Uint8List.fromList(utf8.encode(s.text)), _lastPass)
        : SendRequest(s.fileName!, s.fileBytes!, _lastPass);
    EncodedPayload? p;
    _inFlight = true;
    try {
      p = await ref.read(sendPreviewIoProvider).encode(req);
    } catch (e) {
      p = null;
    } finally {
      _inFlight = false;
    }
    if (!mounted) return;
    if (_dirty) {
      _dirty = false;
      unawaited(_encode());
      return;
    }
    if (gen != _gen) return;
    if (p == null) {
      _clear();
      return;
    }
    if (p.total > maxSendFrames) {
      final old = _image;
      setState(() {
        _payload = null;
        _image = null;
        _tooLarge = p!.total;
      });
      old?.dispose();
      return;
    }
    _tooLarge = null;
    _payload = p;
    _frame = 0;
    await _show(gen);
  }

  Future<void> _show(int gen) async {
    final p = _payload!;
    final rgba = FrameRaster.toRgba(FrameRaster.render(CellGrid.cells(FrameBuilder.sourceFrame(p, _frame))));
    final img = await ref.read(sendPreviewIoProvider).toImage(rgba);
    if (!mounted || gen != _gen) {
      img.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = img);
    old?.dispose();
    if (p.total > 1) {
      _tick = Timer(Duration(milliseconds: ref.read(sendControllerProvider).delayMs), () {
        if (!mounted || gen != _gen) return;
        if (!_active) {
          _stalled = true;
          return;
        }
        _advance(gen);
      });
    }
  }

  void _advance(int gen) {
    final p = _payload;
    if (p == null || gen != _gen) return;
    _frame = (_frame + 1) % p.total;
    _show(gen);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sendControllerProvider, (prev, next) {
      if (prev?.mode != next.mode || prev?.text != next.text || prev?.fileBytes != next.fileBytes) _schedule();
    });
    final l10n = AppLocalizations.of(context)!;
    final img = _image;
    final p = _payload;
    final tooLarge = _tooLarge;
    if (tooLarge != null) {
      return EmptyPane(icon: Icons.block, text: l10n.sendTooLarge(tooLarge, maxSendFrames));
    }
    if (img == null || p == null) return EmptyPane(icon: Icons.qr_code_2, text: l10n.wideSendEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Material(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPresent,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.none),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text(l10n.presentSource(_frame + 1, p.total), style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          TextButton.icon(
            onPressed: widget.onPresent,
            icon: const Icon(Icons.fullscreen),
            label: Text(l10n.previewFullScreen),
          ),
        ]),
      ],
    );
  }
}
