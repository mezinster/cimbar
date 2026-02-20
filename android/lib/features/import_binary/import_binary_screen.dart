import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/file_picker_zone.dart';
import '../../shared/widgets/passphrase_field.dart';
import '../../shared/widgets/progress_card.dart';
import '../../shared/widgets/result_card.dart';
import 'import_binary_controller.dart';

class ImportBinaryScreen extends ConsumerStatefulWidget {
  const ImportBinaryScreen({super.key});

  @override
  ConsumerState<ImportBinaryScreen> createState() => _ImportBinaryScreenState();
}

class _ImportBinaryScreenState extends ConsumerState<ImportBinaryScreen> {
  final _passphraseController = TextEditingController();

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(importBinaryControllerProvider);
    final controller = ref.read(importBinaryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.importBinaryTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.selectBinaryFile, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),

          FilePickerZone(
            onTap: () => controller.pickFile(),
            selectedFileName: state.selectedFileName,
            enabled: !state.isDecoding,
          ),
          const SizedBox(height: 16),

          PassphraseField(
            controller: _passphraseController,
            enabled: !state.isDecoding,
          ),
          const SizedBox(height: 16),

          FilledButton(
            onPressed: state.selectedFileBytes != null &&
                    !state.isDecoding &&
                    _passphraseController.text.isNotEmpty
                ? () => controller.decode(_passphraseController.text)
                : null,
            child: Text(state.isDecoding ? l10n.decoding : l10n.decode),
          ),
          const SizedBox(height: 16),

          if (state.progress != null) ProgressCard(progress: state.progress!),

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
            ),
          ],
        ],
      ),
    );
  }
}
