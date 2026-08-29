import '../../core/session/session_models.dart';

/// Search result row combining list metadata with optional content match.
class SearchResultNode {
  const SearchResultNode({
    required this.id,
    required this.title,
    required this.workspace,
    required this.running,
    required this.runningSubagentCount,
    this.pendingInteraction,
    required this.completed,
    this.snippet,
  });
  final SessionId id;
  final String title;
  final String workspace;
  final bool running;
  final int runningSubagentCount;
  final PendingInteractionStatus? pendingInteraction;
  final bool completed;
  final String? snippet;
}

/// Bounded merged search projection plus refine hint.
class SearchResultSet {
  const SearchResultSet({required this.items, required this.hasMore});
  final List<SearchResultNode> items;
  final bool hasMore;
}

/// Derive merged search results — mirrors `tree.ts:deriveSearchResults`.
///
/// Local title/workspace substring matches lead newest-first, content-only
/// rows retain backend order, duplicates get backend snippet overlay.
/// Bounded to [limit] (host `SESSION_SEARCH_RESULT_LIMIT` = 20).
SearchResultSet deriveSearchResults(
  List<SessionSummary> sessions,
  List<WorkspaceView> workspaces,
  String query,
  List<SessionSearchItem> content,
  bool contentHasMore,
  int limit,
  Set<SessionId> archivedIds,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const SearchResultSet(items: [], hasMore: false);

  // Workspace label by session
  final workspaceBySession = <SessionId, String>{};
  for (final w in workspaces) {
    for (final sid in w.sessionIds) {
      workspaceBySession.putIfAbsent(sid, () => w.name);
    }
  }
  String labelOf(SessionSummary s) {
    final fromWorkspace = workspaceBySession[s.sessionId];
    if (fromWorkspace != null) return fromWorkspace;
    final cwd = s.cwd;
    if (cwd == null || cwd.isEmpty) return 'Ungrouped';
    final base = cwd
        .replaceAll(RegExp(r'[/\\]+$'), '')
        .split(RegExp(r'[/\\]'))
        .last;
    return base.isNotEmpty ? base : cwd;
  }

  final contentBySession = <SessionId, SessionSearchItem>{};
  for (final item in content) {
    contentBySession.putIfAbsent(item.sessionId, () => item);
  }

  // Local title/workspace matches — blank never matches, archived hidden, subagent filtered
  final archived = archivedIds;
  final local = <SessionSummary>[];
  for (final s in sessions) {
    if (s.blank) continue;
    if (s.origin == 'subagent') continue;
    if (archived.contains(s.sessionId)) continue;
    final title = s.displayTitle.toLowerCase();
    final ws = labelOf(s).toLowerCase();
    if (title.contains(q) || ws.contains(q)) {
      local.add(s);
    }
  }
  local.sort((a, b) {
    if (b.updatedAt != a.updatedAt) return b.updatedAt.compareTo(a.updatedAt);
    return a.sessionId.value.compareTo(b.sessionId.value);
  });

  final ordered = <SessionSummary>[];
  final included = <SessionId>{};
  void include(SessionSummary s) {
    if (included.contains(s.sessionId)) return;
    included.add(s.sessionId);
    ordered.add(s);
  }

  for (final s in local) include(s);
  for (final item in content) {
    final s = sessions.firstWhereOrNull((e) => e.sessionId == item.sessionId);
    if (s == null) continue;
    if (s.blank) continue;
    if (s.origin == 'subagent') continue;
    if (archived.contains(s.sessionId)) continue;
    include(s);
  }

  final sliced = ordered.take(limit).toList();
  final hasMore = contentHasMore || ordered.length > limit;
  final items = sliced.map((s) {
    final match = contentBySession[s.sessionId];
    return SearchResultNode(
      id: s.sessionId,
      title: s.displayTitle,
      workspace: labelOf(s),
      running: s.running,
      runningSubagentCount: s.runningSubagentCount,
      pendingInteraction: s.pendingInteraction,
      completed: s.completed,
      snippet: match?.snippet,
    );
  }).toList();

  return SearchResultSet(items: items, hasMore: hasMore);
}

class SessionSearchItem {
  const SessionSearchItem({required this.sessionId, required this.snippet});
  final SessionId sessionId;
  final String snippet;
}

extension _FirstWhereOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
