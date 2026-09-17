import 'package:flutter/material.dart';

import '../../core/models/decode_result.dart';
import '../../l10n/generated/app_localizations.dart';

class ResultCard extends StatelessWidget {
  final DecodeResult result;
  final VoidCallback? onSave;
  final VoidCallback? onShare;

  const ResultCard({
    super.key,
    required this.result,
    this.onSave,
    this.onShare,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  l10n.decodeSuccess,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.decodedFile(result.filename),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            Text(
              l10n.decodedSize(_formatSize(result.data.length)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            // Wrap, not Row: the two labels do not fit side by side in every
            // locale (Russian overflowed by 9 px on a Pixel 8 Pro), so the
            // second button moves to its own line when needed.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onSave != null)
                  FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save),
                    label: Text(l10n.saveFile),
                  ),
                if (onShare != null)
                  OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share),
                    label: Text(l10n.shareFile),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
