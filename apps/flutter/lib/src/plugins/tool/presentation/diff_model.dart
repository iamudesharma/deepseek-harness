/// Diff card model — Dart port of React `diff-card-model.ts`
/// (`packages/client/ui-tool/src/client/tool/models/diff-card-model.ts`).
///
/// A settled `write`/`edit` shows applied contextual hunks from durable
/// `tool/result.data.meta.diffs`; while running (or for a create with empty
/// meta) it falls back to the intended diff derived from call arguments.
/// `+N −N` counts mirror React `diffTotals` in `DiffBlock.tsx`.
library;

import 'dart:convert';

/// One file change shown in a diff card.
class FileDiff {
  const FileDiff({required this.path, required this.oldText, required this.newText});

  /// Model-facing path (relativized at the render site).
  final String path;

  /// Prior content, or null for a create/overwrite without prior content.
  final String? oldText;

  /// Content after the change.
  final String newText;
}

/// Counts lines the way React `contentLines` does: one trailing `\n` is a
/// terminator, not an extra line; empty text is zero lines.
int contentLineCount(String text) {
  if (text.isEmpty) return 0;
  final lines = text.split('\n');
  // A single trailing newline terminates the last line instead of adding one.
  if (lines.length > 1 && lines.last.isEmpty) return lines.length - 1;
  // An empty trailing from `\n\n` still counts the blank line; only one
  // terminator is discounted, matching React's slice(0, -1) on a lone tail.
  return lines.length;
}

/// `+added −removed` over one card's diffs.
({int added, int removed}) diffTotals(List<FileDiff> diffs) {
  var added = 0;
  var removed = 0;
  for (final d in diffs) {
    if (d.oldText != null) removed += contentLineCount(d.oldText!);
    added += contentLineCount(d.newText);
  }
  return (added: added, removed: removed);
}

/// Collapsed suffix text, e.g. `+88 −0`.
String diffStat(List<FileDiff> diffs) {
  final t = diffTotals(diffs);
  return '+${t.added} −${t.removed}';
}

Map<String, Object?>? _asStringMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val as Object?));
  return null;
}

/// Narrows durable `meta.diffs` to typed hunks. Returns null when meta is
/// missing/malformed so the caller falls back; returns `[]` for a create's
/// empty meta (the write-only args fallback then applies).
List<FileDiff>? narrowDiffs(Object? meta) {
  final map = _asStringMap(meta);
  if (map == null) return null;
  final raw = map['diffs'];
  if (raw is! List) return null;
  final out = <FileDiff>[];
  for (final entry in raw) {
    final m = _asStringMap(entry);
    if (m == null) return null;
    final path = m['path'];
    final newText = m['newText'];
    if (path is! String || newText is! String) return null;
    final oldRaw = m['oldText'];
    if (oldRaw != null && oldRaw is! String) return null;
    out.add(FileDiff(path: path, oldText: oldRaw as String?, newText: newText));
  }
  return out;
}

Object? _parseArgs(String argsRaw) {
  if (argsRaw.isEmpty) return null;
  try {
    return jsonDecode(argsRaw);
  } catch (_) {
    return null;
  }
}

String? _pickString(Map<String, Object?> args, List<String> keys) {
  for (final k in keys) {
    final v = args[k];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

/// Intended diff derived purely from call arguments (running state).
FileDiff? intendedDiff(String toolName, String argsRaw) {
  final parsed = _parseArgs(argsRaw);
  final map = _asStringMap(parsed);
  if (map == null) return null;
  final name = toolName.toLowerCase();
  if (name == 'write') {
    final path = _pickString(map, const ['path', 'file_path']);
    final content = map['content'];
    if (path == null || content is! String) return null;
    return FileDiff(path: path, oldText: null, newText: content);
  }
  if (name == 'edit') {
    final path = _pickString(map, const ['path', 'file_path']);
    final oldString = map['old_string'];
    final newString = map['new_string'];
    if (path == null || oldString is! String || newString is! String) return null;
    return FileDiff(path: path, oldText: oldString, newText: newString);
  }
  if (name == 'str_replace_editor') {
    final command = map['command'];
    final path = _pickString(map, const ['path']);
    if (path == null || command is! String) return null;
    if (command == 'create') {
      final text = map['file_text'];
      if (text is! String) return null;
      return FileDiff(path: path, oldText: null, newText: text);
    }
    if (command == 'str_replace') {
      final oldStr = map['old_str'];
      final newStr = map['new_str'];
      if (oldStr is! String || newStr is! String) return null;
      return FileDiff(path: path, oldText: oldStr, newText: newStr);
    }
    return null;
  }
  return null;
}

/// Resolves the diffs to render for a `write`/`edit` call.
///
/// - running → intended diff from args (or null when args are malformed);
/// - settled with non-empty valid `meta.diffs` → applied hunks;
/// - settled `write` with empty/missing/malformed meta → intended args fallback;
/// - settled `edit` with empty/missing/malformed meta → null (generic fallback).
List<FileDiff>? diffsFor({
  required String toolName,
  required String argsRaw,
  required bool running,
  Object? meta,
}) {
  final intended = intendedDiff(toolName, argsRaw);
  if (running) return intended == null ? null : [intended];
  final applied = narrowDiffs(meta);
  if (applied != null && applied.isNotEmpty) return applied;
  if (toolName.toLowerCase() == 'write') {
    return intended == null ? null : [intended];
  }
  return null;
}
