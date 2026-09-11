/// `SessionEventMap` reader semantics mirrored from
/// `packages/core/session/src/types.ts` (`SessionEventMap`, `SessionEvent`,
/// `SurfaceOp`) and the repo-wide required-on-read rule.
///
/// The map is merge-extensible: plugins add event types, so the envelope
/// accepts any string `type`. What makes reconstruction safe is the
/// `ignorable` marker: a reader meeting an unrecognized **required** type must
/// refuse to reconstruct instead of silently dropping it; an unrecognized
/// `ignorable: true` record may be skipped because its loss cannot change how
/// the rest of the log reads.
library;

import 'package:meta/meta.dart';

/// Core `SessionEventMap` members declared by `packages/core/session/src/types.ts`.
/// Includes `system/message` (session-log-v3 canonical surface head).
const Set<String> kCoreSessionEventTypes = {
  'turn/start',
  'turn/end',
  'step/start',
  'step/end',
  'system/message',
  'user/message',
  'assistant/chunk',
  'assistant/message',
  // A model attempt that committed no surface message (failed, retried,
  // cancelled, or stream-error at settlement). Core member — log-only
  // diagnostics, never enters derived history.
  'assistant/attempt',
  'tool/call',
  'tool/result',
  'todo/write',
  'request/header',
  'request/context',
  'session/end-seed',
};

/// Plugin-contributed members merged into `SessionEventMap` across the
/// workspace, extracted mechanically from every `declare module` augmentation
/// (`packages/core/agent`, `core/tools`, `interaction/{user-approval,commands,
/// permission-presets}`, `feedback/message-feedback`, `sandbox/sandbox-policy`, `compaction`, `goal`,
/// `subagent`, `schedule`, `plan-mode`, `preset/agent-presets`,
/// `session/session-title*`, `llm/llm-retry`, `hooks/hook-protocol`,
/// `workflow/tool-workflow`, `feedback/command-feedback`,
/// `experimental/agent-team`, `web/web-search-deepseek`). A Flutter build is a
/// conforming reader of an assembled app's logs only when it knows these.
const Set<String> kPluginSessionEventTypes = {
  'agent/inbox/spliced',
  'agent-preset/selected',
  'approval/asked',
  'approval/decided',
  'approval/policy',
  'command/done',
  'command/run',
  'compaction/end',
  'compaction/prune',
  'compaction/start',
  'compaction/summary',
  'feedback/message-delete',
  'feedback/message-put',
  'feedback/record',
  'goal/change',
  'hook/invoked',
  'hook/result',
  'llm/retry',
  'llm/retry-started',
  'model/selection',
  'permission/preset',
  'plan/mode',
  'sandbox/mode',
  'schedule/change',
  'session-log-deepseek/delivery-accepted',
  'session/title',
  'session/title-llm-request',
  'subagent/descriptor',
  'subagent/model-selection-policy',
  'team/member',
  'team/message/delivered',
  'team/message/queued',
  'team/task',
  'tool/code-dispatch',
  'tool/code-dispatch-start',
  'tool-workflow/agent-end',
  'tool-workflow/agent-start',
  'tool-workflow/run-end',
  'tool-workflow/run-start',
  'web/deepseek-search-llm-request',
};

/// Every event type this build knows: core plus merged plugin extensions.
final Set<String> kKnownSessionEventTypes = {
  ...kCoreSessionEventTypes,
  ...kPluginSessionEventTypes,
};

/// The subset whose events produce LLM messages and are eligible to carry
/// surface metadata (`surfaceOp`, `sourceEventSeqs`). Mirrors `SurfaceEventType`
/// (`system/message`, `user/message`, `assistant/message`, `tool/result`).
const Set<String> kSurfaceEventTypes = {
  'system/message',
  'user/message',
  'assistant/message',
  'tool/result',
};

/// Whether a decoded JSON number is a non-negative safe event sequence.
/// Mirrors Host `isEventSeq` (safe integer, >= 0, no -0; Dart ints have no -0).
/// Integral doubles (JSON `5.0`) count, matching Host `Number.isSafeInteger`.
bool isEventSeq(Object? value) {
  if (value is int) return value >= 0;
  if (value is double) {
    return value >= 0 &&
        value <= 9007199254740991 &&
        value == value.truncateToDouble();
  }
  return false;
}

/// Coerces an integral JSON number to int; throws [ArgumentError] otherwise.
int _asInt(Object? value, String field) {
  if (value is int) return value;
  if (value is double &&
      value >= -9007199254740991 &&
      value <= 9007199254740991 &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw ArgumentError.value(value, field, 'must be an integer');
}

/// How a surface-eligible event entered the ordered surface.
///
/// Mirrors `SurfaceOp`: `'append'` or a positional replacement over the
/// inclusive `[startSeq, endSeq]` node range (used by compaction and the
/// system-head rewrite). Field names track the v3 wire exactly.
@immutable
class SurfaceOp {
  const SurfaceOp._(this.isReplace, this.startSeq, this.endSeq);

  /// The normal tail-append op.
  static final SurfaceOp append = SurfaceOp._(false, null, null);

  /// Builds the replace-range op over earlier event seqs in surface order.
  factory SurfaceOp.replace({required int startSeq, required int endSeq}) =>
      SurfaceOp._(true, startSeq, endSeq);

  /// Decodes the wire form; throws [ArgumentError] on malformed input.
  /// Mirrors Host `isReplaceOp`: exactly the keys `op`/`startSeq`/`endSeq`
  /// with non-negative safe-integer endpoints.
  static SurfaceOp fromJson(Object? wire) {
    if (wire == 'append') return append;
    if (wire is Map &&
        wire.length == 3 &&
        wire['op'] == 'replace' &&
        isEventSeq(wire['startSeq']) &&
        isEventSeq(wire['endSeq'])) {
      return SurfaceOp.replace(
        startSeq: (wire['startSeq'] as num).toInt(),
        endSeq: (wire['endSeq'] as num).toInt(),
      );
    }
    // TODO(K5): legacy bridge — the fork Host (pre-5dda764 rebase) still
    // emits `start`/`end`. Accept while talking to it; remove once the fork
    // Host is rebased, when only the canonical shape above remains.
    if (wire is Map &&
        wire.length == 3 &&
        wire['op'] == 'replace' &&
        isEventSeq(wire['start']) &&
        isEventSeq(wire['end'])) {
      return SurfaceOp.replace(
        startSeq: (wire['start'] as num).toInt(),
        endSeq: (wire['end'] as num).toInt(),
      );
    }
    throw ArgumentError.value(wire, 'surfaceOp', 'malformed surface op');
  }

  /// Whether this op replaces a node range rather than appending.
  final bool isReplace;

  /// Inclusive replacement range start (replace ops only): an earlier event seq.
  final int? startSeq;

  /// Inclusive replacement range end (replace ops only): an earlier event seq.
  final int? endSeq;
}

/// One immutable session-log entry: the discriminated envelope plus validated
/// surface metadata. Payload typing per member lands with its consumer row;
/// [data] is the decoded JSON object view (empty when the wire value is not
/// an object); [dataJson] preserves the raw wire value.
@immutable
class SessionEventEnvelope {
  /// Creates an already-decoded entry.
  const SessionEventEnvelope({
    required this.type,
    required this.seq,
    required this.time,
    required this.data,
    required this.dataJson,
    required this.ignorable,
    this.sourceEventSeqs,
    this.surfaceOp,
    this.surfaceOpJson,
  });

  /// Exact envelope keys accepted by Host `assertSessionWireEvent`.
  /// Anything else is a non-current envelope and must be rejected, not skipped.
  static const Set<String> kWireEnvelopeKeys = {
    'type',
    'seq',
    'time',
    'data',
    'ignorable',
    'surfaceOp',
    'sourceEventSeqs',
  };

  /// Decodes one log entry; throws [ArgumentError] on malformed envelope
  /// fields. Unknown `type`s decode fine ([isKnown] is false) — refusal is a
  /// reader decision, not a decoder decision.
  factory SessionEventEnvelope.fromJson(Map<String, Object?> json) {
    for (final key in json.keys) {
      if (!kWireEnvelopeKeys.contains(key)) {
        throw ArgumentError.value(
          key,
          'session wire event',
          'has unexpected field $key',
        );
      }
    }
    final type = json['type'];
    final seq = json['seq'];
    final time = json['time'];
    if (type is! String || type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'must be a non-empty string');
    }
    final seqInt = _asInt(seq, 'seq');
    if (seqInt < 0) {
      throw ArgumentError.value(seq, 'seq', 'must be non-negative');
    }
    final timeInt = _asInt(time, 'time');
    if (!json.containsKey('data')) {
      throw ArgumentError.value(
        null,
        'data',
        'must be present on session wire event',
      );
    }
    final rawData = json['data'];
    final decodedData = rawData is Map
        ? Map<String, Object?>.from(rawData)
        : const <String, Object?>{};
    final ignorable = json['ignorable'];
    if (ignorable != null && ignorable != true) {
      throw ArgumentError.value(
        ignorable,
        'ignorable',
        'only the literal true is valid',
      );
    }
    final known = kKnownSessionEventTypes.contains(type);
    final isSurface = kSurfaceEventTypes.contains(type);
    final rawSeqs = json['sourceEventSeqs'];
    final rawOp = json['surfaceOp'];
    Object? sourceSeqs;
    SurfaceOp? surfaceOp;
    Object? surfaceOpJson;
    if (!isSurface) {
      if (!known && (ignorable == true)) {
        // Unknown ignorable records retain opaque metadata without affecting
        // history (Host `surfaceOpOf` early return). Never parsed, never folded.
        sourceSeqs = rawSeqs;
        surfaceOpJson = rawOp;
      } else if (rawSeqs != null || rawOp != null) {
        throw ArgumentError(
          'surface metadata on non-surface event "$type" — compiler-forbidden at Session.append',
        );
      }
    } else {
      // Host keeps `sourceEventSeqs`/`surfaceOp` as opaque JSON on the wire;
      // shape rules run in [validateSurfaceMetadata], not here.
      if (rawSeqs != null) {
        sourceSeqs = rawSeqs is List && rawSeqs.every((e) => e is int)
            ? List<int>.from(rawSeqs)
            : rawSeqs;
      }
      surfaceOp = rawOp == null ? null : SurfaceOp.fromJson(rawOp);
    }
    return SessionEventEnvelope(
      type: type,
      seq: seqInt,
      time: timeInt,
      data: decodedData,
      dataJson: rawData,
      ignorable: ignorable == true,
      sourceEventSeqs: sourceSeqs,
      surfaceOp: surfaceOp,
      surfaceOpJson: surfaceOpJson,
    );
  }

  /// Event-type key (`'turn/start'`, plugin extensions included).
  final String type;

  /// Monotonic sequence number within the session.
  final int seq;

  /// Unix epoch milliseconds.
  final int time;

  /// Decoded payload object view for this member (empty when the wire
  /// value is not an object; the raw value stays in [dataJson]).
  final Map<String, Object?> data;

  /// Raw wire payload, preserved verbatim (Host `data: JsonValue`).
  final Object? dataJson;

  /// True when a reader that does not know [type] may skip this entry.
  final bool ignorable;

  /// Cited source seqs (chunk seqs behind an assembled message, shadowed
  /// nodes behind a replacement). A `List<int>` when the wire value is an
  /// integer array; the opaque wire value otherwise (Host keeps this field
  /// as `JsonValue`; shape rules run in [validateSurfaceMetadata]).
  final Object? sourceEventSeqs;

  /// Surface placement; present only on surface-eligible members.
  final SurfaceOp? surfaceOp;

  /// Opaque wire `surfaceOp` retained for unknown ignorable records
  /// (never parsed, never folded).
  final Object? surfaceOpJson;

  /// Whether this is a type this build knows: a core member or a merged
  /// plugin extension. False means an extension from outside the assembled
  /// composition, and the required-on-read gate applies.
  bool get isKnown => kKnownSessionEventTypes.contains(type);

  /// Whether this member belongs to the core map (vs a plugin extension).
  bool get isCore => kCoreSessionEventTypes.contains(type);

  /// Whether this member may carry surface metadata.
  bool get isSurfaceEligible => kSurfaceEventTypes.contains(type);
}

/// Extension adding the reader gate over envelopes: refuse reconstruction on
/// unrecognized required events instead of dropping them silently.
extension SessionEventReaderGate on SessionEventEnvelope {
  /// Throws [StateError] when this build does not know [type] and the event
  /// is not marked ignorable — the required-on-read contract. Returns the
  /// receiver otherwise so callers can chain `if (e.requireKnown().isKnown)`.
  SessionEventEnvelope requireKnown() {
    if (!isKnown && !ignorable) {
      throw StateError(
        'refusing reconstruction: unrecognized required event "$type" at seq $seq '
        '(no ignorable marker)',
      );
    }
    return this;
  }
}

/// Validates one event's surface metadata without checking membership in a
/// log or surface. Mirrors Host `validateSurfaceMetadata`: replacement
/// endpoints must reference earlier events; cited source seqs must be a
/// non-empty deduplicated array of earlier seqs when present as a list.
/// Opaque (non-list) values on unknown ignorable records are retained, not
/// validated.
/// @param envelope - decoded event whose marker and source values are inspected.
/// @returns the validated operation, or null for a log-only or unknown ignorable event.
/// @throws [ArgumentError] when metadata violates marker or source-sequence rules.
SurfaceOp? validateSurfaceMetadata(SessionEventEnvelope envelope) {
  final op = envelope.surfaceOp;
  if (op != null &&
      op.isReplace &&
      (op.startSeq! >= envelope.seq || op.endSeq! >= envelope.seq)) {
    throw ArgumentError.value(
      {'startSeq': op.startSeq, 'endSeq': op.endSeq},
      'surfaceOp',
      'surface replace at seq ${envelope.seq}: startSeq and endSeq must reference earlier events',
    );
  }
  final raw = envelope.sourceEventSeqs;
  if (envelope.type == 'assistant/message' && raw != null) {
    throw ArgumentError.value(
      raw,
      'sourceEventSeqs',
      'assistant/message embeds its source stream and cannot carry sourceEventSeqs',
    );
  }
  if (raw != null) {
    if (raw is! List) {
      // Opaque JSON on unknown ignorable events (retained at decode).
      if (!envelope.isKnown && envelope.ignorable) return op;
      throw ArgumentError.value(
        raw,
        'sourceEventSeqs',
        'must be an array when present',
      );
    }
    if (raw.isEmpty) {
      throw ArgumentError.value(
        raw,
        'sourceEventSeqs',
        'must not be empty',
      );
    }
    final seen = <int>{};
    for (final source in raw) {
      if (!isEventSeq(source)) {
        throw ArgumentError.value(
          raw,
          'sourceEventSeqs',
          'must densely contain non-negative safe integers',
        );
      }
      final s = (source as num).toInt();
      if (!seen.add(s)) {
        throw ArgumentError.value(
          raw,
          'sourceEventSeqs',
          'must not contain duplicates',
        );
      }
      if (s >= envelope.seq) {
        throw ArgumentError.value(
          raw,
          'sourceEventSeqs',
          'must reference earlier events: $s >= current seq ${envelope.seq}',
        );
      }
    }
  }
  return op;
}

/// Rejects noncanonical request-header fields and contradictory tool failure
/// metadata. Mirrors Host `validateSessionEventData` (event-local rules only;
/// complete payloads and embedded provider streams stay owner-validated).
/// @param envelope - decoded event whose locally related payload fields are inspected.
/// @throws [ArgumentError] on header.system presence, empty tools/adapterDefaults, or tool/result error without content[0].isError.
void validateSessionEventData(SessionEventEnvelope envelope) {
  final data = envelope.data;
  if (envelope.type == 'request/header') {
    final header = data['header'];
    if (header is! Map) {
      throw ArgumentError.value(
        data['header'],
        'data.header',
        'must be an object',
      );
    }
    if (header.containsKey('system')) {
      throw ArgumentError(
        'request/header must omit header.system; use system/message',
      );
    }
    final tools = header['tools'];
    if (tools is List && tools.isEmpty) {
      throw ArgumentError('request/header must omit empty tools');
    }
    final defaults = header['adapterDefaults'];
    if (defaults is Map && defaults.isEmpty) {
      throw ArgumentError('request/header must omit empty adapterDefaults');
    }
  } else if (envelope.type == 'tool/result') {
    final error = data['error'];
    if (error == null) return;
    final message = data['message'];
    final content = message is Map ? message['content'] : null;
    final block = content is List && content.isNotEmpty ? content[0] : null;
    if (block is! Map || block['isError'] != true) {
      throw ArgumentError(
        'tool/result error requires message content[0].isError === true',
      );
    }
  }
}

/// Rejects non-current event envelopes without stripping or normalizing wire
/// fields. Mirrors Host `assertSessionWireEvent`: exact envelope keys, safe
/// seq/time, present data, literal-true ignorable, then event-local surface
/// and payload rules. Range membership and source existence require the
/// durable log and remain Host-owned.
/// @param json - one event received in a follow frame or history page.
/// @returns the decoded and validated envelope.
/// @throws [ArgumentError] when the envelope or current event-local metadata is invalid.
SessionEventEnvelope assertSessionWireEvent(Map<String, Object?> json) {
  final envelope = SessionEventEnvelope.fromJson(json);
  validateSurfaceMetadata(envelope);
  validateSessionEventData(envelope);
  return envelope;
}

/// Folds one event into the message text it derives to, or null when it
/// produces none. Mirrors Host `deriveEventMessage`: `user/message` projects
/// verbatim; empty-content `system/message`/`assistant/message` project to
/// null (the node keeps its surface position but contributes no wire message);
/// `tool/result` projects its message; everything else projects to null.
/// @param envelope - decoded event to project.
/// @returns the derived text, or null when the event produces no message.
String? deriveEventMessageText(SessionEventEnvelope envelope) {
  switch (envelope.type) {
    case 'user/message':
      return _messageText(envelope.data);
    case 'system/message':
    case 'assistant/message':
      final text = _messageText(envelope.data);
      if (text == null || text.isEmpty) return null;
      return text;
    case 'tool/result':
      return _messageText(envelope.data);
    default:
      return null;
  }
}

/// Extracts model-visible text from a message payload: `data.message.content`
/// text parts joined, falling back to a top-level string `content` or `text`.
/// Returns null when no text is present (empty-content projection).
String? _messageText(Map<String, Object?> data) {
  final message = data['message'];
  final content = message is Map ? message['content'] : data['content'];
  if (content is String) return content;
  if (content is List) {
    final parts = <String>[];
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        final text = block['text'];
        if (text is String) parts.add(text);
      }
    }
    if (parts.isNotEmpty) return parts.join('');
    // Content blocks with no text parts (e.g. tool-result-only content).
    if (content.isNotEmpty) return null;
    return null;
  }
  final text = data['text'];
  if (text is String) return text;
  return null;
}
