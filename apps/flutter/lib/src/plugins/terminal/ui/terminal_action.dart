/// Session-header console-terminal action, mounted through the
/// `conversation.session.header.actions` hole (id `terminal`, right after
/// the `job-list` entry).
///
/// The action is always visible: unlike jobs, the console pool is
/// host-global rather than session-scoped, so there is no per-session
/// signal to gate on. It navigates to the terminal screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart';

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

    return Tooltip(
      message: t('action.tooltip'),
      child: InkWell(
        onTap: () {
          final SessionId? sid = sessionId;
          if (sid == null) return;
          context.go('/sessions/${sid.value}/terminal');
        },
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DswTokens.spaceSm,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.terminal_rounded,
                size: 14,
                color: aliases.labelTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                t('action.label'),
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXs13,
                  color: aliases.labelTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
