/// The `goal` session-projection slice ui-goal consumes — the Dart stand-in
/// for React's `useProjection('goal')` seat.
///
/// The live value arrives through `session/projection` frames (key `goal`,
/// whole snapshot, higher-seq-wins); the frame consumer that stores it lands
/// with the projection workstream, so activation binds nothing by default and
/// the dock renders nothing — exactly React's loading/absent contract. Boot
/// wiring calls [bindGoalProjectionSource] once a store exists; widgets read
/// [boundGoalProjectionSource]. No local mutable goal state lives here: the
/// host owns the data.
library;

import 'goal_models.dart';

/// Reads one session's projected goal; null = capability absent or loading.
abstract interface class GoalProjectionSource {
  /// The session's current whole-snapshot goal, or null.
  GoalSnapshot? snapshotOf(String sessionId);
}

GoalProjectionSource? _boundSource;

/// Bound projection source for widgets; null until wired.
GoalProjectionSource? get boundGoalProjectionSource => _boundSource;

/// Binds (or clears) the goal projection bridge.
void bindGoalProjectionSource(GoalProjectionSource? source) =>
    _boundSource = source;
