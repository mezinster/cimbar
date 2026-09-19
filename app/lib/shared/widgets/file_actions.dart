import 'package:flutter/material.dart';

import '../../core/services/file_service.dart';
import '../../l10n/generated/app_localizations.dart';

/// Snackbar feedback shared by every screen that offers Open / Save to device.
Future<void> openWithFeedback(BuildContext context, Future<OpenOutcome> Function() open) async {
  final outcome = await open();
  if (!context.mounted || outcome == OpenOutcome.opened) return;
  final l10n = AppLocalizations.of(context)!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(outcome == OpenOutcome.noApp ? l10n.noAppToOpen : l10n.openFailed)),
  );
}

Future<void> exportWithFeedback(BuildContext context, Future<bool> Function() export) async {
  final saved = await export();
  if (!context.mounted || !saved) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.savedToDevice)));
}
