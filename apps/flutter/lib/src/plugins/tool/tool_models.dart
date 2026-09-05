import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/conversation/message_provider.dart';
import '../../core/session/session_models.dart';

/// Kind discriminant for tool cards — closed union, switch with assertNever.
enum ToolCallKind { generic, read, diff, search, bash }

/// Status discriminant for a tool call.
enum ToolCallStatus { pending, running, success, error, cancelled }

/// Single tool invocation derived from `tool/call` + `tool/result` events.
class ToolCall {
  /// Stable id (callId).
  final String id;

  /// Tool name e.g. `read`, `bash`, `edit`.
  final String toolName;

  /// Kind for card selection.
  final ToolCallKind kind;

  /// Current status.
  final ToolCallStatus status;

  /// Input args (JSON-compatible map).
  final Map<String, dynamic> args;

  /// Raw `arguments` JSON string exactly as the model produced it (unparsed).
  /// Empty when the call head arrived without arguments (orphan results,
  /// legacy fixtures). Row summaries derive from this, never from [result].
  final String argsRaw;

  /// Result payload (string or map), null while pending/running.
  final dynamic result;

  /// Durable presentation metadata from `tool/result.data.meta` (e.g.
  /// `{diffs: [...]}` for write/edit). Opaque to the core; card models
  /// narrow it locally. Null when the tool attached none.
  final Object? meta;

  /// Structured failure code from `tool/result.data.error.code`, if any.
  final String? errorCode;

  /// Optional view / render intent from host presenter.
  ///
  /// Legacy: the wire no longer sends `view` (client-derived presentation
  /// decision). Retained only so old fixtures decode without throwing; new
  /// code must read [meta] instead and must never depend on this.
  final Map<String, dynamic>? view;

  /// Wall time ms.
  final int time;

  /// Creates a tool call.
  const ToolCall({
    required this.id,
    required this.toolName,
    required this.kind,
    required this.status,
    this.args = const {},
    this.argsRaw = '',
    this.result,
    this.meta,
    this.errorCode,
    this.view,
    required this.time,
  });
}

/// Classify tool name to [ToolCallKind].
ToolCallKind kindForTool(String toolName) {
  final String n = toolName.toLowerCase();
  if (n == 'read' ||
      n == 'read_image' ||
      n == 'web_fetch' ||
      n == 'str_replace_editor' ||
      n == 'view' ||
      n == 'cat') {
    return ToolCallKind.read;
  }
  if (n == 'write' ||
      n == 'edit' ||
      n == 'str_replace' ||
      n == 'diff' ||
      n == 'apply_patch') {
    return ToolCallKind.diff;
  }
  if (n == 'search' ||
      n == 'grep' ||
      n == 'glob' ||
      n == 'web_search' ||
      n == 'find' ||
      n == 'rg') {
    return ToolCallKind.search;
  }
  if (n == 'bash' ||
      n == 'pwsh' ||
      n == 'shell' ||
      n == 'terminal' ||
      n == 'exec') {
    return ToolCallKind.bash;
  }
  return ToolCallKind.generic;
}

/// Decodes one `tool/call` argument payload into its raw JSON string and its
/// best-effort args map. The canonical wire shape carries `arguments` as a
/// JSON string; legacy/test shapes may carry `args`/`input` as a map or string.
({String argsRaw, Map<String, dynamic> args}) decodeCallArgs(
  Map<String, dynamic> data,
) {
  final dynamic raw =
      data['arguments'] ?? data['args'] ?? data['input'] ?? '';
  if (raw is String) {
    if (raw.isEmpty) return (argsRaw: '', args: const <String, dynamic>{});
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return (
          argsRaw: raw,
          args: decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return (argsRaw: raw, args: const <String, dynamic>{});
    } catch (_) {
      // Mid-stream truncation: keep the raw text for the row fallback.
      return (argsRaw: raw, args: const <String, dynamic>{});
    }
  }
  if (raw is Map) {
    final args = raw.map((k, v) => MapEntry(k.toString(), v));
    try {
      return (argsRaw: jsonEncode(args), args: args);
    } catch (_) {
      return (argsRaw: '', args: args);
    }
  }
  return (argsRaw: '', args: const <String, dynamic>{});
}

/// Flattens model-facing result content blocks to display text.
String flattenResultContent(Object? content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final buf = StringBuffer();
    for (final blk in content) {
      if (blk is Map) {
        final type = blk['type'];
        if (type == 'text' && blk['text'] is String) {
          buf.writeln(blk['text'] as String);
        } else if (type == 'tool-result') {
          final inner = blk['content'];
          final flat = flattenResultContent(inner);
          if (flat.isNotEmpty) buf.writeln(flat);
        } else if (blk['text'] is String) {
          buf.writeln(blk['text'] as String);
        } else if (blk['content'] is String) {
          buf.writeln(blk['content'] as String);
        }
      } else if (blk is String) {
        buf.writeln(blk);
      }
    }
    return buf.toString().trim();
  }
  if (content is Map) {
    final text = content['text'];
    if (text is String) return text;
  }
  return content.toString();
}

/// Decodes one `tool/result` payload: flattened text, error bit, code, meta.
///
/// Canonical shape: `{ message: { content: [...] }, error?: {code}, meta? }`.
/// Legacy/test shapes: `{ result/output/content: ..., isError, error }`.
({String? text, bool isError, String? errorCode, Object? meta}) decodeResult(
  Map<String, dynamic> data,
) {
  final Object? meta = data['meta'];
  final dynamic error = data['error'];
  String? errorCode;
  if (error is Map) {
    final code = error['code'];
    if (code is String) errorCode = code;
  } else if (error is String && error.isNotEmpty) {
    errorCode = error;
  }
  final bool isError =
      (data['isError'] as bool?) ?? error != null || errorCode == 'interrupted';
  String? text;
  final dynamic message = data['message'];
  if (message is Map) {
    final content = message['content'];
    final flat = flattenResultContent(content);
    if (flat.isNotEmpty) text = flat;
  }
  text ??= (() {
    final dynamic direct =
        data['result'] ?? data['output'] ?? data['content'];
    if (direct == null) return null;
    if (direct is String) return direct.isEmpty ? null : direct;
    final flat = flattenResultContent(direct);
    return flat.isEmpty ? null : flat;
  })();
  return (text: text, isError: isError, errorCode: errorCode, meta: meta);
}

/// Fold history entries into a list of [ToolCall]s.
///
/// Joins `tool/call` (seq, args) with the later `tool/result` (status,
/// result) by callId. Unpaired calls stay pending.
List<ToolCall> toolCallsFromHistory(List<HistoryEntry> entries) {
  final Map<String, ToolCall> byId = <String, ToolCall>{};
  final List<String> order = <String>[];

  for (final HistoryEntry entry in entries) {
    final SessionEvent event = entry.event;
    final String type = event.type;
    if (type == 'tool/call' || type == 'tools/call') {
      final String callId =
          (event.data['callId'] as String?) ??
          (event.data['toolCallId'] as String?) ??
          'call-${event.seq}';
      final String toolName =
          (event.data['name'] as String?) ??
          (event.data['tool'] as String?) ??
          'tool';
      final decoded = decodeCallArgs(event.data);
      final ToolCall call = ToolCall(
        id: callId,
        toolName: toolName,
        kind: kindForTool(toolName),
        status: ToolCallStatus.running,
        args: decoded.args,
        argsRaw: decoded.argsRaw,
        view: entry.view,
        time: event.time,
      );
      byId[callId] = call;
      order.add(callId);
    } else if (type == 'tool/result' ||
        type == 'tools/result' ||
        type == 'tool/result/batch') {
      final String callId =
          (event.data['callId'] as String?) ??
          (event.data['toolCallId'] as String?) ??
          '';
      if (callId.isEmpty) continue;
      final ToolCall? existing = byId[callId];
      final decoded = decodeResult(event.data);
      final bool isError = decoded.isError;
      final dynamic result = decoded.text;
      if (existing != null) {
        byId[callId] = ToolCall(
          id: existing.id,
          toolName: existing.toolName,
          kind: existing.kind,
          status: isError ? ToolCallStatus.error : ToolCallStatus.success,
          args: existing.args,
          argsRaw: existing.argsRaw,
          result: result,
          meta: decoded.meta,
          errorCode: decoded.errorCode,
          view: entry.view ?? existing.view,
          time: existing.time,
        );
      } else {
        // Orphan result — synthesize a generic call.
        byId[callId] = ToolCall(
          id: callId,
          toolName: (event.data['name'] as String?) ?? 'tool',
          kind: ToolCallKind.generic,
          status: isError ? ToolCallStatus.error : ToolCallStatus.success,
          args: const {},
          argsRaw: '',
          result: result,
          meta: decoded.meta,
          errorCode: decoded.errorCode,
          view: entry.view,
          time: event.time,
        );
        order.add(callId);
      }
    }
  }

  return <ToolCall>[
    for (final String id in order)
      if (byId[id] != null) byId[id]!,
  ];
}

/// Provider for tool calls of a session.
///
/// Sources from the authoritative `liveHistoryProvider` (session/follow
/// snapshot), not `session/page`. No sentinel probe.
final toolCallsProvider = FutureProvider.family<List<ToolCall>, String>((
  ref,
  sessionId,
) async {
  final live = ref.watch(liveHistoryProvider(sessionId));
  if (live.isEmpty) return const <ToolCall>[];
  return toolCallsFromHistory(live);
});

/// Live tool calls derived from `liveHistoryProvider`.
///
/// Watches the live window and maps via `toolCallsFromHistory`, so
/// tool calls/results appear without a manual refresh (mirrors
/// `ToolCallTree` live updates in `ConversationNode`).
final liveToolCallsProvider = Provider.family<List<ToolCall>, String>((
  ref,
  sessionId,
) {
  // Prefer live history if available, else fall back to one-time fetch.
  final live = ref.watch(liveHistoryProvider(sessionId));
  if (live.isNotEmpty) return toolCallsFromHistory(live);
  final async = ref.watch(toolCallsProvider(sessionId));
  return async.valueOrNull ?? const <ToolCall>[];
});
