/// Session header — title, run-state dot, cancel action while running, and
/// the `conversation.session.header.actions` list hole for dependents.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../core/slots/slot_registry.dart';
import '../hub.dart';
import 'slots/hole_outlet.dart';

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

    final state = ref.watch(sessionsProvider);
    final summary = state.byId[SessionId(sessionId)];
    final running = summary?.running ?? false;

    final String title = summary == null
        ? sessionId
        : summary.blank
        ? 'New session'
        : summary.displayTitle;
    final String? agentPreset = summary?.agentPreset;
    final String location = GoRouterState.of(context).matchedLocation;
    final bool isTrajectory = location.endsWith('/trajectory');
    // Session log action is part of header.utilities hole in React; we keep the actions hole
    // but also render a simple Session log chip for parity when not blank.
    return Container(
      decoration: BoxDecoration(
        color: aliases.bgBase,
        border: Border(bottom: BorderSide(color: aliases.borderL2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: dot + title + Creator mode pill + utilities
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running
                        ? aliases.stateWarnPrimary
                        : aliases.stateSuccessPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeS14,
                            fontWeight: FontWeight.w500,
                            color: aliases.labelPrimary,
                          ),
                        ),
                      ),
                      if (agentPreset != null && agentPreset.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: aliases.bgLayer2,
                            borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                            border: Border.all(color: aliases.borderL2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune_rounded, size: 12, color: aliases.labelTertiary),
                              const SizedBox(width: 4),
                              Text(
                                _presetLabel(agentPreset),
                                style: TextStyle(
                                  fontSize: DswTokens.fontSizeXxs12,
                                  fontWeight: FontWeight.w500,
                                  color: aliases.labelSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Dependent actions (list hole) + utilities
                HoleOutlet(
                  registry: activatedHub?.slots ?? SlotRegistry(),
                  slotKey: 'conversation.session.header.actions',
                ),
                HoleOutlet(
                  registry: activatedHub?.slots ?? SlotRegistry(),
                  slotKey: 'conversation.session.header.utilities',
                ),
                if (!isTrajectory)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        side: BorderSide(color: aliases.borderL2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DswTokens.radiusFull)),
                      ),
                      onPressed: () {},
                      icon: Icon(Icons.download_rounded, size: 14, color: aliases.labelTertiary),
                      label: Text(
                        'Session log',
                        style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelSecondary),
                      ),
                    ),
                  ),
                if (running)
                  IconButton(
                    tooltip: 'Cancel turn',
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    onPressed: () => activatedHub?.controller.cancelTurn(SessionId(sessionId)),
                  ),
              ],
            ),
          ),
          // Tab row: Chat / Trajectory (mirrors conversation.view roster selection)
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: aliases.borderL2)),
            ),
            child: Row(
              children: [
                _HeaderTab(
                  label: 'Chat',
                  selected: !isTrajectory,
                  onTap: () => context.go('/sessions/$sessionId'),
                  aliases: aliases,
                ),
                const SizedBox(width: 24),
                _HeaderTab(
                  label: 'Trajectory',
                  selected: isTrajectory,
                  onTap: () => context.go('/sessions/$sessionId/trajectory'),
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _presetLabel(String preset) {
  final low = preset.toLowerCase();
  if (low.contains('creator')) return 'Creator mode';
  if (low.contains('plan')) return 'Plan mode';
  if (low == 'default' || low.isEmpty) return preset;
  // Title case fallback
  return preset[0].toUpperCase() + preset.substring(1);
}

class _HeaderTab extends StatelessWidget {
  const _HeaderTab({required this.label, required this.selected, required this.onTap, required this.aliases});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? aliases.stateBusinessPrimary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? aliases.stateBusinessPrimary : aliases.labelTertiary,
          ),
        ),
      ),
    );
  }
}
