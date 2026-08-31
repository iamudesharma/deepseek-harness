/// Assistant stream-chunk decoding and tool-argument accumulation — the
/// Flutter port of `packages/client/runtime/src/client/sessions/partial.ts`
/// (`PartialAccumulator`).
///
/// Wire contract: the durable `assistant/chunk` session event carries
/// `{ turn, step, chunk: StreamChunk }` (packages/core/session/src/types.ts);
/// there is no separate tool-argument frame. The model's tool call arrives as
/// `tool-call-delta` chunks whose `argumentsDelta` fragments accumulate into
/// the in-flight block (agent.ts appends one event per delta). The settled
/// whole values still arrive via the `tool/call` event — this accumulator
/// only feeds the in-flight projection.
library;

import 'package:meta/meta.dart';

/// One decoded assistant stream chunk (the StreamChunk variants a client
/// fold can see; usage/finish/unknown variants carry no visible block
/// change).
@immutable
sealed class AssistantChunk {
  const AssistantChunk();
}

/// `text-delta` — appends to the step's text block.
@immutable
class TextDeltaChunk extends AssistantChunk {
  const TextDeltaChunk(this.text);
  final String text;
}

/// `reasoning-delta` — appends to the step's reasoning block.
@immutable
class ReasoningDeltaChunk extends AssistantChunk {
  const ReasoningDeltaChunk(this.text);
  final String text;
}

/// `tool-call-delta` — accumulates into the in-flight tool-call block.
@immutable
class ToolCallDeltaChunk extends AssistantChunk {
  const ToolCallDeltaChunk({
    required this.index,
    required this.id,
    this.name,
    required this.argumentsDelta,
  });

  /// Block index within the step.
  final int index;

  /// Call id fragment (empty on continuation deltas).
  final String id;

  /// Tool name when this delta names it.
  final String? name;

  /// Raw JSON argument fragment to append verbatim.
  final String argumentsDelta;
}

/// Any other chunk variant (block-start/block-end/usage/finish/extension):
/// no tool-argument effect for this accumulator.
@immutable
class OtherChunk extends AssistantChunk {
  const OtherChunk(this.raw);
  final Object? raw;
}

/// Decodes one wire chunk map; unknown shapes degrade to [OtherChunk] rather
/// than throwing — streaming extensions must not break the live tail.
AssistantChunk decodeAssistantChunk(Object? raw) {
  if (raw is! Map) return OtherChunk(raw);
  switch (raw['type']) {
    case 'text-delta':
    case 'text':
      final text = raw['text'];
      return TextDeltaChunk(text is String ? text : '');
    case 'reasoning-delta':
    case 'reasoning':
      final text = raw['text'];
      return ReasoningDeltaChunk(text is String ? text : '');
    case 'tool-call-delta':
      return ToolCallDeltaChunk(
        index: raw['index'] is int ? raw['index'] as int : 0,
        id: raw['id'] is String ? raw['id'] as String : '',
        name: raw['name'] is String ? raw['name'] as String : null,
        argumentsDelta: raw['argumentsDelta'] is String
            ? raw['argumentsDelta'] as String
            : '',
      );
    default:
      return OtherChunk(raw);
  }
}

/// The in-flight tool-call block projection (partial.ts case
/// `'tool-call-delta'`: base = previous block when it was already a partial
/// tool call, else an empty one).
@immutable
class PartialToolCall {
  const PartialToolCall({this.callId = '', this.name = '', this.argsRaw = ''});

  /// First non-empty id seen on the block's deltas.
  final String callId;

  /// Most recent name seen on the block's deltas.
  final String name;

  /// Accumulated raw argument JSON, exactly as the model produced it.
  final String argsRaw;
}

/// Per-step tool-call-delta accumulator: folds decoded chunks into partial
/// tool-call blocks keyed by their wire block index, with block-level
/// immutability (a delta swaps only that index).
class ToolStreamAccumulator {
  final Map<int, PartialToolCall> _blocks = {};

  /// Folds one decoded chunk; returns whether it changed the projection
  /// (only tool-call-delta mutates here — text/reasoning deltas belong to
  /// the caller's own buffers).
  bool fold(AssistantChunk chunk) {
    if (chunk is! ToolCallDeltaChunk) return false;
    final base = _blocks[chunk.index];
    _blocks[chunk.index] = PartialToolCall(
      callId: (base?.callId.isNotEmpty ?? false) ? base!.callId : chunk.id,
      name: chunk.name ?? base?.name ?? '',
      argsRaw: (base?.argsRaw ?? '') + chunk.argumentsDelta,
    );
    return true;
  }

  /// Current partial blocks in index order (holes compacted, mirroring the
  /// partial snapshot's compaction of sparse out-of-order indexes).
  List<PartialToolCall> snapshot() {
    final indexes = _blocks.keys.toList()..sort();
    return [for (final i in indexes) _blocks[i]!];
  }

  /// Drops all accumulated blocks (step settled; further deltas are
  /// stragglers the caller rejects upstream).
  void reset() => _blocks.clear();
}
