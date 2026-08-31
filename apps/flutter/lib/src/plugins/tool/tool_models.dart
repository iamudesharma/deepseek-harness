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

  /// Result payload (string or map), null while pending/running.
  final dynamic result;

  /// Optional view / render intent from host presenter.
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
    this.result,
    this.view,
    required this.time,
  });
}

/// Classify tool name to [ToolCallKind].
ToolCallKind kindForTool(String toolName) {
  final String n = toolName.toLowerCase();
  if (n == 'read' || n == 'str_replace_editor' || n == 'view' || n == 'cat') {
    return ToolCallKind.read;
  }
  if (n == 'edit' || n == 'str_replace' || n == 'diff' || n == 'apply_patch') {
    return ToolCallKind.diff;
  }
  if (n == 'search' || n == 'grep' || n == 'glob' || n == 'find' || n == 'rg') {
    return ToolCallKind.search;
  }
  if (n == 'bash' || n == 'shell' || n == 'terminal' || n == 'exec') {
    return ToolCallKind.bash;
  }
  return ToolCallKind.generic;
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
      final Map<String, dynamic> args =
          (event.data['args'] as Map?)?.cast<String, dynamic>() ??
          (event.data['input'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final ToolCall call = ToolCall(
        id: callId,
        toolName: toolName,
        kind: kindForTool(toolName),
        status: ToolCallStatus.running,
        args: args,
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
      final bool isError = (event.data['isError'] as bool?) ?? false;
      final dynamic result =
          event.data['result'] ?? event.data['output'] ?? event.data['content'];
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
        // Orphan result — synthesize a generic call.
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
