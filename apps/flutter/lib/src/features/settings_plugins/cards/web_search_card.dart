/// Web search card — DeepSeek search provider.
///
/// Mirrors `packages/client/ui-settings-plugins/src/client/WebSearchCard.tsx`
/// plus `web-search-card-controller.ts`. The API key is written through the
/// credentials domain (here stubbed via the same settings mutate path until
/// credentials wiring lands).
library;

import 'package:flutter/material.dart';

import '../card_form.dart';
import '../widgets/fields.dart';
import '../widgets/plugin_card.dart';

class WebSearchCard extends StatelessWidget {
  const WebSearchCard({
    super.key,
    required this.form,
    this.apiKeyConfigured = false,
    this.apiKeyWritable = true,
  });

  final CardForm<Map<String, Object?>> form;

  /// Whether host reports a configured key for the current ref.
  final bool apiKeyConfigured;

  /// Whether credentials domain accepts writes (false disables secret field).
  final bool apiKeyWritable;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: form,
        builder: (context, _) {
          final CardShell shell = form.shell();
          final CardFieldState key = form.field('apiKey');
          final CardFieldState baseUrl = form.field('baseURL');
          final CardFieldState maxUses = form.field('maxUses');
          return PluginCard(
            title: 'Web search',
            description: 'The DeepSeek search provider.',
            shell: shell,
            onSave: () => form.save(),
            onDiscard: () => form.discard(),
            child: Column(
              children: [
                SecretField(
                  id: 'plugin-config-web-search-key',
                  label: 'API key',
                  hint: 'Stored outside the settings file. Leave blank to keep the current key.',
                  text: key.text,
                  disabled: !apiKeyWritable,
                  configured: apiKeyConfigured,
                  stateLabel: apiKeyConfigured ? 'A key is configured.' : 'No key is configured; search is unavailable until one is.',
                  onEdit: (v) => form.edit('apiKey', v),
                ),
                ValueField(
                  id: 'plugin-config-web-search-endpoint',
                  label: 'Endpoint',
                  hint: 'Leave blank to use the provider default.',
                  text: baseUrl.text,
                  overridden: baseUrl.overridden,
                  invalid: baseUrl.invalid,
                  overriddenLabel: 'Overridden',
                  resetLabel: 'Reset to default',
                  invalidLabel: 'Enter a number, or leave blank to use the default.',
                  disabled: !shell.writable,
                  onEdit: (v) => form.edit('baseURL', v),
                  onReset: () => form.resetField('baseURL'),
                ),
                ValueField(
                  id: 'plugin-config-web-search-max-uses',
                  label: 'Max searches per request',
                  hint: 'How many times one request may search before it must answer.',
                  text: maxUses.text,
                  overridden: maxUses.overridden,
                  invalid: maxUses.invalid,
                  overriddenLabel: 'Overridden',
                  resetLabel: 'Reset to default',
                  invalidLabel: 'Enter a number, or leave blank to use the default.',
                  numeric: true,
                  disabled: !shell.writable,
                  onEdit: (v) => form.edit('maxUses', v),
                  onReset: () => form.resetField('maxUses'),
                ),
              ],
            ),
          );
        },
      );
}
