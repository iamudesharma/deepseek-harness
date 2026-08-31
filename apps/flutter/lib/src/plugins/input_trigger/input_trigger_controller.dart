/// Per-session trigger controller — Dart port of
/// `packages/client/ui-input-trigger/src/client/controller.ts`. Owns every
/// piece of mutable interaction state: the authoritative hit (span included;
/// it outlives menu close for space adjudication), the menu store, the
/// candidate-fetch lifecycle, and the chip transaction undo/redo stack.
///
/// The React controller dispatches scoped bail events into the conversation
/// input machine; the Dart composer machine is a later workstream, so pick /
/// space / claim outcomes route through the injected [OutcomeSink] instead —
/// `true` means the input applied the mutation (the bail-event applied-truth
/// contract), and an absent sink drops outcomes.
library;

import 'package:flutter/foundation.dart';

import 'chip_transactions.dart';
import 'detect.dart';
import 'menu_reducer.dart';
import 'trigger_source.dart';

/// Executes one claim/text/insert outcome against the owning input;
/// returns true only when the input actually mutated (the applied-truth
/// contract of the React bail events).
typedef OutcomeSink = bool Function(PickOutcome outcome, TokenSpan span);

/// Roster access the controller borrows from the root registry (registration
/// order preserved).
abstract interface class SourceRoster {
  /// Sources bound to [trigger], order-sorted.
  List<InputTriggerSource> sources(TriggerChar trigger);

  /// Every registered source.
  List<InputTriggerSource> all();
}

/// Per-session trigger pipeline state and orchestration. UI surfaces render
/// from [menu] and route pointer picks back through [pick].
class InputTriggerController {
  /// Creates the controller over [roster]; [sink] executes pick outcomes
  /// (null = outcomes drop, the pre-composer-seam default).
  InputTriggerController({
    required String sessionId,
    required SourceRoster roster,
    OutcomeSink? sink,
    DateTime Function()? now,
  }) : _sessionId = sessionId,
       _roster = roster,
       _sink = sink,
       _now = now ?? (() => DateTime.now()) {
    // Scope-birth prewarm (sessions are always agent-backed in the web model):
    // warm every source once at construction.
    for (final src in _roster.all()) {
      _warm(src);
    }
  }

  final String _sessionId;
  final SourceRoster _roster;
  final OutcomeSink? _sink;
  final DateTime Function() _now;

  /// Menu state store; listeners rebuild on reduction changes only.
  final ValueNotifier<MenuState> menu = ValueNotifier<MenuState>(menuClosed);

  /// Name of the source opened through the programmatic launcher, or null.
  final ValueNotifier<String?> launcher = ValueNotifier<String?>(null);

  /// Aggregated hot lexicon rolls grouped by trigger char, concatenated in
  /// registration order; refreshed on source add/remove and notifications.
  final ValueNotifier<Map<TriggerChar, List<String>>> lexicon =
      ValueNotifier<Map<TriggerChar, List<String>>>(const {});

  /// The authoritative hit: single truth for span CAS material.
  TriggerHit? _hit;

  /// Draft revision the shell reports with each track call (span CAS stamp).
  int draftRev = 0;

  /// Current draft text (chip transactions read/restore it).
  String draft = '';

  bool _disposed = false;

  /// Whether [dispose] has been called — guarded by UI that may still hold a
  /// `ValueListenableBuilder` listening to `menu` when the owning composer
  /// swaps sessions and disposes the old controller before the anchor rebuilds.
  bool get isDisposed => _disposed;

  /// Open single-char typing run: the next contiguous char within the window
  /// coalesces into one chip transaction (machine.ts typingRun).
  ({int end, DateTime at})? _typingRun;

  /// Per-source lexicon unsubscribers (sources without the hook never enter).
  final Map<InputTriggerSource, void Function()> _lexiconOffs = {};

  /// Chip transaction log owned by this workstream (Cmd/Ctrl+Z|Y handlers).
  final ChipUndoStack transactions = ChipUndoStack();

  /// Feed a draft/caret change through trigger detection and drive the menu.
  ///
  /// Records a chip transaction per non-coalesced edit so Cmd/Ctrl+Z walks
  /// real states; [draftRev] advances per mutation for span CAS.
  void track(String newDraft, int caret, TriggerGuard guard) {
    if (_disposed) return;
    if (newDraft != draft) {
      final range = diffEdit(draft, newDraft);
      final typing = range.start == range.end && range.insertedLength == 1;
      final at = _now();
      final run = _typingRun;
      const mergeWindowMs = 1000;
      final merges =
          typing &&
          run != null &&
          run.end == range.start &&
          at.difference(run.at).inMilliseconds <= mergeWindowMs;
      // Single-char runs coalesce into one transaction; anything else opens
      // its own (machine.ts:onDraftChanged).
      if (!merges) transactions.push(draft);
      _typingRun = typing ? (end: range.start + 1, at: at) : null;
      draft = newDraft;
      draftRev += 1;
    }
    clearLauncher();
    final raw = detectTrigger(newDraft, caret, guard);
    if (raw == null) {
      _hit = null;
      stopFetch();
      _reduce(CloseMenuEvent());
      return;
    }
    final hit = TriggerHit(
      trigger: raw.trigger,
      query: raw.query,
      quoted: raw.quoted,
      position: raw.position,
      span: TokenSpan(
        start: raw.span.start,
        end: raw.span.end,
        draftRev: draftRev,
      ),
    );
    final prev = menu.value;
    final launched = launcher.value != null;
    final same =
        !launched &&
        prev.open &&
        prev.hit != null &&
        prev.hit!.trigger == hit.trigger &&
        prev.hit!.query == hit.query &&
        prev.hit!.quoted == hit.quoted &&
        prev.hit!.span.start == hit.span.start &&
        prev.hit!.span.end == hit.span.end;
    _hit = hit;
    if (same) return;
    final roster = _roster.sources(hit.trigger);
    if (roster.isEmpty) {
      stopFetch();
      _reduce(CloseMenuEvent());
      return;
    }
    if (launched ||
        !prev.open ||
        prev.hit == null ||
        prev.hit!.trigger != hit.trigger) {
      menu.value = seedGroups(menu.value, roster);
    }
    _reduce(HitEvent(hit));
    fetchCandidates(hit, roster);
  }

  /// Keyboard arbitration while the menu is open. Inside IME composition
  /// ([composing]) everything passes.
  ArbitrateOutcome arbitrate(ArbitrateKey key, bool composing) {
    if (composing || _disposed) return ArbitrateOutcome.pass;
    final state = menu.value;
    if (!state.open) return ArbitrateOutcome.pass;
    switch (key) {
      case ArbitrateKey.up:
        _reduce(MoveEvent(-1));
        return ArbitrateOutcome.consumed;
      case ArbitrateKey.down:
        _reduce(MoveEvent(1));
        return ArbitrateOutcome.consumed;
      case ArbitrateKey.escape:
        stopFetch();
        _reduce(CloseMenuEvent());
        return ArbitrateOutcome.consumed;
      case ArbitrateKey.enter:
        final highlight = state.highlight;
        if (highlight == null) return ArbitrateOutcome.pass;
        pick(highlight.source, highlight.index);
        return ArbitrateOutcome.pickHighlighted;
    }
  }

  /// Space adjudication over the just-completed leading token: polls sources'
  /// matchSpace (hot state, synchronous) and dispatches the outcome itself.
  /// Returns true when a claim/insert was actually applied — the caller
  /// consumes the keystroke exactly then.
  bool onSpace() {
    final hit = _hit;
    if (_disposed || hit == null || hit.position != TriggerPosition.leading) {
      return false;
    }
    final token = hit.trigger + hit.query;
    for (final src in _roster.sources(hit.trigger)) {
      final outcome = src.matchSpace(_sessionId, token);
      if (outcome == null) continue;
      if (outcome is HandledOutcome) return true;
      return execute(outcome, hit.span);
    }
    return false;
  }

  /// Pointer/enter pick: route the candidate through onPick and execute
  /// claim/insert outcomes via the sink.
  void pick(String source, int index) {
    final state = menu.value;
    final hit = _hit;
    if (_disposed || !state.open || hit == null) return;
    MenuGroup? group;
    for (final g in state.groups) {
      if (g.source == source) group = g;
    }
    final candidate =
        group != null && group.status == 'ready' && index < group.items.length
        ? group.items[index]
        : null;
    if (candidate == null) return;
    InputTriggerSource? src;
    for (final s in _roster.sources(hit.trigger)) {
      if (s.name == source) src = s;
    }
    if (src == null) return;
    final outcome = src.onPick(
      InputTriggerPick(
        candidate: candidate,
        sessionId: _sessionId,
        position: hit.position,
        via: 'menu',
        span: hit.span,
      ),
    );
    stopFetch();
    _reduce(CloseMenuEvent());
    execute(outcome, hit.span);
  }

  /// Serialize one reference occurrence to its model form via the owning
  /// source's codec. Owner missing or codec-less rejects — the submit attempt
  /// blocks instead of silently downgrading to the clipboard text.
  Future<String> serializeReference(String source, String ref) async {
    for (final src in _roster.all()) {
      if (src.name == source) {
        final codec = src.codec;
        if (codec == null) break;
        return codec.serialize(ref);
      }
    }
    throw StateError('slash: no serializer for reference source "$source"');
  }

  /// Undo the newest chip transaction; true when the draft moved back.
  bool undo() {
    final step = transactions.undo(draft);
    if (step == null) return false;
    draft = step.entry.draftBefore;
    draftRev += 1;
    return true;
  }

  /// Redo the newest undone transaction; true when the draft advanced again.
  bool redo() {
    final step = transactions.redo(draft);
    if (step == null) return false;
    draft = step.entry.draftBefore;
    draftRev += 1;
    return true;
  }

  /// Drop the menu group of a disposed source (registry change notification).
  void sourceRemoved(InputTriggerSource source) {
    final state = menu.value;
    if (state.open &&
        state.hit != null &&
        state.hit!.trigger == source.trigger) {
      _reduce(SourceFailedEvent(state.generation, source.name));
    }
    _lexiconOffs.remove(source)?.call();
    refreshLexicon();
  }

  /// Admit a source registered after this controller's birth (registry change
  /// notification): warm it and fold its roll into the live lexicon.
  void sourceAdded(InputTriggerSource source) {
    _warm(source);
    refreshLexicon();
  }

  /// External dismiss (e.g. pointer outside the composer area).
  void dismiss() {
    if (_disposed) return;
    stopFetch();
    _reduce(CloseMenuEvent());
  }

  /// Scope teardown: close, abort, and detach lexicon subscriptions.
  void dispose() {
    _disposed = true;
    stopFetch();
    _reduce(CloseMenuEvent());
    _hit = null;
    for (final off in List.of(_lexiconOffs.values)) {
      off();
    }
    _lexiconOffs.clear();
    menu.dispose();
    launcher.dispose();
    lexicon.dispose();
  }

  void _warm(InputTriggerSource src) {
    try {
      src.warm(_sessionId);
      final off = src.subscribeLexicon(_sessionId, refreshLexicon);
      if (src.lexicon != null && off != null) _lexiconOffs[src] = off;
    } catch (error) {
      // Contain faulty source setup exactly like the root service does: the
      // registration stands and other sources still warm.
      debugPrint(
        '[ui-input-trigger] source "${src.name}" setup failed: $error',
      );
    }
    refreshLexicon();
  }

  /// Re-poll every lexicon-bearing source and publish the aggregated rolls.
  void refreshLexicon() {
    final rolls = <TriggerChar, List<String>>{};
    for (final src in _roster.all()) {
      List<String>? names;
      try {
        names = src.lexicon(_sessionId);
      } catch (error) {
        // A faulty source drops silently with a console record; the refresh
        // runs inside notification callbacks where a throw would starve the
        // remaining consumers.
        debugPrint(
          '[ui-input-trigger] source "${src.name}" lexicon failed: $error',
        );
        continue;
      }
      if (names == null) continue;
      final prev = rolls[src.trigger];
      rolls[src.trigger] = prev == null ? names : [...prev, ...names];
    }
    lexicon.value = Map.unmodifiable(rolls);
  }

  /// Launch the candidate fetch for one hit generation. Settlements reduce
  /// under the generation guard — [menuReduce] drops events whose generation
  /// is stale — so superseded fetches need no explicit cancellation handle.
  void fetchCandidates(TriggerHit hit, List<InputTriggerSource> roster) {
    final generation = menu.value.generation;
    for (final source in roster) {
      () async {
        try {
          final items = await source.candidates(
            _sessionId,
            CandidateRequest(
              query: hit.query,
              quoted: hit.quoted,
              position: hit.position,
            ),
          );
          if (_disposed) return;
          _reduce(SourceSettledEvent(generation, source.name, items));
        } catch (error) {
          if (_disposed) return;
          debugPrint(
            '[ui-input-trigger] source "${source.name}" candidates failed: $error',
          );
          _reduce(SourceFailedEvent(generation, source.name));
        }
      }();
    }
  }

  /// Supersede in-flight candidate fetches. Generation gating in
  /// [menuReduce] already drops every stale settlement, so this only marks
  /// the intent where the React pipeline aborted its AbortController.
  void stopFetch() {}

  void clearLauncher() {
    if (launcher.value != null) launcher.value = null;
  }

  void _reduce(MenuEvent event) {
    final next = menuReduce(menu.value, event);
    if (!identical(next, menu.value)) menu.value = next;
    if (!next.open) clearLauncher();
  }

  /// Execute one outcome via the sink; true = the input applied it.
  bool execute(PickOutcome? outcome, TokenSpan span) {
    if (outcome == null || outcome is HandledOutcome) return false;
    return _sink?.call(outcome, span) ?? false;
  }
}

/// Prefix/suffix common-scan recovering the edit range between two drafts
/// (machine.ts:diffEdit) — used to classify chip transactions for the
/// single-char typing-run coalescing.
({int start, int end, int insertedLength}) diffEdit(String prev, String next) {
  var p = 0;
  final maxCommon = prev.length < next.length ? prev.length : next.length;
  while (p < maxCommon && prev[p] == next[p]) {
    p += 1;
  }
  var s = 0;
  final maxSuffix = maxCommon - p;
  while (s < maxSuffix &&
      prev[prev.length - 1 - s] == next[next.length - 1 - s]) {
    s += 1;
  }
  return (start: p, end: prev.length - s, insertedLength: next.length - s - p);
}
