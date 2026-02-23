import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/decode_tuning_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/language_switcher_button.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tuning = ref.watch(decodeTuningProvider);
    final tuningNotifier = ref.read(decodeTuningProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: ListView(
        children: [
          // Decode Tuning section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.decodeTuning, style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),

                // Symbol Sensitivity slider
                Text(l10n.symbolSensitivity, style: theme.textTheme.bodyMedium),
                Slider(
                  value: tuning.symbolThreshold,
                  min: 0.50,
                  max: 0.95,
                  divisions: 18,
                  label: tuning.symbolThreshold.toStringAsFixed(2),
                  onChanged: (v) => tuningNotifier.setSymbolThreshold(v),
                ),
                Text(
                  l10n.symbolSensitivityDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),

                // White Balance toggle
                SwitchListTile(
                  title: Text(l10n.whiteBalanceLabel),
                  value: tuning.enableWhiteBalance,
                  onChanged: (v) => tuningNotifier.setEnableWhiteBalance(v),
                  contentPadding: EdgeInsets.zero,
                ),

                // Relative Color Matching toggle
                SwitchListTile(
                  title: Text(l10n.relativeColorLabel),
                  value: tuning.useRelativeColor,
                  onChanged: (v) => tuningNotifier.setUseRelativeColor(v),
                  contentPadding: EdgeInsets.zero,
                ),

                // Hash Symbol Detection toggle
                SwitchListTile(
                  title: Text(l10n.hashDetectionLabel),
                  value: tuning.useHashDetection,
                  onChanged: (v) => tuningNotifier.setUseHashDetection(v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),

                // Quadrant Offset slider
                Text(l10n.quadrantOffsetLabel, style: theme.textTheme.bodyMedium),
                Slider(
                  value: tuning.quadrantOffset,
                  min: 0.15,
                  max: 0.40,
                  divisions: 25,
                  label: tuning.quadrantOffset.toStringAsFixed(2),
                  onChanged: (v) => tuningNotifier.setQuadrantOffset(v),
                ),
                Text(
                  l10n.quadrantOffsetDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),

                // Reset button
                OutlinedButton.icon(
                  onPressed: () => tuningNotifier.resetDefaults(),
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.resetDefaults),
                ),
              ],
            ),
          ),
          const Divider(),

          // About section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.about, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  l10n.aboutDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _LinkRow(
                  icon: Icons.language,
                  label: '${l10n.webAppLabel}: ${l10n.webAppUrl}',
                  onTap: () => _openUrl(l10n.webAppUrl),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.version('0.8.3'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            label: l10n.privacyPolicy,
            onTap: () => _openUrl(
              'https://github.com/mezinster/cimbar/blob/master/PRIVACY_POLICY.md',
            ),
          ),
          _LinkTile(
            icon: Icons.gavel_outlined,
            label: l10n.licenseInfo,
            onTap: () => _openUrl(
              'https://github.com/mezinster/cimbar/blob/master/LICENSE',
            ),
          ),
          _LinkTile(
            icon: Icons.code,
            label: l10n.sourceCode,
            onTap: () => _openUrl('https://github.com/mezinster/cimbar'),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LinkRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LinkTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: onTap,
    );
  }
}
