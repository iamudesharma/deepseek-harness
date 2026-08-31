/// Chip transaction undo/redo — the bounded transaction log half of the React
/// input machine (`ui-conversation/src/client/input/machine.ts` pushTxn /
/// onUndo / onRedo), extracted to what this workstream owns: draft-level
/// transactions whose before-states restore verbatim. The ring depth and the
/// cut-the-redo-chain-on-push rule are ported unchanged.
library;

/// One undo unit: the snapshot taken before a transaction applied.
class ChipTransaction {
  /// Creates a unit.
  const ChipTransaction({required this.draftBefore});

  /// Full draft text before the transaction.
  final String draftBefore;
}

/// Bounded undo/redo log over draft snapshots.
class ChipUndoStack {
  /// Creates a stack with the React ring depth (100).
  ChipUndoStack({this.logLimit = 100});

  final int logLimit;

  final List<ChipTransaction> _log = [];
  final List<ChipTransaction> _redo = [];

  /// Whether an undo unit is available.
  bool get canUndo => _log.isNotEmpty;

  /// Whether a redo unit is available.
  bool get canRedo => _redo.isNotEmpty;

  /// Push one undo unit (before-state), trim the ring, and cut the redo chain
  /// (machine.ts:pushTxn).
  void push(String draftBefore) {
    _log.add(ChipTransaction(draftBefore: draftBefore));
    if (_log.length > logLimit) _log.removeAt(0);
    _redo.clear();
  }

  /// Pop the newest unit and return it together with the current draft pushed
  /// onto the redo chain; null when nothing to undo. The caller applies the
  /// returned [ChipTransaction.draftBefore] and feeds the displaced draft back
  /// through [redoPush] when walking the other direction — kept explicit so
  /// the controller stays the sole mutation site of the draft itself.
  ({ChipTransaction entry, String displaced})? undo(String currentDraft) {
    if (_log.isEmpty) return null;
    final entry = _log.removeLast();
    _redo.add(ChipTransaction(draftBefore: currentDraft));
    return (entry: entry, displaced: currentDraft);
  }

  /// Pop the newest redo unit; null when nothing to redo. The displaced
  /// current draft re-enters the undo log without cutting the chain being
  /// walked (machine.ts:onRedo manual push, trim included).
  ({ChipTransaction entry, String displaced})? redo(String currentDraft) {
    if (_redo.isEmpty) return null;
    final entry = _redo.removeLast();
    _log.add(ChipTransaction(draftBefore: currentDraft));
    if (_log.length > logLimit) _log.removeAt(0);
    return (entry: entry, displaced: currentDraft);
  }

  /// Drops every recorded transaction (send-committed posture: committed
  /// content is gone for good — undo must not resurrect it).
  void clear() {
    _log.clear();
    _redo.clear();
  }
}
