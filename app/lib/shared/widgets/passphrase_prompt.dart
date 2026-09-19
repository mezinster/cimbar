import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// In-place passphrase request shown when a fully assembled scan turns out
/// to be encrypted (or the passphrase given up front was wrong). The caller
/// keeps the assembled frames, so submitting here retries the decrypt
/// without rescanning.
class PassphrasePrompt extends StatefulWidget {
  final String? errorText;
  final bool busy;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const PassphrasePrompt({
    super.key,
    this.errorText,
    this.busy = false,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<PassphrasePrompt> createState() => _PassphrasePromptState();
}

class _PassphrasePromptState extends State<PassphrasePrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy || _controller.text.isEmpty) return;
    widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_outline, size: 32),
        const SizedBox(height: 8),
        Text(l10n.passphrasePrompt, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          enabled: !widget.busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: l10n.passphraseHint,
            errorText: widget.errorText,
            prefixIcon: const Icon(Icons.key),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: Text(l10n.cancel)),
            const SizedBox(width: 8),
            FilledButton(onPressed: widget.busy ? null : _submit, child: Text(l10n.decrypt)),
          ],
        ),
      ],
    );
  }
}
