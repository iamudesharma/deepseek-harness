/// Typed ConversationNode model and deterministic fold — Flutter port of the
/// React conversation-nodes contract (`ui-conversation/src/client/conversation-nodes/`
/// plus `ConversationNodeDefinition` in runtime): `match` reads one event,
/// `update` folds it into state, replay is deterministic by log `seq`.
///
/// Families: user message, streaming assistant (tail), tool lifecycle,
/// turn error/retry/max-tokens, compaction (surface-replace), step grouping
/// with summary, command/manual-compaction, and lossless markers. Unknown
/// required events refuse.
library;

import 'package:flutter/foundation.dart';

import '../../../core/events/tool_stream.dart';
import '../../../core/session/session_event_map.dart';
import '../../../core/session/session_models.dart' show SessionId, ToolCallId, DraftAttachmentId;
import 'failure_display.dart';

/// Payload coordinates mirroring `location-index.ts: payloadCoordinates`.
class _Coordinates {
  const _Coordinates({this.turn, this.step, this.session = false});
  final int? turn;
  final int? step;
  final bool session;

  static const int _maxSafe = 9007199254740991;

  static bool _isSafeInt(Object? v) {
    if (v is int) return v >= 0 && v <= _maxSafe;
    if (v is num) {
      final int i = v.toInt();
      return v == i && i >= 0 && i <= _maxSafe;
    }
    return false;
  }

  static _Coordinates fromData(Map<String, Object?> data) {
    if (data.containsKey('turn') && data['turn'] == null) {
      return const _Coordinates(session: true);
    }
    final Object? rawTurn = data['turn'];
    final Object? rawStep = data['step'];
    final int? turn = _isSafeInt(rawTurn) ? (rawTurn as num).toInt() : null;
    final int? step = _isSafeInt(rawStep) ? (rawStep as num).toInt() : null;
    return _Coordinates(turn: turn, step: step);
  }
}

/// One settled or in-flight entry on the conversation surface.
@immutable
sealed class ConversationNode {
  const ConversationNode({required this.key, required this.sourceSeqs});

  /// Stable business id derived from source events.
  final String key;

  /// Every source-event seq cited by this node.
  final List<int> sourceSeqs;
}

class UserMessageNode extends ConversationNode {
  const UserMessageNode({
    required super.key,
    required super.sourceSeqs,
    required this.text,
    this.imageAttachmentIds = const [],
    this.imageNames = const [],
  });
  final String text;
  final List<String> imageAttachmentIds;
  final List<String> imageNames;
}

/// Injected non-user context (runtime snapshot, instructions, catalog etc).
/// React renders this via `ContextInjectionRow` — a collapsed DisclosureRow,
/// not as a user bubble. Flutter previously mis-classified these as user
/// messages and rendered the raw snapshot prose as a large bubble.
class ContextNode extends ConversationNode {
  const ContextNode({
    required super.key,
    required super.sourceSeqs,
    required this.text,
    this.label,
    this.form,
    this.sections,
  });
  final String text;
  final String? label;
  final String? form;
  final List<Map<String, String>>? sections;
}

/// Complete system prompt rendered for one model request — mirrors React
/// `system-prompt` chat node produced by `requestPromptDefinition`.
class SystemPromptNode extends ConversationNode {
  const SystemPromptNode({
    required super.key,
    required super.sourceSeqs,
    required this.text,
    required this.anchorSeq,
  });

  /// Exact model-visible system prompt text with original line breaks.
  final String text;

  /// Sortable anchor seq (the owning `request/header` seq).
  final int anchorSeq;
}

/// Assistant turn content; in-flight while streaming, immutable after the
/// assembled message settles.
class AssistantNode extends ConversationNode {
  const AssistantNode({
    required super.key,
    required super.sourceSeqs,
    required this.text,
    required this.streaming,
    this.interrupted = false,
    this.partialToolCalls = const [],
    this.reasoning,
  });

  final String text;
  final bool streaming;
  final bool interrupted;

  /// In-flight tool-call blocks accumulated from `tool-call-delta` chunks
  /// (the partial.ts projection); empty once the step's message settles.
  final List<PartialToolCall> partialToolCalls;

  /// Optional reasoning text for the Think row (separate from narration).
  /// Collapsed by default, follows latest line while streaming.
  final String? reasoning;
}

/// Turn-level process disclosure projected before the finalized answer (mirrors
/// `TurnProcessChatData` + `turn-process.ts` compact policy).
class TurnProcessNode extends ConversationNode {
  const TurnProcessNode({
    required super.key,
    required super.sourceSeqs,
    required this.turn,
    required this.controlAnchorSeq,
    required this.processStartSeq,
    required this.answerAnchorSeq,
    required this.answerStep,
    required this.inlineReasoning,
    required this.messageCount,
    required this.toolCallCount,
    required this.subagentCount,
  });

  final int turn;
  final int controlAnchorSeq;
  final int processStartSeq;
  final int? answerAnchorSeq;
  final int? answerStep;
  final bool inlineReasoning;
  final int messageCount;
  final int toolCallCount;
  final int subagentCount;

  bool get foldable => messageCount > 0 || toolCallCount > 0 || subagentCount > 0;
}

enum ToolNodeStatus { running, success, error }

/// One nested code-dispatch subcall folded under its root tool call
/// (React parity: `ToolCallBlock` children keyed by `subCallId`).
/// Children are recursive — a subcall may own its own dispatches when
/// `parentCallId` chains deeper than one level, matching `ToolCallTree`.
class ToolSubCall {
  const ToolSubCall({
    required this.subCallId,
    required this.name,
    this.isError = false,
    this.result,
    this.children = const [],
  });

  final ToolCallId subCallId;
  final String name;
  final bool isError;
  final String? result;

  /// Recursive children dispatched from this subcall.
  final List<ToolSubCall> children;

  ToolSubCall copyWith({
    bool? isError,
    String? result,
    List<ToolSubCall>? children,
  }) => ToolSubCall(
    subCallId: subCallId,
    name: name,
    isError: isError ?? this.isError,
    result: result ?? this.result,
    children: children ?? this.children,
  );
}

class ToolNode extends ConversationNode {
  const ToolNode({
    required super.key,
    required super.sourceSeqs,
    required this.callId,
    required this.name,
    required this.status,
    this.result,
    this.isError = false,
    this.subCalls = const [],
    this.argsRaw,
  });

  final ToolCallId callId;
  final String name;
  final ToolNodeStatus status;
  final String? result;
  final bool isError;
  final List<ToolSubCall> subCalls;
  final String? argsRaw;

  ToolNode copyWith({
    required ToolNodeStatus status,
    String? result,
    bool isError = false,
    String? argsRaw,
  }) {
    return ToolNode(
      key: key,
      sourceSeqs: sourceSeqs,
      callId: callId,
      name: name,
      status: status,
      result: result,
      isError: isError,
      subCalls: subCalls,
      argsRaw: argsRaw ?? this.argsRaw,
    );
  }
}

/// Terminal turn failure — friendly copy via [displayFailureMessage].
class TurnErrorNode extends ConversationNode {
  const TurnErrorNode({
    required super.key,
    required super.sourceSeqs,
    required this.friendly,
    required this.raw,
    this.errorCode,
  });

  final String friendly;
  final String raw;
  final String? errorCode;
}

/// Non-surface lifecycle marker kept for transcript losslessness.
class MarkerNode extends ConversationNode {
  const MarkerNode({
    required super.key,
    required super.sourceSeqs,
    required this.label,
  });
  final String label;
}

/// One provider/model route that contributed a billed request attempt
/// (mirrors `TurnTokenUsageRoute` in `turn-usage.ts` / `chat-nodes.ts`).
@immutable
class TurnTokenUsageRoute {
  const TurnTokenUsageRoute({required this.provider, required this.model});
  final String provider;
  final String model;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnTokenUsageRoute &&
          provider == other.provider &&
          model == other.model;

  @override
  int get hashCode => Object.hash(provider, model);
}

/// Exact provider-reported token accounting for every attempt in one
/// completed Turn (mirrors `TurnTokenUsage` in `turn-usage.ts`).
@immutable
class TurnTokenUsage {
  const TurnTokenUsage({
    required this.uncachedInputTokens,
    required this.outputTokens,
    required this.totalTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.reasoningTokens,
    this.routes,
  });

  /// Sum of uncached prompt input across all attempts.
  final int uncachedInputTokens;
  final int outputTokens;
  /// Exact aggregate prompt plus output total across all attempts.
  final int totalTokens;
  /// Present only when every attempt reported the bucket.
  final int? cacheReadTokens;
  /// Present only when every attempt reported the bucket.
  final int? cacheWriteTokens;
  /// Output subset, present only when every attempt reported it.
  final int? reasoningTokens;
  /// Present only when every billed attempt has provider/model attribution.
  final List<TurnTokenUsageRoute>? routes;

  /// Billed input tokens = uncached + cacheRead + cacheWrite (missing as 0).
  int get billedInputTokens =>
      uncachedInputTokens + (cacheReadTokens ?? 0) + (cacheWriteTokens ?? 0);
}

/// Completed-turn footer row that owns actions and optional feature contributions
/// (mirrors `TurnTailChatData` in `chat-nodes.ts`).
@immutable
class TurnTailNode extends ConversationNode {
  const TurnTailNode({
    required super.key,
    required super.sourceSeqs,
    required this.turn,
    required this.seq,
    required this.time,
    this.closingText,
    this.closingSeq,
    this.ttftMs,
    this.tokensPerSecond,
    this.tokenUsage,
    this.branchUnavailable = false,
    this.runMs,
  });

  /// Turn number (1-indexed).
  final int turn;

  /// Seq of the `turn/end` event that closes this Turn.
  final int seq;

  /// Wall time of the `turn/end` event.
  final int time;

  /// Last finalized content-bearing assistant text in this Turn, if any.
  final String? closingText;

  /// Seq of the closing assistant message, if any.
  final int? closingSeq;

  /// First-step TTFT in ms (turn start → first token); absent when unrecorded.
  final int? ttftMs;

  /// Decode throughput over steps carrying both timing and provider usage.
  final double? tokensPerSecond;

  /// Exact per-Turn accounting; absent when the loaded evidence is incomplete.
  final TurnTokenUsage? tokenUsage;

  /// Whether non-rendered later evidence makes the closing seq non-tail.
  final bool branchUnavailable;

  /// Turn wall time `end - start` when both are inside the loaded window.
  final int? runMs;
}

/// One producer-correlated model retry attempt (React `ModelRetryNode`):
/// scheduled when `llm/retry` lands, started once `llm/retry-started`
/// correlates by retry number.
class ModelRetryNode extends ConversationNode {
  const ModelRetryNode({
    required super.key,
    required super.sourceSeqs,
    required this.retry,
    required this.maxRetries,
    required this.delayMs,
    this.failureCode,
    this.failureMessage,
    this.started = false,
  });

  final int retry;
  final int maxRetries;
  final int delayMs;
  final String? failureCode;
  final String? failureMessage;
  final bool started;

  ModelRetryNode copyWithStarted() => ModelRetryNode(
    key: key,
    sourceSeqs: sourceSeqs,
    retry: retry,
    maxRetries: maxRetries,
    delayMs: delayMs,
    failureCode: failureCode,
    failureMessage: failureMessage,
    started: true,
  );
}

/// One model call within a turn: owns nodes produced between `step/start`
/// and `step/end` (streaming assistant, tool calls/results).
class StepGroupNode extends ConversationNode {
  const StepGroupNode({
    required super.key,
    required super.sourceSeqs,
    required this.turn,
    required this.step,
    required this.children,
    required this.summary,
    required this.settled,
  });

  final int turn;
  final int step;
  final List<ConversationNode> children;
  final String summary;
  final bool settled;
}

/// Compaction output replacing a bracketed range of surface nodes.
///
/// Mirrors `CompactionSummaryNode` in `conversation.ts`: `shadowedItemCount` is
/// the authoritative length of `shadowedSeqs`, `shadowedTokenCount` the
/// heuristic price, both null when the summary event is unavailable. Flutter
/// keeps them non-null with 0 fallback for legacy fixtures, but the checkpoint
/// path stores the exact counts.
class CompactionNode extends ConversationNode {
  const CompactionNode({
    required super.key,
    required super.sourceSeqs,
    required this.text,
    this.shadowedTokenCount = 0,
    this.shadowedItemCount = 0,
  });

  final String text;

  /// Token count the host attributed to the shadowed range
  /// (`compaction/summary.shadowedTokenCount`); 0 when undeclared.
  final int shadowedTokenCount;

  /// Number of surface items replaced (`shadowedSeqs.length`); 0 when undeclared.
  final int shadowedItemCount;
}

/// Outcome of a slash-command lifecycle (mirrors `CommandNode` in conversation.ts).
class CommandOutcome {
  const CommandOutcome({required this.kind, this.text, this.sourceEventSeq});

  /// `success` or `error`.
  final String kind;
  final String? text;
  final int? sourceEventSeq;
}

/// One slash-command lifecycle — generic command row (non-compact).
class CommandNode extends ConversationNode {
  const CommandNode({
    required super.key,
    required super.sourceSeqs,
    required this.commandId,
    this.name,
    this.args,
    this.outcome,
    this.time = 0,
  });

  final String commandId;
  final String? name;
  final String? args;
  final CommandOutcome? outcome;
  final int time;
}

/// Manual compaction combined node — the `/compact` command folded with its
/// compaction transaction (mirrors `ManualCompactionChatData`).
/// When `compaction` is null the command is still running or has failed
/// without a checkpoint; the UI shows the generic command card or the
/// running disclosure. When non-null the disclosure is anchored at the
/// checkpoint's seq and shows the compaction summary.
class ManualCompactionNode extends ConversationNode {
  const ManualCompactionNode({
    required super.key,
    required super.sourceSeqs,
    required this.command,
    this.compaction,
  });

  final CommandNode command;
  final CompactionNode? compaction;
}

/// Immutable conversation snapshot: nodes in surface order.
@immutable
class ChatSnapshot {
  const ChatSnapshot(this.nodes);
  final List<ConversationNode> nodes;

  List<String> toTranscriptLines() => [
    for (final n in nodes)
      switch (n) {
        UserMessageNode(:final key, :final text) => 'user $key $text',
        ContextNode(:final key, :final text, :final label) =>
          'context $key ${label ?? ''} $text',
        AssistantNode(
          :final key,
          :final text,
          :final streaming,
          :final interrupted,
        ) =>
          'assistant $key ${streaming ? '(streaming) ' : ''}$text${interrupted ? ' [interrupted]' : ''}',
        ToolNode(:final key, :final name, :final status, :final isError) =>
          'tool $key $name ${status == ToolNodeStatus.success ? 'ok' : 'error${isError ? ' (isError)' : ''}'}',
        TurnErrorNode(:final key, :final friendly) =>
          'turn-error $key $friendly',
        MarkerNode(:final key, :final label) => 'marker $key $label',
        ModelRetryNode(:final key, :final retry, :final started) =>
          'model-retry $key retry #$retry${started ? ' started' : ''}',
        StepGroupNode(:final key, :final summary) => 'group $key $summary',
        CompactionNode(:final key, :final text) => 'compact $key $text',
        CommandNode(:final key, :final name, :final outcome) =>
          'command $key ${name ?? ''} ${outcome?.kind ?? 'running'}',
        ManualCompactionNode(:final key, :final command, :final compaction) =>
          'manual-compaction $key ${command.name ?? ''} ${compaction != null ? 'compact:${compaction.text}' : (command.outcome != null ? 'done:${command.outcome!.kind}' : 'running')}',
        SystemPromptNode(:final key, :final text) =>
          'system-prompt $key $text',
        TurnTailNode(:final key, :final turn, :final tokenUsage) =>
          'turn-tail $key turn $turn ${tokenUsage == null ? 'no-usage' : 'usage:${tokenUsage.totalTokens}'}',
        TurnProcessNode(:final key, :final turn, :final toolCallCount, :final messageCount) =>
          'turn-process $key turn $turn tools:$toolCallCount msgs:$messageCount',
      },
  ];
}

/// Deterministic event → node folder.
class ConversationNodeFolder {
  final List<ConversationNode> _nodes = [];
  final Map<String, StringBuffer> _chunkBuffers = {};
  final Map<String, StringBuffer> _reasoningBuffers = {};
  final Set<String> _inFlightAssistantKeys = {};
  final Map<ToolCallId, ToolNode> _toolsByCallId = {};
  final Set<String> _settledKeys = {};
  final Map<String, List<ConversationNode>> _groupChildren = {};

  /// In-flight tool-call-delta accumulators keyed like the chunk buffers
  /// (partial.ts: argument fragments accumulate into the step's in-flight
  /// projection; the settled `assistant/message` supersedes them).
  final Map<String, ToolStreamAccumulator> _toolStreams = {};

  int _turn = 0;
  int _step = 0;
  // Location index memory mirrors ConversationLocationIndex currentTurn/currentStep.
  int? _currentTurn;
  int? _currentStep;
  final Map<int, _Coordinates> _coordinates = {};
  String? _openGroupKey;
  int? _compactionStartSeq;
  int? _compactionStartIndex;

  /// Pending React checkpoint pair (`shadow-price protocol`): a
  /// `compaction/summary` is log-only; the immediately following
  /// `user/message` with a replace `surfaceOp` performs the surface
  /// replacement. Held here between the two events.
  _PendingCompaction? _pendingCompaction;

  /// Tool subcall parent map + depth map mirroring `ToolCallTree`
  /// (`packages/client/runtime/src/client/sessions/tool-call-tree.ts`) —
  /// out-of-order `parentCallId` edges are stored at the parent key
  /// regardless of arrival order; depth/cycle guards use the same map walk
  /// and the fixed 256 ceiling.
  final Map<ToolCallId, List<ToolSubCall>> _childrenByParent = {};
  final Map<ToolCallId, int> _depthByCall = {};

  /// Manual compaction states keyed by `commandId`.
  final Map<String, _ManualState> _manualByCommandId = {};

  /// Pending manual summaries keyed by `commandId`.
  final Map<String, _PendingCompaction> _manualPendingByCommandId = {};

  /// Per-turn tail accumulation for `TurnTailNode` (mirrors `turn-tail.ts`
  /// `TurnTailState` + `tailData` + `deriveTurnTokenUsage` + `deriveTurnMetrics`).
  ///
  /// Keyed by turn number; window-local. `turn/start` seeds an entry,
  /// `assistant/message` and `tool/call|result|llm/retry` update it, `turn/end`
  /// materializes a `TurnTailNode` if start was present.
  final Map<int, _TailAcc> _turnTailByTurn = {};

  /// Per-turn process accumulation for `TurnProcessNode` (mirrors `turn-process.ts`
  /// compact policy). Tracks evidence before final answer.
  final Map<int, _ProcessAcc> _turnProcessByTurn = {};

  /// Tool call time index for StatsLine toolMs derivation (callId → call time).
  final Map<ToolCallId, int> _toolCallTime = {};

  /// Step start time index for llmMs/TTFT derivation (step key → start time).
  final Map<String, int> _stepStartTime = {};
  final Map<String, int> _stepFirstTokenTime = {};

  /// Conversation-wide StatsLine-style totals derived incrementally
  /// (mirrors `sessionStats` projection when that key is absent).
  final Map<int, int> _toolResultDurations = {};

  /// Update location index memory like `ConversationLocationIndex.rebuild`
  /// + `appendBoundary`/`appendNonBoundary`. Maintains [_currentTurn]/
  /// [_currentStep] and per-seq [_coordinates] for payloadCoordinates parity.
  void _updateLocationForEnvelope(SessionEventEnvelope envelope) {
    final _Coordinates explicit = _Coordinates.fromData(envelope.data);
    // Boundary events set current before generic handling, mirroring rebuild order.
    if (envelope.type == 'turn/start') {
      final int? t = envelope.data['turn'] is num ? (envelope.data['turn'] as num).toInt() : null;
      if (t != null) {
        _currentTurn = t;
        _currentStep = null;
        _turn = t;
      }
    }
    if (envelope.type == 'step/start') {
      final int? t = envelope.data['turn'] is num ? (envelope.data['turn'] as num).toInt() : null;
      final int? s = envelope.data['step'] is num ? (envelope.data['step'] as num).toInt() : null;
      if (t != null) _currentTurn = t;
      if (s != null) _currentStep = s;
      if (t != null) _turn = t;
      if (s != null) _step = s;
    }
    if (!explicit.session && explicit.turn != null) {
      if (_currentTurn != explicit.turn) _currentStep = null;
      _currentTurn = explicit.turn;
      if (explicit.step != null) _currentStep = explicit.step;
    }
    final int? turn = explicit.session ? null : (explicit.turn ?? _currentTurn);
    final int? step;
    if (explicit.session || envelope.type == 'turn/start' || envelope.type == 'turn/end') {
      step = null;
    } else {
      step = explicit.step ?? (turn == _currentTurn ? _currentStep : null);
    }
    _coordinates[envelope.seq] = _Coordinates(turn: turn, step: step, session: explicit.session);
    // Close step/turn memory at boundaries
    if (envelope.type == 'step/end' && _currentTurn == envelope.data['turn'] && _currentStep == envelope.data['step']) {
      _currentStep = null;
    }
    if (envelope.type == 'turn/end' && _currentTurn == envelope.data['turn']) {
      _currentTurn = null;
      _currentStep = null;
    }
  }

  ChatSnapshot snapshot() => ChatSnapshot(List.unmodifiable(_nodes));

  void _append(ConversationNode node) {
    assert(!_settledKeys.contains(node.key));
    final openKey = _openGroupKey;
    if (openKey != null) {
      _groupChildren.putIfAbsent(openKey, () => []).add(node);
      _rebuildOpenGroup();
      return;
    }
    _nodes.add(node);
  }

  static String _extractUserText(Map<String, Object?> data) {
    final dynamic content = data['content'];
    if (content is String) {
      if (content.trim().isNotEmpty) return content.trim();
    }
    if (content is List) {
      final buf = StringBuffer();
      for (final dynamic blk in content) {
        if (blk is Map) {
          final dynamic t = blk['text'] as Object?;
          if (t is String && t.trim().isNotEmpty) buf.writeln(t.trim());
          final dynamic alt = blk['content'] as Object?;
          if (alt is String && alt.trim().isNotEmpty) buf.writeln(alt.trim());
        } else if (blk is String && blk.trim().isNotEmpty) {
          buf.writeln(blk.trim());
        }
      }
      final s = buf.toString().trim();
      if (s.isNotEmpty) return s;
    }
    final dynamic text = data['text'];
    if (text is String && text.trim().isNotEmpty) return text.trim();
    final dynamic message = data['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    return '';
  }

  bool _isCompactionUserMessage(SessionEventEnvelope envelope) {
    return _compactCheckpointId(envelope) != null;
  }

  bool _isReplaceOp(SessionEventEnvelope envelope) {
    if (envelope.surfaceOp?.isReplace ?? false) return true;
    final dataOp = envelope.data['surfaceOp'];
    if (dataOp is Map && dataOp['op'] == 'replace') return true;
    if (dataOp == 'replace') return true;
    return false;
  }

  SurfaceOp? _surfaceOpOf(SessionEventEnvelope envelope) {
    if (envelope.surfaceOp != null) return envelope.surfaceOp;
    final dataOp = envelope.data['surfaceOp'];
    if (dataOp == null) return null;
    try {
      return SurfaceOp.fromJson(dataOp);
    } catch (_) {
      return null;
    }
  }

  /// Returns the compactionId when this user/message is a compaction
  /// checkpoint (replace-op with source plugin compact), else null.
  String? _compactCheckpointId(SessionEventEnvelope envelope) {
    if (envelope.type != 'user/message') return null;
    if (!_isReplaceOp(envelope)) return null;
    final source = envelope.data['source'];
    if (source is Map) {
      final kind = source['kind'];
      final plugin = source['plugin'];
      if (kind == 'plugin' && plugin == 'compact') {
        final cid = source['compactionId'];
        return cid is String && cid.isNotEmpty ? cid : '';
      }
    }
    // Legacy checkpoints may omit compactionId: still treat as compact when
    // plugin marker is present (React fallback ignores those, but we filter
    // the user bubble either way).
    final src = envelope.data['source'];
    if (src is Map && src['plugin'] == 'compact') return '';
    return null;
  }

  String? _sourceCommandIdFromCheckpoint(SessionEventEnvelope envelope) {
    final source = envelope.data['source'];
    if (source is Map) {
      final id = source['sourceCommandId'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  void add(SessionEventEnvelope envelope) {
    envelope.requireKnown();
    if (!envelope.isKnown) return;
    _updateLocationForEnvelope(envelope);
    _trackTurnTail(envelope);
    _trackTurnProcess(envelope);

    switch (envelope.type) {
      case 'user/message':
        // Manual compaction checkpoint has priority: it carries sourceCommandId
        // and participates in the manual lifecycle, not the automatic one.
        final manualCmdId = _sourceCommandIdFromCheckpoint(envelope);
        if (manualCmdId != null &&
            _isReplaceOp(envelope) &&
            _compactCheckpointId(envelope) != null) {
          _handleManualCheckpoint(envelope, manualCmdId);
          break;
        }
        // Automatic pending handling (global shadow-price protocol)
        if (_pendingCompaction != null && _isReplaceOp(envelope)) {
          final pid = _pendingCompaction!.compactionId;
          final cid = _compactCheckpointId(envelope);
          if (pid == null || cid == null || cid.isEmpty || pid == cid) {
            _applyCompactionCheckpoint(envelope);
            break;
          }
          // CompactionId mismatch: drop pending without consuming this
          // user message as its checkpoint.
        }
        final checkpointId = _compactCheckpointId(envelope);
        if (checkpointId != null) {
          // Checkpoint without matching pending: still a compaction marker
          // (window cut left the summary outside, React fallback shows
          // summary null). Create a marker with empty summary.
          _applyCompactionCheckpointOrFallback(envelope);
          break;
        }
        // Non-checkpoint compact source without replace (should not happen)
        if (_isCompactionUserMessage(envelope)) break;
        // Classify context vs user/steering via source.kind (React message.ts).
        final source = envelope.data['source'];
        final sourceKind = source is Map ? source['kind']?.toString() : null;
        if (sourceKind != null && sourceKind != 'user') {
          // Injected context — render as compact disclosure, not a user bubble.
          final srcMap = source is Map ? source as Map : <String, Object?>{};
          final ctxText = _extractContextText(envelope.data);
          final label = _contextProvenanceLabel(srcMap);
          final form = srcMap['form']?.toString();
          final sections = _contextSnapshotSections(srcMap);
          _append(
            ContextNode(
              key: 'ctx${envelope.seq}',
              sourceSeqs: [envelope.seq],
              text: ctxText,
              label: label,
              form: form,
              sections: sections,
            ),
          );
          break;
        }
        final userText = _extractUserText(envelope.data);
        final List<String> imgIds = [];
        final List<String> imgNames = [];
        final dynamic content = envelope.data['content'];
        if (content is List) {
          for (final blk in content) {
            if (blk is Map && blk['type'] == 'image') {
              final att = blk['attachment'];
              if (att is Map) {
                final id = att['attachmentId']?.toString();
                if (id != null && id.isNotEmpty) {
                  imgIds.add(id);
                  imgNames.add(att['name']?.toString() ?? '');
                }
              }
            }
          }
        }
        // Preserve the turn's user bubble even when the block extraction yields
        // an empty string (e.g. image-only prompts); React shows the row.
        _append(
          UserMessageNode(
            key: 'u${envelope.seq}',
            sourceSeqs: [envelope.seq],
            text: userText,
            imageAttachmentIds: List.unmodifiable(imgIds),
            imageNames: List.unmodifiable(imgNames),
          ),
        );

      // ---- Streaming assistant (in-flight tail) ----
      case 'assistant/chunk':
        // Streaming identity is per (turn, step): agent loops settle one
        // assistant message per step inside a single turn.
        final key =
            'a-turn${envelope.data['turn']}-step${envelope.data['step']}';
        _assertUnsettled(key);
        // Decode once and route: tool-call-delta fragments accumulate into
        // the in-flight tool-call projection; every other variant keeps the
        // historical text-append behavior byte-for-byte, but reasoning-delta
        // is kept separate for the Think row (mirrors React ReasoningRow).
        final rawChunk = envelope.data['chunk'];
        final decoded = decodeAssistantChunk(rawChunk);
        String chunkText = '';
        String reasoningDelta = '';
        List<PartialToolCall> partials = const [];
        if (decoded is ToolCallDeltaChunk) {
          final accumulator = _toolStreams.putIfAbsent(
            key,
            ToolStreamAccumulator.new,
          );
          accumulator.fold(decoded);
          partials = accumulator.snapshot();
        } else if (decoded is TextDeltaChunk) {
          chunkText = decoded.text;
        } else if (decoded is ReasoningDeltaChunk) {
          reasoningDelta = decoded.text;
        } else {
          final rawMap = rawChunk as Map?;
          final type = rawMap?['type']?.toString();
          if (type == 'block-end') {
            final block = rawMap?['block'] as Map?;
            final bt = block?['type']?.toString();
            final txt = block?['text'] as String? ?? '';
            if (bt == 'reasoning') {
              final rb = _reasoningBuffers.putIfAbsent(key, StringBuffer.new);
              rb.clear();
              if (txt.isNotEmpty) rb.write(txt);
            } else if (bt == 'text') {
              final b = _chunkBuffers.putIfAbsent(key, StringBuffer.new);
              b.clear();
              if (txt.isNotEmpty) b.write(txt);
            } else if (bt == 'tool-call') {
              // tool-call block-end is handled via tool streams; no text buffer
            }
            // Reflective block-end authoritative content already written;
            // produce node directly and skip generic delta append.
            final buffer = _chunkBuffers.putIfAbsent(key, StringBuffer.new);
            final reasoningBuffer = _reasoningBuffers.putIfAbsent(
              key,
              StringBuffer.new,
            );
            final previousSourceSeqs = _inFlightAssistantKeys.contains(key)
                ? _seqsOf(key)
                : <int>[];
            final effectivePartials = _partialsOf(key);
            final node = AssistantNode(
              key: key,
              sourceSeqs: [...previousSourceSeqs, envelope.seq],
              text: buffer.toString(),
              streaming: true,
              partialToolCalls: effectivePartials,
              reasoning: reasoningBuffer.isEmpty
                  ? null
                  : reasoningBuffer.toString(),
            );
            _upsert(node);
            break;
          } else if (type == 'block-start') {
            // marker only, no text
          } else {
            final text = (rawMap?['text'] ?? '').toString();
            if (text.isNotEmpty) chunkText = text;
          }
        }
        final buffer = _chunkBuffers.putIfAbsent(key, StringBuffer.new)
          ..write(chunkText);
        final reasoningBuffer = _reasoningBuffers.putIfAbsent(
          key,
          StringBuffer.new,
        )..write(reasoningDelta);
        final previousSourceSeqs = _inFlightAssistantKeys.contains(key)
            ? _seqsOf(key)
            : <int>[];
        // Preserve previously accumulated partials when this chunk is not a tool delta.
        final effectivePartials = decoded is ToolCallDeltaChunk
            ? partials
            : _partialsOf(key);
        final node = AssistantNode(
          key: key,
          sourceSeqs: [...previousSourceSeqs, envelope.seq],
          text: buffer.toString(),
          streaming: true,
          partialToolCalls: effectivePartials,
          reasoning: reasoningBuffer.isEmpty
              ? null
              : reasoningBuffer.toString(),
        );
        _upsert(node);

      case 'assistant/message':
        final key =
            'a-turn${envelope.data['turn']}-step${envelope.data['step']}';
        _assertUnsettled(key);
        final interrupted = envelope.data['interrupted'] == true;
        final cited = envelope.sourceEventSeqs;
        final seqs = (cited != null && cited.isNotEmpty) ? cited : _seqsOf(key);
        final bufferedText = _textOf(key);
        final durableText = _extractTextFromMessage(envelope.data['message']);
        // Durable `assistant/message` content is authoritative for replay
        // (React `toAssistantBlocks`); buffers are only for live tail without
        // a final message. This fixes old persisted thinking sessions where
        // `assistant/chunk` block-ends were the sole source but are now
        // ignored via `block-end` authoritative handling, and also handles
        // cases where chunk history is missing (window cut).
        final effectiveText = durableText.isNotEmpty ? durableText : bufferedText;
        final reasoning = _reasoningOf(key);
        // Prefer durable message blocks for reasoning when available: parse
        // content blocks for type reasoning (React: toAssistantBlocks includes
        // reasoning blocks from the settled message).
        final durableReasoning = _extractReasoningFromMessage(
          envelope.data['message'],
        );
        final effectiveReasoning = durableReasoning.isNotEmpty
            ? durableReasoning
            : reasoning;
        final node = AssistantNode(
          key: key,
          sourceSeqs: seqs,
          text: effectiveText,
          streaming: false,
          interrupted: interrupted,
          reasoning: effectiveReasoning.isEmpty ? null : effectiveReasoning,
        );
        final topIndex = _nodes.indexWhere((n) => n.key == key);
        final groupChildren = _openGroupKey == null
            ? null
            : _groupChildren[_openGroupKey];
        final groupIndex = groupChildren?.indexWhere((n) => n.key == key) ?? -1;
        if (topIndex != -1) {
          _nodes[topIndex] = node; // settle the in-flight tail
        } else if (groupIndex != -1 && groupChildren != null) {
          groupChildren[groupIndex] = node;
          _rebuildOpenGroup();
        } else {
          _append(node); // assembled message without visible chunks
        }
        _inFlightAssistantKeys.remove(key);
        _chunkBuffers.remove(key);
        _reasoningBuffers.remove(key);
        _toolStreams.remove(key);
        _settle(key);

      // ---- Tools ----
      case 'tool/call':
        final callId = ToolCallId(envelope.data['callId'].toString());
        final rawArgs =
            envelope.data['arguments']?.toString() ??
            envelope.data['args']?.toString() ??
            envelope.data['input']?.toString();
        final node = ToolNode(
          key: 't$callId',
          sourceSeqs: [envelope.seq],
          callId: callId,
          name: envelope.data['name'].toString(),
          status: ToolNodeStatus.running,
          argsRaw: rawArgs,
        );
        _toolsByCallId[callId] = node;
        _append(node);

      case 'tool/result':
        final payloadMessage = envelope.data['message'];
        // Canonical wire shape carries identity in source.callId
        // (createToolResultMessage); tolerate legacy flat callId.
        final String? rawCallId = payloadMessage is Map
            ? ((((payloadMessage['source'] as Map?)?['callId']) ??
                      payloadMessage['callId'] ??
                      envelope.data['callId']))
                  ?.toString()
            : envelope.data['callId']?.toString();
        if (rawCallId == null || rawCallId == 'null') {
          throw StateError('tool/result without callId at seq ${envelope.seq}');
        }
        final callId = ToolCallId(rawCallId);
        final node = _toolsByCallId[callId];
        if (node == null)
          throw StateError('tool/result for unknown call $callId');
        final isError =
            envelope.data['isError'] == true || envelope.data['error'] != null;
        final resultText = _extractToolResultText(
          envelope.data,
          payloadMessage,
        );
        final settled = node.copyWith(
          status: isError ? ToolNodeStatus.error : ToolNodeStatus.success,
          result: resultText,
          isError: isError,
        );
        final settledWithSource = ToolNode(
          key: settled.key,
          sourceSeqs: [...settled.sourceSeqs, envelope.seq],
          callId: settled.callId,
          name: settled.name,
          status: settled.status,
          result: settled.result,
          isError: settled.isError,
          subCalls: settled.subCalls,
          argsRaw: settled.argsRaw,
        );
        // Re-project subcalls from childrenByParent map (preserves any
        // out-of-order dispatches already stored).
        final projected = _projectToolNode(settledWithSource);
        final topIdx = _nodes.indexWhere((n) => n.key == projected.key);
        if (topIdx != -1) {
          _nodes[topIdx] = projected;
        }
        final openChildren = _openGroupKey == null
            ? null
            : _groupChildren[_openGroupKey];
        final grpIdx =
            openChildren?.indexWhere((n) => n.key == projected.key) ?? -1;
        if (grpIdx != -1 && openChildren != null) {
          openChildren[grpIdx] = projected;
          _rebuildOpenGroup();
        }
        _settle(projected.key);
        _toolsByCallId[callId] = projected;

      // ---- Code-dispatch subcalls (React ToolCallBlock children) ----
      // Mirrors `ToolCallTree.childrenByParent` with fixed 256 depth cap and
      // cycle rejection, tolerating out-of-order delivery by storing at parent
      // key regardless of arrival order.
      case 'tool/code-dispatch-start':
      case 'tool/code-dispatch':
        final String? rootRaw = envelope.data['rootCallId']?.toString();
        final String? parentRaw =
            envelope.data['parentCallId']?.toString() ?? rootRaw;
        if (rootRaw == null || rootRaw.isEmpty) {
          throw StateError(
            'code-dispatch without rootCallId at seq ${envelope.seq}',
          );
        }
        final rootCallId = ToolCallId(rootRaw);
        final ToolCallId? parentCallId =
            parentRaw == null ? null : ToolCallId(parentRaw);
        final parentIdx = _nodes.indexWhere(
          (n) => n is ToolNode && n.callId == rootCallId,
        );
        final openKids = _openGroupKey == null
            ? null
            : _groupChildren[_openGroupKey];
        final kidIdx =
            openKids?.indexWhere(
              (n) => n is ToolNode && n.callId == rootCallId,
            ) ??
            -1;
        if (parentIdx == -1 && (openKids == null || kidIdx == -1)) {
          throw StateError(
            'code-dispatch for unknown root call $rootCallId at seq ${envelope.seq}',
          );
        }
        final parent =
            (parentIdx != -1 ? _nodes[parentIdx] : openKids![kidIdx])
                as ToolNode;
        final subCallId = ToolCallId(envelope.data['subCallId'].toString());
        final name = envelope.data['name']?.toString() ?? '';
        final isError = envelope.data['isError'] == true;
        final contentRaw = envelope.data['content'];
        final content = contentRaw == null
            ? null
            : _extractContentBlocksText(contentRaw);
        final ToolCallId effectiveParent = parentCallId ?? rootCallId;
        if (!_acceptEdge(effectiveParent, subCallId)) {
          break;
        }
        final incoming = ToolSubCall(
          subCallId: subCallId,
          name: name,
          isError: isError,
          result: content,
        );
        _upsertChildAtParent(
          effectiveParent,
          incoming,
          envelope.type == 'tool/code-dispatch',
        );
        // Rebuild the root's recursive projection from the map.
        final withSubs = ToolNode(
          key: parent.key,
          sourceSeqs: [...parent.sourceSeqs, envelope.seq],
          callId: parent.callId,
          name: parent.name,
          status: parent.status,
          result: parent.result,
          isError: parent.isError,
          subCalls: _collectChildren(rootCallId),
          argsRaw: parent.argsRaw,
        );
        if (parentIdx != -1) {
          _nodes[parentIdx] = withSubs;
        }
        if (openKids != null && kidIdx != -1) {
          openKids[kidIdx] = withSubs;
          _rebuildOpenGroup();
        }
        _toolsByCallId[rootCallId] = withSubs;

      // ---- Step grouping (summary view) ----
      case 'step/start':
        _turn = envelope.data['turn'] as int? ?? _turn;
        _step = envelope.data['step'] as int? ?? 1;
        final key = 'g$_turn-$_step';
        _openGroupKey = key;
        _groupChildren[key] = [];
        // The group container goes to the surface directly — _append would
        // route it into itself (open-key routing).
        _nodes.add(
          StepGroupNode(
            key: key,
            sourceSeqs: [envelope.seq],
            turn: _turn,
            step: _step,
            children: const [],
            summary: 'Step $_step',
            settled: false,
          ),
        );

      case 'step/end':
        final key = _openGroupKey;
        if (key == null) break;
        final index = _nodes.indexWhere((n) => n.key == key);
        if (index == -1) {
          _openGroupKey = null;
          break;
        }
        final group = _nodes[index] as StepGroupNode;
        // Empty steps drive no visible surface: drop the container like React
        // (steps are invisible location brackets; Flutter keeps the container
        // only when it collected real content for that step).
        if (group.children.isEmpty) {
          _nodes.removeAt(index);
          _groupChildren.remove(key);
          _openGroupKey = null;
          break;
        }
        final tools = group.children.whereType<ToolNode>().length;
        final hasError = group.children.any(
          (c) =>
              c is TurnErrorNode ||
              (c is ToolNode && c.status == ToolNodeStatus.error),
        );
        _nodes[index] = StepGroupNode(
          key: key,
          sourceSeqs: [...group.sourceSeqs, envelope.seq],
          turn: group.turn,
          step: group.step,
          children: List.unmodifiable(group.children),
          summary:
              'Step ${group.step} · $tools tool${tools == 1 ? '' : 's'}${hasError ? ' · error' : ''}',
          settled: true,
        );
        for (final child in group.children) {
          _settledKeys.add(child.key);
        }
        _settledKeys.add('group-$key');
        _groupChildren.remove(key);
        _openGroupKey = null;

      // ---- Errors / retries / max tokens ----
      case 'turn/end'
          when envelope.data['reason'] is Map &&
              (envelope.data['reason'] as Map)['kind'] == 'error':
        final reason = (envelope.data['reason'] as Map)['error'];
        final mapped = displayFailureMessage(reason);
        _append(
          TurnErrorNode(
            key: 'e${envelope.seq}',
            sourceSeqs: [envelope.seq],
            friendly: mapped.friendly,
            raw: mapped.raw,
            errorCode: reason is Map ? reason['code'] as String? : null,
          ),
        );

      case 'turn/end'
          when envelope.data['reason'] is Map &&
              (envelope.data['reason'] as Map)['kind'] == 'max-tokens':
        _append(
          TurnErrorNode(
            key: 'e${envelope.seq}',
            sourceSeqs: [envelope.seq],
            friendly: 'max tokens reached',
            raw: envelope.data['reason'].toString(),
          ),
        );

      case 'llm/retry-started':
      case 'llm/retry':
        {
          final retry = (envelope.data['retry'] as num?)?.toInt() ?? 0;
          final key = 'r${envelope.data['retryId'] ?? envelope.seq}';
          final idx = _nodes.indexWhere(
            (n) =>
                n is ModelRetryNode && n.retry == retry ||
                n.key == key && n is ModelRetryNode,
          );
          if (envelope.type == 'llm/retry-started') {
            final target = idx == -1 ? null : _nodes[idx] as ModelRetryNode?;
            if (target != null) {
              _nodes[idx] = target.copyWithStarted();
            }
            break;
          }
          final failure = envelope.data['failure'];
          final failureMap = failure is Map
              ? failure.cast<String, dynamic>()
              : const <String, dynamic>{};
          final node = ModelRetryNode(
            key: key,
            sourceSeqs: [envelope.seq],
            retry: retry,
            maxRetries: (envelope.data['maxRetries'] as num?)?.toInt() ?? 0,
            delayMs: (envelope.data['delayMs'] as num?)?.toInt() ?? 0,
            failureCode: failureMap['code']?.toString(),
            failureMessage: failureMap['message']?.toString(),
          );
          if (idx != -1 && _nodes[idx] is ModelRetryNode) {
            _nodes[idx] = node;
          } else {
            _append(node);
          }
        }

      // ---- Compaction: automatic surface-replace ----
      case 'compaction/start':
        // Manual starts carry sourceCommandId; keep them out of the automatic bracket.
        if (envelope.data['sourceCommandId'] != null) {
          _getOrCreateManual(envelope.data['sourceCommandId'].toString())
            ..compactionId = envelope.data['compactionId']?.toString()
            ..startSeq = envelope.seq;
          break;
        }
        _compactionStartSeq = envelope.seq;
        _compactionStartIndex = _nodes.length;
        break;

      case 'compaction/summary':
        // Manual summaries carry sourceCommandId; route to per-command pending.
        if (envelope.data['sourceCommandId'] != null) {
          final cmdId = envelope.data['sourceCommandId'].toString();
          final shadowed = envelope.data['shadowedSeqs'];
          if (shadowed is List && shadowed.isNotEmpty) {
            _manualPendingByCommandId[cmdId] = _PendingCompaction(
              summarySeq: envelope.seq,
              compactionId: envelope.data['compactionId']?.toString(),
              text: _contentBlocksText(envelope.data['summary']),
              shadowedSeqs: shadowed.whereType<int>().toList(growable: false),
              shadowedTokenCount:
                  (envelope.data['shadowedTokenCount'] as num?)?.toInt() ?? 0,
            );
            final state = _getOrCreateManual(cmdId);
            state.summarySeq = envelope.seq;
            state.pending = _manualPendingByCommandId[cmdId];
          } else {
            // No shadowed payload: legacy fallback — still record summary text for manual node?
          }
          _syncManualNode(cmdId);
          break;
        }
        // Automatic: shadow-price pending for global checkpoint.
        final dynamic shadowed = envelope.data['shadowedSeqs'];
        if (shadowed is List && shadowed.isNotEmpty) {
          final cid = envelope.data['compactionId']?.toString();
          _pendingCompaction = _PendingCompaction(
            summarySeq: envelope.seq,
            compactionId: cid,
            text: _contentBlocksText(envelope.data['summary']),
            shadowedSeqs: shadowed.whereType<int>().toList(growable: false),
            shadowedTokenCount:
                (envelope.data['shadowedTokenCount'] as num?)?.toInt() ?? 0,
          );
        } else {
          _collapseToCompaction(envelope);
        }
        break;

      case 'compaction/prune':
        // Shadow-price protocol for prune: same pending shape as summary but
        // without display text. Held for the immediate checkpoint replace.
        // Prune never carries sourceCommandId today; keep global.
        final dynamic pruned = envelope.data['shadowedSeqs'];
        if (pruned is List && pruned.isNotEmpty) {
          _pendingCompaction = _PendingCompaction(
            summarySeq: envelope.seq,
            compactionId: null,
            text: '',
            shadowedSeqs: pruned.whereType<int>().toList(growable: false),
            shadowedTokenCount:
                (envelope.data['shadowedTokenCount'] as num?)?.toInt() ?? 0,
          );
        }
        break;

      case 'compaction/end':
        if (envelope.data['sourceCommandId'] != null) {
          final cmdId = envelope.data['sourceCommandId'].toString();
          // Clearing pending is done after checkpoint; keep state for window
          // fallback until checkpoint lands. We just clear transient.
          _manualPendingByCommandId.remove(cmdId);
          break;
        }
        _pendingCompaction = null;
        _compactionStartSeq = null;
        _compactionStartIndex = null;
        break;

      // ---- Command lifecycle (manual compaction ownership) ----
      case 'command/run':
        final cmdId = envelope.data['commandId']?.toString() ?? '';
        if (cmdId.isEmpty) break;
        final state = _getOrCreateManual(cmdId);
        state.commandSeq = envelope.seq;
        state.commandTime = envelope.time;
        state.name = envelope.data['name']?.toString();
        state.args = envelope.data['args']?.toString();
        state.outcome = null;
        _syncManualNode(cmdId);
        break;

      case 'command/done':
        final cmdId = envelope.data['commandId']?.toString() ?? '';
        if (cmdId.isEmpty) break;
        final state = _getOrCreateManual(cmdId);
        final kind = envelope.data['kind']?.toString() ?? 'error';
        final text = envelope.data['text']?.toString();
        final sourceEventSeq = (envelope.data['sourceEventSeq'] as num?)
            ?.toInt();
        state.outcome = CommandOutcome(
          kind: kind,
          text: text,
          sourceEventSeq: sourceEventSeq,
        );
        state.doneSeq = envelope.seq;
        _syncManualNode(cmdId);
        break;

      case 'request/header':
        final systemText = _extractSystemPromptText(envelope.data);
        if (systemText != null && systemText.trim().isNotEmpty) {
          // Filter placeholder snapshots (e.g. "{{system}}") — they carry no
          // model-visible prose and would otherwise produce a spurious row.
          final trimmed = systemText.trim();
          final isPlaceholder =
              trimmed == '{{system}}' || trimmed == '{{tools}}';
          if (!isPlaceholder) {
            _append(
              SystemPromptNode(
                key: 'system-${envelope.seq}',
                sourceSeqs: [envelope.seq],
                text: systemText,
                anchorSeq: envelope.seq,
              ),
            );
          }
        }
        break;

      // ---- Lossless lifecycle markers (React: structural, never a visible row) ----
      case 'turn/start':
        _turn = envelope.data['turn'] as int? ?? _turn;
        break;
      case 'session/end-seed':
        // Position-only marker for the trajectory boundary; no chat row.
        break;

      // Common log-only records that carry no surface node (mirrors React
      // conversation gate — these flow into separate panels/projections).
      case 'todo/write' ||
          'request/context' ||
          'hook/invoked' ||
          'hook/result' ||
          'plan/mode':
        break;

      default:
        break; // merged plugin extensions carry no surface node here
    }
    if (envelope.type == 'turn/end') {
      _maybeEmitTurnTail(envelope);
      _maybeEmitTurnProcess(envelope);
    } else if (envelope.type == 'step/start' || envelope.type == 'step/end') {
      // Keep StatsLine step counts in sync: already tracked in _trackTurnTail
    }
  }

  // ---- TurnTail helpers (mirrors turn-tail.ts + turn-metrics.ts + token-format.ts) ----

  static const int _maxSafeInt = 9007199254740991;

  bool _isSafeCount(int value) =>
      value >= 0 && value <= _maxSafeInt;

  int? _safeSum(List<int> values) {
    var total = 0;
    for (final v in values) {
      total += v;
      if (total < 0 || total > _maxSafeInt) return null;
    }
    return total;
  }

  _TailAcc _tailFor(int turn) =>
      _turnTailByTurn.putIfAbsent(turn, () => _TailAcc(turn: turn));

  void _trackTurnTail(SessionEventEnvelope envelope) {
    final String type = envelope.type;
    // Resolve via location index memory (payloadCoordinates parity). Session-scoped events have no turn.
    final _Coordinates? coords = _coordinates[envelope.seq];
    if (coords != null && coords.session) return; // session scoped, not per-turn
    int resolveTurn() {
      if (coords != null && coords.turn != null) return coords.turn!;
      final dynamic rawTurn = envelope.data['turn'];
      if (rawTurn is int) return rawTurn;
      if (rawTurn is num) return rawTurn.toInt();
      return _turn;
    }

    if (type == 'turn/start') {
      final int t = (envelope.data['turn'] as num?)?.toInt() ?? _turn;
      if (t == 0) return;
      final acc = _tailFor(t);
      acc.hasStart = true;
      acc.startTime = envelope.time;
      acc.startSeq = envelope.seq;
      // Ensure the folder's _turn cursor is consistent for subsequent fallback resolutions
      // (the existing switch case also sets _turn, this is just for early bookkeeping).
      return;
    }
    if (type == 'step/start') {
      final int t = resolveTurn();
      if (t == 0) return;
      final int step = (envelope.data['step'] as num?)?.toInt() ?? 0;
      if (step != 0) {
        _stepStartTime['$t-$step'] = envelope.time;
      }
      // Ensure tail entry exists even if turn/start was window-cut; we still track steps for stats
      _tailFor(t);
      return;
    }
    if (type == 'assistant/chunk') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _tailFor(t);
      // Detect first non-empty text delta for TTFT (mirrors isTokenDelta / chunkHasText)
      final dynamic chunk = envelope.data['chunk'];
      bool hasText = false;
      String? text;
      if (chunk is Map) {
        final String ctype = chunk['type']?.toString() ?? '';
        if (ctype == 'text-delta') {
          text = chunk['text']?.toString() ?? '';
          if (text.trim().isNotEmpty) hasText = true;
        } else if (ctype == 'block-end') {
          final block = chunk['block'] as Map?;
          final String btype = block?['type']?.toString() ?? '';
          final String btext = block?['text']?.toString() ?? '';
          if (btype == 'text' && btext.trim().isNotEmpty) hasText = true;
        } else if (ctype == 'reasoning-delta') {
          // Reasoning alone does not establish TTFT for the prose path
        } else {
          // Fallback: check 'text' field presence
          text = chunk['text']?.toString();
          if (text != null && text.trim().isNotEmpty && ctype != 'block-start') hasText = true;
        }
      }
      if (hasText && acc.firstAssistantTime == null) {
        acc.firstAssistantTime = envelope.time;
      }
      // Track step-level first token time for stats fallback
      final int step = (envelope.data['step'] as num?)?.toInt() ?? 0;
      if (hasText && step != 0) {
        final String k = '$t-$step';
        _stepFirstTokenTime.putIfAbsent(k, () => envelope.time);
      }
      return;
    }
    if (type == 'assistant/message') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _tailFor(t);
      final Object? rawMsg = envelope.data['message'];
      final String text = rawMsg is Map
          ? _extractTextFromMessage(rawMsg)
          : '';
      final Object? rawUsage = envelope.data['usage'];
      Map<String, Object?>? usageMap;
      if (rawUsage is Map) {
        try {
          usageMap = Map<String, Object?>.from(rawUsage as Map);
        } catch (_) {
          usageMap = null;
        }
      }
      Map<String, Object?>? sourceMap;
      if (rawMsg is Map) {
        final src = (rawMsg as Map)['source'];
        if (src is Map) {
          try {
            sourceMap = Map<String, Object?>.from(src as Map);
          } catch (_) {
            sourceMap = null;
          }
        }
      }
      final int step = (envelope.data['step'] as num?)?.toInt() ?? 0;
      acc.assistants.add(_AssistantRecord(
        seq: envelope.seq,
        time: envelope.time,
        text: text,
        usage: usageMap,
        source: sourceMap,
        step: step == 0 ? null : step,
      ));
      if (text.trim().isNotEmpty && acc.firstAssistantTime == null) {
        acc.firstAssistantTime = envelope.time;
      }
      if (text.trim().isNotEmpty) {
        if (envelope.seq > acc.latestTranscriptSeq) acc.latestTranscriptSeq = envelope.seq;
      } else {
        if (envelope.seq > acc.latestTranscriptSeq) acc.latestTranscriptSeq = envelope.seq;
      }
      // Step-level first token time for stats: if this is the first assistant text for the step
      if (step != 0 && text.trim().isNotEmpty) {
        final String k = '$t-$step';
        _stepFirstTokenTime.putIfAbsent(k, () => envelope.time);
      }
      return;
    }
    if (type == 'tool/call') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _tailFor(t);
      acc.toolCount += 1;
      if (envelope.seq > acc.latestTranscriptSeq) acc.latestTranscriptSeq = envelope.seq;
      final String? rawId = envelope.data['callId']?.toString();
      if (rawId != null && rawId.isNotEmpty) {
        _toolCallTime[ToolCallId(rawId)] = envelope.time;
      }
      return;
    }
    if (type == 'tool/result') {
      final int t = resolveTurn();
      if (t == 0) {
        // Resolve callId even without turn for duration, but still need turn for transcript?
        // Attempt to recover turn via fallback cursor at call time; if still 0 skip tail transcript update
      }
      // Always attempt to compute tool duration for stats
      String? rawId;
      final Object? payloadMessage = envelope.data['message'];
      if (payloadMessage is Map) {
        final src = (payloadMessage as Map)['source'];
        if (src is Map && src['callId'] != null) {
          rawId = src['callId'].toString();
        } else if (payloadMessage['callId'] != null) {
          rawId = payloadMessage['callId'].toString();
        }
      }
      rawId ??= envelope.data['callId']?.toString();
      if (rawId != null && rawId != 'null') {
        final callId = ToolCallId(rawId);
        if (_toolCallTime.containsKey(callId)) {
          final int callTime = _toolCallTime[callId]!;
          final int dur = (envelope.time - callTime).clamp(0, 1 << 30);
          _toolResultDurations[callId.hashCode] = dur;
        }
      }
      if (t != 0) {
        final acc = _tailFor(t);
        if (envelope.seq > acc.latestTranscriptSeq) acc.latestTranscriptSeq = envelope.seq;
      }
      return;
    }
    if (type == 'llm/retry' || type == 'llm/retry-started') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _tailFor(t);
      if (envelope.seq > acc.latestTranscriptSeq) acc.latestTranscriptSeq = envelope.seq;
      return;
    }
    if (type == 'turn/end') {
      // For turn/end that carries error/maxTokens, also counts as transcript for branch check if error present
      final dynamic reason = envelope.data['reason'];
      final bool isErrorCase = reason is Map && (reason['kind'] == 'error' || reason['kind'] == 'max-tokens');
      if (isErrorCase) {
        final int t = (envelope.data['turn'] as num?)?.toInt() ?? _turn;
        if (t != 0) {
          final acc = _tailFor(t);
          if (envelope.seq > acc.latestTranscriptSeq) acc.latestTranscriptSeq = envelope.seq;
        }
      }
      return;
    }
  }

  void _trackTurnProcess(SessionEventEnvelope envelope) {
    final String type = envelope.type;
    final _Coordinates? coords = _coordinates[envelope.seq];
    if (coords != null && coords.session) return;
    bool isSubagentTool(String name) => name == 'subagent' || name.startsWith('subagent_');
    int resolveTurn() {
      if (coords != null && coords.turn != null) return coords.turn!;
      final dynamic rt = envelope.data['turn'];
      if (rt is int) return rt;
      if (rt is num) return rt.toInt();
      return _turn;
    }

    if (type == 'turn/start') {
      final int t = (envelope.data['turn'] as num?)?.toInt() ?? _turn;
      if (t == 0) return;
      final acc = _turnProcessByTurn.putIfAbsent(t, () => _ProcessAcc(turn: t));
      acc.controlAnchorSeq = acc.controlAnchorSeq == 1 << 30 ? envelope.seq : acc.controlAnchorSeq;
      return;
    }
    if (type == 'assistant/message') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _turnProcessByTurn.putIfAbsent(t, () => _ProcessAcc(turn: t));
      final Object? rawMsg = envelope.data['message'];
      final String text = rawMsg is Map ? _extractTextFromMessage(rawMsg) : '';
      final List<dynamic>? blocks = rawMsg is Map ? rawMsg['content'] as List<dynamic>? : null;
      final bool hasReply = text.trim().isNotEmpty || (blocks != null && blocks.any((b) => b is Map && b['type'] != 'tool-call' && (b['text']?.toString().trim().isNotEmpty ?? false)));
      final bool hasReasoning = blocks != null && blocks.any((b) => b is Map && b['type'] == 'reasoning' && (b['text']?.toString().trim().isNotEmpty ?? false));
      if (hasReply) {
        acc.messageCount += 1;
        final int step = (envelope.data['step'] as num?)?.toInt() ?? 0;
        if (step != 0) {
          acc.stepHasAnswer[step] = true;
          acc.stepAnswerSeq[step] = envelope.seq;
          if (hasReasoning) acc.stepHasReasoning[step] = true;
        }
        if (acc.processStartSeq == null) acc.processStartSeq = envelope.seq;
        if (envelope.seq < acc.controlAnchorSeq) acc.controlAnchorSeq = envelope.seq;
      }
      return;
    }
    if (type == 'assistant/chunk') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _turnProcessByTurn.putIfAbsent(t, () => _ProcessAcc(turn: t));
      final dynamic chunk = envelope.data['chunk'];
      String? ctype;
      if (chunk is Map) ctype = chunk['type']?.toString();
      if (ctype == 'text-delta' || ctype == 'reasoning-delta' || ctype == 'tool-call-delta') {
        if (acc.processStartSeq == null) acc.processStartSeq = envelope.seq;
        if (envelope.seq < acc.controlAnchorSeq) acc.controlAnchorSeq = envelope.seq;
      }
      return;
    }
    if (type == 'tool/call') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _turnProcessByTurn.putIfAbsent(t, () => _ProcessAcc(turn: t));
      final String name = envelope.data['name']?.toString() ?? '';
      if (isSubagentTool(name)) acc.subagentCount += 1;
      else acc.toolCallCount += 1;
      if (acc.processStartSeq == null) acc.processStartSeq = envelope.seq;
      if (envelope.seq < acc.controlAnchorSeq) acc.controlAnchorSeq = envelope.seq;
      return;
    }
    if (type == 'llm/retry') {
      final int t = resolveTurn();
      if (t == 0) return;
      final acc = _turnProcessByTurn.putIfAbsent(t, () => _ProcessAcc(turn: t));
      if (acc.processStartSeq == null) acc.processStartSeq = envelope.seq;
      return;
    }
  }

  void _maybeEmitTurnProcess(SessionEventEnvelope envelope) {
    final _Coordinates? coords = _coordinates[envelope.seq];
    final int? rawTurn = envelope.data['turn'] is num ? (envelope.data['turn'] as num).toInt() : envelope.data['turn'] as int?;
    final int turn = coords?.turn ?? rawTurn ?? _turn;
    if (turn == 0) return;
    final acc = _turnProcessByTurn[turn];
    if (acc == null) return;
    int? answerStep;
    if (acc.stepHasAnswer.isNotEmpty) {
      answerStep = acc.stepHasAnswer.keys.reduce((a, b) => a > b ? a : b);
    }
    final int controlSeq = acc.controlAnchorSeq == 1 << 30 ? envelope.seq : acc.controlAnchorSeq;
    final int processSeq = acc.processStartSeq ?? controlSeq;
    int msgCount = acc.messageCount;
    if (answerStep != null && acc.stepHasAnswer[answerStep] == true && msgCount > 0) msgCount -= 1;
    final int? answerSeq = answerStep != null ? acc.stepAnswerSeq[answerStep] : null;
    final bool inlineReasoning = answerStep != null ? (acc.stepHasReasoning[answerStep] ?? false) : false;
    final node = TurnProcessNode(
      key: 'process-$turn',
      sourceSeqs: [controlSeq, if (answerSeq != null) answerSeq else envelope.seq],
      turn: turn,
      controlAnchorSeq: controlSeq,
      processStartSeq: processSeq,
      answerAnchorSeq: answerSeq,
      answerStep: answerStep,
      inlineReasoning: inlineReasoning,
      messageCount: msgCount.clamp(0, 1 << 30),
      toolCallCount: acc.toolCallCount,
      subagentCount: acc.subagentCount,
    );
    final int existingIdx = _nodes.indexWhere((n) => n is TurnProcessNode && n.turn == turn);
    if (existingIdx != -1) {
      _nodes[existingIdx] = node;
    } else {
      // Insert before the answer node (earliest evidence before answer), not after.
      // Find answer node index if known, else before tail.
      int insertBefore = -1;
      if (answerSeq != null) {
        insertBefore = _nodes.indexWhere((n) => n.sourceSeqs.contains(answerSeq));
      }
      if (insertBefore != -1) {
        _nodes.insert(insertBefore, node);
      } else {
        final int tailIdx = _nodes.indexWhere((n) => n is TurnTailNode && n.turn == turn);
        if (tailIdx != -1) _nodes.insert(tailIdx, node);
        else _append(node);
      }
    }
    _settledKeys.add(node.key);
  }

  TurnTokenUsage? _deriveTurnTokenUsage(_TailAcc acc) {
    if (!acc.hasStart) return null;
    if (acc.assistants.isEmpty) return null;
    final List<Map<String, Object?>> usages = [];
    final List<Map<String, Object?>?> sources = [];
    for (final rec in acc.assistants) {
      final u = rec.usage;
      if (u == null) return null;
      usages.add(u);
      sources.add(rec.source);
    }
    final List<int> inputTokensList = [];
    final List<int> outputTokensList = [];
    final List<int> totalTokensList = [];
    final List<int?> cacheReads = [];
    final List<int?> cacheWrites = [];
    final List<int?> reasonings = [];
    final List<TurnTokenUsageRoute?> routes = [];
    for (int i = 0; i < usages.length; i++) {
      final Map<String, Object?> u = usages[i];
      final Map<String, Object?>? src = sources[i];
      Object? input = u['inputTokens'] ?? u['uncachedInputTokens'];
      Object? output = u['outputTokens'];
      Object? total = u['totalTokens'];
      // Some fixtures may use camel variations; coerce num to int
      int? inputInt;
      int? outputInt;
      int? totalInt;
      if (input is int) inputInt = input;
      else if (input is num) inputInt = input.toInt();
      else return null;
      if (output is int) outputInt = output;
      else if (output is num) outputInt = output.toInt();
      else return null;
      if (total is int) totalInt = total;
      else if (total is num) totalInt = total.toInt();
      else return null;
      if (!_isSafeCount(inputInt) || !_isSafeCount(outputInt) || !_isSafeCount(totalInt)) return null;
      inputTokensList.add(inputInt);
      outputTokensList.add(outputInt);
      totalTokensList.add(totalInt);
      final cr = u['cacheReadTokens'];
      if (cr is int) {
        if (!_isSafeCount(cr)) return null;
        cacheReads.add(cr);
      } else if (cr is num) {
        final v = cr.toInt();
        if (!_isSafeCount(v)) return null;
        cacheReads.add(v);
      } else if (cr == null) {
        cacheReads.add(null);
      } else {
        return null;
      }
      final cw = u['cacheWriteTokens'];
      if (cw is int) {
        if (!_isSafeCount(cw)) return null;
        cacheWrites.add(cw);
      } else if (cw is num) {
        final v = cw.toInt();
        if (!_isSafeCount(v)) return null;
        cacheWrites.add(v);
      } else if (cw == null) {
        cacheWrites.add(null);
      } else {
        return null;
      }
      final rs = u['reasoningTokens'];
      if (rs is int) {
        if (!_isSafeCount(rs)) return null;
        if (rs > outputInt) return null;
        reasonings.add(rs);
      } else if (rs is num) {
        final v = rs.toInt();
        if (!_isSafeCount(v)) return null;
        if (v > outputInt) return null;
        reasonings.add(v);
      } else if (rs == null) {
        reasonings.add(null);
      } else {
        return null;
      }
      if (src != null) {
        final String prov = src['provider']?.toString() ?? '';
        final String model = src['model']?.toString() ?? '';
        if (prov.isNotEmpty && model.isNotEmpty) {
          routes.add(TurnTokenUsageRoute(provider: prov, model: model));
        } else {
          routes.add(null);
        }
      } else {
        routes.add(null);
      }
    }
    final int? sumInput = _safeSum(inputTokensList);
    final int? sumOutput = _safeSum(outputTokensList);
    final int? sumTotal = _safeSum(totalTokensList);
    if (sumInput == null || sumOutput == null || sumTotal == null) return null;
    int? sumCacheRead;
    if (cacheReads.every((e) => e != null)) {
      sumCacheRead = _safeSum(cacheReads.whereType<int>().toList());
      if (sumCacheRead == null) return null;
    }
    int? sumCacheWrite;
    if (cacheWrites.every((e) => e != null)) {
      sumCacheWrite = _safeSum(cacheWrites.whereType<int>().toList());
      if (sumCacheWrite == null) return null;
    }
    int? sumReasoning;
    if (reasonings.every((e) => e != null)) {
      sumReasoning = _safeSum(reasonings.whereType<int>().toList());
      if (sumReasoning == null) return null;
    }
    List<TurnTokenUsageRoute>? aggregatedRoutes;
    if (routes.every((r) => r != null)) {
      final uniq = <String, TurnTokenUsageRoute>{};
      for (final r in routes) {
        final route = r!;
        uniq['${route.provider}\u0000${route.model}'] = route;
      }
      aggregatedRoutes = uniq.values.toList(growable: false);
    }
    return TurnTokenUsage(
      uncachedInputTokens: sumInput,
      outputTokens: sumOutput,
      totalTokens: sumTotal,
      cacheReadTokens: sumCacheRead,
      cacheWriteTokens: sumCacheWrite,
      reasoningTokens: sumReasoning,
      routes: aggregatedRoutes,
    );
  }

  void _maybeEmitTurnTail(SessionEventEnvelope envelope) {
    final int? rawTurn = envelope.data['turn'] is num
        ? (envelope.data['turn'] as num).toInt()
        : envelope.data['turn'] as int?;
    final int turn = rawTurn ?? _turn;
    if (turn == 0) return;
    final _TailAcc acc = _turnTailByTurn.putIfAbsent(turn, () => _TailAcc(turn: turn));
    acc.endTime = envelope.time;
    acc.endSeq = envelope.seq;
    // Ensure latest transcript includes the end event itself when it carries error evidence
    if (envelope.seq > acc.latestTranscriptSeq) acc.latestTranscriptSeq = envelope.seq;
    // Determine closing assistant (last content-bearing)
    _AssistantRecord? closingRecord;
    for (int i = acc.assistants.length - 1; i >= 0; i--) {
      if (acc.assistants[i].text.trim().isNotEmpty) {
        closingRecord = acc.assistants[i];
        break;
      }
    }
    final int? closingSeq = closingRecord?.seq;
    final bool branchUnavailable = closingRecord == null || acc.latestTranscriptSeq != closingSeq;
    int? ttftMs;
    if (acc.hasStart && acc.startTime != null && acc.firstAssistantTime != null) {
      ttftMs = (acc.firstAssistantTime! - acc.startTime!).clamp(0, 1 << 30);
    }
    int? runMs;
    if (acc.hasStart && acc.startTime != null && acc.endTime != null) {
      runMs = (acc.endTime! - acc.startTime!).clamp(0, 1 << 30);
    }
    final TurnTokenUsage? tokenUsage = _deriveTurnTokenUsage(acc);
    double? tokensPerSecond;
    if (tokenUsage != null && tokenUsage.outputTokens > 0 && acc.firstAssistantTime != null && acc.endTime != null) {
      final int decodeMs = (acc.endTime! - acc.firstAssistantTime!).clamp(0, 1 << 30);
      if (decodeMs > 0) {
        tokensPerSecond = tokenUsage.outputTokens / (decodeMs / 1000);
      }
    }
    final List<int> sourceSeqs = <int>[
      if (acc.startSeq != null) acc.startSeq!,
      acc.endSeq ?? envelope.seq,
      ...acc.assistants.map((a) => a.seq),
    ];
    final node = TurnTailNode(
      key: 'tt$turn',
      sourceSeqs: sourceSeqs,
      turn: turn,
      seq: envelope.seq,
      time: envelope.time,
      closingText: closingRecord?.text,
      closingSeq: closingSeq,
      ttftMs: ttftMs,
      tokensPerSecond: tokensPerSecond,
      tokenUsage: tokenUsage,
      branchUnavailable: branchUnavailable,
      runMs: runMs,
    );
    final int existingIdx = _nodes.indexWhere((n) => n is TurnTailNode && n.turn == turn);
    if (existingIdx != -1) {
      _nodes[existingIdx] = node;
    } else {
      // Ensure we are not inside an open group (turn/end should have closed it)
      final openKey = _openGroupKey;
      if (openKey != null && _groupChildren.containsKey(openKey)) {
        // If for some reason a group is still open, settle it first then append
        // Prevent routing tail into the group
        final snapOpen = _openGroupKey;
        _openGroupKey = null;
        _append(node);
        _openGroupKey = snapOpen;
      } else {
        _append(node);
      }
    }
    _settledKeys.add(node.key);
  }

  // ---- Manual compaction helpers ----

  _ManualState _getOrCreateManual(String commandId) => _manualByCommandId
      .putIfAbsent(commandId, () => _ManualState(commandId: commandId));

  void _syncManualNode(String commandId) {
    final state = _manualByCommandId[commandId]!;
    // Non-compact commands: produce a generic CommandNode.
    if (state.name != null && state.name != 'compact') {
      final key = 'cmd:$commandId';
      final existingIdx = _nodes.indexWhere((n) => n.key == key);
      final node = CommandNode(
        key: key,
        sourceSeqs: [
          state.commandSeq,
          if (state.doneSeq != null) state.doneSeq!,
        ],
        commandId: commandId,
        name: state.name,
        args: state.args,
        outcome: state.outcome,
        time: state.commandTime,
      );
      // Also check open group.
      final openChildren = _openGroupKey == null
          ? null
          : _groupChildren[_openGroupKey!];
      final grpIdx = openChildren?.indexWhere((n) => n.key == key) ?? -1;
      if (existingIdx != -1) {
        _nodes[existingIdx] = node;
      } else if (grpIdx != -1 && openChildren != null) {
        openChildren[grpIdx] = node;
        _rebuildOpenGroup();
      } else {
        _append(node);
      }
      return;
    }

    // Compact path: build ManualCompactionNode.
    // If checkpoint already landed, node is at replacement position and was inserted
    // by _handleManualCheckpoint; just update its command outcome in place.
    final manualKey = 'manual-compaction:$commandId';
    final existingIdx = _nodes.indexWhere((n) => n.key == manualKey);
    // If checkpoint exists, compaction is already materialized; update command part.
    if (state.compactionNode != null) {
      if (existingIdx != -1) {
        final existing = _nodes[existingIdx] as ManualCompactionNode;
        final updatedCommand = CommandNode(
          key: existing.command.key,
          sourceSeqs: existing.command.sourceSeqs,
          commandId: commandId,
          name: state.name ?? 'compact',
          args: state.args,
          outcome: state.outcome,
          time: state.commandTime,
        );
        final updated = ManualCompactionNode(
          key: existing.key,
          sourceSeqs: existing.sourceSeqs,
          command: updatedCommand,
          compaction: existing.compaction,
        );
        _nodes[existingIdx] = updated;
        return;
      }
      // Fallback: should have been inserted, but insert if missing.
    }

    // Running or not-yet-checkpointed: insert a manual node with null compaction.
    // This mirrors React's "compact · Compacting context…" running row.
    if (state.commandSeq == 0 && state.name == null)
      return; // not enough info yet
    final commandNode = CommandNode(
      key: 'cmd:$commandId',
      sourceSeqs: [state.commandSeq, if (state.doneSeq != null) state.doneSeq!],
      commandId: commandId,
      name: state.name ?? 'compact',
      args: state.args,
      outcome: state.outcome,
      time: state.commandTime,
    );
    final manualNode = ManualCompactionNode(
      key: manualKey,
      sourceSeqs: [state.commandSeq, if (state.doneSeq != null) state.doneSeq!],
      command: commandNode,
      compaction: null,
    );
    final openChildren = _openGroupKey == null
        ? null
        : _groupChildren[_openGroupKey!];
    final grpIdx = openChildren?.indexWhere((n) => n.key == manualKey) ?? -1;
    if (existingIdx != -1) {
      _nodes[existingIdx] = manualNode;
    } else if (grpIdx != -1 && openChildren != null) {
      openChildren[grpIdx] = manualNode;
      _rebuildOpenGroup();
    } else {
      // Only insert running compact nodes when command/run has been seen
      // (fallbackState would otherwise create one from checkpoint alone;
      // that path is handled in _handleManualCheckpoint fallback).
      if (state.commandSeq != 0) _append(manualNode);
    }
  }

  void _handleManualCheckpoint(
    SessionEventEnvelope envelope,
    String commandId,
  ) {
    final state = _getOrCreateManual(commandId);
    state.checkpoint = envelope;
    state.checkpointSeq = envelope.seq;
    state.compactionId = envelope.data['source'] is Map
        ? (envelope.data['source'] as Map)['compactionId']?.toString()
        : null;
    // Resolve pending summary for this command.
    _PendingCompaction? pending = _manualPendingByCommandId[commandId];
    // Fallback: if pending missing, try global pending (legacy) or window-cut.
    pending ??= _pendingCompaction;
    String text = '';
    List<int> shadowed = const [];
    int tokenCount = 0;
    int summarySeq = envelope.seq;
    if (pending != null &&
        (pending.compactionId == null ||
            pending.compactionId == state.compactionId ||
            state.compactionId == null ||
            state.compactionId!.isEmpty)) {
      text = pending.text;
      shadowed = pending.shadowedSeqs;
      tokenCount = pending.shadowedTokenCount;
      summarySeq = pending.summarySeq;
      // Consume pending for this command.
      _manualPendingByCommandId.remove(commandId);
      if (identical(pending, _pendingCompaction)) _pendingCompaction = null;
    } else {
      // Window cut: use sourceEventSeqs as fallback shadowed set, empty text
      final fallback =
          envelope.sourceEventSeqs ??
          (envelope.data['sourceEventSeqs'] is List
              ? (envelope.data['sourceEventSeqs'] as List)
                    .whereType<int>()
                    .toList()
              : const <int>[]);
      shadowed = fallback;
      text = '';
      summarySeq = envelope.seq;
    }

    final compaction = CompactionNode(
      key: 'k${envelope.seq}',
      sourceSeqs: [summarySeq, envelope.seq, ...shadowed],
      text: text,
      shadowedTokenCount: tokenCount,
      shadowedItemCount: shadowed.length,
    );
    state.compactionNode = compaction;
    state.pending = pending;

    // Remove shadowed nodes (same authoritative logic as automatic).
    final replacements = <int>[];
    for (var i = _nodes.length - 1; i >= 0; i--) {
      final node = _nodes[i];
      final inShadowed = shadowed.any(node.sourceSeqs.contains);
      final isGroupShadowed =
          node is StepGroupNode &&
          node.children.any((c) => shadowed.any(c.sourceSeqs.contains));
      if (inShadowed || isGroupShadowed) {
        replacements.add(i);
        _nodes.removeAt(i);
      }
    }
    if (_openGroupKey != null) {
      final gc = _groupChildren[_openGroupKey!];
      if (gc != null) {
        final before = gc.length;
        gc.removeWhere((c) => shadowed.any(c.sourceSeqs.contains));
        if (gc.length != before) _rebuildOpenGroup();
      }
    }
    for (final entry in _groupChildren.values) {
      entry.removeWhere((c) => shadowed.any(c.sourceSeqs.contains));
    }

    // Remove any existing running manual node for this command (it sits at old position).
    final runningIdx = _nodes.indexWhere(
      (n) => n.key == 'manual-compaction:$commandId',
    );
    if (runningIdx != -1) {
      // It is not shadowed (command seq not in shadowed), so remove explicitly.
      _nodes.removeAt(runningIdx);
      // Adjust replacement indices after removal.
      for (var i = 0; i < replacements.length; i++) {
        if (replacements[i] > runningIdx) replacements[i] -= 1;
      }
    }
    // Also remove from open group if there.
    if (_openGroupKey != null) {
      final gc = _groupChildren[_openGroupKey!];
      gc?.removeWhere((n) => n.key == 'manual-compaction:$commandId');
      if (gc != null) _rebuildOpenGroup();
    }

    final commandNode = CommandNode(
      key: 'cmd:$commandId',
      sourceSeqs: [
        state.commandSeq,
        if (state.doneSeq != null) state.doneSeq!,
        summarySeq,
        envelope.seq,
      ],
      commandId: commandId,
      name: state.name ?? 'compact',
      args: state.args,
      outcome: state.outcome,
      time: state.commandTime,
    );
    final manualNode = ManualCompactionNode(
      key: 'manual-compaction:$commandId',
      sourceSeqs: [state.commandSeq, summarySeq, envelope.seq, ...shadowed],
      command: commandNode,
      compaction: compaction,
    );
    if (replacements.isEmpty) {
      _nodes.add(manualNode);
    } else {
      replacements.sort();
      _nodes.insert(replacements.first, manualNode);
    }
    _settledKeys.add(manualNode.key);
    // Also ensure state reflects checkpoint consumed.
    state.commandSeq = state.commandSeq == 0 ? envelope.seq : state.commandSeq;
  }

  /// Applies the pending summary through the replace-op `user/message`
  /// checkpoint: removes every node whose source seqs intersect the
  /// declared shadowed set (or fall inside the op's node range), then
  /// inserts the compaction node at the first removal position.
  ///
  /// React's `compactSummary` joins `type === 'text'` blocks with `''`
  /// (no separator) and the surface layer's `replacementRange` locates the
  /// op's `[start, end]` seqs in surface order, not numeric index order.
  void _applyCompactionCheckpoint(SessionEventEnvelope envelope) {
    final pending = _pendingCompaction!;
    _pendingCompaction = null;
    _applyCompactionWith(envelope, pending);
  }

  /// Fallback when a checkpoint arrives without a matching pending summary
  /// (window cut left the summary outside). Mirrors React's
  /// `fallbackState` which still materializes a compaction node with
  /// `summary: null` and null counts.
  void _applyCompactionCheckpointOrFallback(SessionEventEnvelope envelope) {
    final pending = _pendingCompaction;
    if (pending != null) {
      _applyCompactionCheckpoint(envelope);
      return;
    }
    _pendingCompaction = null;
    final fallbackSeqs =
        envelope.sourceEventSeqs ??
        (envelope.data['sourceEventSeqs'] is List
            ? (envelope.data['sourceEventSeqs'] as List)
                  .whereType<int>()
                  .toList()
            : const <int>[]);
    _applyCompactionWith(
      envelope,
      _PendingCompaction(
        summarySeq: envelope.seq,
        compactionId: _compactCheckpointId(envelope),
        text: '',
        shadowedSeqs: fallbackSeqs,
        shadowedTokenCount: 0,
      ),
    );
  }

  void _applyCompactionWith(
    SessionEventEnvelope envelope,
    _PendingCompaction pending,
  ) {
    final replacements = <int>[];
    // Authoritative removal is by shadowedSeqs (the exact set the
    // summary/prune metering event priced). The op's [start,end] is
    // kept only for legacy index fixtures — when shadowed is present we
    // ignore the op range to avoid dual-mode ambiguity that would
    // remove keep in the index-vs-seq fixture.
    for (var i = _nodes.length - 1; i >= 0; i--) {
      final node = _nodes[i];
      final inShadowed = pending.shadowedSeqs.any(node.sourceSeqs.contains);
      // Also check inside settled StepGroupNode children: if any child is
      // shadowed, treat the group as shadowed.
      final isGroupShadowed =
          node is StepGroupNode &&
          node.children.any(
            (c) => pending.shadowedSeqs.any(c.sourceSeqs.contains),
          );
      if (inShadowed || isGroupShadowed) {
        replacements.add(i);
        _nodes.removeAt(i);
      }
    }
    // Prune shadowed children from any remaining open group.
    if (_openGroupKey != null) {
      final gc = _groupChildren[_openGroupKey];
      if (gc != null) {
        final before = gc.length;
        gc.removeWhere((c) => pending.shadowedSeqs.any(c.sourceSeqs.contains));
        if (gc.length != before) _rebuildOpenGroup();
      }
    }
    for (final entry in _groupChildren.values) {
      entry.removeWhere((c) => pending.shadowedSeqs.any(c.sourceSeqs.contains));
    }
    final shadowedCount = pending.shadowedSeqs.length;
    final compact = CompactionNode(
      key: 'k${envelope.seq}',
      sourceSeqs: [pending.summarySeq, envelope.seq, ...pending.shadowedSeqs],
      text: pending.text,
      shadowedTokenCount: pending.shadowedTokenCount,
      shadowedItemCount: shadowedCount,
    );
    if (replacements.isEmpty) {
      _nodes.add(compact);
    } else {
      replacements.sort();
      _nodes.insert(replacements.first, compact);
    }
    _settledKeys.add(compact.key);
  }

  static String _contentBlocksText(Object? summary) {
    if (summary is String) return summary.trim();
    if (summary is List) {
      final buf = StringBuffer();
      for (final dynamic blk in summary) {
        if (blk is Map) {
          final type = blk['type'];
          if (type == 'text') {
            final dynamic t = blk['text'];
            if (t is String) buf.write(t);
          }
        } else if (blk is String) {
          buf.write(blk);
        }
      }
      return buf.toString().trim();
    }
    return '';
  }

  void _collapseToCompaction(SessionEventEnvelope envelope) {
    final start = _compactionStartSeq;
    final startIndex = _compactionStartIndex;
    if (start == null || startIndex == null) return;
    final clamped = startIndex.clamp(0, _nodes.length) as int;
    final shadowed = <int>{start};
    for (var i = clamped; i < _nodes.length; i++) {
      shadowed.addAll(_nodes[i].sourceSeqs);
    }
    final rawText = envelope.data['text'];
    final summaryText = rawText is String
        ? rawText.trim()
        : _contentBlocksText(envelope.data['summary']);
    final text = summaryText.isNotEmpty
        ? summaryText
        : (envelope.data['text'] ?? '').toString().trim();
    final compact = CompactionNode(
      key: 'k${envelope.seq}',
      sourceSeqs: [envelope.seq, ...shadowed],
      text: text,
      shadowedTokenCount: 0,
      shadowedItemCount:
          shadowed.length - 1, // exclude the bracket marker itself
    );
    if (clamped < _nodes.length) {
      _nodes.removeRange(clamped, _nodes.length);
      _nodes.insert(clamped, compact);
    } else {
      _nodes.add(compact);
    }
    _settledKeys.add(compact.key);
  }

  /// Re-renders the open group node from its children list.
  void _rebuildOpenGroup() {
    final key = _openGroupKey;
    if (key == null) return;
    final index = _nodes.indexWhere((n) => n.key == key);
    if (index == -1) return;
    final existing = _nodes[index] as StepGroupNode;
    final children = List.of(_groupChildren[key] ?? const <ConversationNode>[]);
    _nodes[index] = StepGroupNode(
      key: key,
      sourceSeqs: [...existing.sourceSeqs],
      turn: existing.turn,
      step: existing.step,
      children: List.unmodifiable(children),
      summary:
          'Step ${existing.step} · ${children.whereType<ToolNode>().length} tool${children.whereType<ToolNode>().length == 1 ? '' : 's'}',
      settled: false,
    );
  }

  static String _extractToolResultText(
    Map<String, Object?> envelopeData,
    Object? payloadMessage,
  ) {
    final direct = envelopeData['result'];
    if (direct is String && direct.isNotEmpty) return direct;
    if (direct is List) {
      final text = _contentBlocksText(direct);
      if (text.isNotEmpty) return text;
      // Try to extract via content blocks style
      final alt = _extractContentBlocksText(direct);
      if (alt != null && alt.isNotEmpty) return alt;
    }
    if (direct != null && direct is! String && direct is! List) {
      // Check if direct is map with text
      if (direct is Map && direct['text'] is String)
        return direct['text'] as String;
    }
    if (payloadMessage is Map) {
      final content = payloadMessage['content'];
      if (content is List) {
        final buf = StringBuffer();
        for (final entry in content) {
          if (entry is Map) {
            if (entry['type'] == 'tool-result') {
              final inner = entry['content'];
              if (inner is List) {
                for (final blk in inner) {
                  if (blk is Map &&
                      blk['type'] == 'text' &&
                      blk['text'] is String) {
                    buf.writeln(blk['text'] as String);
                  } else if (blk is Map && blk['content'] is String) {
                    buf.writeln(blk['content'] as String);
                  } else if (blk is Map && blk['text'] is String) {
                    buf.writeln(blk['text'] as String);
                  }
                }
              } else if (entry['text'] is String) {
                buf.writeln(entry['text'] as String);
              } else if (entry['content'] is String) {
                buf.writeln(entry['content'] as String);
              }
            } else if (entry['type'] == 'text' && entry['text'] is String) {
              buf.writeln(entry['text'] as String);
            } else if (entry['text'] is String) {
              buf.writeln(entry['text'] as String);
            } else if (entry['content'] is String) {
              buf.writeln(entry['content'] as String);
            }
          } else if (entry is String) {
            buf.writeln(entry);
          }
        }
        final s = buf.toString().trim();
        if (s.isNotEmpty) return s;
      }
      if (content is String && content.isNotEmpty) return content;
      final txt = payloadMessage['text'];
      if (txt is String && txt.isNotEmpty) return txt;
    }
    final alt =
        envelopeData['content'] ??
        envelopeData['output'] ??
        envelopeData['text'];
    if (alt is String) return alt;
    if (alt is List) {
      final buf = StringBuffer();
      for (final blk in alt) {
        if (blk is Map && blk['text'] is String)
          buf.writeln(blk['text'] as String);
        else if (blk is String)
          buf.writeln(blk);
      }
      final s = buf.toString().trim();
      if (s.isNotEmpty) return s;
    }
    // Check isError content via error field
    final err = envelopeData['error'];
    if (err is Map && err['message'] is String) return err['message'] as String;
    if (err is String) return err;
    return '';
  }

  static String? _extractContentBlocksText(Object? raw) {
    if (raw is String) return raw.isNotEmpty ? raw : null;
    if (raw is List) {
      final buf = StringBuffer();
      for (final entry in raw) {
        if (entry is Map) {
          final t = entry['text'];
          if (t is String)
            buf.writeln(t);
          else if (entry['content'] is String)
            buf.writeln(entry['content'] as String);
        } else if (entry is String) {
          buf.writeln(entry);
        }
      }
      final s = buf.toString().trim();
      return s.isEmpty ? null : s;
    }
    if (raw is Map && raw['text'] is String) return raw['text'] as String;
    return null;
  }

  static String _extractContextText(Map<String, Object?> data) {
    return _extractUserText(data);
  }

  /// Extract model-visible system prompt text from a `request/header` envelope.
  /// Checks top-level `prompt`/`system`/`text` and nested `header` map, joining
  /// content blocks via [_contentBlocksText] when needed. Returns null when
  /// empty.
  static String? _extractSystemPromptText(Map<String, Object?> data) {
    String? asString(Object? value) {
      if (value is String) return value;
      if (value is List) return _contentBlocksText(value);
      return null;
    }

    for (final key in ['prompt', 'system', 'text', 'systemPrompt']) {
      final v = data[key];
      if (v != null) {
        final s = asString(v);
        if (s != null && s.trim().isNotEmpty) return s;
        if (v is Map) {
          for (final inner in ['text', 'system', 'prompt', 'content']) {
            final iv = v[inner];
            final s2 = asString(iv);
            if (s2 != null && s2.trim().isNotEmpty) return s2;
          }
        }
      }
    }
    final header = data['header'];
    if (header is Map) {
      for (final key in ['system', 'prompt', 'text', 'systemPrompt']) {
        final v = header[key];
        if (v != null) {
          final s = asString(v);
          if (s != null && s.trim().isNotEmpty) return s;
        }
      }
    }
    return null;
  }

  static String? _contextProvenanceLabel(Map src) {
    final label = src['label'];
    if (label is String && label.isNotEmpty) return label;
    final name = src['name'];
    if (name is String && name.isNotEmpty) return name;
    final plugin = src['plugin'];
    if (plugin is String && plugin.isNotEmpty) return plugin;
    final kind = src['kind'];
    if (kind is String && kind.isNotEmpty) return kind;
    // For snapshot, try to use first section name
    final sections = src['sections'];
    if (sections is List && sections.isNotEmpty) {
      final first = sections.first;
      if (first is Map && first['name'] is String)
        return first['name'] as String;
    }
    return null;
  }

  static List<Map<String, String>>? _contextSnapshotSections(Map src) {
    final sections = src['sections'];
    if (sections is List) {
      final out = <Map<String, String>>[];
      for (final sec in sections) {
        if (sec is Map) {
          final name = sec['name']?.toString();
          final text = sec['text']?.toString();
          if (name != null && text != null)
            out.add({'name': name, 'text': text});
        }
      }
      if (out.isNotEmpty) return out;
    }
    return null;
  }

  void _assertUnsettled(String key) {
    if (_settledKeys.contains(key)) {
      throw StateError('fold would mutate settled node "$key"');
    }
  }

  void _settle(String key) => _settledKeys.add(key);

  List<int> _seqsOf(String assistantKey) =>
      _findAssistant(assistantKey)?.sourceSeqs ?? const <int>[];

  String _textOf(String assistantKey) =>
      _findAssistant(assistantKey)?.text ?? '';

  String _reasoningOf(String assistantKey) =>
      _findAssistant(assistantKey)?.reasoning ??
      _reasoningBuffers[assistantKey]?.toString() ??
      '';

  List<PartialToolCall> _partialsOf(String assistantKey) =>
      _findAssistant(assistantKey)?.partialToolCalls ?? const [];

  String _extractReasoningFromMessage(Object? message) {
    if (message is! Map) return '';
    final content = message['content'];
    if (content is List) {
      final buf = StringBuffer();
      for (final blk in content) {
        if (blk is Map && blk['type'] == 'reasoning') {
          final t = blk['text'];
          if (t is String) buf.write(t);
        }
        // Legacy: blocks may be under 'blocks'
        if (blk is Map && blk['kind'] == 'reasoning') {
          final t = blk['text'];
          if (t is String) buf.write(t);
        }
      }
      return buf.toString();
    }
    return '';
  }

  String _extractTextFromMessage(Object? message) {
    if (message is! Map) return '';
    final content = message['content'];
    if (content is List) {
      final buf = StringBuffer();
      for (final blk in content) {
        if (blk is Map && blk['type'] == 'text') {
          final t = blk['text'];
          if (t is String) {
            if (buf.isNotEmpty) buf.writeln();
            buf.write(t);
          }
        }
        if (blk is Map && blk['kind'] == 'text') {
          final t = blk['text'];
          if (t is String) {
            if (buf.isNotEmpty) buf.writeln();
            buf.write(t);
          }
        }
      }
      return buf.toString().trim();
    }
    if (content is String) return content;
    return '';
  }

  void _upsert(AssistantNode node) {
    // Top-level hit.
    final index = _nodes.indexWhere((n) => n.key == node.key);
    if (index != -1) {
      _nodes[index] = node;
      _inFlightAssistantKeys.add(node.key);
      return;
    }
    // Open-group hit or append via group routing.
    final openKey = _openGroupKey;
    if (openKey != null) {
      final gc = _groupChildren[openKey];
      if (gc != null) {
        final gIdx = gc.indexWhere((n) => n.key == node.key);
        if (gIdx != -1) {
          gc[gIdx] = node;
          _rebuildOpenGroup();
          _inFlightAssistantKeys.add(node.key);
          return;
        }
      }
      // Not found anywhere — route through the group like any other content.
      _append(node);
      _inFlightAssistantKeys.add(node.key);
      return;
    }
    _nodes.add(node);
    _inFlightAssistantKeys.add(node.key);
  }

  AssistantNode? _findAssistant(String key) {
    for (final n in _nodes) {
      if (n is AssistantNode && n.key == key) return n;
      if (n is StepGroupNode) {
        for (final c in n.children) {
          if (c is AssistantNode && c.key == key) return c;
        }
      }
    }
    final openKey = _openGroupKey;
    if (openKey != null) {
      final gc = _groupChildren[openKey];
      if (gc != null) {
        for (final c in gc) {
          if (c is AssistantNode && c.key == key) return c as AssistantNode;
        }
      }
    }
    return null;
  }

  void _replaceByKey(String key, ConversationNode next) {
    final index = _nodes.indexWhere((n) => n.key == key);
    assert(index != -1, 'replace target $key missing');
    _nodes[index] = next;
  }

  // ---- Tool subcall helpers (childrenByParent + 256 cap + cycle) ----

  /// Mirrors `ToolCallTree.wouldCreateCycle`.
  bool _wouldCreateCycleMap(ToolCallId parentId, ToolCallId childId) {
    if (parentId == childId) return true;
    final pending = <ToolCallId>[childId];
    final visited = <ToolCallId>{childId};
    for (var i = 0; i < pending.length; i++) {
      final callId = pending[i];
      for (final child in _childrenByParent[callId] ?? const []) {
        if (child.subCallId == parentId) return true;
        if (visited.contains(child.subCallId)) continue;
        visited.add(child.subCallId);
        pending.add(child.subCallId);
      }
    }
    return false;
  }

  /// Mirrors `ToolCallTree.acceptEdge` — depth cap 256 and cycle rejection.
  bool _acceptEdge(ToolCallId parentCallId, ToolCallId subCallId) {
    if (_wouldCreateCycleMap(parentCallId, subCallId)) return false;
    final pending = <({ToolCallId callId, int depth})>[
      (callId: subCallId, depth: (_depthByCall[parentCallId] ?? 1) + 1),
    ];
    final updates = <ToolCallId, int>{};
    for (var i = 0; i < pending.length; i++) {
      final candidate = pending[i];
      final knownDepth =
          updates[candidate.callId] ?? _depthByCall[candidate.callId] ?? 1;
      if (candidate.depth <= knownDepth) continue;
      if (candidate.depth > 256) return false;
      updates[candidate.callId] = candidate.depth;
      for (final child in _childrenByParent[candidate.callId] ?? const []) {
        pending.add((callId: child.subCallId, depth: candidate.depth + 1));
      }
    }
    for (final entry in updates.entries) {
      _depthByCall[entry.key] = entry.value;
    }
    return true;
  }

  void _upsertChildAtParent(
    ToolCallId parentId,
    ToolSubCall incoming,
    bool isSettlement,
  ) {
    final siblings = _childrenByParent[parentId] ?? const [];
    final at = siblings.indexWhere((c) => c.subCallId == incoming.subCallId);
    if (at != -1) {
      final existing = siblings[at];
      if (!isSettlement && existing.result != null) return;
      final merged = existing.copyWith(
        isError: incoming.isError,
        result: incoming.result,
        children: existing.children,
      );
      final next = List<ToolSubCall>.of(siblings);
      next[at] = merged;
      _childrenByParent[parentId] = next;
      return;
    }
    _childrenByParent[parentId] = [...siblings, incoming];
  }

  List<ToolSubCall> _collectChildren(ToolCallId callId) {
    final direct = _childrenByParent[callId] ?? const [];
    return [
      for (final child in direct)
        child.copyWith(children: _collectChildren(child.subCallId)),
    ];
  }

  ToolNode _projectToolNode(ToolNode node) {
    final projected = _collectChildren(node.callId);
    if (projected.length == node.subCalls.length &&
        projected.every(
          (c) => node.subCalls.any((e) => e.subCallId == c.subCallId),
        )) {
      // Keep identity if nothing changed (avoid churn for sameReferences)
      bool same = projected.length == node.subCalls.length;
      if (same) {
        for (var i = 0; i < projected.length; i++) {
          if (projected[i].subCallId != node.subCalls[i].subCallId) {
            same = false;
            break;
          }
        }
      }
      if (same) return node;
    }
    return ToolNode(
      key: node.key,
      sourceSeqs: node.sourceSeqs,
      callId: node.callId,
      name: node.name,
      status: node.status,
      result: node.result,
      isError: node.isError,
      subCalls: projected,
      argsRaw: node.argsRaw,
    );
  }
}

/// Summary half of the React checkpoint pair, held until the replace-op
/// `user/message` checkpoint arrives.
class _PendingCompaction {
  const _PendingCompaction({
    required this.summarySeq,
    this.compactionId,
    required this.text,
    required this.shadowedSeqs,
    required this.shadowedTokenCount,
  });

  final int summarySeq;
  final String? compactionId;
  final String text;
  final List<int> shadowedSeqs;
  final int shadowedTokenCount;
}

class _ManualState {
  _ManualState({required this.commandId});
  final String commandId;
  String? name;
  String? args;
  CommandOutcome? outcome;
  int commandSeq = 0;
  int commandTime = 0;
  int? doneSeq;
  String? compactionId;
  int? startSeq;
  int? summarySeq;
  _PendingCompaction? pending;
  SessionEventEnvelope? checkpoint;
  int? checkpointSeq;
  CompactionNode? compactionNode;
}

/// Per-turn tail accumulation (window-local) mirroring `TurnTailState` + `tailData`.
class _TailAcc {
  _TailAcc({required this.turn});
  final int turn;
  int? startTime;
  int? startSeq;
  bool hasStart = false;
  int? endTime;
  int? endSeq;
  int? firstAssistantTime;
  int latestTranscriptSeq = -1;
  int toolCount = 0;
  final List<_AssistantRecord> assistants = [];
}

class _ProcessAcc {
  _ProcessAcc({required this.turn});
  final int turn;
  int controlAnchorSeq = 1 << 30;
  int? processStartSeq;
  int? answerAnchorSeq;
  int? answerStep;
  bool inlineReasoning = false;
  int messageCount = 0;
  int toolCallCount = 0;
  int subagentCount = 0;
  final Map<int, bool> stepHasAnswer = {};
  final Map<int, bool> stepHasReasoning = {};
  final Map<int, int> stepAnswerSeq = {};
}

/// One assistant message within a turn (finalized `assistant/message`).
class _AssistantRecord {
  _AssistantRecord({
    required this.seq,
    required this.time,
    required this.text,
    this.usage,
    this.source,
    this.step,
  });
  final int seq;
  final int time;
  final String text;
  final Map<String, Object?>? usage;
  final Map<String, Object?>? source;
  final int? step;
}
