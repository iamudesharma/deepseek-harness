/// Todo dock panel — Flutter port of React `TodoPanel.tsx` (`TodoDock`).
///
/// Collapsed-by-default bar above the composer showing the localized title +
/// progress counts, expanding to status-glyphed rows. Source is the host
/// `todos` projection ([todoProjectionProvider], React `useProjection`);
/// while the projection is absent (before the first write) it falls back to
/// the last `todo_write` tool call in the live history window. Empty renders
/// nothing, matching React's dock.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/session/session_models.dart';
import '../../../features/conversation/message_provider.dart'
    show liveHistoryProvider;
import '../../../theme/app_theme.dart';
import '../locales.dart' show kConversationNamespace;
import '../todo_state.dart' show TodoItem, todoProjectionProvider;

/// Derives the current todo list from history: last `todo_write` call args.
///
/// Fallback while the host `todos` projection is absent. Mirrors the
/// tool-card fold's arg sources (`args | arguments | input`, string or map).
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
      final content = (t['content'] ?? t['text'] ?? '').toString();
      final status = (t['status'] ?? 'pending').toString();
      if (content.isNotEmpty) {
        out.add(TodoItem(content: content, status: status));
      }
    }
  }
  return out;
}

/// Fill a `{name}` template (the `Translate` face takes bare keys only).
String _fill(String template, Map<String, String> values) {
  var out = template;
  values.forEach((key, value) {
    out = out.replaceAll('{$key}', value);
  });
  return out;
}

/// Header summary: per-status counts joined with en-space + `·`;
/// zero-count segments omitted (React `progressLabel`).
String progressLabel(List<TodoItem> todos, String Function(String key) t) {
  final done = todos.where((t) => t.status == 'completed').length;
  final active = todos.where((t) => t.status == 'in_progress').length;
  final pending = todos.length - done - active;
  final parts = <String>[];
  if (done > 0) {
    parts.add(_fill(t('todo.progress.done'), {'done': '$done'}));
  }
  if (active > 0) {
    parts.add(_fill(t('todo.progress.active'), {'active': '$active'}));
  }
  if (pending > 0) {
    parts.add(_fill(t('todo.progress.pending'), {'pending': '$pending'}));
  }
  // En spaces (U+2002): HTML collapses runs of ASCII spaces; the separator
  // needs the literal wide space (React progressLabel).
  return parts.join(' · ');
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
    // Projection first (React `TodoDock`), history fallback while absent.
    final projected = ref.watch(todoProjectionProvider(widget.sessionId));
    final history = ref.watch(liveHistoryProvider(widget.sessionId));
    final todos = projected ?? currentTodosFromHistory(history);
    if (todos.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final t = ref.bindLocale(kConversationNamespace);

    // Same horizontal bounds as the composer card below (`composer.dart`:
    // outer `Padding(16,0,16,8)` + `Center` + `ConstrainedBox(maxWidth:780)`
    // + borderless card). The clearance lives outside the cap and the bar
    // fills it, so both edges land exactly on the composer's.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          // React `.root`: 0.5px l1 border, 12px radius, tip-surface fill.
          child: Container(
            decoration: BoxDecoration(
              color: aliases.specificTip,
              borderRadius: BorderRadius.circular(DswTokens.radiusLg),
              border: Border.all(color: aliases.borderL1, width: 0.5),
            ),
            // React `.body`: column, gap 8, padding 6px 12px.
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DswTokens.spaceMd,
                vertical: 6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _collapsed = !_collapsed),
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    child: Row(
                      children: [
                        Icon(
                          Icons.checklist_rounded,
                          size: 14,
                          color: aliases.labelTertiary,
                        ),
                        const SizedBox(width: 10),
                        // React `.title`: 13/24 w500 primary, flex none.
                        Text(
                          t('todo.title'),
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXs13,
                            height: 24 / 13,
                            fontWeight: FontWeight.w500,
                            color: aliases.labelPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // React `.progress`: 13/20 tertiary, ellipsis.
                        Expanded(
                          child: Text(
                            progressLabel(todos, t),
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXs13,
                              height: 20 / 13,
                              color: aliases.labelTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          _collapsed
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 14,
                          color: aliases.labelTertiary,
                        ),
                      ],
                    ),
                  ),
                  if (!_collapsed) ...[
                    const SizedBox(height: DswTokens.spaceSm),
                    // React `.list`: max-height 180px, scrolls inside.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final item in todos)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                // React `.item`: 13/20 secondary, gap 10.
                                child: Row(
                                  children: [
                                    _StatusGlyph(
                                      status: item.status,
                                      aliases: aliases,
                                    ),
                                    const SizedBox(width: 10),
                                    // Figma strip is single-line: long items
                                    // ellipsize with no inline expand.
                                    Expanded(
                                      child: Text(
                                        item.content,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: DswTokens.fontSizeXs13,
                                          height: 20 / 13,
                                          color: aliases.labelSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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
    // React glyphs share the 14px artboard centered in a 16px cell.
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: switch (status) {
            'completed' => Icon(
              Icons.check_circle_outline_rounded,
              size: 14,
              color: aliases.stateSuccessPrimary,
            ),
            'in_progress' => _ProgressRing(color: aliases.stateBusinessPrimary),
            _ => Icon(
              Icons.radio_button_unchecked_rounded,
              size: 14,
              color: aliases.labelCaption,
            ),
          },
        ),
      ),
    );
  }
}

/// In-progress ring: business-blue arc spinning 1s linear infinite
/// (React `.glyphProgress` + `todo-progress-spin`).
class _ProgressRing extends StatefulWidget {
  const _ProgressRing({required this.color});
  final Color color;

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<_ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(painter: _RingPainter(color: widget.color)),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final r = (size.shortestSide - 1.2) / 2;
    // Fading arc (gradient approximated by a 270° sweep); rotation comes
    // from the wrapping RotationTransition.
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: r,
      ),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.color != color;
}
