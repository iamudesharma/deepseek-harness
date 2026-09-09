/// Session header — breadcrumb lineage, title actions/utilities holes, and
/// the Chat/Trajectory view tabs.
///
/// Flutter port of `ConversationSessionHeader` in
/// `packages/client/ui-conversation/src/client/skeleton/ConversationSession.tsx`
/// (`ConversationRoot.module.css` metrics): the title row holds the crumb
/// cluster (subagent ancestry with `/` separators, last crumb current) plus
/// the `header.actions` slot, and the `header.utilities` slot pins right.
/// The bottom hairline is column-owned (see `column.dart`); this header
/// carries no fill and no border, like React.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/session/session_models.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../core/slots/slot_registry.dart';
import '../../conversation/locales.dart' show kConversationNamespace;
import '../hub.dart';
import 'slots/hole_outlet.dart';

/// One ancestry breadcrumb (React `Breadcrumb`: id, displayTitle, subagent).
class HeaderCrumb {
  const HeaderCrumb({
    required this.id,
    required this.displayTitle,
    required this.subagent,
  });
  final SessionId id;
  final String displayTitle;
  final bool subagent;
}

/// Subagent ancestry chain ending at [id] (React `deriveAncestry`):
/// walks `parentSessionId` while the origin is `subagent`, cycle-guarded.
List<HeaderCrumb> deriveHeaderAncestry(
  Map<SessionId, SessionSummary> byId,
  SessionId id,
) {
  final chain = <HeaderCrumb>[];
  final seen = <SessionId>{};
  SessionId? cursor = id;
  while (cursor != null) {
    if (!seen.add(cursor)) break;
    final summary = byId[cursor];
    if (summary == null) break;
    chain.insert(
      0,
      HeaderCrumb(
        id: summary.sessionId,
        displayTitle: summary.displayTitle,
        subagent: summary.origin == 'subagent',
      ),
    );
    if (summary.origin != 'subagent') break;
    cursor = summary.parentSessionId;
  }
  return chain;
}

/// Header row for the active conversation.
class SessionHeaderView extends ConsumerWidget {
  /// Creates the header for one session.
  const SessionHeaderView({super.key, required this.sessionId});

  /// Owning session.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final t = ref.bindLocale(kConversationNamespace);

    final state = ref.watch(sessionsProvider);
    final summary = state.byId[SessionId(sessionId)];
    final ancestry = deriveHeaderAncestry(state.byId, SessionId(sessionId));

    String location = '';
    try {
      location = GoRouterState.of(context).matchedLocation;
    } catch (_) {
      location = '';
    }
    final bool isTrajectory = location.endsWith('/trajectory');
    final SlotRegistry registry = activatedHub?.slots ?? SlotRegistry();
    final bool hasUtilities = registry
        .winnersOfSlot('conversation.session.header.utilities')
        .isNotEmpty;

    // React `.header`: padding 12px 28px 0 20px, no fill, no border (the
    // 0.5px l3 hairline is the column divider below).
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 28, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // React `.titleRow`: min-height 32, gap 0.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                // React `.titleCluster`: flex 1, gap 10, min-width 0.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: HeaderCrumbs(
                          ancestry: ancestry,
                          fallbackId: sessionId,
                          blankTitle: summary != null && summary.blank
                              ? 'New session'
                              : null,
                          aliases: aliases,
                          hierarchyLabel: t('session.hierarchy'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        fit: FlexFit.loose,
                        child: HoleOutlet(
                          registry: registry,
                          slotKey: 'conversation.session.header.actions',
                          direction: Axis.horizontal,
                          spacing: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                // React `.headerUtilities`: gap 8, margin-left 20, hidden
                // when empty.
                if (hasUtilities)
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: HoleOutlet(
                      registry: registry,
                      slotKey: 'conversation.session.header.utilities',
                      direction: Axis.horizontal,
                      spacing: 8,
                    ),
                  ),
              ],
            ),
          ),
          // View tabs (React `tabs.length > 1` roster; this client ships
          // exactly the chat + trajectory views).
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Row(
              children: [
                _HeaderTab(
                  label: 'Chat',
                  selected: !isTrajectory,
                  onTap: () {
                    try {
                      context.go('/sessions/$sessionId');
                    } catch (_) {}
                  },
                  aliases: aliases,
                ),
                const SizedBox(width: 36),
                _HeaderTab(
                  label: 'Trajectory',
                  selected: isTrajectory,
                  onTap: () {
                    try {
                      context.go('/sessions/$sessionId/trajectory');
                    } catch (_) {}
                  },
                  aliases: aliases,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Breadcrumb ancestry nav (React `.crumbs`): `/`-separated crumb buttons,
/// last crumb current and disabled; raw id fallback while unknown.
class HeaderCrumbs extends StatelessWidget {
  const HeaderCrumbs({
    required this.ancestry,
    required this.fallbackId,
    required this.blankTitle,
    required this.aliases,
    required this.hierarchyLabel,
  });

  final List<HeaderCrumb> ancestry;
  final String fallbackId;
  final String? blankTitle;
  final DswAliases aliases;
  final String hierarchyLabel;

  @override
  Widget build(BuildContext context) {
    // Defensive blank title: the column hides the header while blank, so
    // this only shows when a blank summary is mounted directly. Unknown
    // sessions (no summary) fall through to the raw-id fallback below,
    // matching React's `ancestry.length === 0` branch.
    if (blankTitle != null) {
      return Text(
        blankTitle!,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: DswTokens.fontSizeS14,
          fontWeight: FontWeight.w500,
          color: aliases.labelPrimary,
        ),
      );
    }
    if (ancestry.isEmpty) {
      return Text(
        fallbackId,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: DswTokens.fontSizeS14,
          fontWeight: FontWeight.w500,
          color: aliases.labelPrimary,
        ),
      );
    }
    return Semantics(
      container: true,
      label: hierarchyLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < ancestry.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '/',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    height: 20 / 14,
                    color: aliases.labelCaption,
                  ),
                ),
              ),
            Flexible(
              child: HeaderCrumbButton(
                crumb: ancestry[i],
                last: i == ancestry.length - 1,
                aliases: aliases,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HeaderCrumbButton extends StatelessWidget {
  const HeaderCrumbButton({
    required this.crumb,
    required this.last,
    required this.aliases,
  });

  final HeaderCrumb crumb;
  final bool last;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final bool small = crumb.subagent;
    final textStyle = TextStyle(
      fontSize: small ? DswTokens.fontSizeXxs12 : DswTokens.fontSizeS14,
      height: small ? 18 / 12 : 20 / 14,
      fontWeight: last ? FontWeight.w500 : FontWeight.w400,
      color: last ? aliases.labelPrimary : aliases.labelTertiary,
    );
    // The lineage slot has no Flutter contributors; the title fallback
    // below mirrors React's `{ fallback: title }`.
    final label = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        crumb.displayTitle,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      ),
    );
    if (last) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: label,
      );
    }
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: aliases.labelTertiary,
        overlayColor: aliases.interactiveBgHover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        ),
        textStyle: textStyle,
      ),
      onPressed: () {
        try {
          context.go('/sessions/${crumb.id.value}');
        } catch (_) {}
      },
      child: label,
    );
  }
}

class _HeaderTab extends StatelessWidget {
  const _HeaderTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.aliases,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    // React `.tab`: 13/16 w500 tertiary, padding-bottom 11, 2px bar with
    // 2px radius; selected rides the business blue. IntrinsicWidth keeps
    // the bar exactly the text width inside the tab row.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                height: 16 / 13,
                fontWeight: FontWeight.w500,
                color: selected
                    ? aliases.stateBusinessPrimary
                    : aliases.labelTertiary,
              ),
            ),
            const SizedBox(height: 9),
            Container(
              height: 2,
              decoration: BoxDecoration(
                color: selected
                    ? aliases.stateBusinessPrimary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
