import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/state_dot.dart';
import '../goal_models.dart';
import '../locales.dart';

/// GoalBar — current goal strip with progress and actions.
///
/// Flutter port of web `GoalBar.tsx`: glyph, phase label, truncated
/// objective, progress bar when determinable, and icon actions
/// (pause/resume, edit, clear). Renders nothing when goal is `null` to match
/// web's "no goal renders nothing" gate.
///
/// Pure build, no `ctx` — callbacks are plain `VoidCallback`/`ValueChanged`.
class GoalBar extends ConsumerWidget {
  /// Creates the goal bar.
  const GoalBar({
    super.key,
    required this.goal,
    this.onPause,
    this.onResume,
    this.onEdit,
    this.onClear,
    this.pending = false,
  });

  /// Current goal — `null` renders nothing (web parity).
  final GoalSnapshot? goal;

  /// Called when pause is pressed (active goals).
  final VoidCallback? onPause;

  /// Called when resume is pressed (paused goals).
  final VoidCallback? onResume;

  /// Called when edit is pressed with the current objective.
  final ValueChanged<String>? onEdit;

  /// Called when clear is pressed.
  final VoidCallback? onClear;

  /// Whether an action is in flight — disables controls.
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoalSnapshot? g = goal;
    // Web gate: loading/undefined/null/complete renders nothing.
    if (g == null || g.phase == GoalPhase.complete)
      return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    // Phase + action copy resolve through the goal dictionaries; the
    // revision watch inside bindLocale re-renders on a Language-row switch.
    final Translate t = ref.bindLocale(kGoalNamespace);
    final String phaseLabel = switch (g.phase) {
      GoalPhase.active => t('phase.active'),
      GoalPhase.paused => t('phase.paused'),
      GoalPhase.blocked => t('phase.blocked'),
      GoalPhase.complete => t('phase.complete'),
    };

    final Color phaseColor = switch (g.phase) {
      GoalPhase.active => aliases.stateSuccessPrimary,
      GoalPhase.paused => aliases.labelTertiary,
      GoalPhase.blocked => aliases.stateWarnPrimary,
      GoalPhase.complete => aliases.stateSuccessPrimary,
    };

    final StateDotState dotState = switch (g.phase) {
      GoalPhase.active => StateDotState.ongoing,
      GoalPhase.paused => StateDotState.warning,
      GoalPhase.blocked => StateDotState.warning,
      GoalPhase.complete => StateDotState.done,
    };

    final double? progress = g.progress;

    return Container(
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        border: Border.all(color: aliases.borderL2),
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceMd,
        vertical: DswTokens.spaceSm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StateDot(state: dotState, size: 10),
              const SizedBox(width: DswTokens.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                ),
                child: Text(
                  phaseLabel,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    fontWeight: FontWeight.w600,
                    color: phaseColor,
                  ),
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Text(
                  g.objective,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.labelPrimary,
                  ),
                ),
              ),
              if (g.phase == GoalPhase.blocked && g.blockedReason != null)
                Padding(
                  padding: const EdgeInsets.only(left: DswTokens.spaceSm),
                  child: Tooltip(
                    message: g.blockedReason!,
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: aliases.stateWarnPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: DswTokens.spaceSm),
              _GoalActions(
                phase: g.phase,
                pending: pending,
                aliases: aliases,
                onPause: onPause,
                onResume: onResume,
                onEdit: onEdit == null ? null : () => onEdit!(g.objective),
                onClear: onClear,
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            ClipRRect(
              borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 4,
                backgroundColor: aliases.bgOverlay,
                valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(progress.clamp(0, 1) * 100).round()}%',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelCaption,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalActions extends ConsumerWidget {
  const _GoalActions({
    required this.phase,
    required this.pending,
    required this.aliases,
    this.onPause,
    this.onResume,
    this.onEdit,
    this.onClear,
  });

  final GoalPhase phase;
  final bool pending;
  final DswAliases aliases;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onEdit;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kGoalNamespace);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (phase == GoalPhase.active)
          _IconAction(
            tooltip: t('action.pause'),
            icon: Icons.pause,
            onPressed: pending ? null : onPause,
            aliases: aliases,
          ),
        if (phase == GoalPhase.paused)
          _IconAction(
            tooltip: t('action.resume'),
            icon: Icons.play_arrow,
            onPressed: pending ? null : onResume,
            aliases: aliases,
          ),
        _IconAction(
          tooltip: t('action.edit'),
          icon: Icons.edit_outlined,
          onPressed: pending ? null : onEdit,
          aliases: aliases,
        ),
        _IconAction(
          tooltip: t('action.clear'),
          icon: Icons.delete_outline,
          onPressed: pending ? null : onClear,
          aliases: aliases,
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.aliases,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final DswAliases aliases;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 16),
        color: aliases.labelSecondary,
        disabledColor: aliases.labelCaption,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
    );
  }
}
