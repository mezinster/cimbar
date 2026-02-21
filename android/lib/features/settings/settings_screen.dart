import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/language_switcher_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        actions: const [LanguageSwitcherButton()],
      ),
      body: ListView(
        children: [
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
