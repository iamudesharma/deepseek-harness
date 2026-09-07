/// Typed Dart models for `remote.mux` domain streams — exact wire fields
/// from `packages/api/gateway/stream-protocol.ts` and
/// `packages/api/session-controller/src/types.ts` etc.
///
/// No business logic; pure parsing + validation. Business folding lives in
/// `live_sync.dart` / `sessions_controller.dart` / `workspace_provider.dart` etc.
library;

import '../session/session_models.dart';

/// `session/follow` snapshot — first item.
class SessionFollowSnapshot {
  final Map<String, dynamic> header;
  final int cursor;
  final List<Map<String, dynamic>> records;
  final bool hasMore;
  final SessionProjectionsBlock? projections;
  const SessionFollowSnapshot({
    required this.header,
    required this.cursor,
    required this.records,
    required this.hasMore,
    this.projections,
  });

  factory SessionFollowSnapshot.fromJson(Map<String, dynamic> json) {
    final headerRaw = json['header'] as Map?;
    if (headerRaw == null) throw FormatException('snapshot: missing header');
    final header = headerRaw.cast<String, dynamic>();
    final cursor = json['cursor'] as int? ?? -1;
    final records = (json['records'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final hasMore = json['hasMore'] as bool? ?? false;
    SessionProjectionsBlock? projections;
    final proj = json['projections'];
    if (proj is Map) {
      try {
        projections = SessionProjectionsBlock.fromJson(proj.cast<String, dynamic>());
      } catch (_) {}
    }
    return SessionFollowSnapshot(
      header: header,
      cursor: cursor,
      records: records,
      hasMore: hasMore,
      projections: projections,
    );
  }
}

/// `session/follow` live event.
class SessionFollowEvent {
  final Map<String, dynamic> event;
  const SessionFollowEvent(this.event);
  factory SessionFollowEvent.fromJson(Map<String, dynamic> json) {
    final ev = json['event'] as Map?;
    if (ev == null) throw FormatException('event: missing event');
    return SessionFollowEvent(ev.cast<String, dynamic>());
  }
}

/// `session/control` baseline.
class SessionControlBaseline {
  final Map<String, List<Map<String, dynamic>>> queues;
  final Map<String, List<Map<String, dynamic>>> jobs;
  final Map<String, SessionProjectionsBlock> projections;
  const SessionControlBaseline({
    required this.queues,
    required this.jobs,
    required this.projections,
  });

  factory SessionControlBaseline.fromJson(Map<String, dynamic> json) {
    final v = json['value'] is Map ? json['value'] as Map : json;
    final queuesRaw = v['queues'] as Map? ?? const {};
    final jobsRaw = v['jobs'] as Map? ?? const {};
    final projRaw = v['projections'] as Map? ?? const {};
    final queues = <String, List<Map<String, dynamic>>>{};
    for (final e in queuesRaw.entries) {
      final k = e.key as String;
      final list = (e.value as List? ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      queues[k] = list;
    }
    final jobs = <String, List<Map<String, dynamic>>>{};
    for (final e in jobsRaw.entries) {
      final k = e.key as String;
      final list = (e.value as List? ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      jobs[k] = list;
    }
    final projections = <String, SessionProjectionsBlock>{};
    for (final e in projRaw.entries) {
      final k = e.key as String;
      final blockRaw = e.value as Map?;
      if (blockRaw != null) {
        try {
          projections[k] = SessionProjectionsBlock.fromJson(blockRaw.cast<String, dynamic>());
        } catch (_) {}
      }
    }
    return SessionControlBaseline(queues: queues, jobs: jobs, projections: projections);
  }
}

/// `workspace/follow` baseline.
class WorkspaceFollowBaseline {
  final List<WorkspaceView> workspaces;
  final List<String> order;
  final List<String> archived;
  const WorkspaceFollowBaseline({
    required this.workspaces,
    required this.order,
    required this.archived,
  });

  factory WorkspaceFollowBaseline.fromJson(Map<String, dynamic> json) {
    final v = json['value'] is Map ? json['value'] as Map : json;
    final items = (v['workspaces'] as List? ?? v['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => WorkspaceView.fromJson(m.cast<String, dynamic>()))
        .toList();
    final order = (v['order'] as List? ?? v['workspaceIds'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final archived = (v['archived'] as List? ?? v['archivedSessionIds'] as List? ?? const [])
        .whereType<String>()
        .toList();
    return WorkspaceFollowBaseline(workspaces: items, order: order, archived: archived);
  }
}
