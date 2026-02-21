import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';

/// Globe icon button that opens a bottom sheet for quick language switching.
///
/// Place in AppBar actions on every tabbed screen.
class LanguageSwitcherButton extends ConsumerWidget {
  const LanguageSwitcherButton({super.key});

  static const _flags = {
    'en': '\u{1F1FA}\u{1F1F8}',
    'ru': '\u{1F1F7}\u{1F1FA}',
    'tr': '\u{1F1F9}\u{1F1F7}',
    'uk': '\u{1F1FA}\u{1F1E6}',
    'ka': '\u{1F1EC}\u{1F1EA}',
  };

  static const _localeNames = {
    'en': 'English',
    'ru': 'Русский',
    'tr': 'Türkçe',
    'uk': 'Українська',
    'ka': 'ქართული',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.language),
      tooltip: AppLocalizations.of(context)!.language,
      onPressed: () => _showLanguageSheet(context, ref),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentLocale = ref.read(localeProvider);

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.language,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              RadioListTile<Locale?>(
                title: Row(
                  children: [
                    const Icon(Icons.phone_android, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.systemDefault),
                  ],
                ),
                value: null,
                groupValue: currentLocale,
                onChanged: (v) {
                  ref.read(localeProvider.notifier).setLocale(v);
                  Navigator.of(sheetContext).pop();
                },
              ),
              ...AppLocalizations.supportedLocales.map((locale) {
                final code = locale.languageCode;
                final flag = _flags[code] ?? '';
                final name = _localeNames[code] ?? code;
                return RadioListTile<Locale?>(
                  title: Row(
                    children: [
                      Text(flag, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(name),
                    ],
                  ),
                  value: locale,
                  groupValue: currentLocale,
                  onChanged: (v) {
                    ref.read(localeProvider.notifier).setLocale(v);
                    Navigator.of(sheetContext).pop();
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
