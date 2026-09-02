/// Agent loop card — how the agent dispatches tool calls.
///
/// Mirrors `packages/client/ui-settings-plugins/src/client/AgentLoopCard.tsx`.
library;

import 'package:flutter/material.dart';

import '../card_form.dart';
import '../widgets/fields.dart';
import '../widgets/plugin_card.dart';

class AgentLoopCard extends StatelessWidget {
  const AgentLoopCard({super.key, required this.form});

  final CardForm<Map<String, Object?>> form;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: form,
        builder: (context, _) {
          final CardShell shell = form.shell();
          final CardFieldState parallel = form.field('maxParallelToolCalls');
          return PluginCard(
            title: 'Agent loop',
            description: 'How the agent dispatches tool calls.',
            shell: shell,
            onSave: () => form.save(),
            onDiscard: () => form.discard(),
            child: ValueField(
              id: 'plugin-config-agent-loop-parallel',
              label: 'Parallel tool calls',
              hint: 'Upper bound on parallel-safe calls running at once within one step.',
              text: parallel.text,
              overridden: parallel.overridden,
              invalid: parallel.invalid,
              overriddenLabel: 'Overridden',
              resetLabel: 'Reset to default',
              invalidLabel: 'Enter a number, or leave blank to use the default.',
              numeric: true,
              disabled: !shell.writable,
              onEdit: (v) => form.edit('maxParallelToolCalls', v),
              onReset: () => form.resetField('maxParallelToolCalls'),
            ),
          );
        },
      );
}
