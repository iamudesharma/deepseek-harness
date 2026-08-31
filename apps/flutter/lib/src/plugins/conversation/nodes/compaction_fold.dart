/// Surface-replace semantics for compaction/summary over the folded node
/// list: removes the bracketed range and inserts one CompactionNode citing
/// every shadowed source seq plus the summary event itself.
library;

import 'conversation_nodes.dart';

CompactionNode? applyCompactionSummary({
  required List<ConversationNode> nodes,
  required int? bracketStartSeq,
  required int summarySeq,
  required String text,
}) {
  if (bracketStartSeq == null) return null;
  final bracketIndex = nodes.indexWhere(
    (n) => n.sourceSeqs.contains(bracketStartSeq),
  );
  if (bracketIndex == -1) return null;
  final shadowed = <int>{};
  for (var i = bracketIndex; i < nodes.length; i++) {
    shadowed.addAll(nodes[i].sourceSeqs);
  }
  return CompactionNode(
    key: 'k$summarySeq',
    sourceSeqs: [summarySeq, ...shadowed],
    text: text,
  );
}
