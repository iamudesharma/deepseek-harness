/// Goal activation source — Dart port of React
/// `packages/client/ui-goal/src/client/activation-source.ts`
/// (`createGoalActivationSource`).
///
/// Orders Remote reads and live activation edges with epochs so a stale
/// read never overwrites a newer edge: live-event epochs invalidate
/// in-flight reads, running flips and connection resets trigger fresh
/// authoritative reads, and identical snapshots publish nothing. Manual
/// pause stays authoritative: actions are CAS-guarded ([GoalControl]) and
/// the source only publishes what the Host reports.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/connection_controller.dart'
    show connectionClientProvider, connectionStateProvider, ConnectionState;
import '../../core/services/remote_event_bus.dart';
import '../../core/session/session_models.dart';
import '../../core/session/sessions_controller.dart';
import 'goal_control.dart' show GoalRef;
import 'goal_models.dart';
import 'goal_projection.dart';

/// Process-local continuation eligibility; never persisted.
/// Mirrors `GoalActivation`.
enum GoalActivation {
  /// The live process may automatically continue an active goal.
  armed,

  /// The live process must not automatically continue.
  disarmed;

  /// Parses the Host literal; null for anything else.
  static GoalActivation? tryParse(Object? value) {
    return switch (value) {
      'armed' => GoalActivation.armed,
      'disarmed' => GoalActivation.disarmed,
      _ => null,
    };
  }
}

/// One activation snapshot: the exact current goal identity plus its
/// process-local continuation state. Null identity means no current goal.
class GoalActivationSnapshot {
  /// Creates the snapshot (const empty = no current goal).
  const GoalActivationSnapshot({this.id, this.revision, this.activation});

  /// Empty snapshot: no current goal.
  static const empty = GoalActivationSnapshot();

  /// Exact current goal identity.
  final String? id;

  /// Exact current goal revision.
  final int? revision;

  /// Current process-local continuation state.
  final GoalActivation? activation;

  /// Value equality over the snapshot (React `sameSnapshot`).
  bool sameAs(GoalActivationSnapshot other) =>
      id == other.id &&
      revision == other.revision &&
      activation == other.activation;
}

/// Live inputs for one session's activation source.
/// Mirrors `GoalActivationDeps`.
class GoalActivationDeps {
  /// Creates the deps.
  const GoalActivationDeps({
    required this.projectionRef,
    required this.getGoal,
    required this.subscribeActivation,
    required this.subscribeReset,
  });

  /// Current active CAS ref from the durable projection, if any.
  final GoalRef? Function() projectionRef;

  /// Reads the current live goal (`goals/get`).
  final Future<GoalView?> Function() getGoal;

  /// Subscribes to activation edges; returns the unsubscriber.
  final VoidCallback Function(void Function(GoalView? goal)) subscribeActivation;

  /// Subscribes to connection-generation resets; returns the unsubscriber.
  final VoidCallback Function(VoidCallback listener) subscribeReset;
}

/// Exact current goal identity plus activation, as `goals/get` serves it.
class GoalView {
  /// Creates the view.
  const GoalView({
    required this.id,
    required this.revision,
    required this.activation,
  });

  /// Exact goal identity.
  final String id;

  /// Exact goal revision.
  final int revision;

  /// Process-local continuation eligibility.
  final GoalActivation activation;

  /// Parses a Host `goals/get` value; null when absent or malformed
  /// (no live goal is transient, not an error).
  static GoalView? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final revision = value['revision'];
    final activation = GoalActivation.tryParse(value['activation']);
    if (id is! String || revision is! int || activation == null) return null;
    return GoalView(id: id, revision: revision, activation: activation);
  }
}

/// Registrant-private activation source with epoch ordering.
/// Create per session; call [dispose] to release Remote event, reset, and
/// polling listeners (mirrors subscribe-while-observed).
class GoalActivationSource extends ChangeNotifier {
  /// Creates the source and subscribes its inputs.
  GoalActivationSource(this._deps) {
    _unsubscribers.addAll([
      _deps.subscribeActivation(_onActivation),
      _deps.subscribeReset(_onReset),
    ]);
    _refreshProjection();
  }

  final GoalActivationDeps _deps;
  final List<VoidCallback> _unsubscribers = [];
  int _eventEpoch = 0;
  int _projectionEpoch = 0;
  int _readEpoch = 0;

  GoalActivationSnapshot _snapshot = GoalActivationSnapshot.empty;

  /// Current snapshot (empty = no current goal).
  GoalActivationSnapshot get snapshot => _snapshot;

  void _publish(GoalActivationSnapshot next) {
    if (_snapshot.sameAs(next)) return;
    _snapshot = next;
    notifyListeners();
  }

  void _startRead(GoalRef? ref) {
    if (ref == null) return;
    final read = ++_readEpoch;
    final startedAtEvent = _eventEpoch;
    final startedAtProjection = _projectionEpoch;
    _deps.getGoal().then((goal) {
      if (read != _readEpoch ||
          startedAtEvent != _eventEpoch ||
          startedAtProjection != _projectionEpoch) {
        return;
      }
      if (goal == null) {
        if (_deps.projectionRef() == null) {
          _publish(GoalActivationSnapshot.empty);
        }
        return;
      }
      _publish(
        GoalActivationSnapshot(
          id: goal.id,
          revision: goal.revision,
          activation: goal.activation,
        ),
      );
    });
  }

  /// Re-reads after polling the projection (call when it may have changed).
  void refreshProjection() {
    _projectionEpoch++;
    final ref = _deps.projectionRef();
    if (ref == null) {
      if (_snapshot.id != null) {
        _publish(GoalActivationSnapshot.empty);
      }
      return;
    }
    if (_snapshot.id != ref.id || _snapshot.revision != ref.revision) {
      _publish(
        GoalActivationSnapshot(
          id: ref.id,
          revision: ref.revision,
          activation: _snapshot.activation,
        ),
      );
    }
    _startRead(ref);
  }

  /// Re-checks the running flip (call when it may have changed).
  void refreshRunning() {
    // Running state is read live; a flip triggers a fresh authoritative
    // read so a stale activation never survives a turn boundary.
    _startRead(_deps.projectionRef());
  }

  void _refreshProjection() => refreshProjection();

  void _onActivation(GoalView? goal) {
    _eventEpoch++;
    _readEpoch++;
    if (goal == null) {
      _publish(GoalActivationSnapshot.empty);
      return;
    }
    _publish(
      GoalActivationSnapshot(
        id: goal.id,
        revision: goal.revision,
        activation: goal.activation,
      ),
    );
  }

  void _onReset() {
    _eventEpoch++;
    _projectionEpoch++;
    _startRead(_deps.projectionRef());
  }

  @override
  void dispose() {
    for (final unsub in _unsubscribers) {
      try {
        unsub();
      } catch (_) {}
    }
    _unsubscribers.clear();
    super.dispose();
  }
}

/// Active CAS ref from the durable goal projection, if the phase is active.
GoalRef? goalProjectionRef(GoalSnapshot? snapshot) {
  if (snapshot == null || snapshot.phase != GoalPhase.active) return null;
  return GoalRef(id: snapshot.id, revision: snapshot.revision);
}

/// Per-session activation snapshot, kept alive while observed (mirrors
/// subscribe-while-observed; unmount releases Remote/reset listeners).
/// Resets refresh on every fresh connection generation.
final goalActivationProvider =
    ChangeNotifierProvider.family<GoalActivationSource, String>((ref, sessionId) {
  final client = ref.watch(connectionClientProvider);
  final source = GoalActivationSource(
    GoalActivationDeps(
      projectionRef: () {
        final projections = boundGoalProjectionSource;
        if (projections == null) return null;
        return goalProjectionRef(projections.snapshotOf(sessionId));
      },
      getGoal: () async {
        try {
          final body = await client.callMethod('goals/get', {
            'agentId': sessionId,
          });
          return GoalView.tryFromJson(body);
        } catch (_) {
          return null;
        }
      },
      subscribeActivation: (listener) {
        final bus = ref.read(remoteBusProvider);
        return bus.$on('goal/activation-changed', (args) {
          final payload = args.isNotEmpty ? args[0] : null;
          listener(_activationGoal(payload));
        });
      },
      subscribeReset: (listener) {
        var last = ref.read(connectionStateProvider);
        void onState() {
          final next = ref.read(connectionStateProvider);
          if (next == ConnectionState.connected && last != next) {
            listener();
          }
          last = next;
        }

        // Connection-state transitions arrive through provider listens, not
        // the bus: re-check on every rebuild while observed.
        ref.listen<ConnectionState>(connectionStateProvider, (_, _) => onState());
        return () {};
      },
    ),
  );
  ref.onDispose(source.dispose);
  // Running flips drive fresh authoritative reads (React onRunning); other
  // sessions changes are ignored so polling stays flip-triggered, not noisy.
  var lastRunning = ref.read(sessionsProvider).byId[SessionId(sessionId)]?.running ?? false;
  ref.listen(sessionsProvider, (_, next) {
    final running =
        next.byId[SessionId(sessionId)]?.running ?? false;
    if (running == lastRunning) return;
    lastRunning = running;
    source.refreshRunning();
  });
  // Projection and running changes arrive through rebuilds while observed.
  ref.listen(sessionsProvider, (_, _) => source.refreshRunning());
  return source;
});

/// Parses one `goal/activation-changed` bus payload to a view (null clears).
GoalView? _activationGoal(Object? payload) {
  if (payload is! Map) return null;
  final goal = payload['goal'];
  if (goal == null) return null;
  if (goal is! Map) return null;
  return GoalView.tryFromJson(Map<String, Object?>.from(goal));
}
