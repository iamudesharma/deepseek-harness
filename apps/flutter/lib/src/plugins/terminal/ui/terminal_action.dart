/// Session-header console-terminal action, mounted through the
/// `conversation.session.header.actions` hole (id `terminal`, right after
/// the `job-list` entry).
///
/// The action is always visible: unlike jobs, the console pool is
/// host-global rather than session-scoped, so there is no per-session
/// signal to gate on. On the desktop shell it toggles the docked terminal
/// panel; mobile shells keep the full-screen route.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../platform/layout.dart' show isMobileShell;
import '../../../theme/app_theme.dart';
import '../locales.dart';
import '../terminal_models.dart';

/// Session-header entry point for the console terminal panel.
class TerminalAction extends ConsumerWidget {
  /// Creates the header action.
  const TerminalAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(kTerminalNamespace);
    final SessionId? sessionId = ref.watch(currentSessionIdProvider);
    final bool panelVisible = ref.watch(terminalPanelVisibleProvider);
    final Color accent = panelVisible
        ? aliases.labelPrimary
        : aliases.labelTertiary;

    return Tooltip(
      message: panelVisible ? t('dock.hide') : t('action.tooltip'),
      // Narrow header slots cannot fit the name: collapse to a
      // lightly-padded icon instead of overflowing the Row — the same
      // contract as `AgentPresetHeaderLabel`'s iconOnly seat.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool iconOnly =
              constraints.maxWidth < 64 && constraints.maxWidth.isFinite;
          return InkWell(
            onTap: () {
              final SessionId? sid = sessionId;
              if (sid == null) return;
              if (isMobileShell(context)) {
                context.go('/sessions/${sid.value}/terminal');
                return;
              }
              ref.read(terminalPanelVisibleProvider.notifier).state =
                  !panelVisible;
            },
            borderRadius: BorderRadius.circular(DswTokens.radiusSm),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: iconOnly ? 2 : DswTokens.spaceSm,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal_rounded, size: 14, color: accent),
                  if (!iconOnly) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        t('action.label'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXs13,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
