import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

class FilePickerZone extends StatelessWidget {
  final VoidCallback onTap;
  final String? selectedFileName;
  final bool enabled;

  const FilePickerZone({
    super.key,
    required this.onTap,
    this.selectedFileName,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selectedFileName != null ? Icons.insert_drive_file : Icons.upload_file,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              selectedFileName ?? l10n.dropFileHere,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: selectedFileName != null
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: enabled ? onTap : null,
              child: Text(l10n.selectFile),
            ),
          ],
        ),
      ),
    );
  }
}
