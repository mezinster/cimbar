import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';

class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  static const _localeNames = {
    'en': 'English',
    'ru': 'Русский',
    'tr': 'Türkçe',
    'uk': 'Українська',
    'ka': 'ქართული',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.language,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        RadioListTile<Locale?>(
          title: Text(l10n.systemDefault),
          value: null,
          groupValue: currentLocale,
          onChanged: (v) => ref.read(localeProvider.notifier).setLocale(v),
        ),
        ...AppLocalizations.supportedLocales.map((locale) {
          final name = _localeNames[locale.languageCode] ?? locale.languageCode;
          return RadioListTile<Locale?>(
            title: Text(name),
            value: locale,
            groupValue: currentLocale,
            onChanged: (v) => ref.read(localeProvider.notifier).setLocale(v),
          );
        }),
      ],
    );
  }
}
