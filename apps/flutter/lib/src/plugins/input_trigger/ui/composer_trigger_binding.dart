/// Composer-side trigger binding — closes the loop between the per-session
/// [InputTriggerController] and the composer's own `TextEditingController`.
/// Dart port of the React input-machine slice this workstream mounts
/// (`ui-conversation/src/client/input/facade.ts` insertReference/setDraft +
/// `machine.ts` mint/reconcile/referenceDraftText):
///
///   * every field edit feeds `controller.track` so chip transactions and
///     trigger detection run on live drafts;
///   * pick outcomes splice into the field — reference inserts mint an
///     occurrence whose draft text is `'@' + label`;
///   * Backspace/Delete adjacent to an occurrence removes exactly that chip
///     range (InputBar.tsx occurrence-deletion branch);
///   * undo/redo restore the controller's transaction draft INTO the field.
library;

import 'package:flutter/widgets.dart';

import '../input_trigger_controller.dart';
import '../trigger_source.dart';

/// One inline reference occurrence in the draft — Dart port of machine.ts
/// `Occurrence` (contract.ts): the range the chip occupies plus its cached
/// projections.
class ComposerOccurrence {
  const ComposerOccurrence({
    required this.occurrenceId,
    required this.source,
    required this.ref,
    required this.offset,
    required this.length,
    required this.label,
    this.appearance,
    required this.clipboardText,
  });

  /// Machine-minted stable identity (monotonic per binding).
  final int occurrenceId;

  /// Owning source name.
  final String source;

  /// Owner-scoped reference id.
  final String ref;

  /// Draft offset where the chip text starts.
  final int offset;

  /// Chip text length (the `'@label'` display form).
  final int length;

  /// Display label without the leading marker glyph.
  final String label;

  /// Domain glyph hint (`'session' | 'file' | 'folder'`); null = plain.
  final String? appearance;

  /// Clipboard / persistence projection (never the model form).
  final String clipboardText;
}

/// Binds one session's [InputTriggerController] to the composer field.
///
/// The binding owns the occurrence table only; the controller stays the sole
/// owner of draft/transactions/menu state, and the field's text is written
/// exclusively through [field] mutations that mirror controller outcomes.
class ComposerTriggerBinding {
  /// Creates the binding over [field] and [controller]. [onCommit] receives
  /// every text the binding writes so the owning composer can mirror it into
  /// its own Riverpod state (programmatic edits bypass TextField.onChanged).
  ComposerTriggerBinding(this._field, this._controller, this._onCommit) {
    _controller.draft = _field.text;
    _field.addListener(_onFieldChanged);
  }

  final TextEditingController _field;
  final InputTriggerController _controller;
  final void Function(String text) _onCommit;

  final List<ComposerOccurrence> _occurrences = [];
  int _occurrenceSeq = 0;
  bool _disposed = false;

  /// Live occurrence table, offset-sorted.
  List<ComposerOccurrence> get occurrences => List.unmodifiable(_occurrences);

  /// The bound controller (exposed for tests asserting pipeline coupling).
  InputTriggerController get controller => _controller;

  /// Detach the field listener. The controller outlives the binding (the
  /// registry owns its lifecycle); the field must survive too.
  void dispose() {
    _disposed = true;
    _field.removeListener(_onFieldChanged);
  }

  // ---- field -> controller ----

  void _onFieldChanged() {
    if (_disposed) return;
    final prev = _controller.draft;
    final next = _field.text;
    // Every notification feeds detection — including caret/selection-only
    // changes (the React selectionchange re-detect): the menu follows the
    // token under the caret without waiting for a text edit. track() itself
    // gates chip-transaction pushes on real text changes.
    _controller.track(
      next,
      _caret(),
      const TriggerGuard(TriggerGuardTier.plain),
    );
    if (identical(prev, next) || prev == next) return;
    _reconcile(prev, next);
  }

  int _caret() {
    final selection = _field.selection;
    if (!selection.isValid) return _field.text.length;
    final base = selection.baseOffset;
    if (base < 0) return _field.text.length;
    return base > _field.text.length ? _field.text.length : base;
  }

  // ---- outcomes (the OutcomeSink face) ----

  /// Apply one pick outcome against the field; true = the field mutated (the
  /// applied-truth contract of the React bail events). Stale-span picks no-op
  /// (TokenSpan draftRev CAS), claims ride the commands workstream.
  bool apply(PickOutcome outcome, TokenSpan span) {
    if (_disposed) return false;
    if (span.draftRev != 0 && span.draftRev != _controller.draftRev) {
      return false;
    }
    switch (outcome) {
      case HandledOutcome():
        return false;
      case ClaimOutcome():
        // Command claims begin their transactions through the commands
        // plugin's popup shell; the composer seam consumes them there.
        return false;
      case TextOutcome(:final text):
        return _splice(span.start, span.end, text);
      case InsertOutcome(:final insert):
        // machine.ts:referenceDraftText — the draft holds `@` + label while
        // the occurrence keeps the clipboard projection.
        final before = _occurrences.length;
        if (!_splice(span.start, span.end, '@${insert.label}')) return false;
        _occurrences.add(
          ComposerOccurrence(
            occurrenceId: ++_occurrenceSeq,
            source: insert.source,
            ref: insert.ref,
            offset: span.start,
            length: insert.label.length + 1,
            label: insert.label,
            appearance: insert.appearance,
            clipboardText: insert.clipboardText,
          ),
        );
        _sortOccurrences();
        assert(_occurrences.length == before + 1);
        return true;
    }
  }

  /// Remove the chip occurrence adjacent to a collapsed caret — the InputBar
  /// keydown branch: Backspace targets the occurrence ending at the caret,
  /// Delete the one starting at it. True = removed (the caller consumes the
  /// keystroke); false = fall through to native deletion.
  bool deleteOccurrenceAt(int caret, {required bool backward}) {
    if (_disposed) return false;
    ComposerOccurrence? target;
    for (final o in _occurrences) {
      final hit = backward ? o.offset + o.length == caret : o.offset == caret;
      if (hit) target = o;
    }
    if (target == null) return false;
    return _splice(target.offset, target.offset + target.length, '');
  }

  // ---- undo / redo bridge ----

  /// Undo the newest chip transaction and push the restored draft into the
  /// field; true when the draft moved back.
  bool undo() {
    if (_disposed) return false;
    final moved = _controller.undo();
    if (moved) _syncField();
    return moved;
  }

  /// Redo the newest undone transaction into the field; true when the draft
  /// advanced again.
  bool redo() {
    if (_disposed) return false;
    final moved = _controller.redo();
    if (moved) _syncField();
    return moved;
  }

  void _syncField() {
    final restored = _controller.draft;
    final prev = _field.text;
    if (prev == restored) return;
    _field.value = TextEditingValue(
      text: restored,
      selection: TextSelection.collapsed(offset: restored.length),
      composing: TextRange.empty,
    );
    _reconcile(prev, restored);
    _onCommit(restored);
  }

  // ---- shared mutation core ----

  /// Replace [start],[end) with [replacement], place the caret after it, feed
  /// the edit through the controller, and reconcile occurrences.
  bool _splice(int start, int end, String replacement) {
    final prev = _field.text;
    if (start < 0 || end < start || end > prev.length) return false;
    final next = prev.replaceRange(start, end, replacement);
    _field.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
    _reconcile(prev, next);
    _controller.track(
      next,
      start + replacement.length,
      const TriggerGuard(TriggerGuardTier.plain),
    );
    _onCommit(next);
    return true;
  }

  /// Reconcile the occurrence table with one edit — machine.ts:reconcile:
  /// entries wholly before the edited range stay, entries at/after shift by
  /// the length delta, entries intersecting the range drop (their structured
  /// chip becomes ordinary draft text).
  void _reconcile(String prev, String next) {
    if (_occurrences.isEmpty) return;
    final range = diffEdit(prev, next);
    final delta = range.insertedLength - (range.end - range.start);
    _occurrences.retainWhere(
      (o) => o.offset + o.length <= range.start || o.offset >= range.end,
    );
    if (delta != 0) {
      for (var i = 0; i < _occurrences.length; i++) {
        final o = _occurrences[i];
        if (o.offset < range.end) continue;
        _occurrences[i] = ComposerOccurrence(
          occurrenceId: o.occurrenceId,
          source: o.source,
          ref: o.ref,
          offset: o.offset + delta,
          length: o.length,
          label: o.label,
          appearance: o.appearance,
          clipboardText: o.clipboardText,
        );
      }
    }
    _sortOccurrences();
  }

  void _sortOccurrences() =>
      _occurrences.sort((a, b) => a.offset.compareTo(b.offset));
}
