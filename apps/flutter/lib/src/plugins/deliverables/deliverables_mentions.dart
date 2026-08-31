/// Turn-scoped produced-file vocabulary — the Dart slice of
/// `packages/client/ui-deliverables/src/client/turn-deliverables.ts`.
///
/// Client-only and model-free: the vocabulary is the mutation tools' own
/// follow-along `locations`, never the closing prose. The turn accumulator
/// (folding tool call/result locations per Turn) lands with the
/// conversation-fold workstream; this module owns the derivation readers and
/// the file-mention resolution the chat prose will consume.
library;

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
