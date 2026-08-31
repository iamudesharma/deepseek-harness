/// Session-header preset label — Flutter port of `AgentPresetLabel.tsx`:
/// the read-only report of what preset the current session already runs
/// (fixed at session start; the header never offers a switch).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_provider.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../locales.dart';

/// Header entry rendering the current session's preset display name; hidden
/// while no session is selected or its summary carries no preset.
class AgentPresetHeaderLabel extends ConsumerWidget {
  /// Creates the label.
  const AgentPresetHeaderLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(kAgentPresetNamespace);

    final summary = ref.watch(currentSessionProvider);
    final String? presetId = summary?.agentPreset;
    if (presetId == null) return const SizedBox.shrink();

    // Roster-independent fallback keeps the label replay-stable while the
    // catalog loads: id first, localized built-in copy when it ships.
    final display = presetDisplayText(id: presetId, builtIn: true, t: t);
    return Tooltip(
      message: t('headerHint'),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DswTokens.spaceSm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: aliases.bgOverlay,
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          border: Border.all(color: aliases.borderL2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 12, color: aliases.labelTertiary),
            const SizedBox(width: 4),
            Text(
              display.name,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                fontWeight: FontWeight.w600,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
