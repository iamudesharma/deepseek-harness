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
const Set<String> kCoreSessionEventTypes = {
  'turn/start',
  'turn/end',
  'step/start',
  'step/end',
  'user/message',
  'assistant/chunk',
  'assistant/message',
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
/// permission-presets}`, `sandbox/sandbox-policy`, `compaction`, `goal`,
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
/// surface metadata (`surfaceOp`, `sourceEventSeqs`). Mirrors `SurfaceEventType`.
const Set<String> kSurfaceEventTypes = {
  'user/message',
  'assistant/message',
  'tool/result',
};

/// How a surface-eligible event entered the ordered surface.
///
/// Mirrors `SurfaceOp`: `'append'` or an inclusive `[start, end]` node range
/// replacement (used by compaction).
@immutable
class SurfaceOp {
  const SurfaceOp._(this.isReplace, this.start, this.end);

  /// The normal tail-append op.
  static final SurfaceOp append = SurfaceOp._(false, null, null);

  /// Builds the replace-range op.
  factory SurfaceOp.replace(int start, int end) =>
      SurfaceOp._(true, start, end);

  /// Decodes the wire form; throws [ArgumentError] on malformed input.
  static SurfaceOp fromJson(Object? wire) {
    if (wire == 'append') return append;
    if (wire is Map) {
      if (wire['op'] == 'replace' &&
          wire['start'] is int &&
          wire['end'] is int) {
        return SurfaceOp.replace(wire['start'] as int, wire['end'] as int);
      }
    }
    throw ArgumentError.value(wire, 'surfaceOp', 'malformed surface op');
  }

  /// Whether this op replaces a node range rather than appending.
  final bool isReplace;

  /// Inclusive replacement range start (replace ops only).
  final int? start;

  /// Inclusive replacement range end (replace ops only).
  final int? end;
}

/// One immutable session-log entry: the discriminated envelope plus validated
/// surface metadata. Payload typing per member lands with its consumer row;
/// [data] stays the decoded JSON object.
@immutable
class SessionEventEnvelope {
  /// Creates an already-decoded entry.
  const SessionEventEnvelope({
    required this.type,
    required this.seq,
    required this.time,
    required this.data,
    required this.ignorable,
    this.sourceEventSeqs,
    this.surfaceOp,
  });

  /// Decodes one log entry; throws [ArgumentError] on malformed envelope
  /// fields. Unknown `type`s decode fine ([isKnown] is false) — refusal is a
  /// reader decision, not a decoder decision.
  factory SessionEventEnvelope.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    final seq = json['seq'];
    final time = json['time'];
    final data = json['data'];
    if (type is! String || type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'must be a non-empty string');
    }
    if (seq is! int)
      throw ArgumentError.value(seq, 'seq', 'must be an integer');
    if (time is! int)
      throw ArgumentError.value(time, 'time', 'must be an integer');
    if (data != null && data is! Map) {
      throw ArgumentError.value(data, 'data', 'must be an object');
    }
    final decodedData = data is! Map
        ? const <String, Object?>{}
        : Map<String, Object?>.from(data);
    final ignorable = json['ignorable'];
    if (ignorable != null && ignorable != true) {
      throw ArgumentError.value(
        ignorable,
        'ignorable',
        'only the literal true is valid',
      );
    }
    final isSurface = kSurfaceEventTypes.contains(type);
    Object? sourceSeqs;
    SurfaceOp? surfaceOp;
    if (!isSurface) {
      // Non-surface events never carry surface metadata.
      sourceSeqs = json['sourceEventSeqs'];
      surfaceOp = json['surfaceOp'] == null
          ? null
          : SurfaceOp.fromJson(json['surfaceOp']);
      if (sourceSeqs != null || surfaceOp != null) {
        throw ArgumentError(
          'surface metadata on non-surface event "$type" — compiler-forbidden at Session.append',
        );
      }
    } else {
      final seqs = json['sourceEventSeqs'];
      if (seqs != null) {
        if (seqs is! List || seqs.any((e) => e is! int)) {
          throw ArgumentError.value(
            seqs,
            'sourceEventSeqs',
            'must be integer seqs',
          );
        }
        sourceSeqs = List<int>.from(seqs);
      }
      surfaceOp = json['surfaceOp'] == null
          ? null
          : SurfaceOp.fromJson(json['surfaceOp']);
    }
    return SessionEventEnvelope(
      type: type,
      seq: seq,
      time: time,
      data: decodedData,
      ignorable: ignorable == true,
      sourceEventSeqs: sourceSeqs as List<int>?,
      surfaceOp: surfaceOp,
    );
  }

  /// Event-type key (`'turn/start'`, plugin extensions included).
  final String type;

  /// Monotonic sequence number within the session.
  final int seq;

  /// Unix epoch milliseconds.
  final int time;

  /// Decoded payload object for this member.
  final Map<String, Object?> data;

  /// True when a reader that does not know [type] may skip this entry.
  final bool ignorable;

  /// Cited source seqs (chunk seqs behind an assembled message, shadowed
  /// nodes behind a replacement). Present only on surface-eligible members.
  final List<int>? sourceEventSeqs;

  /// Surface placement; present only on surface-eligible members.
  final SurfaceOp? surfaceOp;

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
