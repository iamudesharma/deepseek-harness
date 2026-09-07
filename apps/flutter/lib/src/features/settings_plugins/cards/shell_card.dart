/// Shell plugin card — limits every command the agent runs.
///
/// Mirrors `packages/client/ui-settings-plugins/src/client/BashCard.tsx` +
/// `bash-card-controller.ts` (namespace `shell`).
library;

import 'package:flutter/material.dart';

import '../card_form.dart';
import '../widgets/fields.dart';
import '../widgets/plugin_card.dart';

class ShellCard extends StatelessWidget {
  const ShellCard({
    super.key,
    required this.form,
  });

  final CardForm<Map<String, Object?>> form;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: form,
        builder: (context, _) {
          final CardShell shell = form.shell();
          final CardFieldState timeout = form.field('timeoutMs');
          final CardFieldState output = form.field('maxOutputBytes');
          final bool writable = shell.writable;
          return PluginCard(
            title: 'Shell',
            description: 'Limits every command the agent runs.',
            shell: shell,
            onSave: () => form.save(),
            onDiscard: () => form.discard(),
            child: Column(
              children: [
                ValueField(
                  id: 'plugin-config-bash-timeout',
                  label: 'Command timeout (ms)',
                  hint: 'How long one command may run before it is terminated.',
                  text: timeout.text,
                  overridden: timeout.overridden,
                  invalid: timeout.invalid,
                  overriddenLabel: 'Overridden',
                  resetLabel: 'Reset to default',
                  invalidLabel: 'Enter a number, or leave blank to use the default.',
                  numeric: true,
                  disabled: !writable,
                  onEdit: (v) => form.edit('timeoutMs', v),
                  onReset: () => form.resetField('timeoutMs'),
                ),
                ValueField(
                  id: 'plugin-config-bash-output',
                  label: 'Output cap per stream (bytes)',
                  hint: 'Output beyond this spills to a temporary file rather than being lost.',
                  text: output.text,
                  overridden: output.overridden,
                  invalid: output.invalid,
                  overriddenLabel: 'Overridden',
                  resetLabel: 'Reset to default',
                  invalidLabel: 'Enter a number, or leave blank to use the default.',
                  numeric: true,
                  disabled: !writable,
                  onEdit: (v) => form.edit('maxOutputBytes', v),
                  onReset: () => form.resetField('maxOutputBytes'),
                ),
              ],
            ),
          );
        },
      );
}
