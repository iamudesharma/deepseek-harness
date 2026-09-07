/// Todo summary — Dart port of React `plan-summary.ts` + `todo-row.tsx`
/// summarization (`packages/client/ui-tool/src/client/tool/toolviews/`).
library;

import 'dart:convert';

/// `done/total` plus the first active item's content and parallel-active extra.
class TodoSummary {
  const TodoSummary({
    required this.done,
    required this.total,
    this.activeContent,
    this.extra = 0,
  });

  final int done;
  final int total;
  final String? activeContent;
  final int extra;

  /// `3/6 completed`, or `Todo update` when args carry no todo list.
  String get head => total == 0 && done == 0 && activeContent == null
      ? 'Todo update'
      : '$done/$total completed';

  /// Full row text: head plus the active item, e.g. `3/6 completed · Impl Hero`.
  String get text => activeContent == null || activeContent!.isEmpty
      ? head
      : '$head · $activeContent';
}

Object? _parseArgs(String argsRaw) {
  if (argsRaw.isEmpty) return null;
  try {
    return jsonDecode(argsRaw);
  } catch (_) {
    return null;
  }
}

/// Summarizes a `todo_write` argument payload.
TodoSummary summarizeTodos(String argsRaw) {
  final parsed = _parseArgs(argsRaw);
  Map<String, Object?>? map;
  if (parsed is Map<String, Object?>) {
    map = parsed;
  } else if (parsed is Map) {
    map = parsed.map((k, v) => MapEntry(k.toString(), v as Object?));
  }
  final todos = map?['todos'];
  if (todos is! List) return const TodoSummary(done: 0, total: 0);
  var done = 0;
  final active = <String>[];
  for (final t in todos) {
    Map<String, Object?>? item;
    if (t is Map<String, Object?>) {
      item = t;
    } else if (t is Map) {
      item = t.map((k, v) => MapEntry(k.toString(), v as Object?));
    }
    if (item == null) continue;
    if (item['status'] == 'completed') {
      done++;
    } else {
      final content = item['content'] ?? item['text'];
      if (content is String && content.isNotEmpty) active.add(content);
    }
  }
  return TodoSummary(
    done: done,
    total: todos.length,
    activeContent: active.isEmpty ? null : active.first,
    extra: active.length > 1 ? active.length - 1 : 0,
  );
}
