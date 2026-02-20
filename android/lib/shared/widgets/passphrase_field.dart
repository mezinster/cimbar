import 'package:flutter/material.dart';

import '../../core/services/crypto_service.dart';
import '../../l10n/generated/app_localizations.dart';

class PassphraseField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;

  const PassphraseField({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  @override
  State<PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<PassphraseField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final strength = CryptoService.passphraseStrength(widget.controller.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: _obscure,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.passphrase,
            hintText: l10n.passphraseHint,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (widget.controller.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: strength / 100,
            color: strength < 40
                ? Colors.red
                : strength < 70
                    ? Colors.orange
                    : Colors.green,
            backgroundColor: Colors.grey.shade300,
          ),
        ],
      ],
    );
  }
}
