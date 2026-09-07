/// Frozen cross-package contract of the trigger pipeline, Dart port of
/// `packages/client/ui-input-trigger/src/types.ts`. Sources (commands,
/// reference) see [InputTriggerSource] alone; the controller executes pick
/// outcomes through the injected sink.
library;

/// Trigger character a source binds to: `'/'` or `'@'`.
typedef TriggerChar = String;

/// Where the trigger token sits in the draft: the trimmed draft starts with
/// it (`leading`) or it appears mid-text (`inline`).
enum TriggerPosition { leading, inline }

/// Availability tier derived from the input phase: plain = both chars live;
/// claimed = `'/'` suppressed, `'@'` live; frozen = none.
enum TriggerGuardTier { plain, claimed, frozen }

/// Trigger availability guard handed to detection and tracking.
class TriggerGuard {
  /// Creates a guard over [tier].
  const TriggerGuard(this.tier);

  /// The active tier.
  final TriggerGuardTier tier;
}

/// Keys the menu intercepts while open (all behind the IME composition guard).
enum ArbitrateKey { up, down, enter, escape }

/// `consumed` = key handled; `pickHighlighted` = enter picked the highlight;
/// `pass` = let the input see it.
enum ArbitrateOutcome { consumed, pickHighlighted, pass }

/// One menu candidate. Pure display data — zero behavior.
class InputTriggerCandidate {
  /// Creates a candidate.
  const InputTriggerCandidate({
    required this.name,
    this.description,
    this.icon,
    this.hint,
    this.section,
    this.value,
  });

  /// Display name (the exact-match key).
  final String name;

  /// Secondary line.
  final String? description;

  /// Icon hint.
  final String? icon;

  /// Argument placeholder shown for input-taking commands.
  final String? hint;

  /// Optional visual heading shared by adjacent candidates.
  final String? section;

  /// Opaque source-owned pick payload.
  final String? value;
}

/// Pick-moment snapshot of the trigger token span. CAS: a stale [draftRev]
/// no-ops the whole action on the composer side.
class TokenSpan {
  /// Creates a span snapshot.
  const TokenSpan({
    required this.start,
    required this.end,
    required this.draftRev,
  });

  /// Span start (the trigger char index).
  final int start;

  /// Span end (the caret at detection time).
  final int end;

  /// Draft revision stamped by the caller for pick-time CAS.
  final int draftRev;
}

/// Settled result of a command submit transaction.
class SubmitOutcome {
  /// Creates an outcome.
  const SubmitOutcome({required this.kind, this.text});

  /// `'success' | 'error'`.
  final String kind;

  /// Failure or success text when present.
  final String? text;
}

/// Command-mode entry credential: integrity-watched draft prefix plus the
/// submit transaction closure (React `CommandClaim.submit`).
class CommandClaim {
  /// Creates a claim.
  const CommandClaim({
    required this.token,
    this.hint,
    this.images = false,
    required this.submit,
  });

  /// Integrity-watched draft prefix, e.g. `'/goal '` — breaking startsWith
  /// releases the claim.
  final String token;

  /// Ghost-text hint rendered while the claim's args are blank.
  final String? hint;

  /// Whether composer image attachments may accompany this command's submit.
  final bool images;

  /// Enter transaction supplied by the source; resolves with the settled
  /// outcome.
  final Future<SubmitOutcome> Function(
    String args,
    List<Map<String, Object?>> images,
  )
  submit;
}

/// Inline reference insertion: the draft holds the complete display text while
/// the occurrence keeps its range and cached projections.
class ReferenceInsert {
  /// Creates an insert outcome payload.
  const ReferenceInsert({
    required this.source,
    required this.ref,
    required this.label,
    this.appearance,
    required this.clipboardText,
  });

  /// Owning source name.
  final String source;

  /// Owner-scoped reference id.
  final String ref;

  /// Inline display label.
  final String label;

  /// Domain glyph hint: `'session' | 'file' | 'folder'`.
  final String? appearance;

  /// Clipboard / persistence projection (never the model form).
  final String clipboardText;
}

/// Unified pick return. `null` = miss → default sink; [handled] = the source
/// dealt with it internally; [claim]/[insert]/[text] execute via the sink.
sealed class PickOutcome {
  const PickOutcome();
}

/// The source dealt with the pick internally (e.g. opened its popup shell).
class HandledOutcome extends PickOutcome {
  /// Constant instance.
  const HandledOutcome();
}

/// Claim the draft into a command transaction.
class ClaimOutcome extends PickOutcome {
  /// Wraps the claim.
  const ClaimOutcome(this.claim);

  /// The claim to begin.
  final CommandClaim claim;
}

/// Replace the token span with an inline reference chip.
class InsertOutcome extends PickOutcome {
  /// Wraps the reference insertion.
  const InsertOutcome(this.insert);

  /// The reference to insert.
  final ReferenceInsert insert;
}

/// Replace the token span with literal text — the plain-text reference path.
class TextOutcome extends PickOutcome {
  /// Creates the text outcome.
  const TextOutcome(this.text, {this.continueTracking = false});

  /// Literal replacement for the trigger token span (e.g. `/name `).
  final String text;

  /// Keep completion open after the splice (directory descent).
  final bool continueTracking;
}

/// Everything a source receives on pick.
class InputTriggerPick {
  /// Creates a pick envelope.
  const InputTriggerPick({
    required this.candidate,
    required this.sessionId,
    required this.position,
    required this.via,
    required this.span,
  });

  /// Picked candidate.
  final InputTriggerCandidate candidate;

  /// Session projection id.
  final String sessionId;

  /// Token position at detection time.
  final TriggerPosition position;

  /// Which path produced the pick: menu / space / enter.
  final String via;

  /// Span snapshot for CAS.
  final TokenSpan span;
}

/// Candidate request passed to a source; superseded on query change / close.
class CandidateRequest {
  /// Creates a request.
  const CandidateRequest({
    required this.query,
    this.quoted = false,
    required this.position,
    this.cancelled,
  });

  /// Live-filtered query between the trigger char and the caret.
  final String query;

  /// Whether the active @file token is an open quoted path.
  final bool quoted;

  /// Token position.
  final TriggerPosition position;

  /// Superseded-on-query-change probe; null when the pipeline keeps no
  /// cancellation handle (generation gating drops late settlements anyway).
  final bool Function()? cancelled;
}

/// Reference codec owned by a source producing [InsertOutcome]s.
abstract interface class ReferenceCodec {
  /// Clipboard / persistence projection of one reference (e.g. `/name`).
  String clipboardText(String ref);

  /// Model serialization of one reference (e.g. `<skill>name</skill>`).
  Future<String> serialize(String ref);
}

/// One trigger source registered under a `(trigger, name)` pair. Callbacks
/// receive the session id projection only — sources keep no copy across calls.
abstract class InputTriggerSource {
  /// Creates a source.
  const InputTriggerSource();

  /// Trigger character bound to this source.
  TriggerChar get trigger;

  /// Menu group label; unique per trigger — duplicate registration throws.
  String get name;

  /// Menu group display order (lower = higher in the list; default 0).
  int get order => 0;

  /// Whether the menu renders the source-title row; defaults to true.
  bool get showGroupTitle => true;

  /// Candidates for one hit generation.
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  );

  /// Every pick lands here; outcomes are executed by the pipeline.
  PickOutcome? onPick(InputTriggerPick pick);

  /// Synchronous space-time adjudication over hot state only; `token` is the
  /// just-completed leading token (e.g. `/goal`). Null = not claimed.
  PickOutcome? matchSpace(String sessionId, String token) => null;

  /// Scope-birth prewarm (fire-and-forget).
  void warm(String sessionId) {}

  /// Synchronous hot-snapshot name roll; null = backing data not warm yet.
  List<String>? lexicon(String sessionId) => null;

  /// Subscribe to lexicon changes for one session; returns unsubscribe.
  void Function()? subscribeLexicon(
    String sessionId,
    void Function() listener,
  ) => null;

  /// Reference codec; required for sources producing insert outcomes.
  ReferenceCodec? get codec => null;
}
