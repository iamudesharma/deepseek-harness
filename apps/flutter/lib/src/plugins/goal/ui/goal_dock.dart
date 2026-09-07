/// Composer goal dock — Flutter port of `GoalDock`/`GoalBar.tsx`'s dock
/// adapter, mounted through the hub composer-dock seam (`registerDock`
/// id `goal`, the `conversation.input.dock` entry analog).
///
/// The live goal arrives through [boundGoalProjectionSource] (the
/// `useProjection('goal')` stand-in): loading, absent, complete, and just-
/// cleared goals render nothing, so an ordinary conversation never grows a
/// strip for a capability it is not using. The mutation verbs ride the bound
/// [GoalControl]; failures render inline as `message (code)` while success
/// stays silent (the mutated goal reaches this dock through the projection).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_provider.dart';
import '../../../core/session/session_models.dart' show SessionId;
import '../../../theme/app_theme.dart';
import '../goal_control.dart';
import '../goal_models.dart';
import '../goal_projection.dart';
import 'goal_bar.dart';

/// Dock builder registered by the plugin.
Widget buildGoalDock(BuildContext context) => const _GoalDock();

GoalControl? _boundControl;

/// Bound control bridge for widgets; null until `ui-goal` activates.
GoalControl? get boundGoalControl => _boundControl;

/// Binds (or clears) the goal control bridge.
void bindGoalControl(GoalControl? control) => _boundControl = control;

class _GoalDock extends ConsumerStatefulWidget {
  const _GoalDock();

  @override
  ConsumerState<_GoalDock> createState() => _GoalDockState();
}

class _GoalDockState extends ConsumerState<_GoalDock> {
  bool _pending = false;
  String? _actionError;
  String? _clearedGoalId;

  Future<void> _run(Future<GoalActionResult> Function() action) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _actionError = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _pending = false;
      if (!result.ok) _actionError = '${result.message} (${result.code})';
    });
  }

  @override
  Widget build(BuildContext context) {
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final source = boundGoalProjectionSource;
    final control = boundGoalControl;
    final SessionId? sessionId = ref.watch(currentSessionIdProvider);
    final goal = sessionId == null || source == null
        ? null
        : source.snapshotOf(sessionId.value);

    // Loading, absent, complete, and just-cleared goals have no strip at all.
    if (goal == null ||
        control == null ||
        sessionId == null ||
        goal.phase == GoalPhase.complete ||
        goal.id == _clearedGoalId) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoalBar(
          goal: goal,
          pending: _pending,
          onPause: () => _run(() => control.pause(sessionId.value)),
          onResume: () => _run(() => control.resume(sessionId.value)),
          onEdit: (objective) =>
              _run(() => control.edit(sessionId.value, objective)),
          onClear: () async {
            await _run(() => control.clear(sessionId.value));
            if (mounted) setState(() => _clearedGoalId = goal.id);
          },
        ),
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _actionError!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.stateErrorPrimary,
              ),
            ),
          ),
      ],
    );
  }
}
