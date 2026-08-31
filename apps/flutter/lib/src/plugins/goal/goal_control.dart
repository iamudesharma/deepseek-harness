/// Goal mutation verbs — the Dart slice of the generated Goal Remote API
/// (`ctx.remote.goals.*` in `packages/client/ui-goal/src/client/index.ts`),
/// carried over `ConnectionClient.callMethod` because no typed remote face
/// exists yet.
///
/// Method names and payload fields mirror `GoalsApi` (`rpc-map.ts`) exactly:
/// every verb is CAS-guarded by the ref read from the session's projected
/// goal at call time; with no projection there is nothing to mutate and the
/// verb fails with `no-current-goal` without touching the wire (the same
/// `refOf → undefined` short-circuit the React apply() builds).
library;

import 'package:flutter/foundation.dart';

import '../../core/connection/connection_client.dart';
import 'goal_projection.dart';

/// Compare-and-set identity for one exact goal revision.
@immutable
class GoalRef {
  /// Stable goal id.
  final String id;

  /// Revision the caller observed.
  final int revision;

  /// Creates a CAS ref.
  const GoalRef({required this.id, required this.revision});

  @override
  bool operator ==(Object other) =>
      other is GoalRef && other.id == id && other.revision == revision;

  @override
  int get hashCode => Object.hash(id, revision);

  @override
  String toString() => 'GoalRef($id@$revision)';
}

/// Settled outcome of one goal mutation, rendered inline by the strip. The
/// strip renders the failure only — the mutated goal arrives through the
/// projection — so success carries no value.
@immutable
class GoalActionResult {
  /// Whether the RPC succeeded.
  final bool ok;

  /// Error code when [ok] is false.
  final String code;

  /// Error message when [ok] is false.
  final String message;

  /// Creates a result.
  const GoalActionResult({required this.ok, this.code = '', this.message = ''});

  /// The shared no-projection failure.
  static const GoalActionResult noCurrentGoal = GoalActionResult(
    ok: false,
    code: 'no-current-goal',
    message: 'no current goal to mutate',
  );

  /// Maps a carrier failure (`callMethod` throws on `result.ok == false`).
  factory GoalActionResult.failure(Object error) =>
      GoalActionResult(ok: false, code: 'rpc-error', message: error.toString());
}

/// The four mutation verbs of the goal strip, published as the `'goal'`
/// service.
class GoalControl {
  /// Creates the control over [client], reading CAS refs through
  /// [projectionSource] at verb call time.
  const GoalControl({required this.client, this.projectionSource});

  /// The mutation carrier (`ConnectionClient.callMethod`).
  final ConnectionClient client;

  /// The session projection read; null keeps every verb on the
  /// no-current-goal short-circuit.
  final GoalProjectionSource? projectionSource;

  /// The session's current projected CAS ref, read at verb call time (no
  /// staleness fence: the RPC's CAS is the guard).
  GoalRef? refOf(String sessionId) {
    final snapshot = projectionSource?.snapshotOf(sessionId);
    if (snapshot == null) return null;
    return GoalRef(id: snapshot.id, revision: snapshot.revision);
  }

  /// Replace the current goal's objective (`goals/edit`, CAS on the
  /// projected ref). Host expects {args:{agentId, ref, request:{objective}}}
  Future<GoalActionResult> edit(String sessionId, String objective) async {
    final ref = refOf(sessionId);
    if (ref == null) return GoalActionResult.noCurrentGoal;
    return _run('goals/edit', {
      'agentId': sessionId,
      'ref': {'id': ref.id, 'revision': ref.revision},
      'request': {'objective': objective},
    });
  }

  /// Pause an active goal (`goals/pause`).
  Future<GoalActionResult> pause(String sessionId) =>
      _verb('goals/pause', sessionId);

  /// Resume a paused goal (`goals/resume`).
  Future<GoalActionResult> resume(String sessionId) =>
      _verb('goals/resume', sessionId);

  /// Clear the current goal, retaining a durable tombstone (`goals/clear`).
  Future<GoalActionResult> clear(String sessionId) =>
      _verb('goals/clear', sessionId);

  Future<GoalActionResult> _verb(String method, String sessionId) async {
    final ref = refOf(sessionId);
    if (ref == null) return GoalActionResult.noCurrentGoal;
    return _run(method, {
      'agentId': sessionId,
      'ref': {'id': ref.id, 'revision': ref.revision},
    });
  }

  Future<GoalActionResult> _run(
    String method,
    Map<String, Object?> payload,
  ) async {
    try {
      await client.callMethod(method, payload);
      return const GoalActionResult(ok: true);
    } catch (error) {
      return GoalActionResult.failure(error);
    }
  }
}
