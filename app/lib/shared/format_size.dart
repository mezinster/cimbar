import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';

/// A byte count in the app's language: its decimal separator ("14,8" in most
/// European languages) and unit names ("КБ" in Russian, Ukrainian and
/// Belarusian).
String formatSize(AppLocalizations l10n, int bytes) {
  if (bytes < 1024) return l10n.sizeBytes('$bytes');
  if (bytes < 1024 * 1024) {
    return l10n.sizeKilobytes(_oneDecimal(l10n.localeName, bytes / 1024));
  }
  return l10n.sizeMegabytes(_oneDecimal(l10n.localeName, bytes / (1024 * 1024)));
}

String _oneDecimal(String locale, double value) {
  try {
    return NumberFormat('0.0', locale).format(value);
  } on ArgumentError {
    return value.toStringAsFixed(1);
  }
}
