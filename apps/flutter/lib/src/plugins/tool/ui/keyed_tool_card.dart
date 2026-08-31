/// Chat-node renderer face of the tool plugin: adapts the folded
/// [ChatNodeData] onto a [ToolCall] and dispatches through the presentation
/// registry with the generic fallback — the Dart analog of ToolCallTree's
/// single keyed dispatch path (`renderSlot('tool.call.toolview', owner,
/// { entryKey, fallback })` in `ui-tool/src/client/tool/ToolCallTree.tsx`).
///
/// The node fold exposes a tool call to this seam as
/// `ChatNodeData(key: 't<callId>', lines: [callId, ?result])`, so the adapter
/// derives what it can deterministically: one line is a running call, two
/// lines are settled. Error vs success collapses until the fold carries
/// `isError` through lines; args are not part of the chat-node share yet.
library;

import 'package:flutter/material.dart';

import '../../conversation/hub.dart' show ChatNodeData, ChatNodeRenderer;
import '../tool_models.dart';
import '../tool_presentation_registry.dart';
import 'tool_call_tree.dart';

/// Rebuilds the card-facing [ToolCall] from the chat-node share.
ToolCall toolCallFromChatNode(String toolName, ChatNodeData data) {
  // Prefer the folded ToolNode when available (full fidelity: args, status,
  // error, subcalls). Fallback to the lossy lines representation for tests
  // that construct ChatNodeData manually.
  final raw = data.raw;
  if (raw is ToolNodeAdapter) {
    return raw.toToolCall();
  }
  final String callId = data.lines.isNotEmpty ? data.lines.first : data.key;
  final bool settled = data.lines.length > 1;
  // Derive isError from raw if present; otherwise success when settled.
  return ToolCall(
    id: callId,
    toolName: toolName,
    kind: kindForTool(toolName),
    status: settled ? ToolCallStatus.success : ToolCallStatus.running,
    result: settled ? data.lines.sublist(1).join('\n') : null,
    time: 0,
  );
}

/// Minimal adapter for a folded ToolNode so the renderer does not import the
/// full ConversationNode model (avoids circular import). The ChatView passes
/// the ToolNode via ChatNodeData.raw when available.
abstract class ToolNodeAdapter {
  ToolCall toToolCall();
}

/// The generic card used when no presentation claims the tool name — React's
/// `fallback: <GenericToolCard …>` on the keyed dispatch.
Widget genericToolCard(BuildContext context, ToolCall call) =>
    GenericToolCard(call: call);

/// Builds the chat-node renderer registered under [toolName]: every render
/// re-resolves through [presentations] (the keyed-slot dispatch semantics) and
/// falls back to the generic card for an unclaimed name.
ChatNodeRenderer toolCardRenderer(
  ToolPresentationRegistry presentations,
  String toolName,
) {
  return (BuildContext context, ChatNodeData data) {
    final builder = presentations.resolve(toolName) ?? genericToolCard;
    return KeyedToolCard(
      key: ValueKey('toolview:${callKeyOf(data)}'),
      toolName: toolName,
      data: data,
      child: builder(context, toolCallFromChatNode(toolName, data)),
    );
  };
}

/// Builds the `tool-call` chat-node renderer: one entry point that extracts the
/// wire tool name from the node's data and dispatches through the same keyed
/// table with generic fallback (mirrors React's ToolCallTree root composition).
ChatNodeRenderer toolCallTreeRenderer(ToolPresentationRegistry presentations) {
  return (BuildContext context, ChatNodeData data) {
    final String toolName = data.toolName ?? 'tool';
    // If raw carries a full ToolNode, delegate to its adapter for fidelity
    // (preserves args, error, status); otherwise use lossy reconstruction.
    final String callId = data.lines.isNotEmpty ? data.lines.first : data.key;
    // Build the call via the generic path, then let the row handle subcalls
    // when raw is a ToolNodeAdapter that carries children.
    final ToolCall call = toolCallFromChatNode(toolName, data);
    final builder = presentations.resolve(toolName) ?? genericToolCard;
    final Widget card = builder(context, call);
    // When raw is a richer ToolNode (with subcalls), render via the recursive
    // ToolCallTree row that shows subcalls. Otherwise use the simple keyed row.
    final raw = data.raw;
    if (raw is ToolNodeAdapterWithSubCalls) {
      return _ToolCallTreeRow(
        key: ValueKey('tool-call:${data.key}'),
        toolName: toolName,
        data: data,
        call: call,
        card: card,
        subCalls: raw.subCalls,
      );
    }
    return KeyedToolCard(
      key: ValueKey('toolview:${callKeyOf(data)}'),
      toolName: toolName,
      data: data,
      child: card,
    );
  };
}

/// Extension for nodes that carry nested subcalls.
abstract class ToolNodeAdapterWithSubCalls extends ToolNodeAdapter {
  List<ToolSubCallAdapter> get subCalls;
}

abstract class ToolSubCallAdapter {
  String get subCallId;
  String get name;
  bool get isError;
  String? get result;
  List<ToolSubCallAdapter> get children;
}

/// Call identity used for the row value key.
String callKeyOf(ChatNodeData data) =>
    data.lines.isNotEmpty ? data.lines.first : data.key;

/// One keyed call row: collapsed summary + expand-gated dispatched card body,
/// mirroring ToolRow's unified interaction (the whole row toggles).
class KeyedToolCard extends StatefulWidget {
  /// Creates the card row for one folded tool call.
  const KeyedToolCard({
    super.key,
    required this.toolName,
    required this.data,
    required this.child,
  });

  /// Wire tool name this renderer was registered under.
  final String toolName;

  /// Folded chat-node share (callId + optional result line).
  final ChatNodeData data;

  /// The dispatched card body.
  final Widget child;

  @override
  State<KeyedToolCard> createState() => _KeyedToolCardState();
}

class _KeyedToolCardState extends State<KeyedToolCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final call = toolCallFromChatNode(widget.toolName, widget.data);
    final running = call.status == ToolCallStatus.running;
    final result = call.result;
    final expandable = result != null && result.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: expandable ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              children: [
                Icon(
                  running ? Icons.pending_outlined : Icons.check_circle_outline,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(widget.toolName),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    expandable ? result!.split('\n').first : widget.data.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (expandable)
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 14),
              ],
            ),
          ),
        ),
        if (_open && expandable)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: widget.child,
          ),
      ],
    );
  }
}

/// Recursive root+subcall row used by the `tool-call` chat-node renderer.
/// Mirrors React's ToolCallBranch: a root row dispatched through the keyed
/// table, then recursively indented subcalls with left border.
class _ToolCallTreeRow extends StatefulWidget {
  const _ToolCallTreeRow({
    super.key,
    required this.toolName,
    required this.data,
    required this.call,
    required this.card,
    required this.subCalls,
  });

  final String toolName;
  final ChatNodeData data;
  final ToolCall call;
  final Widget card;
  final List<ToolSubCallAdapter> subCalls;

  @override
  State<_ToolCallTreeRow> createState() => _ToolCallTreeRowState();
}

class _ToolCallTreeRowState extends State<_ToolCallTreeRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final running = call.status == ToolCallStatus.running;
    final result = call.result?.toString();
    final expandable =
        (result != null && result.isNotEmpty) || cardHasBody(widget.card);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: expandable ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              children: [
                Icon(
                  widget.call.status == ToolCallStatus.error
                      ? Icons.error_outline
                      : running
                      ? Icons.pending_outlined
                      : Icons.check_circle_outline,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(widget.toolName),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result != null && result.isNotEmpty
                        ? result.split('\n').first
                        : widget.data.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (expandable)
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 14),
              ],
            ),
          ),
        ),
        if (_open && expandable)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: widget.card,
          ),
        if (widget.subCalls.isNotEmpty) _SubCallTree(subCalls: widget.subCalls),
      ],
    );
  }

  bool cardHasBody(Widget card) => true;
}

class _SubCallRow extends StatelessWidget {
  const _SubCallRow({required this.sub});

  final ToolSubCallAdapter sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            sub.isError ? Icons.error_outline : Icons.code_rounded,
            size: 12,
            color: sub.isError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).textTheme.bodySmall?.color
                      ?.withOpacity(0.7),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub.result != null && sub.result!.isNotEmpty)
                  Text(
                    sub.result!,
                    style: TextStyle(
                      fontSize: 11,
                      color: sub.isError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).textTheme.bodySmall?.color
                                ?.withOpacity(0.6),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubCallTree extends StatelessWidget {
  const _SubCallTree({required this.subCalls});
  final List<ToolSubCallAdapter> subCalls;
  @override
  Widget build(BuildContext context) {
    if (subCalls.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 4, 0, 2),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sub in subCalls) ...[
            _SubCallRow(sub: sub),
            if (sub.children.isNotEmpty) _SubCallTree(subCalls: sub.children),
          ],
        ],
      ),
    );
  }
}
