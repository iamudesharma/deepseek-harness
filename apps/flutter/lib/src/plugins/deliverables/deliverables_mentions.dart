/// Turn-scoped produced-file vocabulary — the Dart slice of
/// `packages/client/ui-deliverables/src/client/turn-deliverables.ts`.
///
/// Client-only and model-free: the vocabulary is the mutation tools' own
/// follow-along `locations`, never the closing prose. The turn accumulator
/// (folding tool call/result locations per Turn) lands with the
/// conversation-fold workstream; this module owns the derivation readers and
/// the file-mention resolution the chat prose will consume.
library;

import 'dart:convert';

/// Immutable produced-file facts published against one Turn.
class DeliverablesTurnData {
  /// `(seq, path)` pairs in first-seen order.
  final List<({int seq, String path})> produced;

  /// Creates turn data.
  const DeliverablesTurnData(this.produced);
}

/// Trailing path segment, the part that identifies the file at a glance.
String basename(String path) {
  final at = path.lastIndexOf('/');
  final win = path.lastIndexOf(r'\');
  final last = at > win ? at : win;
  return last == -1 ? path : path.substring(last + 1);
}

/// Files produced by one Turn data value.
///
/// A produced file must be listed whether or not the model remembered to
/// name it. Paths keep first-seen order and appear once, so a file written
/// and then edited in the same turn is one entry. [closingSeq] excludes
/// later Tool settlements: the Conversation Location index owns turn
/// membership before this runs, so paths cannot spill across turns.
List<String> producedForClosing(
  DeliverablesTurnData? data, {
  int closingSeq = -1,
}) {
  if (data == null) return const [];
  final paths = <String>[];
  final seen = <String>{};
  for (final produced in data.produced) {
    if (closingSeq >= 0 && produced.seq > closingSeq) continue;
    if (seen.contains(produced.path)) continue;
    seen.add(produced.path);
    paths.add(produced.path);
  }
  return paths;
}

/// One resolved file mention: the full path (the disambiguator) plus the
/// open action handed back by the consumer.
class ResolvedMention {
  /// Exact produced path the token resolved to.
  final String path;

  /// Opens the file through the chat view's opener.
  final void Function() open;

  /// Creates a resolution.
  const ResolvedMention({required this.path, required this.open});
}

/// File-mention vocabulary over one turn's produced paths, for the closing
/// message's prose: an inline-code token opens the file it names. A token
/// resolves by exact path, or by being exactly the basename of exactly one
/// produced path — a basename two paths share stays inert rather than
/// guessing, so a mention link can never open the wrong file or 404.
///
/// An exact path always wins first, even when its basename is ambiguous
/// across the turn (React `producedFileMentions` parity: `paths.includes`
/// before `onlyPathWithBasename`).
ResolvedMention? resolveFileMention(
  List<String> paths,
  String token,
  void Function(String path) openFile,
) {
  if (paths.contains(token)) {
    return ResolvedMention(path: token, open: () => openFile(token));
  }
  final matches = paths.where((path) => basename(path) == token).toList();
  if (matches.length != 1) return null;
  return ResolvedMention(
    path: matches.single,
    open: () => openFile(matches.single),
  );
}

/// Selector-matched produced paths for the turn-tail chain entry.
///
/// The same claim test React `selectProducedFiles` runs: no produced files,
/// no vocabulary (`null` declines before mount). The Dart conversation hub
/// has no `conversation.chat.turnTail` chain seam yet, so the owning view
/// renders an empty chain at zero cost; when the seam lands, it feeds this
/// same reader over the turn's `DeliverablesTurnData`.
List<String>? selectProducedFiles(
  DeliverablesTurnData? data, {
  int closingSeq = -1,
}) {
  final paths = producedForClosing(data, closingSeq: closingSeq);
  return paths.isEmpty ? null : paths;
}

String? _mutationPath(String name, Object? argsRaw) {
  Object? args;
  if (argsRaw is String) {
    try {
      args = jsonDecode(argsRaw);
    } catch (_) {
      return null;
    }
  } else if (argsRaw is Map) {
    args = argsRaw;
  }
  if (args is! Map) return null;
  final Map<String, dynamic> map = args is Map<String, dynamic>
      ? args
      : Map<String, dynamic>.from(args as Map);
  String? pathValue(Object? v) {
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  switch (name) {
    case 'write':
      if (map['content'] is! String) return null;
      return pathValue(map['file_path']);
    case 'edit':
      final oldStr = map['old_string'];
      final newStr = map['new_string'];
      if (oldStr is! String ||
          oldStr.isEmpty ||
          newStr is! String ||
          oldStr == newStr) {
        return null;
      }
      final replaceAll = map['replace_all'];
      if (replaceAll != null && replaceAll is! bool) return null;
      return pathValue(map['file_path']);
    case 'str_replace_editor':
      final path = pathValue(map['path']);
      if (path == null) return null;
      switch (map['command']) {
        case 'create':
          return map['file_text'] is String ? path : null;
        case 'str_replace':
          final oldStr = map['old_str'];
          if (oldStr is! String || oldStr.isEmpty) return null;
          final newStr = map['new_str'];
          if (newStr != null && newStr is! String) return null;
          return path;
        case 'insert':
          final line = map['insert_line'];
          if (line is! int || line < 0) return null;
          return map['new_str'] is String ? path : null;
        default:
          return null;
      }
    default:
      return null;
  }
}

/// Derives produced paths for [turn] directly from history entries.
///
/// Stopgap until the conversation fold publishes `DeliverablesTurnData`:
/// joins `tool/call` mutation paths with successful `tool/result` by
/// `callId`, scoped to [turn], first-seen order, deduped.
List<String> producedPathsForTurn(
  List<dynamic> history, {
  required int turn,
  int closingSeq = -1,
}) {
  final Map<String, String> pending = {};
  final Map<String, int> callTurn = {};
  final List<({int seq, String path})> produced = [];
  // Pass 1: collect mutation paths per callId.
  for (final entry in history) {
    final dynamic ev = (entry as dynamic).event;
    final String type = (ev as dynamic).type as String;
    final Map<String, dynamic> data =
        ((ev as dynamic).data as Map).cast<String, dynamic>();
    if (type == 'tool/call') {
      final String? callId =
          (data['callId'] ?? data['id'])?.toString();
      if (callId == null || callId.isEmpty) continue;
      final int evTurn = (data['turn'] as num?)?.toInt() ?? turn;
      if (evTurn != turn) continue;
      final String name =
          (data['name'] ?? data['toolName'] ?? '').toString();
      final Object? argsRaw =
          data['args'] ?? data['arguments'] ?? data['input'];
      final path = _mutationPath(name, argsRaw);
      if (path != null) {
        pending[callId] = path;
        callTurn[callId] = evTurn;
      }
    }
  }
  // Pass 2: keep only successful results.
  for (final entry in history) {
    final dynamic ev = (entry as dynamic).event;
    final String type = (ev as dynamic).type as String;
    if (type != 'tool/result') continue;
    final Map<String, dynamic> data =
        ((ev as dynamic).data as Map).cast<String, dynamic>();
    if (data['isError'] == true || data['error'] != null) continue;
    final dynamic msg = data['message'];
    String? callId;
    if (msg is Map) {
      final src = msg['source'];
      if (src is Map) callId = src['callId']?.toString();
      callId ??= msg['callId']?.toString();
    }
    callId ??= data['callId']?.toString() ?? data['id']?.toString();
    if (callId == null) continue;
    final path = pending[callId];
    if (path == null) continue;
    final int seq = (ev as dynamic).seq as int;
    if (closingSeq >= 0 && seq > closingSeq) continue;
    produced.add((seq: seq, path: path));
  }
  final seen = <String>{};
  final out = <String>[];
  produced.sort((a, b) => a.seq.compareTo(b.seq));
  for (final p in produced) {
    if (seen.add(p.path)) out.add(p.path);
  }
  return out;
}
