import 'package:flutter/material.dart';

import '../../core/models/decode_result.dart';

class ProgressCard extends StatelessWidget {
  final DecodeProgress progress;

  const ProgressCard({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = progress.state == DecodeState.error;

    return Card(
      color: isError ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!isError && progress.state != DecodeState.done)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (isError)
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                if (progress.state == DecodeState.done)
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    progress.message ?? '',
                    style: TextStyle(
                      color: isError ? theme.colorScheme.onErrorContainer : null,
                    ),
                  ),
                ),
              ],
            ),
            if (!isError && progress.state != DecodeState.done) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress.progress),
            ],
          ],
        ),
      ),
    );
  }
}
