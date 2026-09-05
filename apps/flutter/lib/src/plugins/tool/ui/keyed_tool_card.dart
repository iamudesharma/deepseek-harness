/// Chat-node renderer face of the tool plugin: adapts the folded
/// [ChatNodeData] onto a [ToolCall] and dispatches through the presentation
/// registry with the generic fallback — the Dart analog of ToolCallTree's
/// single keyed dispatch path (`renderSlot('tool.call.toolview', owner,
/// { entryKey, fallback })` in `ui-tool/src/client/tool/ToolCallTree.tsx`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../conversation/hub.dart' show ChatNodeData, ChatNodeRenderer;
import '../../conversation/locales.dart' show kConversationNamespace;
import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_provider.dart' show currentSessionProvider;
import '../../../core/session/session_models.dart';
import '../../../theme/app_theme.dart';
import '../../deliverables/deliverables_open.dart'
    show canOpenHostPathProvider, openHostPath;
import '../tool_models.dart';
import '../tool_presentation_registry.dart';
import 'tool_call_tree.dart';
import '../presentation/diff_model.dart' as diff_model;
import '../presentation/terminal_model.dart' as terminal_model;
import '../presentation/todo_model.dart' as todo_model;
import '../presentation/tool_row_model.dart' as row_model;

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

/// Resolve a display path back to an absolute host path for the open handoff.
String resolveWorkspacePath(String? cwd, String path) {
  if (path.startsWith('/') ||
      path.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path) ||
      path.startsWith('~')) {
    return path;
  }
  if (cwd == null || cwd.isEmpty) return path;
  final root = cwd.replaceAll(RegExp(r'[/\\]+$'), '');
  return '$root/$path';
}

IconData iconForVariant(row_model.ToolRowVariant variant) => switch (variant) {
  row_model.ToolRowVariant.write ||
  row_model.ToolRowVariant.edit => Icons.edit_outlined,
  row_model.ToolRowVariant.bash => Icons.terminal,
  row_model.ToolRowVariant.read => Icons.article_outlined,
  row_model.ToolRowVariant.search => Icons.search,
  row_model.ToolRowVariant.code => Icons.code_rounded,
  row_model.ToolRowVariant.others => Icons.build_outlined,
};

/// Collapsed summary for one [ToolCall], mirroring React's per-tool rows:
/// - `todo_write` → `N/M completed · active item` (TodoRow);
/// - foreground `bash`/`pwsh` → `description ?? command` (BashRow);
/// - error → the failure first line (ToolRow failureLine);
/// - otherwise the args-derived summary (FileMutationRow/GenericToolCard).
String collapsedSummary(ToolCall call, row_model.ToolRowModel model) {
  if (model.state == row_model.ToolRowState.error && model.errorSummary != null) {
    return model.errorSummary!;
  }
  final name = call.toolName.toLowerCase();
  if (name == 'todo_write') {
    return todo_model.summarizeTodos(call.argsRaw).text;
  }
  if (name == 'bash' || name == 'pwsh') {
    if (!terminal_model.isBackgroundCall(call.argsRaw)) {
      final s = terminal_model.terminalSummary(call.argsRaw);
      if (s.isNotEmpty) return s;
    }
  }
  return model.summary;
}

/// `+N −N` suffix for `write`/`edit` rows, or null when no diff applies.
/// Mirrors React `ToolRow`'s `diffStat` suffix (meta hunks when settled,
/// intended args diff while running / on create).
String? diffStatFor(ToolCall call) {
  final name = call.toolName.toLowerCase();
  if (name != 'write' && name != 'edit' && name != 'str_replace_editor') {
    return null;
  }
  if (call.status == ToolCallStatus.error) return null;
  final diffs = diff_model.diffsFor(
    toolName: call.toolName,
    argsRaw: call.argsRaw,
    running: call.status == ToolCallStatus.running,
    meta: call.meta,
  );
  if (diffs == null || diffs.isEmpty) return null;
  return diff_model.diffStat(diffs);
}

/// One keyed call row: collapsed summary + expand-gated dispatched card body,
/// mirroring ToolRow's unified interaction (the whole row toggles).
class KeyedToolCard extends ConsumerStatefulWidget {
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
  ConsumerState<KeyedToolCard> createState() => _KeyedToolCardState();
}

class _KeyedToolCardState extends ConsumerState<KeyedToolCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final call = toolCallFromChatNode(widget.toolName, widget.data);
    final running = call.status == ToolCallStatus.running;
    final Translate t = ref.bindLocale(kConversationNamespace);
    final SessionSummary? session = ref.watch(currentSessionProvider);
    final String? cwd = session?.cwd;
    final model = row_model.toolRowModel(
      toolName: call.toolName,
      argsRaw: call.argsRaw,
      running: running,
      isError: call.status == ToolCallStatus.error,
      interrupted: call.errorCode == 'interrupted',
      resultText: call.result?.toString(),
      cwd: cwd,
      callId: call.id,
    );
    final String title = rowTitleFor(t, call, model);
    final String summary = collapsedSummary(call, model);
    final String? diffStat = diffStatFor(call);
    final bool expandable = _expandable(call);
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
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
                  call.status == ToolCallStatus.error
                      ? Icons.error_outline
                      : running
                      ? Icons.pending_outlined
                      : iconForVariant(model.variant),
                  size: 14,
                  color: call.status == ToolCallStatus.error
                      ? aliases.stateErrorPrimary
                      : aliases.labelTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: aliases.labelSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 2,
                  height: 2,
                  decoration: BoxDecoration(
                    color: aliases.labelCaption,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SummaryText(
                    call: call,
                    model: model,
                    summary: summary,
                    cwd: cwd,
                  ),
                ),
                if (diffStat != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    diffStat,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'SF Mono',
                      color: aliases.labelTertiary,
                    ),
                  ),
                ],
                if (expandable)
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: aliases.labelTertiary,
                  ),
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

String _titleFor(Translate t, row_model.ToolRowModel model) {
  final localized = t(model.titleKey);
  // The locale service returns the key itself when untranslated.
  if (localized == model.titleKey) return model.titleFallback;
  return localized;
}

/// Row title: `todo_write` owns its row title (React TodoRow), everything
/// else uses the generic variant title.
String rowTitleFor(Translate t, ToolCall call, row_model.ToolRowModel model) {
  if (call.toolName.toLowerCase() == 'todo_write') {
    const key = 'todo.rowTitle';
    final localized = t(key);
    if (localized == key) return 'Update to-do list';
    return localized;
  }
  return _titleFor(t, model);
}

bool _expandable(ToolCall call) {
  final result = call.result?.toString() ?? '';
  if (result.isNotEmpty) return true;
  if (call.argsRaw.isNotEmpty) return true;
  return false;
}

/// Collapsed summary text; file-tool summaries open the host path on tap.
class _SummaryText extends ConsumerWidget {
  const _SummaryText({
    required this.call,
    required this.model,
    required this.summary,
    required this.cwd,
  });

  final ToolCall call;
  final row_model.ToolRowModel model;
  final String summary;
  final String? cwd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final style = TextStyle(fontSize: 13, color: aliases.labelTertiary);
    if (model.filePath == null || model.filePath!.isEmpty) {
      return Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final canOpenAsync = ref.watch(canOpenHostPathProvider);
    final canOpen = canOpenAsync.valueOrNull ?? false;
    return GestureDetector(
      onTap: canOpen
          ? () {
              final client = ref.read(connectionClientProvider);
              final abs = resolveWorkspacePath(cwd, model.filePath!);
              openHostPath(client, abs);
            }
          : null,
      child: Text(
        summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(
          decoration: canOpen ? TextDecoration.underline : TextDecoration.none,
          decorationStyle: TextDecorationStyle.dotted,
        ),
      ),
    );
  }
}

/// Recursive root+subcall row used by the `tool-call` chat-node renderer.
/// Mirrors React's ToolCallBranch: a root row dispatched through the keyed
/// table, then recursively indented subcalls with left border.
class _ToolCallTreeRow extends ConsumerStatefulWidget {
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
  ConsumerState<_ToolCallTreeRow> createState() => _ToolCallTreeRowState();
}

class _ToolCallTreeRowState extends ConsumerState<_ToolCallTreeRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final running = call.status == ToolCallStatus.running;
    final Translate t = ref.bindLocale(kConversationNamespace);
    final SessionSummary? session = ref.watch(currentSessionProvider);
    final String? cwd = session?.cwd;
    final model = row_model.toolRowModel(
      toolName: call.toolName,
      argsRaw: call.argsRaw,
      running: running,
      isError: call.status == ToolCallStatus.error,
      interrupted: call.errorCode == 'interrupted',
      resultText: call.result?.toString(),
      cwd: cwd,
      callId: call.id,
    );
    final String title = rowTitleFor(t, call, model);
    final String summary = collapsedSummary(call, model);
    final String? diffStat = diffStatFor(call);
    final bool expandable =
        (call.result?.toString().isNotEmpty ?? false) ||
        call.argsRaw.isNotEmpty;
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
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
                      : iconForVariant(model.variant),
                  size: 14,
                  color: widget.call.status == ToolCallStatus.error
                      ? aliases.stateErrorPrimary
                      : aliases.labelTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: aliases.labelSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 2,
                  height: 2,
                  decoration: BoxDecoration(
                    color: aliases.labelCaption,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SummaryText(
                    call: call,
                    model: model,
                    summary: summary,
                    cwd: cwd,
                  ),
                ),
                if (diffStat != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    diffStat,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'SF Mono',
                      color: aliases.labelTertiary,
                    ),
                  ),
                ],
                if (expandable)
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: aliases.labelTertiary,
                  ),
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
