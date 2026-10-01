import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/encode/send_jobs.dart';
import '../../core/format/cimbar_spec.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/file_picker_zone.dart';
import '../../shared/widgets/language_switcher_button.dart';
import '../../shared/widgets/passphrase_field.dart';
import 'present_screen.dart';
import 'send_controller.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  // Seeded from the provider: the controller outlives this widget across tab switches.
  late final _text = TextEditingController(text: ref.read(sendControllerProvider).text);
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pass.addListener(_onPassChanged);
  }

  @override
  void dispose() {
    _pass.removeListener(_onPassChanged);
    _pass.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onPassChanged() => setState(() {});

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    final f = result.first;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    ref.read(sendControllerProvider.notifier).setFile(f.name, bytes);
  }

  Future<void> _present() async {
    final controller = ref.read(sendControllerProvider.notifier);
    final p = await controller.encode(_pass.text, cap: maxSendFrames);
    if (p == null || !mounted) return;
    final delayMs = ref.read(sendControllerProvider).delayMs;
    // Full-screen: pushed on the root navigator so it covers the tab shell.
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) => PresentScreen(payload: p, delayMs: delayMs)));
  }

  String _errorText(AppLocalizations l10n, String e) {
    if (e == 'empty') return l10n.sendEmpty;
    if (e.startsWith('tooLarge:')) {
      final parts = e.split(':');
      return l10n.sendTooLarge(int.tryParse(parts[1]) ?? 0, int.tryParse(parts[2]) ?? 0);
    }
    if (e.startsWith('failed:')) return l10n.sendFailed(e.substring(7));
    return e;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(sendControllerProvider);
    final controller = ref.read(sendControllerProvider.notifier);
    final canSend = state.hasInput && !state.busy;
    final inputBytes = state.mode == SendMode.text ? utf8Length(state.text) : (state.fileBytes?.length ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabSend),
        actions: const [LanguageSwitcherButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<SendMode>(
            segments: [
              ButtonSegment(value: SendMode.text, label: Text(l10n.sendModeText)),
              ButtonSegment(value: SendMode.file, label: Text(l10n.sendModeFile)),
            ],
            selected: {state.mode},
            onSelectionChanged: (s) => controller.setMode(s.first),
          ),
          const SizedBox(height: 16),
          if (state.mode == SendMode.text)
            TextField(
              key: const Key('sendText'),
              controller: _text,
              maxLines: 10,
              minLines: 4,
              decoration: InputDecoration(
                hintText: l10n.sendTextHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: controller.setText,
            )
          else
            FilePickerZone(onTap: _pickFile, selectedFileName: state.fileName),
          const SizedBox(height: 8),
          if (state.hasInput)
            Text(
              l10n.sendEstimate(_formatSize(inputBytes), estimateFrames(state, encrypted: _pass.text.isNotEmpty)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          PassphraseField(controller: _pass),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(l10n.sendFrameDelay)),
              DropdownButton<int>(
                value: state.delayMs,
                items: [
                  for (final ms in CimbarSpec.delayOptionsMs)
                    DropdownMenuItem(value: ms, child: Text('$ms ms')),
                ],
                onChanged: (v) {
                  if (v != null) controller.setDelay(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.slideshow),
            label: Text(l10n.sendPresent),
            onPressed: canSend ? _present : null,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.gif_box_outlined),
            label: Text(l10n.sendShareGif),
            onPressed: canSend ? () => controller.shareGif(_pass.text) : null,
          ),
          if (state.busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorText(l10n, state.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
