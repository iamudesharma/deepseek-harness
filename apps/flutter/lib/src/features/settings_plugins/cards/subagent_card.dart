/// Subagent model-selection card — full parity with React.
///
/// Mirrors `packages/client/ui-settings-plugins/src/client/SubagentModelSelectionCard.tsx`
/// via [SubagentController] (catalog join, staged enabled + allowedModels).
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../settings_plugins/widgets/plugin_card.dart';
import '../card_form.dart';
import 'subagent_controller.dart';

class SubagentCard extends StatelessWidget {
  const SubagentCard({super.key, required this.controller});

  final SubagentController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final SubagentCardState s = controller.state;
          final DswAliases aliases =
              Theme.of(context).extension<DswThemeExtension>()?.aliases ??
                  (Theme.of(context).brightness == Brightness.dark
                      ? DswTokens.darkAliases
                      : DswTokens.lightAliases);

          // Derive shell for PluginCard chrome.
          final pluginShell = _toShell(s);

          // Group available vs unavailable.
          final Map<String, List<SubagentModelCandidate>> availableGroups = {};
          final List<SubagentModelCandidate> unavailable = [];
          for (final c in s.candidates) {
            if (!c.available) {
              unavailable.add(c);
            } else {
              availableGroups.putIfAbsent(c.provider, () => []).add(c);
            }
          }
          // Need provider display names: candidates carry providerName, group by provider.
          // Build map provider -> {providerName, list}
          final Map<String, ({String name, List<SubagentModelCandidate> list})> grouped = {};
          for (final c in s.candidates.where((e) => e.available)) {
            final existing = grouped[c.provider];
            if (existing == null) {
              grouped[c.provider] = (name: c.providerName, list: [c]);
            } else {
              existing.list.add(c);
            }
          }

          Widget candidateRow(SubagentModelCandidate c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: c.selected,
                      onChanged: (!s.writable || s.saving) ? null : (_) => controller.toggleModel(c.key),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.modelName,
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeS14,
                                color: aliases.labelPrimary,
                              )),
                          Text('${c.providerName} · ${c.provider}/${c.model}',
                              style: TextStyle(fontSize: 11, color: aliases.labelTertiary)),
                        ],
                      ),
                    ),
                    if (!c.available)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: aliases.bgOverlay,
                          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                        ),
                        child: Text('Currently unavailable',
                            style: TextStyle(fontSize: 11, color: aliases.labelTertiary)),
                      ),
                  ],
                ),
              );

          return PluginCard(
            title: 'Subagent',
            description: 'Control which models agents may choose for subagents.',
            shell: pluginShell,
            onSave: () => controller.save(),
            onDiscard: () => controller.discard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Toggle row
                Row(
                  children: [
                    Expanded(
                      child: Text('Allow agents to choose models for subagents',
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeS14,
                            fontWeight: FontWeight.w500,
                            color: aliases.labelPrimary,
                          )),
                    ),
                    Switch(
                      value: s.enabled,
                      activeThumbColor: aliases.stateBusinessPrimary,
                      onChanged: (!s.writable || s.saving) ? null : (_) => controller.toggleEnabled(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.enabled
                      ? 'When enabled, agents can choose a provider, model, and reasoning effort for each subagent from the authorized models below. Applies only to new sessions.'
                      : 'Subagents use configured defaults or inherit the parent agent\'s model. Saved model choices are retained.',
                  style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary),
                ),
                if (s.enabled) ...[
                  const SizedBox(height: DswTokens.spaceMd),
                  if (s.catalogStatus == 'loading')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Loading models…',
                          style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary)),
                    ),
                  if (s.catalogStatus == 'error')
                    Container(
                      padding: const EdgeInsets.all(DswTokens.spaceSm),
                      decoration: BoxDecoration(
                        color: aliases.stateErrorPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                        border: Border.all(color: aliases.stateErrorPrimary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Models could not be loaded.',
                                style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
                          ),
                          TextButton(
                            onPressed: s.saving ? null : () => controller.retryCatalog(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  if (s.catalogPartial)
                    Padding(
                      padding: const EdgeInsets.only(top: DswTokens.spaceSm),
                      child: Text('Some model providers could not be loaded; saved choices remain removable.',
                          style: TextStyle(fontSize: 11, color: aliases.labelCaption)),
                    ),
                  if (s.candidates.isNotEmpty) ...[
                    const SizedBox(height: DswTokens.spaceSm),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: aliases.borderL1),
                        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                      ),
                      padding: const EdgeInsets.all(DswTokens.spaceMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Models agents may choose',
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeXxs12,
                                fontWeight: FontWeight.w600,
                                color: aliases.labelPrimary,
                              )),
                          const SizedBox(height: DswTokens.spaceSm),
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(entry.value.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: aliases.labelTertiary,
                                  )),
                            ),
                            for (final c in entry.value.list) candidateRow(c),
                          ],
                          if (unavailable.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Text('Saved but currently unavailable',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: aliases.labelTertiary,
                                  )),
                            ),
                            for (final c in unavailable) candidateRow(c),
                          ],
                        ],
                      ),
                    ),
                  ] else if (s.catalogStatus == 'ready')
                    Padding(
                      padding: const EdgeInsets.only(top: DswTokens.spaceSm),
                      child: Text('No model provider currently advertises a model.',
                          style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary)),
                    ),
                  if (s.invalid)
                    Padding(
                      padding: const EdgeInsets.only(top: DswTokens.spaceSm),
                      child: Text('Select at least one model before saving.',
                          style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
                    ),
                ],
                if (s.conflicted)
                  Padding(
                    padding: const EdgeInsets.only(top: DswTokens.spaceSm),
                    child: Text('Settings changed elsewhere. Discard your draft and try again.',
                        style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
                  ),
              ],
            ),
          );
        },
      );
}

// Adapt SubagentCardState to generic CardShell for PluginCard.
CardShell _toShell(SubagentCardState s) => CardShell(
      available: s.available,
      writable: s.writable,
      dirty: s.dirty,
      invalid: s.invalid,
      saving: s.saving,
      failed: s.failed,
    );
