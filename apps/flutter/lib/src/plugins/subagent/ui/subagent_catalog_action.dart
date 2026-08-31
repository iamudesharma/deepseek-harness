/// Header catalog action — Flutter port of `SubagentCatalogAction` trimmed to
/// the session data the Dart session model carries (`SessionSummary`:
/// parent lineage, running bit, title; no projection token/timing metrics).
///
/// Visibility rule matches React: the action renders only with evidence of
/// children (summary-known descendants), so selecting a childless session
/// never flashes an empty trigger.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../theme/app_theme.dart';
import '../subagent_link.dart';

/// Children of [parent] known from the shared sessions list, oldest first.
List<SessionSummary> subagentChildrenOf(SessionsState state, SessionId parent) {
  final children =
      state.byId.values.where((s) => s.parentSessionId == parent).toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  return children;
}

/// Session-header entry: count trigger + child navigation menu.
class SubagentCatalogAction extends ConsumerWidget {
  /// Creates the header action bound to its link.
  const SubagentCatalogAction({super.key, required this.link});

  /// Navigation face driven by menu picks.
  final SubagentLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final SessionsState sessions = ref.watch(sessionsProvider);
    final SessionId? current = ref.watch(currentSessionIdProvider);
    if (current == null) return const SizedBox.shrink();

    final List<SessionSummary> children = subagentChildrenOf(sessions, current);
    // No evidence of children — no action (React visibility rule).
    if (children.isEmpty) return const SizedBox.shrink();

    final int runningCount = children.where((s) => s.running).length;
    final String countLabel =
        '${children.length} ${runningCount > 0 ? '$runningCount running · ' : ''}subagent${children.length == 1 ? '' : 's'}';

    return PopupMenuButton<SessionId>(
      tooltip: 'Subagent sessions',
      enabled: true,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      ),
      color: aliases.specificMenu,
      onSelected: (SessionId childId) {
        link.openChild(
          SubagentAddress(parentSessionId: current, childSessionId: childId),
        );
      },
      itemBuilder: (BuildContext ctx) => <PopupMenuEntry<SessionId>>[
        for (final SessionSummary child in children)
          PopupMenuItem<SessionId>(
            value: child.sessionId,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: child.running
                        ? aliases.stateWarnPrimary
                        : aliases.stateSuccessPrimary,
                  ),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.title ?? child.sessionId.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          fontWeight: FontWeight.w500,
                          color: aliases.labelPrimary,
                        ),
                      ),
                      Text(
                        child.running
                            ? 'running'
                            : child.origin == 'subagent'
                            ? 'subagent'
                            : '',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: aliases.labelCaption,
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DswTokens.spaceSm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: runningCount > 0
              ? aliases.stateBusinessTertiary
              : aliases.bgOverlay,
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          border: Border.all(
            color: runningCount > 0
                ? aliases.stateBusinessPrimary
                : aliases.borderL2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 12,
              color: runningCount > 0
                  ? aliases.stateBusinessPrimary
                  : aliases.labelSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              countLabel,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                fontWeight: FontWeight.w600,
                color: runningCount > 0
                    ? aliases.stateBusinessPrimary
                    : aliases.labelSecondary,
              ),
            ),
            Icon(Icons.expand_more, size: 12, color: aliases.labelTertiary),
          ],
        ),
      ),
    );
  }
}
