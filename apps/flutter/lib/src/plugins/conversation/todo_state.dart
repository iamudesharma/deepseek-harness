import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One todo item for the panel.
class TodoItem {
  const TodoItem({required this.content, required this.status});
  final String content;
  final String status;
}

/// Authoritative per-session todo list from live projections.
///
/// Updated by `live_sync` from `session/follow` snapshot
/// `projections.todos` and live `session/projection key:todos` frames,
/// matching React's `useProjection('todos')` (`TodoDock`). Whole-value
/// rule: every write carries the complete replacement list (last-wins);
/// `null` means before the first write. Readers fall back to the
/// history-derived list while the projection is absent.
final todoProjectionProvider = StateProvider.family<List<TodoItem>?, String>(
  (ref, sessionId) => null,
);

/// Decode a host `todos` projection value (`TodoItem[] | null`).
///
/// `null` (before the first write) and malformed shapes decode to `null`,
/// mirroring the projection null-clear rule used by the other typed sinks.
List<TodoItem>? decodeTodoProjection(Object? value) {
  if (value == null) return null;
  if (value is! List) return null;
  final out = <TodoItem>[];
  for (final t in value) {
    if (t is Map) {
      final content = (t['content'] ?? t['text'] ?? '').toString();
      final status = (t['status'] ?? 'pending').toString();
      if (content.isNotEmpty) {
        out.add(TodoItem(content: content, status: status));
      }
    }
  }
  return out;
}
