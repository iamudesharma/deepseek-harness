import 'package:flutter/foundation.dart';

/// Phase discriminant for the current goal — mirrors `GoalSnapshot.phase`
/// (`active` | `paused` | `blocked` | `complete`) from `@deepseek-ai/dsh-goal`.
@immutable
enum GoalPhase { active, paused, blocked, complete }

/// Minimal goal snapshot for Flutter presentation.
///
/// Matches the host `GoalSnapshot` shape trimmed to UI-required fields; JSON
/// keys stay identical to the host contract so a projection decoder can map
/// the `session/projection` frame value directly. The [id]/[revision] pair is
/// the CAS ref every mutation verb sends (`goal.edit` et al).
@immutable
class GoalSnapshot {
  /// Stable goal id.
  final String id;

  /// Human objective — the goal statement.
  final String objective;

  /// Current phase.
  final GoalPhase phase;

  /// Optional blocked reason shown as tooltip when `phase == blocked`.
  final String? blockedReason;

  /// Progress 0..1 when determinable (e.g. step count), null when unknown.
  final double? progress;

  /// Revision for CAS — bumped on each mutation.
  final int revision;

  /// Creates a goal snapshot.
  const GoalSnapshot({
    required this.id,
    required this.objective,
    required this.phase,
    this.blockedReason,
    this.progress,
    this.revision = 0,
  });

  /// Decodes one projected goal value (`{ goal: {...} }` whole snapshot or the
  /// bare goal object); returns null for absent/loading projections.
  static GoalSnapshot? fromProjection(Object? value) {
    Object? cur = value;
    if (cur is Map && cur['goal'] is Map) cur = cur['goal'];
    if (cur is! Map) return null;
    final id = cur['id'];
    final objective = cur['objective'];
    if (id is! String || objective is! String) return null;
    final revisionRaw = cur['revision'];
    final progressRaw = cur['progress'];
    return GoalSnapshot(
      id: id,
      objective: objective,
      phase: switch (cur['phase']) {
        'active' => GoalPhase.active,
        'paused' => GoalPhase.paused,
        'blocked' => GoalPhase.blocked,
        'complete' => GoalPhase.complete,
        _ => GoalPhase.active,
      },
      blockedReason: switch (cur['blockedReason']) {
        {'message': final String message} => message,
        final String message => message,
        _ => null,
      },
      progress: progressRaw is num ? progressRaw.toDouble() : null,
      revision: revisionRaw is int ? revisionRaw : 0,
    );
  }

  /// Copy with.
  GoalSnapshot copyWith({
    String? id,
    String? objective,
    GoalPhase? phase,
    String? blockedReason,
    double? progress,
    int? revision,
  }) {
    return GoalSnapshot(
      id: id ?? this.id,
      objective: objective ?? this.objective,
      phase: phase ?? this.phase,
      blockedReason: blockedReason ?? this.blockedReason,
      progress: progress ?? this.progress,
      revision: revision ?? this.revision,
    );
  }
}
