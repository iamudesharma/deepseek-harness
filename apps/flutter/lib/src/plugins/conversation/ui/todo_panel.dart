/// Todo dock panel — Flutter port of React `TodoPanel.tsx` (`TodoDock`).
///
/// Collapsed-by-default bar above the composer showing `To-dos` + progress
/// (`5 completed` / active / pending counts), expanding to status-glyphed
/// rows. Source is the last `todo_write` tool call in the live history
/// window (the host `todos` projection has no Dart face yet); empty renders
/// nothing, matching React's dock.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../features/conversation/message_provider.dart'
    show liveHistoryProvider;
import '../../../theme/app_theme.dart';

/// One todo item for the panel.
class TodoItem {
  const TodoItem({required this.content, required this.status});
  final String content;
  final String status;
}

/// Derives the current todo list from history: last `todo_write` call args.
List<TodoItem> currentTodosFromHistory(List<HistoryEntry> history) {
  Map<String, dynamic>? lastArgs;
  for (final entry in history) {
    final ev = entry.event;
    if (ev.type != 'tool/call') continue;
    final data = ev.data;
    final name = data['name'] as String? ?? data['toolName'] as String?;
    if (name != 'todo_write') continue;
    final dynamic args = data['args'] ?? data['arguments'] ?? data['input'];
    Map<String, dynamic>? map;
    if (args is String) {
      try {
        final parsed = jsonDecode(args);
        if (parsed is Map) {
          map = parsed.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        continue;
      }
    } else if (args is Map) {
      map = args.map((k, v) => MapEntry(k.toString(), v));
    }
    if (map != null && map['todos'] is List) lastArgs = map;
  }
  if (lastArgs == null) return const [];
  final todos = lastArgs['todos'] as List;
  final out = <TodoItem>[];
  for (final t in todos) {
    if (t is Map) {
      final content =
          (t['content'] ?? t['text'] ?? '').toString();
      final status = (t['status'] ?? 'pending').toString();
      if (content.isNotEmpty) {
        out.add(TodoItem(content: content, status: status));
      }
    }
  }
  return out;
}

String _progressLabel(List<TodoItem> todos) {
  final done = todos.where((t) => t.status == 'completed').length;
  final active = todos.where((t) => t.status == 'in_progress').length;
  final pending = todos.length - done - active;
  final parts = <String>[];
  if (done > 0) parts.add('$done completed');
  if (active > 0) parts.add('$active in progress');
  if (pending > 0) parts.add('$pending pending');
  return parts.join(' · ');
}

/// Dock panel for one session, mounted above the composer.
class TodoPanel extends ConsumerStatefulWidget {
  const TodoPanel({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends ConsumerState<TodoPanel> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(liveHistoryProvider(widget.sessionId));
    final todos = currentTodosFromHistory(history);
    if (todos.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            borderRadius: BorderRadius.circular(DswTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.checklist_rounded,
                      size: 14, color: aliases.labelTertiary),
                  const SizedBox(width: 8),
                  Text(
                    'To-dos',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _progressLabel(todos),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _collapsed
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (!_collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  for (final item in todos)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatusGlyph(
                              status: item.status, aliases: aliases),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.content,
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeS14,
                                color: item.status == 'completed'
                                    ? aliases.labelTertiary
                                    : aliases.labelPrimary,
                                decoration: item.status == 'completed'
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.status, required this.aliases});
  final String status;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (status) {
      case 'completed':
        icon = Icons.check_circle_rounded;
        color = aliases.stateSuccessPrimary;
        break;
      case 'in_progress':
        icon = Icons.autorenew_rounded;
        color = aliases.stateBusinessPrimary;
        break;
      default:
        icon = Icons.radio_button_unchecked_rounded;
        color = aliases.labelTertiary;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
