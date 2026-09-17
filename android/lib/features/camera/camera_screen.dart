import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/decode_result.dart';
import '../../core/services/file_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/passphrase_field.dart';
import '../../shared/widgets/progress_card.dart';
import '../../shared/widgets/result_card.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cameraTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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

          if (state.result != null) ...[
            const SizedBox(height: 16),
            ResultCard(
              result: state.result!,
              onSave: () async {
                final path = await controller.saveResult();
                if (path != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.fileSaved)),
                  );
                }
              },
              onShare: () => FileService.shareResult(state.result!),
            ),
          ],
        ],
      ),
    );
  }
}
