import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/encode/frame_budget.dart';
import '../../../core/encode/send_jobs.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/repeat_button.dart';
import '../../send/send_controller.dart';
import '../domain/photo_fit.dart';
import 'photo_optimiser_provider.dart';

/// True while the optimiser screen is on the root navigator.
final photoOptimiserOpenProvider = StateProvider<bool>((_) => false);

/// Hands [photo] to the optimiser and pushes [PhotoOptimiserScreen] on the
/// root navigator (a full-screen route on the shell's navigator would leave
/// the tab bar dead). If the screen is already open it only swaps the photo.
Future<void> openPhotoOptimiser(
  BuildContext context,
  WidgetRef ref,
  PendingPhoto photo,
) async {
  // The caller may be gone by the time the route closes; the container stays.
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(pendingPhotoProvider.notifier).state = photo;
  if (container.read(photoOptimiserOpenProvider)) return;
  container.read(photoOptimiserOpenProvider.notifier).state = true;
  try {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const PhotoOptimiserScreen()),
    );
  } finally {
    // pendingPhotoProvider is left set: the screen still watches it while
    // its exit animation runs, and a null there would throw.
    container.read(photoOptimiserOpenProvider.notifier).state = false;
  }
}

/// Shrinks a photo to fit a chosen number of frames before sending it.
class PhotoOptimiserScreen extends ConsumerStatefulWidget {
  const PhotoOptimiserScreen({super.key});

  @override
  ConsumerState<PhotoOptimiserScreen> createState() =>
      _PhotoOptimiserScreenState();
}

class _PhotoOptimiserScreenState extends ConsumerState<PhotoOptimiserScreen> {
  /// Set from the first tap of Continue/Skip until the screen pops, so a
  /// second tap cannot deliver twice.
  bool _delivering = false;

  /// Runs [action] and, if it handed a file over, puts it in the Send tab,
  /// pops and shows the Send tab — synchronously, before anything else can
  /// run. Showing Send matters when the optimiser was opened from elsewhere
  /// (the Camera tab's "Send this photo instead").
  Future<void> _continue(
    Future<({String name, Uint8List bytes})?> Function() action,
  ) async {
    if (_delivering) return;
    setState(() => _delivering = true);
    final r = await action();
    if (!mounted) return;
    if (r == null) {
      setState(() => _delivering = false);
      return;
    }
    ref.read(sendControllerProvider.notifier)
      ..setMode(SendMode.file)
      ..setFile(r.name, r.bytes);
    _popToSend();
  }

  /// Pops this screen and switches the shell to the Send tab, where the
  /// file now waits.
  void _popToSend() {
    final router = ref.read(routerProvider);
    Navigator.of(context).pop();
    router.go('/send');
  }

  /// Sends the untouched original through [SendController.loadFile], which
  /// still refuses a file above the receivers' size cap.
  void _skip() {
    if (_delivering) return;
    _delivering = true;
    final original = ref.read(photoOptimiserProvider.notifier).skip();
    final file = File(original.path);
    final send = ref.read(sendControllerProvider.notifier)
      ..setMode(SendMode.file);
    // The controller outlives this screen.
    unawaited(
      send.loadFile(original.name, length: file.length, read: file.readAsBytes),
    );
    _popToSend();
  }

  /// Asks for the frame count; empty or invalid input changes nothing.
  Future<void> _typeCount() async {
    final st = ref.read(photoOptimiserProvider);
    final n = await showDialog<int>(
      context: context,
      builder: (_) => _FrameCountDialog(initial: st.frames, max: st.maxFrames),
    );
    if (n == null || !mounted) return;
    ref.read(photoOptimiserProvider.notifier).setFrames(n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final st = ref.watch(photoOptimiserProvider);
    final notifier = ref.read(photoOptimiserProvider.notifier);
    final delayMs = ref.watch(sendControllerProvider.select((s) => s.delayMs));
    final result = st.result;
    final failed = st.error != null;
    final needed = st.neededFrames;
    final unfit = result != null && !result.fits && needed != null;
    final canContinue = st.canContinue && !_delivering;

    void step(int d) =>
        notifier.setFrames(ref.read(photoOptimiserProvider).frames + d);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.photoOptimiseTitle)),
      // Pinned outside the scroll view so Continue is never scrolled away.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Unfit: "Continue with M frames" re-fits at M, which sends an
              // image at least as good as the one shown for the same frame
              // count (manual keeps side and quality, so the very same
              // image), so the image shown is offered on its own only when
              // M passes the send cap and Continue with M cannot be.
              if (unfit && needed <= maxSendFrames)
                FilledButton(
                  key: const Key('photoContinueWith'),
                  onPressed: canContinue
                      ? () => _continue(notifier.continueAtNeeded)
                      : null,
                  child: Text(
                    l10n.photoContinueWith(needed),
                    textAlign: TextAlign.center,
                  ),
                )
              else if (unfit)
                OutlinedButton(
                  key: const Key('photoContinue'),
                  onPressed: canContinue
                      ? () => _continue(notifier.continueWithResult)
                      : null,
                  child: Text(
                    l10n.photoContinueAsIs(
                      framesForFile(
                        st.outputName,
                        result.bytes.length,
                        encrypted: true,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                FilledButton(
                  key: const Key('photoContinue'),
                  onPressed: canContinue
                      ? () => _continue(notifier.continueWithResult)
                      : null,
                  child: Text(l10n.photoContinue, textAlign: TextAlign.center),
                ),
              const SizedBox(height: 4),
              TextButton(
                key: const Key('photoSkip'),
                onPressed: _delivering ? null : _skip,
                child: Text(l10n.photoSkip, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Preview(state: st),
          const SizedBox(height: 8),
          SizedBox(
            height: 4,
            child: (st.opening || st.fitting) && !failed
                ? const LinearProgressIndicator()
                : null,
          ),
          const SizedBox(height: 16),
          if (failed)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  st.error == 'memory'
                      ? l10n.photoMemoryError
                      : l10n.photoDecodeError,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            )
          else ...[
            Text(l10n.photoFramesToSend, style: theme.textTheme.titleSmall),
            Row(
              children: [
                RepeatButton(
                  icon: Icons.remove,
                  semanticLabel: l10n.photoFewerFrames,
                  step: -1,
                  // Read at step time: two taps in one frame must both count.
                  onStep: step,
                  onHoldStart: notifier.beginHold,
                  onHoldEnd: notifier.endHold,
                ),
                Semantics(
                  button: true,
                  hint: l10n.photoEditFrameCount,
                  child: InkWell(
                    key: const Key('photoFrameCount'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: _typeCount,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '${st.frames}',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                ),
                RepeatButton(
                  icon: Icons.add,
                  semanticLabel: l10n.photoMoreFrames,
                  step: 1,
                  onStep: step,
                  onHoldStart: notifier.beginHold,
                  onHoldEnd: notifier.endHold,
                ),
              ],
            ),
            Text(
              l10n.photoTransferTime(
                st.frames,
                st.frames * delayMs / 1000,
                delayMs,
              ),
            ),
            if (st.frames > maxGifFrames) ...[
              const SizedBox(height: 4),
              Text(
                l10n.photoGifCapNote(maxGifFrames),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (unfit) ...[
              const SizedBox(height: 4),
              Text(
                l10n.photoDoesNotFit(st.frames, needed),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (st.longestSide > 0) _ManualControls(state: st),
          ],
        ],
      ),
    );
  }
}

/// Asks for the frame count. Pops the typed number, or null for Cancel and
/// for empty input; the notifier clamps it.
class _FrameCountDialog extends StatefulWidget {
  const _FrameCountDialog({required this.initial, required this.max});

  final int initial;
  final int max;

  @override
  State<_FrameCountDialog> createState() => _FrameCountDialogState();
}

class _FrameCountDialogState extends State<_FrameCountDialog> {
  // Owned by the dialog: disposing it when showDialog's future completes
  // would pull it from under the exit animation.
  late final _controller = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(int.tryParse(_controller.text));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.photoFramesToSend),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(helperText: '1–${widget.max}'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(material.cancelButtonLabel),
        ),
        TextButton(onPressed: _submit, child: Text(material.okButtonLabel)),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.state});

  final PhotoOptimiserState state;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    return Column(
      children: [
        SizedBox(
          height: 240,
          child: result == null
              ? Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 64,
                    color: Theme.of(context).disabledColor,
                  ),
                )
              : Image.memory(
                  result.bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image, size: 64)),
                ),
        ),
        if (result != null) ...[
          const SizedBox(height: 8),
          Text(
            _label(AppLocalizations.of(context)!, result),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  String _label(AppLocalizations l10n, PhotoFitResult r) {
    final longest = state.longestSide;
    int scaled(int v) =>
        r.maxSide >= longest ? v : (v * r.maxSide / longest).round();
    final kb = r.bytes.isEmpty
        ? 0
        : math.max(1, (r.bytes.length / 1024).round());
    return l10n.photoResultLabel(
      scaled(state.width),
      scaled(state.height),
      r.quality,
      kb,
    );
  }
}

class _ManualControls extends ConsumerWidget {
  const _ManualControls({required this.state});

  final PhotoOptimiserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final notifier = ref.read(photoOptimiserProvider.notifier);
    final manual = !state.auto;
    final side = manual ? state.manualSide : state.result?.maxSide;
    final quality =
        (manual ? state.manualQuality : state.result?.quality) ?? 70;
    final sides = candidateSides(state.longestSide);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.photoManual, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(l10n.photoSide, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in sides)
              ChoiceChip(
                label: Text(s == sides.first ? l10n.photoOriginal : '$s'),
                selected: s == side,
                onSelected: (_) => notifier.setManual(side: s),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.photoQuality(quality)),
        Slider(
          min: 1,
          max: 100,
          divisions: 99,
          value: quality.clamp(1, 100).toDouble(),
          label: '$quality',
          onChanged: (v) => notifier.setManual(quality: v.round()),
        ),
        if (manual)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: notifier.backToAuto,
              child: Text(l10n.photoBackToAuto),
            ),
          ),
      ],
    );
  }
}
