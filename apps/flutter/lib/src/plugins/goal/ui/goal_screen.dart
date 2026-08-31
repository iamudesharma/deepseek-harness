import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_provider.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../goal_models.dart';
import '../locales.dart';
import '../goal_projection.dart';
import 'goal_bar.dart';

/// Goal screen — header + [GoalBar] + current-goal strip.
///
/// Flutter-side surface for the goal domain (React ships only the dock and
/// chat renderer): reads the bound [boundGoalProjectionSource] projection
/// bridge and routes mutations through the bound [boundGoalControl], so it
/// shows exactly what the composer dock shows — no local goal state.
class GoalScreen extends ConsumerWidget {
  /// Creates the goal screen.
  const GoalScreen({super.key, this.sessionId});

  /// Optional session scoping — falls back to the current session.
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final String sid =
        sessionId ?? ref.watch(currentSessionIdProvider)?.value ?? '';
    final GoalSnapshot? goal = boundGoalProjectionSource?.snapshotOf(sid);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Goal',
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          _HeaderCard(aliases: aliases, goal: goal),
          const SizedBox(height: DswTokens.spaceLg),
          if (goal != null)
            GoalBar(goal: goal)
          else
            _EmptyGoal(aliases: aliases),
          if (goal != null) ...[
            const SizedBox(height: DswTokens.spaceLg),
            Text(
              'Current goal',
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: DswTokens.spaceSm),
            _GoalListTile(snapshot: goal, aliases: aliases),
          ],
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.aliases, required this.goal});

  final DswAliases aliases;
  final GoalSnapshot? goal;

  @override
  Widget build(BuildContext context) {
    final String title = goal == null ? 'No active goal' : goal!.objective;
    final String subtitle = goal == null
        ? 'Use /goal to create one.'
        : 'Phase: ${goal!.phase.name} · ${goal!.progress == null ? 'progress unknown' : '${(goal!.progress! * 100).round()}%'}';

    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: aliases.stateBusinessTertiary,
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            ),
            child: Icon(
              Icons.flag_outlined,
              size: 20,
              color: aliases.stateBusinessPrimary,
            ),
          ),
          const SizedBox(width: DswTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalListTile extends StatelessWidget {
  const _GoalListTile({required this.snapshot, required this.aliases});

  final GoalSnapshot snapshot;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final Color phaseColor = switch (snapshot.phase) {
      GoalPhase.active => aliases.stateSuccessPrimary,
      GoalPhase.paused => aliases.labelTertiary,
      GoalPhase.blocked => aliases.stateWarnPrimary,
      GoalPhase.complete => aliases.labelCaption,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceMd,
        vertical: DswTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: phaseColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: DswTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.objective,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${snapshot.phase.name} · ${snapshot.id}',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (snapshot.progress != null)
            Text(
              '${(snapshot.progress! * 100).round()}%',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                fontWeight: FontWeight.w600,
                color: aliases.labelSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyGoal extends ConsumerWidget {
  const _EmptyGoal({required this.aliases});

  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kGoalNamespace);
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Column(
        children: [
          Icon(Icons.flag_outlined, size: 28, color: aliases.labelCaption),
          const SizedBox(height: DswTokens.spaceSm),
          Text(
            t('empty.title'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t('empty.hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
