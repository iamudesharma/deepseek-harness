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
      // Narrow header slots (e.g. a 24px rail entry) cannot fit the name:
      // collapse to a lightly-padded icon instead of overflowing the Row.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool iconOnly =
              constraints.maxWidth < 64 && constraints.maxWidth.isFinite;
          // React `.label`: static 22px row, 6px radius, translucent
          // secondary fill (token `--dsw-alias-fill-tsp-secondary` is
          // referenced but undefined upstream, so transparent stands in),
          // 12/22 secondary text, 4px gap, max-width 180, icon at 70%.
          return Container(
            constraints: const BoxConstraints(maxWidth: 180),
            height: 22,
            padding: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: 0.7,
                  child: Icon(
                    Icons.tune,
                    size: 12,
                    color: aliases.labelSecondary,
                  ),
                ),
                if (!iconOnly) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      display.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        height: 22 / 12,
                        color: aliases.labelSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
