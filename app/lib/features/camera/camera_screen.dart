import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../shared/widgets/wide_layout.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/models/decode_result.dart';
import '../../core/services/file_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/file_actions.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/passphrase_field.dart';
import '../../shared/widgets/progress_card.dart';
import '../../shared/widgets/result_card.dart';
import '../photo/presentation/photo_optimiser_provider.dart';
import '../photo/presentation/photo_optimiser_screen.dart';
import 'camera_controller.dart';
import 'live_scan_screen.dart';
import 'photo_capture_screen.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  final _passphraseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _passphraseController.addListener(_onPassphraseChanged);
  }

  @override
  void dispose() {
    _passphraseController.removeListener(_onPassphraseChanged);
    _passphraseController.dispose();
    super.dispose();
  }

  void _onPassphraseChanged() => setState(() {});

  /// The photo decoder reports failures as stable codes; render them in the
  /// user's language and fall back to its English message only when there is
  /// no code (the GIF pipeline's progress messages, which are English).
  DecodeProgress _localized(AppLocalizations l10n, CameraState s) {
    final p = s.progress!;
    final code = s.errorCode;
    if (code == null) return p;
    final text = switch (code) {
      'multi_frame' => l10n.errorMultiFrameNeedsLive(s.errorTotal ?? 0),
      'passphrase_required' => l10n.errorPassphraseRequired,
      'not_located' => l10n.errorNoBarcodeFound,
      'unreadable_image' || 'unsupported_grid' => l10n.errorDecoderFailed(p.message ?? ''),
      'decode_failed' => l10n.errorDecoderFailed(p.message ?? ''),
      _ => p.message ?? '',
    };
    return DecodeProgress(state: p.state, progress: p.progress, message: text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(cameraControllerProvider);
    final controller = ref.read(cameraControllerProvider.notifier);
    final theme = Theme.of(context);
    // A shared photo that didn't decode may be an ordinary photo detection
    // mistook for a barcode: offer to send it instead.
    final sharedPhotoFailed = state.fromShare &&
        !state.isDecoding &&
        state.result == null &&
        state.capturedPhotoPath != null &&
        (state.errorCode != null || state.progress?.state == DecodeState.error);

    final wide = isWide(context);
    final resultCard = state.result == null
        ? null
        : ResultCard(
            result: state.result!,
            onOpen: () => openWithFeedback(context, () => FileService.openResult(state.result!)),
            onExport: () => exportWithFeedback(context, () => FileService.exportBytes(state.result!.filename, state.result!.data)),
            onShare: () => FileService.shareResult(state.result!),
            onShareText: (t) => SharePlus.instance.share(ShareParams(text: t)),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cameraTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: adaptiveBody(
        context,
        right: resultCard != null
            ? SingleChildScrollView(child: resultCard)
            : EmptyPane(icon: Icons.camera_alt_outlined, text: l10n.wideResultEmpty),
        children: [
          Text(l10n.cameraScanInstruction,
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),

          PassphraseField(
            controller: _passphraseController,
            enabled: !state.isDecoding,
          ),
          const SizedBox(height: 16),

          // Capture zone
          if (state.capturedPhotoBytes == null) ...[
            // No photo yet — show capture buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isDecoding
                        ? null
                        : () async {
                            final bytes = await Navigator.of(context, rootNavigator: true).push<Uint8List>(
                              MaterialPageRoute(builder: (_) => const PhotoCaptureScreen()),
                            );
                            if (bytes != null) controller.setPhoto(bytes);
                          },
                    icon: const Icon(Icons.camera_alt),
                    label: Text(l10n.cameraTakePhoto),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isDecoding
                        ? null
                        : () => controller.pickFromGallery(),
                    icon: const Icon(Icons.photo_library),
                    label: Text(l10n.cameraFromGallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: !state.isDecoding
                  ? () => Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => LiveScanScreen(
                            passphrase: _passphraseController.text,
                          ),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.videocam),
              label: Text(l10n.liveScanButton),
            ),
          ] else ...[
            // Photo captured — show thumbnail + retake
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                state.capturedPhotoBytes!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: state.isDecoding ? null : () => controller.reset(),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.cameraRetake),
            ),
          ],
          const SizedBox(height: 16),

          FilledButton(
            onPressed: state.capturedPhotoBytes != null &&
                    !state.isDecoding
                ? () => controller.decode(_passphraseController.text)
                : null,
            child: Text(state.isDecoding ? l10n.decoding : l10n.decode),
          ),
          const SizedBox(height: 16),

          if (state.progress != null) ProgressCard(progress: _localized(l10n, state)),

          if (sharedPhotoFailed) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('sendPhotoInstead'),
              // Opened on the root navigator's context: the optimiser's
              // Continue switches to the Send tab, which disposes this screen.
              // The staged file's name is the sanitised original name.
              onPressed: () => openPhotoOptimiser(
                  rootNavigatorKey.currentContext ?? context,
                  ref,
                  PendingPhoto(
                      path: state.capturedPhotoPath!,
                      name: state.capturedPhotoPath!.split(RegExp(r'[\\/]')).last)),
              icon: const Icon(Icons.send),
              label: Text(l10n.shareSendInstead),
            ),
          ],

          if (resultCard != null && !wide) ...[
            const SizedBox(height: 16),
            resultCard,
          ],
        ],
      ),
    );
  }
}
