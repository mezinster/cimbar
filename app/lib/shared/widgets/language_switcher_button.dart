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
    'pl': '\u{1F1F5}\u{1F1F1}',
    'be': '\u{1F1E7}\u{1F1FE}',
  };

  static const _localeNames = {
    'en': 'English',
    'ru': 'Русский',
    'tr': 'Türkçe',
    'uk': 'Українська',
    'ka': 'ქართული',
    'pl': 'Polski',
    'be': 'Беларуская',
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

    // A focused text field would keep the keyboard up over the sheet.
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      // Above the shell, so the bottom tab bar doesn't cover the last rows.
      useRootNavigator: true,
      // Sized to its rows, up to the safe area, scrolling on short screens.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: RadioGroup<Locale?>(
              groupValue: currentLocale,
              onChanged: (v) {
                ref.read(localeProvider.notifier).setLocale(v);
                Navigator.of(sheetContext).pop();
              },
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
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
