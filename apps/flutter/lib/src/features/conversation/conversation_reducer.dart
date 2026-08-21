import '../../core/session/session_models.dart';
import '../tool/tool_models.dart';
import 'message_provider.dart';

/// Normalized output of the conversation event stream.
///
/// The Flutter UI package only renders this shape — raw events are never
/// mapped directly to `ChatMessage`s. The reducer is the single place that
/// assembles chunks, correlates tool calls/results by `callId`, and finalizes
/// turn state on provider/model failure.
class ReducedConversation {
  /// Ordered messages (user / assistant / system / retry disclosures).
  final List<Message> messages;

  /// Ordered tools with lifecycle finalized (no orphaned `running`).
  final List<ToolCall> tools;

  /// Friendly, concise error for the assistant tail (null when turn succeeded).
  final String? errorMessage;

  /// Raw provider error text for an optional Details disclosure.
  final String? rawError;

  /// Whether the current turn ended in failure.
  final bool turnFailed;

  const ReducedConversation({
    required this.messages,
    required this.tools,
    this.errorMessage,
    this.rawError,
    required this.turnFailed,
  });
}

/// Map a raw provider error string to a concise, user-facing message.
///
/// Keeps the original in `rawError` for Details. Strips leading
/// `NNN ModelError:` prefixes and maps known patterns (promotion expiry,
/// model not supported, 401/403/429 families). Falls back to the cleaned
/// message itself.
({String friendly, String raw}) _friendlyError(String raw) {
  String cleaned = raw.trim();
  // Host/mux often serializes the provider error as JSON inside the message
  // string, e.g. 401: {"type":"ModelError","message":"Free promotion..."}.
  // Unwrap the inner message before friendly mapping so the model-name regex
  // and the Details raw both operate on coherent text.
  if (cleaned.contains('"message"') && cleaned.contains('ModelError')) {
    final RegExpMatch? inner = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(cleaned);
    if (inner != null && (inner.group(1)?.isNotEmpty ?? false)) {
      // Prefer the inner message, but keep the full raw for Details.
      cleaned = inner.group(1)!;
    }
  }
  // Also handle the 401: {"type":...} envelope where the whole string is JSON-like.
  if (cleaned.startsWith('401: {') || cleaned.startsWith('{"type"')) {
    final RegExpMatch? inner = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(cleaned);
    if (inner != null) cleaned = inner.group(1)!;
  }
  // Strip leading "401 ModelError: " / "ModelError: " / status prefix
  cleaned = cleaned.replaceAll(RegExp(r'^\d{3}\s*:?\s*ModelError:\s*', caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'^ModelError:\s*', caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'^\d{3}\s*:?\s*'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^["\s\{]+'), '').replaceAll(RegExp(r'["\}\s]+$'), '').trim();
  final lower = cleaned.toLowerCase();

  if (lower.contains('promotion has ended for')) {
    // Model names contain no periods; the provider often appends a second
    // sentence ("You can continue using the model...") and the raw envelope
    // may include JSON quotes/braces. Capture only the model token, not the
    // trailing sentence. Strip JSON artifacts first.
    String afterFor = cleaned.split(RegExp(r'promotion has ended for\s*', caseSensitive: false)).last;
    // Strip leading/trailing JSON punctuation and whitespace.
    afterFor = afterFor.replaceAll(RegExp(r'^[\s\"\{]+'), '').replaceAll(RegExp(r'[\s\"\}\]]+$'), '').trim();
    // Cut at the first sentence-terminating period (followed by space + capital
    // or at end-of-string). A model name never contains a period.
    final RegExp periodCut = RegExp(r'\.(?:\s+|$)');
    final RegExpMatch? periodMatch = periodCut.firstMatch(afterFor);
    final String model = periodMatch != null ? afterFor.substring(0, periodMatch.start).trim() : afterFor.trim();
    final String safeModel = model.isEmpty || model.length > 60
        ? 'this model'
        : model.replaceAll(RegExp("^['\"]+|['\"]+\$"), '').trim();
    return (friendly: 'Response failed\n\nThe $safeModel promotion has ended.\nPlease select another model or upgrade your plan.', raw: raw);
  }
  if (lower.contains('model not supported') || lower.contains('model_not_supported')) {
    return (friendly: 'Response failed\n\nThe selected model is not supported.\nPlease choose a different model.', raw: raw);
  }
  if (lower.contains('freeusagelimit') || lower.contains('free usage limit')) {
    return (friendly: 'Response failed\n\nFree usage limit reached.\nPlease select another model or upgrade your plan.', raw: raw);
  }
  if (RegExp(r'\b401\b').hasMatch(raw)) {
    return (friendly: 'Response failed\n\nAuthentication failed (401).\nPlease check your model configuration.', raw: raw);
  }
  if (RegExp(r'\b403\b').hasMatch(raw)) {
    return (friendly: 'Response failed\n\nAccess denied (403).\nPlease check your permissions or model access.', raw: raw);
  }
  if (RegExp(r'\b429\b').hasMatch(raw)) {
    return (friendly: 'Response failed\n\nRate limit exceeded (429).\nPlease wait a moment and try again.', raw: raw);
  }
  // Fallback: cleaned message itself (without raw JSON prefix).
  if (cleaned.isEmpty) cleaned = raw.trim();
  return (friendly: cleaned.isEmpty ? 'Response failed' : cleaned, raw: raw);
}

String? _extractErrorMessage(dynamic error) {
  if (error is Map) {
    final m = (error as Map).cast<String, dynamic>();
    final String? type = m['type'] as String?;
    final String? msg = (m['message'] as String?) ?? (m['error'] as String?);
    if (type != null && msg != null && msg.trim().isNotEmpty) {
      if (type.contains('ModelError')) return '$type: $msg';
      return msg;
    }
    if (msg != null && msg.trim().isNotEmpty) return msg;
    if (type != null) return type;
    return null;
  }
  if (error is String && error.trim().isNotEmpty) return error;
  return null;
}

String _unescapeHtml(String input) {
  return input
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/');
}

String? _asString(dynamic v) {
  if (v is String) return v;
  if (v == null || v is Map || v is List) return null;
  try {
    final String s = v.toString();
    if (s.startsWith('Instance of')) return null;
    return s;
  } catch (_) {
    return null;
  }
}

String _extractText(Map<String, dynamic> data) {
  final dynamic content = data['content'];
  if (content is String) return content;
  if (content is List) {
    final StringBuffer buf = StringBuffer();
    for (final dynamic block in content) {
      if (block is Map) {
        final String? t = _asString(block['text']) ?? _asString(block['content']);
        if (t != null) buf.writeln(t);
      } else if (block is String) {
        buf.writeln(block);
      }
    }
    final String s = buf.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return _asString(data['text']) ?? _asString(data['message']) ?? _asString(data['delta']) ?? '';
}

/// Single-pass reduction of the DeepSeek Harness / OpenCode event log
/// into a normalized conversation shape.
///
/// Responsibilities (per spec):
/// - assemble streamed `assistant/chunk` deltas (text vs reasoning)
/// - parse `assistant/message` blocks into `Message` + pending tool ghosts
/// - correlate `tool/call` / `tool/result` by `callId`
/// - finalize unresolved tools on `turn/end` error or `agentError`
/// - produce one concise `errorMessage` + `rawError` for the tail
ReducedConversation reduceConversation(
  List<HistoryEntry> entries, {
  bool isRunning = false,
  String? agentError,
}) {
  final Map<String, ToolCall> byId = <String, ToolCall>{};
  final List<String> toolOrder = <String>[];
  final List<Message> messages = <Message>[];
  final StringBuffer chunkTextBuffer = StringBuffer();
  final StringBuffer chunkReasoningBuffer = StringBuffer();
  int? chunkSeq;
  int? chunkTime;
  String? rawError;
  String? friendlyError;
  bool turnFailed = false;

  String _toolFriendlyArgs(dynamic raw) {
    if (raw is String) {
      final String t = raw.trim();
      if (t.isEmpty || t == '{}' || t == '[]') return '';
      return t;
    }
    return '';
  }

  // Helper: mark all pending/running tools as cancelled.
  void cancelUnresolved() {
    for (final String id in byId.keys.toList()) {
      final ToolCall c = byId[id]!;
      if (c.status == ToolCallStatus.pending || c.status == ToolCallStatus.running) {
        byId[id] = ToolCall(
          id: c.id,
          toolName: c.toolName,
          kind: c.kind,
          status: ToolCallStatus.cancelled,
          args: c.args,
          result: c.result,
          view: c.view,
          time: c.time,
        );
      }
    }
  }

  for (final HistoryEntry entry in entries) {
    final SessionEvent event = entry.event;
    final String type = event.type;

    if (type == 'user/message') {
      // Flush chunk buffers as non-streaming partial only if no final
      // message has superseded them — otherwise clear.
      if (chunkTextBuffer.isNotEmpty || chunkReasoningBuffer.isNotEmpty) {
        chunkTextBuffer.clear();
        chunkReasoningBuffer.clear();
        chunkSeq = null;
        chunkTime = null;
      }
      final String text = _unescapeHtml(_extractText(event.data));
      messages.add(Message(
        id: 'user-${event.seq}',
        role: MessageRole.user,
        content: text.isEmpty ? '(empty message)' : text,
        time: event.time,
      ));
    } else if (type == 'assistant/chunk') {
      final dynamic rawDelta = event.data['delta'] ?? event.data['chunk'] ?? event.data['text'];
      String delta = '';
      String? deltaType;
      if (rawDelta is String) {
        delta = rawDelta;
      } else if (rawDelta is Map) {
        final Map<String, dynamic> m = (rawDelta as Map).cast<String, dynamic>();
        deltaType = m['type'] as String?;
        if (m['type'] == 'reasoning' && m['text'] is String) {
          delta = _asString(m['text']) ?? '';
        } else if (m['type'] == 'text' && m['text'] is String) {
          delta = _asString(m['text']) ?? '';
        } else {
          delta = _asString(m['text']) ?? _asString(m['delta']) ?? _asString(m['content']) ?? '';
        }
      } else {
        delta = _asString(rawDelta) ?? '';
      }
      if (delta.isEmpty) continue;
      chunkSeq ??= event.seq;
      chunkTime ??= event.time;
      if (deltaType == 'reasoning') {
        chunkReasoningBuffer.write(delta);
      } else {
        chunkTextBuffer.write(delta);
      }
    } else if (type == 'assistant/message') {
      // Final message supersedes any buffered chunks — clear without emitting
      // a duplicate partial.
      chunkTextBuffer.clear();
      chunkReasoningBuffer.clear();
      chunkSeq = null;
      chunkTime = null;

      // Assistant messages with empty content (status-only, no visible blocks)
      // are not rendered in React — AssistantMarkdown returns null when
      // hasVisible is false (streaming=false, interrupted!=true, only tool-call
      // blocks). Skip them the same way to prevent blank "Assistant" headers.
      final dynamic rawContentProbe = event.data['content'];
      final bool contentEmpty = rawContentProbe == null ||
          (rawContentProbe is List && rawContentProbe.isEmpty) ||
          (rawContentProbe is String && rawContentProbe.trim().isEmpty);
      if (contentEmpty) {
        // Keep tool-call ghosts for lifecycle (deduplicated via byId), but
        // don't emit an empty assistant bubble. The tool rows render separately.
        final bool hasVisibleBlock = rawContentProbe is List &&
            rawContentProbe.any((blk) => blk is Map && blk['type'] != 'tool-call');
        if (!hasVisibleBlock) {
          // Still record pending tool ghosts for cancelled handling, then skip bubble.
          if (rawContentProbe is List) {
            for (final dynamic blk in rawContentProbe) {
              if (blk is Map && blk['type'] == 'tool-call') {
                final String callId = (blk['id'] as String?) ?? (blk['callId'] as String?) ?? 'call-${event.seq}';
                final String name = (blk['name'] as String?) ?? 'tool';
                if (!byId.containsKey(callId)) {
                  byId[callId] = ToolCall(
                    id: callId,
                    toolName: name,
                    kind: kindForTool(name),
                    status: ToolCallStatus.pending,
                    args: const <String, dynamic>{},
                    time: event.time,
                  );
                  toolOrder.add(callId);
                }
              }
            }
          }
          continue;
        }
      }

      final String text = _unescapeHtml(_extractText(event.data));
      final dynamic rawContent = event.data['content'];
      List<AssistantBlock>? blocks;
      if (rawContent is List) {
        final List<AssistantBlock> b = <AssistantBlock>[];
        for (final dynamic blk in rawContent) {
          if (blk is Map) {
            final String? t = blk['type'] as String?;
            if (t == 'text' && blk['text'] is String) {
              final String t2 = _unescapeHtml(blk['text'] as String).trim();
              if (t2.isEmpty) continue;
              b.add(AssistantBlock.text(t2));
            } else if (t == 'reasoning' && blk['text'] is String) {
              final String r2 = _unescapeHtml(blk['text'] as String).trim();
              if (r2.isEmpty) continue;
              b.add(AssistantBlock.reasoning(r2));
            } else if (t == 'tool-call') {
              final String callId = (blk['id'] as String?) ?? (blk['callId'] as String?) ?? 'call-${event.seq}-${b.length}';
              final String name = (blk['name'] as String?) ?? 'tool';
              // Tool-call blocks are not kept in the assistant Message — they
              // are owned by the tool list (ghost pending → deduped via byId).
              // Keeping them in both places renders each call twice (block bubble
              // + tool-list bubble). The empty-assistant hasVisible check in
              // React (hasVisible = streaming || interrupted || some != tool-call)
              // returns null for tool-call-only nodes, so no empty bubble.
              // Ghost pending tool for this block (unless a real tool/call already exists).
              if (!byId.containsKey(callId)) {
                final dynamic rawArgs = blk['arguments'] ?? blk['args'];
                Map<String, dynamic> parsedArgs = const <String, dynamic>{};
                if (rawArgs is Map) {
                  parsedArgs = (rawArgs as Map).cast<String, dynamic>();
                  if (parsedArgs.isEmpty) parsedArgs = const <String, dynamic>{};
                } else if (rawArgs is String && rawArgs.trim().isNotEmpty && rawArgs.trim() != '{}') {
                  // Keep raw string; don't try to JSON-decode here.
                  parsedArgs = const <String, dynamic>{};
                }
                byId[callId] = ToolCall(
                  id: callId,
                  toolName: name,
                  kind: kindForTool(name),
                  status: ToolCallStatus.pending,
                  args: parsedArgs,
                  time: event.time,
                );
                toolOrder.add(callId);
              }
            }
          }
        }
        if (b.isNotEmpty) blocks = List<AssistantBlock>.unmodifiable(b);
      }
      messages.add(Message(
        id: 'assistant-${event.seq}',
        role: MessageRole.assistant,
        content: text,
        time: event.time,
        blocks: blocks,
      ));
    } else if (type == 'tool/call' || type == 'tools/call') {
      final String callId = (event.data['callId'] as String?) ??
          (event.data['toolCallId'] as String?) ??
          'call-${event.seq}';
      final String toolName = (event.data['name'] as String?) ??
          (event.data['tool'] as String?) ??
          'tool';
      final Map<String, dynamic> args = (event.data['args'] as Map?)?.cast<String, dynamic>() ??
          (event.data['input'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final String friendly = _toolFriendlyArgs(event.data['args'] ?? event.data['input']);
      // Upgrade pending ghost or create running.
      final ToolCall? existing = byId[callId];
      if (existing != null && existing.status == ToolCallStatus.pending) {
        byId[callId] = ToolCall(
          id: existing.id,
          toolName: toolName,
          kind: kindForTool(toolName),
          status: ToolCallStatus.running,
          args: args.isEmpty ? existing.args : args,
          view: entry.view ?? existing.view,
          time: existing.time,
        );
      } else if (!byId.containsKey(callId)) {
        byId[callId] = ToolCall(
          id: callId,
          toolName: toolName,
          kind: kindForTool(toolName),
          status: ToolCallStatus.running,
          args: args,
          view: entry.view,
          time: event.time,
        );
        toolOrder.add(callId);
      } else {
        // Already running/succeeded — keep.
      }
      _toolFriendlyArgs(friendly); // touch to avoid unused warning in some analyzers
    } else if (type == 'tool/result' || type == 'tools/result' || type == 'tool/result/batch') {
      final String callId = (event.data['callId'] as String?) ??
          (event.data['toolCallId'] as String?) ??
          '';
      if (callId.isEmpty) continue;
      final bool isError = (event.data['isError'] as bool?) ?? false;
      final dynamic result = event.data['result'] ?? event.data['output'] ?? event.data['content'];
      final ToolCall? existing = byId[callId];
      if (existing != null) {
        byId[callId] = ToolCall(
          id: existing.id,
          toolName: existing.toolName,
          kind: existing.kind,
          status: isError ? ToolCallStatus.error : ToolCallStatus.success,
          args: existing.args,
          result: result,
          view: entry.view ?? existing.view,
          time: existing.time,
        );
      } else {
        byId[callId] = ToolCall(
          id: callId,
          toolName: (event.data['name'] as String?) ?? 'tool',
          kind: ToolCallKind.generic,
          status: isError ? ToolCallStatus.error : ToolCallStatus.success,
          args: const {},
          result: result,
          view: entry.view,
          time: event.time,
        );
        toolOrder.add(callId);
      }
    } else if (type == 'llm/retry') {
      final Map<String, dynamic> data = event.data;
      final int retry = (data['retry'] as num?)?.toInt() ?? 0;
      final int maxRetries = (data['maxRetries'] as num?)?.toInt() ?? 0;
      final int delayMs = (data['delayMs'] as num?)?.toInt() ?? 0;
      final dynamic failure = data['failure'];
      String failureMsg = '';
      if (failure is Map) {
        failureMsg = _asString((failure as Map).cast<String, dynamic>()['message']) ?? failure.toString();
      } else if (failure != null) {
        failureMsg = failure.toString();
      }
      final String mode = _asString(data['mode']) ?? 'normal';
      messages.add(Message(
        id: 'retry-${event.seq}',
        role: MessageRole.system,
        content: '',
        time: event.time,
        retry: retry,
        maxRetries: maxRetries,
        delayMs: delayMs,
        failureMessage: _unescapeHtml(failureMsg),
        retryMode: mode,
      ));
    } else if (type == 'turn/end') {
      final dynamic reason = event.data['reason'];
      if (reason is Map && reason['kind'] == 'error') {
        final dynamic err = reason['error'];
        final String? msg = _extractErrorMessage(err) ?? _extractErrorMessage(reason) ?? err.toString();
        if (msg != null && msg.trim().isNotEmpty) {
          rawError = msg;
          final mapped = _friendlyError(msg);
          friendlyError = mapped.friendly;
          rawError = mapped.raw;
        } else if (err != null) {
          rawError = err.toString();
          final mapped = _friendlyError(rawError!);
          friendlyError = mapped.friendly;
          rawError = mapped.raw;
        } else {
          friendlyError = 'Response failed';
          rawError = 'turn/end error';
        }
        turnFailed = true;
        cancelUnresolved();
        // Clear streaming buffers — turn is over.
        chunkTextBuffer.clear();
        chunkReasoningBuffer.clear();
      } else {
        // Successful turn — clear friendly error (previous turn's failure
        // should not leak into a clean turn). Keep tools as-is.
        // No-op for streaming buffers that were already flushed via assistant/message.
      }
    } else if (type == 'turn/error') {
      final String msg = _unescapeHtml(_asString(event.data['message']) ?? event.data.toString());
      rawError = msg;
      friendlyError = _friendlyError(msg).friendly;
      rawError = _friendlyError(msg).raw;
      turnFailed = true;
      cancelUnresolved();
      chunkTextBuffer.clear();
      chunkReasoningBuffer.clear();
    } else if (type.startsWith('tool/')) {
      // Other tool events not explicitly handled — ignore.
      continue;
    } else {
      // Unknown types: surface as system notes only when they carry readable text
      // (mirrors messagesFromHistory fallback).
      final String text = _unescapeHtml(_extractText(event.data));
      if (text.isNotEmpty) {
        messages.add(Message(id: 'system-${event.seq}', role: MessageRole.system, content: text, time: event.time));
      }
    }
  }

  // Agent-level error (host/agent-error frame) — treated like a turn failure
  // that cancels unresolved tools and surfaces a concise message.
  if (agentError != null && agentError.trim().isNotEmpty) {
    final mapped = _friendlyError(agentError);
    // Prefer the more specific turn error if already present; otherwise use agent error.
    friendlyError ??= mapped.friendly;
    rawError ??= mapped.raw;
    turnFailed = true;
    cancelUnresolved();
    chunkTextBuffer.clear();
    chunkReasoningBuffer.clear();
  }

  // Streaming tail: emit buffered chunks as a single streaming message
  // when the turn is still in-flight (isRunning) and turn hasn't failed.
  if (isRunning && !turnFailed && (chunkTextBuffer.isNotEmpty || chunkReasoningBuffer.isNotEmpty)) {
    final String text = chunkTextBuffer.toString();
    final String reasoning = chunkReasoningBuffer.toString();
    List<AssistantBlock>? blocks;
    if (reasoning.isNotEmpty) {
      blocks = <AssistantBlock>[
        AssistantBlock.reasoning(reasoning),
        if (text.isNotEmpty) AssistantBlock.text(text),
      ];
    }
    messages.add(Message(
      id: 'assistant-${chunkSeq ?? DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: text.isNotEmpty ? text : reasoning,
      time: chunkTime ?? DateTime.now().millisecondsSinceEpoch,
      streaming: true,
      blocks: blocks,
    ));
  }

  // Build ordered tool list (first-appearance order; cancelled tools last
  // among unresolved keeps the "N tools not executed" grouping stable).
  final List<ToolCall> tools = <ToolCall>[
    for (final String id in toolOrder)
      if (byId[id] != null) byId[id]!,
  ];

  return ReducedConversation(
    messages: List<Message>.unmodifiable(messages),
    tools: List<ToolCall>.unmodifiable(tools),
    errorMessage: friendlyError,
    rawError: rawError,
    turnFailed: turnFailed,
  );
}
