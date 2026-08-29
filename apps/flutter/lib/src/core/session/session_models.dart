import 'dart:convert';

/// Branded session identifier (opaque cross-boundary id, never bare string).
///
/// Mirrors `SessionId` from `@deepseek-ai/dsh-session/types` which brands via
/// `Branded<'SessionId'>`. Dart port uses an extension type for zero-cost
/// wrapping and exhaustive type safety.
///
/// Usage:
///
/// ```dart
/// const id = SessionId('abc-123');
/// final raw = id.value; // underlying string
/// ```
extension type const SessionId(String value) implements String {
  /// Unwrap to raw string.
  String get raw => value;

  /// JSON encode as plain string.
  String toJson() => value;

  /// Decode from JSON string.
  static SessionId fromJson(String json) => SessionId(json);
}

/// Branded workspace identifier.
extension type const WorkspaceId(String value) implements String {
  String get raw => value;
}

/// Branded message identifier for queued inbox items.
///
/// Mirrors `MessageId` from `@deepseek-ai/dsh-llm/brand`.
extension type const MessageId(String value) implements String {
  String get raw => value;
  String toJson() => value;
  static MessageId fromJson(String json) => MessageId(json);
}

/// Queue action for `session.updateQueue` — edit/remove/steer.
///
/// Mirrors `QueueAction` in `packages/host/apiproxy/src/api/sessions.ts`:
/// `{kind:'edit', content}` | `{kind:'remove'}` | `{kind:'steer'}`.
sealed class QueueAction {
  const QueueAction();
  Map<String, dynamic> toJson();
}

class QueueActionEdit extends QueueAction {
  final List<Map<String, dynamic>> content;
  const QueueActionEdit(this.content);
  @override
  Map<String, dynamic> toJson() => {'kind': 'edit', 'content': content};
}

class QueueActionRemove extends QueueAction {
  const QueueActionRemove();
  @override
  Map<String, dynamic> toJson() => {'kind': 'remove'};
}

class QueueActionSteer extends QueueAction {
  const QueueActionSteer();
  @override
  Map<String, dynamic> toJson() => {'kind': 'steer'};
}

/// Pending interaction status — mirrors
/// `PendingInteractionStatus` in `packages/client/runtime/src/client/sessions/pending.ts`.
///
/// Exact precedence: `approval` → `plan-review` → `question` → subagents → running → completed → idle.
typedef PendingInteractionStatus = String;

/// Summary row returned by `session.list`.
///
/// Mirrors `SessionSummary` in `packages/host/apiproxy/src/api/sessions.ts`
/// plus `SessionListEntry` derived fields `pendingInteraction` / `completed`
/// projected by `flattenLineage` in `manager.ts`. Keep JSON keys identical to
/// the host contract so `ConnectionClient` can decode directly.
class SessionSummary {
  /// Unique session identifier.
  final SessionId sessionId;

  /// Last update time: later of creation and latest human-authored prompt.
  /// Milliseconds since epoch.
  final int updatedAt;

  /// Whether the attached agent is currently running.
  final bool running;

  /// Derived conversation-not-started bit.
  final bool blank;

  /// Fork/spawn lineage (`header.parentSessionId` passthrough).
  final SessionId? parentSessionId;

  /// Durable origin hint (e.g. `'subagent'`).
  final String? origin;

  /// Working directory passthrough.
  final String? cwd;

  /// Agent preset id the session's agent was composed from.
  final String? agentPreset;

  /// Host-computed title (from projection cache); `null` when absent.
  final String? title;

  /// Interaction currently blocking this session (amber dot).
  /// One of `approval` | `plan-review` | `question` when present.
  final PendingInteractionStatus? pendingInteraction;

  /// Finished running while not selected and not yet opened — green done reminder.
  /// Absent (false) means no reminder.
  final bool completed;

  /// Running descendants connected through uninterrupted subagent-origin lineage.
  /// Derived via `indexSubagentDescendants` (see tree.ts / session_models search).
  final int runningSubagentCount;

  /// Creates a session summary.
  const SessionSummary({
    required this.sessionId,
    required this.updatedAt,
    required this.running,
    required this.blank,
    this.parentSessionId,
    this.origin,
    this.cwd,
    this.agentPreset,
    this.title,
    this.pendingInteraction,
    this.completed = false,
    this.runningSubagentCount = 0,
  });

  /// Creates a copy with selected fields replaced.
  ///
  /// `title == null` is intentionally NOT a set-to-null operation — pass
  /// `titleSet` to distinguish clear-from-retain. Use [withTitle] when the
  /// source can be `null` (projection `string|null`).
  SessionSummary copyWith({
    SessionId? sessionId,
    int? updatedAt,
    bool? running,
    bool? blank,
    SessionId? parentSessionId,
    String? origin,
    String? cwd,
    String? agentPreset,
    String? title,
    PendingInteractionStatus? pendingInteraction,
    bool? completed,
    int? runningSubagentCount,
  }) {
    return SessionSummary(
      sessionId: sessionId ?? this.sessionId,
      updatedAt: updatedAt ?? this.updatedAt,
      running: running ?? this.running,
      blank: blank ?? this.blank,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      origin: origin ?? this.origin,
      cwd: cwd ?? this.cwd,
      agentPreset: agentPreset ?? this.agentPreset,
      title: title ?? this.title,
      pendingInteraction: pendingInteraction ?? this.pendingInteraction,
      completed: completed ?? this.completed,
      runningSubagentCount: runningSubagentCount ?? this.runningSubagentCount,
    );
  }

  /// Copy with an explicit title value that may be `null` (projection refresh).
  SessionSummary withTitle(String? newTitle) => SessionSummary(
    sessionId: sessionId,
    updatedAt: updatedAt,
    running: running,
    blank: blank,
    parentSessionId: parentSessionId,
    origin: origin,
    cwd: cwd,
    agentPreset: agentPreset,
    title: newTitle,
    pendingInteraction: pendingInteraction,
    completed: completed,
    runningSubagentCount: runningSubagentCount,
  );

  /// Copy with an explicit pending-interaction marker that may be `null`
  /// (resolution/reconnect must clear the amber dot, not retain it).
  SessionSummary withPendingInteraction(PendingInteractionStatus? status) =>
      SessionSummary(
        sessionId: sessionId,
        updatedAt: updatedAt,
        running: running,
        blank: blank,
        parentSessionId: parentSessionId,
        origin: origin,
        cwd: cwd,
        agentPreset: agentPreset,
        title: title,
        pendingInteraction: status,
        completed: completed,
        runningSubagentCount: runningSubagentCount,
      );

  /// Decode from host JSON — title lives under `projections.values['title']`
  /// per `session.title` projection (`null` before first title lands).
  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    // Title is a projection, not a top-level field.
    String? title;
    final projections = json['projections'];
    if (projections is Map) {
      final values = projections['values'];
      if (values is Map) {
        final t = values['title'];
        if (t is String && t.isNotEmpty) title = t;
      }
    }
    // Fallback for test fixtures / legacy payloads that still carry top-level title.
    title ??= json['title'] as String?;
    final pending = json['pendingInteraction'] as String?;
    final normalizedPending =
        pending == 'approval' ||
            pending == 'plan-review' ||
            pending == 'question'
        ? pending
        : null;
    return SessionSummary(
      sessionId: SessionId(json['sessionId'] as String),
      updatedAt: json['updatedAt'] as int,
      running: json['running'] as bool,
      blank: json['blank'] as bool,
      parentSessionId: json['parentSessionId'] == null
          ? null
          : SessionId(json['parentSessionId'] as String),
      origin: json['origin'] as String?,
      cwd: json['cwd'] as String?,
      agentPreset: json['agentPreset'] as String?,
      title: title,
      pendingInteraction: normalizedPending,
      completed: json['completed'] == true,
      runningSubagentCount: json['runningSubagentCount'] is int
          ? json['runningSubagentCount'] as int
          : 0,
    );
  }

  /// Encode to host JSON.
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId.value,
    'updatedAt': updatedAt,
    'running': running,
    'blank': blank,
    if (parentSessionId != null) 'parentSessionId': parentSessionId!.value,
    if (origin != null) 'origin': origin,
    if (cwd != null) 'cwd': cwd,
    if (agentPreset != null) 'agentPreset': agentPreset,
    if (title != null) 'title': title,
    if (pendingInteraction != null) 'pendingInteraction': pendingInteraction,
    if (completed) 'completed': true,
    if (runningSubagentCount != 0) 'runningSubagentCount': runningSubagentCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionSummary &&
          sessionId == other.sessionId &&
          updatedAt == other.updatedAt &&
          running == other.running &&
          blank == other.blank &&
          parentSessionId == other.parentSessionId &&
          origin == other.origin &&
          cwd == other.cwd &&
          agentPreset == other.agentPreset &&
          title == other.title &&
          pendingInteraction == other.pendingInteraction &&
          completed == other.completed &&
          runningSubagentCount == other.runningSubagentCount;

  @override
  int get hashCode => Object.hash(
    sessionId,
    updatedAt,
    running,
    blank,
    parentSessionId,
    origin,
    cwd,
    agentPreset,
    title,
    pendingInteraction,
    completed,
    runningSubagentCount,
  );

  /// Human-facing title mirroring React `displayTitleOf` (title → cwd basename → id).
  String get displayTitle {
    final t = title;
    if (t != null && t.isNotEmpty) return t;
    final c = cwd;
    if (c != null && c.isNotEmpty) {
      final parts = c.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.last;
    }
    return sessionId.value;
  }

  @override
  String toString() =>
      'SessionSummary($sessionId, updatedAt: $updatedAt, running: $running, blank: $blank, pending: $pendingInteraction, completed: $completed)';

  /// Session status precedence — mirrors `Rows.tsx:sessionStatuses`:
  /// `approval` → `plan-review` → `question` → subagents → running → completed → idle.
  ///
  /// Returns ordered labels (first is primary dot state).
  List<SessionStatus> sessionStatuses() {
    final sub = runningSubagentCount == 0
        ? null
        : SessionStatus(
            state: 'ongoing',
            label: runningSubagentCount == 1
                ? '1 subagent running'
                : '$runningSubagentCount subagents running',
          );
    switch (pendingInteraction) {
      case 'approval':
        {
          final s = SessionStatus(state: 'warning', label: 'Waiting approval');
          return sub == null ? [s] : [s, sub];
        }
      case 'plan-review':
        {
          final s = SessionStatus(state: 'warning', label: 'Plan review');
          return sub == null ? [s] : [s, sub];
        }
      case 'question':
        {
          final s = SessionStatus(state: 'warning', label: 'Waiting answer');
          return sub == null ? [s] : [s, sub];
        }
    }
    if (running) {
      final primary = SessionStatus(state: 'ongoing', label: 'Running');
      return sub == null ? [primary] : [primary, sub];
    }
    if (sub != null) return [sub];
    if (completed) return [SessionStatus(state: 'done', label: 'Completed')];
    return [SessionStatus(state: 'done', label: 'Idle')];
  }
}

/// One status entry for a session row — mirrors `Rows.tsx:SessionStatus`.
class SessionStatus {
  const SessionStatus({required this.state, required this.label});
  final String state; // 'ongoing' | 'warning' | 'done' | 'error'
  final String label;
}

/// Minimal session event stub.
///
/// The host event log is extensive (see `SessionEventMap` in `dsh-session`);
/// UI needs only a typed envelope that survives rendering. Full `data` is kept
/// as JSON and accessed by conversation node folds.
class SessionEvent {
  /// Event type discriminant (e.g. `'user/message'`, `'turn/start'`).
  final String type;

  /// Raw payload (JSON-compatible map).
  final Map<String, dynamic> data;

  /// Monotonic sequence number inside the session log.
  final int seq;

  /// Wall time milliseconds since epoch.
  final int time;

  /// Whether the event is ignorable for older clients (`ignorable: true` envelope).
  final bool ignorable;

  /// Creates a session event stub.
  const SessionEvent({
    required this.type,
    required this.data,
    required this.seq,
    required this.time,
    this.ignorable = false,
  });

  /// Decode from host JSON (host `HistoryEntry.event`).
  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    return SessionEvent(
      type: json['type'] as String,
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      seq: json['seq'] as int,
      time: json['time'] as int,
      ignorable: json['ignorable'] as bool? ?? false,
    );
  }

  /// Encode to JSON.
  Map<String, dynamic> toJson() => {
    'type': type,
    'data': data,
    'seq': seq,
    'time': time,
    if (ignorable) 'ignorable': true,
  };

  @override
  String toString() => 'SessionEvent(type: $type, seq: $seq)';
}

/// History page entry: raw event plus optional host-computed view.
///
/// Mirrors `HistoryEntry` in `packages/host/apiproxy/src/api/sessions.ts`.
class HistoryEntry {
  /// Raw session event.
  final SessionEvent event;

  /// Optional host-computed render intent (present for tool events whose
  /// presenter produced one).
  final Map<String, dynamic>? view;

  /// Creates a history entry.
  const HistoryEntry({required this.event, this.view});

  /// Decode from host JSON.
  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      event: SessionEvent.fromJson(json['event'] as Map<String, dynamic>),
      view: (json['view'] as Map?)?.cast<String, dynamic>(),
    );
  }

  /// Encode to JSON.
  Map<String, dynamic> toJson() => {
    'event': event.toJson(),
    if (view != null) 'view': view,
  };
}

/// Workspace view (subset needed for chooser UI).
///
/// Mirrors `WorkspaceView` in `packages/host/apiproxy/src/api/workspace.ts`:
/// `workspaceId` / `path` / `title` / `sessionIds` / `createdAt` / `updatedAt`.
/// Flutter legacy `name`/`cwd` fields remain as aliases of `title`/`path`.
class WorkspaceView {
  /// Workspace identifier.
  final WorkspaceId workspaceId;

  /// Display name or path.
  final String name;

  /// Optional root path.
  final String? cwd;

  /// Host-owned session membership in display order (from `workspace.list`).
  final List<SessionId> sessionIds;

  /// ISO-8601 creation instant (host `createdAt`), parsed to millis for parity.
  final int? createdAt;

  /// ISO-8601 last-mutation instant.
  final int? updatedAtMillis;

  /// Canonical path (alias of [cwd] from host `path`).
  String? get path => cwd;

  /// Display title (alias of [name] from host `title`).
  String get title => name;

  /// Creates a workspace view.
  const WorkspaceView({
    required this.workspaceId,
    required this.name,
    this.cwd,
    this.sessionIds = const [],
    this.createdAt,
    this.updatedAtMillis,
  });

  /// Decode from host JSON.
  factory WorkspaceView.fromJson(Map<String, dynamic> json) {
    final String? path = json['path'] as String?;
    final String? title = json['title'] as String?;
    final String? createdAtStr = json['createdAt'] as String?;
    final String? updatedAtStr = json['updatedAt'] as String?;
    int? createdAtMillis;
    int? updatedAtMillis;
    if (createdAtStr != null) {
      try {
        createdAtMillis = DateTime.parse(createdAtStr).millisecondsSinceEpoch;
      } catch (_) {}
    }
    if (updatedAtStr != null) {
      try {
        updatedAtMillis = DateTime.parse(updatedAtStr).millisecondsSinceEpoch;
      } catch (_) {}
    }
    return WorkspaceView(
      workspaceId: WorkspaceId(json['workspaceId'] as String),
      name:
          json['name'] as String? ??
          title ??
          json['title'] as String? ??
          path ??
          json['workspaceId'] as String,
      cwd: json['cwd'] as String? ?? path,
      sessionIds: (json['sessionIds'] as List<dynamic>? ?? [])
          .whereType<String>()
          .map(SessionId.new)
          .toList(),
      createdAt: createdAtMillis,
      updatedAtMillis: updatedAtMillis,
    );
  }

  /// Encode to JSON (host contract: `path`/`title` over `cwd`/`name`).
  Map<String, dynamic> toJson() => {
    'workspaceId': workspaceId.value,
    'name': name,
    if (cwd != null) 'cwd': cwd,
    if (cwd != null) 'path': cwd,
    'title': name,
    if (sessionIds.isNotEmpty)
      'sessionIds': sessionIds.map((id) => id.value).toList(),
    if (createdAt != null)
      'createdAt': DateTime.fromMillisecondsSinceEpoch(createdAt!)
          .toIso8601String(),
    if (updatedAtMillis != null)
      'updatedAt': DateTime.fromMillisecondsSinceEpoch(updatedAtMillis!)
          .toIso8601String(),
  };

  @override
  String toString() => 'WorkspaceView($workspaceId, $name)';
}

/// Projection baseline block carried on history / list rows (stub).
class SessionProjectionsBlock {
  /// Seq of the last event the values reflect (-1 for empty log).
  final int asOfSeq;

  /// Whole current value per registered projection key.
  final Map<String, dynamic> values;

  /// Creates a projections block.
  const SessionProjectionsBlock({required this.asOfSeq, required this.values});

  /// Decode from host JSON.
  factory SessionProjectionsBlock.fromJson(Map<String, dynamic> json) {
    return SessionProjectionsBlock(
      asOfSeq: json['asOfSeq'] as int,
      values: (json['values'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// Encode to JSON.
  Map<String, dynamic> toJson() => {'asOfSeq': asOfSeq, 'values': values};
}

/// Helper to pretty-print JSON for diagnostics.
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
