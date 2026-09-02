import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/session_provider.dart';
import '../../../core/session/session_models.dart';
import '../../../features/conversation/message_provider.dart'
    show liveHistoryProvider, liveHasMoreProvider, liveLoadingOlderProvider;
import '../../../theme/app_theme.dart';
import '../../../theme/motion.dart';
import '../../../widgets/primitives/json_tree.dart';
import '../../../widgets/primitives/markdown.dart';
import '../../tool/tool_models.dart';
import '../trajectory_provider.dart';

// ---------------------------------------------------------------------------
// Trajectory view — parity with React ui-trajectory
// ---------------------------------------------------------------------------
// Ports: TrajectoryView.tsx (toolbar + timeline + ledger split),
// TrajectoryToolbar.tsx, TrajectoryTimeline.tsx + .module.css,
// TrajectoryTable.tsx + .module.css (ledger), views.module.css (root/ledger).
// Visual contract: 32px toolbar, 50px 3-lane timeline, 30px ledger rows
// (122px Event + flex Content), kind pills (76->19 @620), turnRail 2px
// accent, selectionRail 3px, request dots, collapsed summaries, search dim,
// timeline<->ledger selection, viewport 180ms, hover 120ms, spinner 700ms.
// ---------------------------------------------------------------------------

/// Closed set of ledger row kinds — mirrors `TrajectoryCellKind`.
enum TrajectoryCellKind {
  system,
  user,
  context,
  compacted,
  message,
  tool,
  subtool,
}

/// One ledger row — Dart mirror of `TrajectoryCellProps` essentials.
class LedgerRow {
  final int index;
  final TrajectoryCellKind kind;
  final String text;
  final String? previewMarkdown;
  final String? inputDetail;
  final String? outputDetail;
  final String? thinkingDetail;
  final List<ToolCall>? toolCallsInline;
  final String? result;
  final bool isError;
  final double? timeSeconds;
  final int? startedAt;
  final String? callId;
  final int turn;
  final String group;
  final bool turnStart;
  final bool turnEnd;
  final bool groupStart;
  final bool isCollapsedSummary;
  final String? collapsedSummary;

  const LedgerRow({
    required this.index,
    required this.kind,
    required this.text,
    this.previewMarkdown,
    this.inputDetail,
    this.outputDetail,
    this.thinkingDetail,
    this.toolCallsInline,
    this.result,
    this.isError = false,
    this.timeSeconds,
    this.startedAt,
    this.callId,
    required this.turn,
    required this.group,
    this.turnStart = false,
    this.turnEnd = false,
    this.groupStart = false,
    this.isCollapsedSummary = false,
    this.collapsedSummary,
  });
}

String _extractText(Map<String, dynamic> data) {
  final dynamic content = data['content'];
  if (content is String) return content;
  if (content is List) {
    final sb = StringBuffer();
    for (final blk in content) {
      if (blk is Map) {
        final String? t = blk['text'] as String? ?? blk['content'] as String?;
        if (t != null) sb.writeln(t);
      } else if (blk is String) sb.writeln(blk);
    }
    final s = sb.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return (data['text'] as String?) ??
      (data['message'] as String?) ??
      (data['prompt'] as String?) ??
      '';
}

String _previewFor(String full, int maxLen) {
  if (full.length <= maxLen) return full;
  return '${full.substring(0, maxLen - 1)}…';
}

// Derive ledger rows from HistoryEntry window — approximates
// `deriveTrajectoryLayout` + `flattenRecords` for Flutter's host history.
List<LedgerRow> _ledgerFromHistory(List<HistoryEntry> entries) {
  if (entries.isEmpty) return const [];
  final rows = <LedgerRow>[];
  int idx = 0;
  final hasEnvelope = entries.any((e) => e.event.type == 'turn/start');
  final List<int> userSeqs = entries
      .where((e) => e.event.type == 'user/message')
      .map((e) => e.event.seq)
      .toList();

  int turnForSeq(int seq) {
    if (hasEnvelope) {
      int startsSeen = 0;
      for (final e in entries) {
        if (e.event.type == 'turn/start' && e.event.seq <= seq) {
          startsSeen += 1;
        }
      }
      if (startsSeen > 0) return startsSeen.clamp(1, 1 << 30);
      return 1;
    } else {
      if (userSeqs.isEmpty) return 1;
      for (int i = userSeqs.length - 1; i >= 0; i--) {
        if (seq >= userSeqs[i]) return i + 1;
      }
      return 1;
    }
  }

  final Map<int, int> turnGroupCounter = {};
  for (final entry in entries) {
    final ev = entry.event;
    final type = ev.type;
    if (type == 'turn/start') {
      continue;
    }
    if (type == 'turn/end' || type == 'turn/error') {
      continue;
    }
    TrajectoryCellKind kind;
    String text = '';
    String? inputDetail;
    String? outputDetail;
    String? thinkingDetail;
    String? preview;
    bool isError = ev.data['isError'] == true;
    String? callId;
    String? result;
    switch (type) {
      case 'user/message':
        {
          final src = ev.data['source'];
          final srcKind = src is Map ? src['kind'] as String? : null;
          if (srcKind == 'user') {
            kind = TrajectoryCellKind.user;
          } else {
            kind = TrajectoryCellKind.context;
          }
          final String t = _extractText(ev.data);
          text = _previewFor(t.isEmpty ? '(empty message)' : t, 160);
          inputDetail = t;
          if (kind == TrajectoryCellKind.context) {
            preview = t;
          }
          break;
        }
      case 'assistant/message':
        {
          kind = TrajectoryCellKind.message;
          final msg = ev.data['message'] is Map
              ? (ev.data['message'] as Map).cast<String, dynamic>()
              : ev.data;
          final String t = _extractText(msg);
          text = _previewFor(t.isEmpty ? '' : t, 160);
          outputDetail = t;
          final rawContent = msg['content'];
          if (rawContent is List) {
            for (final blk in rawContent) {
              if (blk is Map && blk['type'] == 'reasoning' && blk['text'] is String) {
                thinkingDetail = (thinkingDetail ?? '') + (blk['text'] as String) + '\n';
              }
            }
            if (thinkingDetail != null) thinkingDetail = thinkingDetail.trim();
          }
          preview = t;
          break;
        }
      case 'assistant/chunk':
        {
          kind = TrajectoryCellKind.message;
          final raw = ev.data['chunk'] ?? ev.data['delta'] ?? ev.data['text'];
          String delta = '';
          if (raw is String) delta = raw;
          else if (raw is Map) delta = (raw['text'] as String?) ?? (raw['delta'] as String?) ?? '';
          if (delta.isEmpty) continue;
          text = _previewFor(delta, 160);
          preview = delta;
          break;
        }
      case 'tool/call':
        {
          kind = TrajectoryCellKind.tool;
          final String name = (ev.data['name'] as String?) ??
              (ev.data['toolName'] as String?) ??
              'tool';
          final dynamic args = ev.data['args'] ?? ev.data['arguments'] ?? ev.data['input'];
          String argsText = '';
          if (args is String) argsText = args;
          else if (args is Map || args is List) {
            try { argsText = jsonEncode(args); } catch (_) { argsText = '$args'; }
          }
          callId = ev.data['callId'] as String? ?? ev.data['id'] as String?;
          text = argsText.isEmpty ? name : '$name · ${_previewFor(argsText, 120)}';
          inputDetail = argsText;
          break;
        }
      case 'tool/result':
        {
          kind = TrajectoryCellKind.tool;
          final String name = (ev.data['name'] as String?) ?? 'tool';
          final dynamic out = ev.data['output'] ?? ev.data['result'] ?? ev.data['content'];
          String outText = '';
          if (out is String) outText = out;
          else if (out != null) {
            try { outText = jsonEncode(out); } catch (_) { outText = '$out'; }
          }
          callId = ev.data['callId'] as String? ?? ev.data['id'] as String?;
          text = outText.isEmpty ? name : '$name · ${_previewFor(outText, 120)}';
          result = outText;
          isError = ev.data['isError'] == true || ev.data['error'] != null;
          break;
        }
      case 'compaction/start':
      case 'compaction/end':
      case 'compaction/summary':
      case 'compaction/prune':
        kind = TrajectoryCellKind.compacted;
        text = (ev.data['summary'] as String?) ?? type;
        preview = ev.data['summary'] as String?;
        break;
      case 'request/header':
      case 'session/title':
      case 'session/title-llm-request':
      case 'model/selection':
        kind = TrajectoryCellKind.system;
        text = _previewFor(_extractText(ev.data).isEmpty ? type : _extractText(ev.data), 160);
        inputDetail = jsonEncode(ev.data);
        break;
      case 'llm/retry':
        kind = TrajectoryCellKind.system;
        final retry = ev.data['retry'];
        final maxRetries = ev.data['maxRetries'];
        text = 'retry $retry/${maxRetries ?? '?'}';
        break;
      default:
        if (type.startsWith('system') || type == 'session/end-seed') {
          kind = TrajectoryCellKind.system;
        } else if (type.contains('context') || type == 'request/context') {
          kind = TrajectoryCellKind.context;
        } else {
          kind = TrajectoryCellKind.system;
        }
        final String t = _extractText(ev.data);
        text = t.isEmpty ? type : _previewFor(t, 160);
        if (t.isNotEmpty) preview = t;
        break;
    }

    final int turn = turnForSeq(ev.seq);
    final int gcount = (turnGroupCounter[turn] ?? 0) + 1;
    turnGroupCounter[turn] = gcount;
    final bool isFirstInTurn = rows.isEmpty || rows.last.turn != turn;
    final bool isGroupStart = isFirstInTurn;

    final int? startedAt = ev.time;
    double? timeSeconds;

    final row = LedgerRow(
      index: idx++,
      kind: kind,
      text: text,
      previewMarkdown: preview,
      inputDetail: inputDetail,
      outputDetail: outputDetail,
      thinkingDetail: thinkingDetail,
      isError: isError,
      timeSeconds: timeSeconds,
      startedAt: startedAt,
      callId: callId,
      result: result,
      turn: turn,
      group: 'Turn $turn',
      turnStart: isFirstInTurn,
      groupStart: isGroupStart,
    );
    rows.add(row);
  }

  for (int i = 0; i < rows.length; i++) {
    final cur = rows[i];
    final next = i + 1 < rows.length ? rows[i + 1] : null;
    final bool isLastInTurn = next == null || next.turn != cur.turn;
    if (isLastInTurn) {
      rows[i] = LedgerRow(
        index: cur.index,
        kind: cur.kind,
        text: cur.text,
        previewMarkdown: cur.previewMarkdown,
        inputDetail: cur.inputDetail,
        outputDetail: cur.outputDetail,
        thinkingDetail: cur.thinkingDetail,
        isError: cur.isError,
        timeSeconds: cur.timeSeconds,
        startedAt: cur.startedAt,
        callId: cur.callId,
        result: cur.result,
        turn: cur.turn,
        group: cur.group,
        turnStart: cur.turnStart,
        turnEnd: true,
        groupStart: cur.groupStart,
      );
    }
  }

  return List<LedgerRow>.unmodifiable(rows);
}

/// Flutter timeline model — mirrors `deriveTrajectoryTimeline`.
class TimelineModel {
  final int start;
  final int end;
  final List<TimelineSpan> spans;
  final List<TurnBoundary> boundaries;
  const TimelineModel({required this.start, required this.end, required this.spans, required this.boundaries});
}

class TimelineSpan {
  final int index;
  final TrajectoryCellKind kind;
  final int lane;
  final int start;
  final int end;
  final bool isError;
  const TimelineSpan({required this.index, required this.kind, required this.lane, required this.start, required this.end, this.isError = false});
}

class TurnBoundary {
  final int turn;
  final int time;
  const TurnBoundary({required this.turn, required this.time});
}

int _laneForKind(TrajectoryCellKind k) => switch (k) {
  TrajectoryCellKind.user => 0,
  TrajectoryCellKind.context => 0,
  TrajectoryCellKind.system => 0,
  TrajectoryCellKind.compacted => 1,
  TrajectoryCellKind.message => 1,
  TrajectoryCellKind.tool => 2,
  TrajectoryCellKind.subtool => 2,
};

TimelineModel? deriveTimeline(List<LedgerRow> rows, String mode) {
  if (rows.isEmpty) return null;
  final bool equal = mode == 'time' || mode == 'sequence';
  int start;
  int end;
  if (equal) {
    start = 0;
    end = rows.length * 10;
    final spans = <TimelineSpan>[];
    for (final r in rows) {
      final int s = r.index * 10;
      final int e = s + 8;
      spans.add(TimelineSpan(index: r.index, kind: r.kind, lane: _laneForKind(r.kind), start: s, end: e, isError: r.isError));
    }
    final boundaries = <TurnBoundary>[];
    for (int i = 1; i < rows.length; i++) {
      if (rows[i].turn != rows[i - 1].turn) {
        boundaries.add(TurnBoundary(turn: rows[i].turn, time: rows[i].index * 10));
      }
    }
    return TimelineModel(start: start, end: end, spans: spans, boundaries: boundaries);
  } else {
    int minT = rows.first.startedAt ?? 0;
    int maxT = rows.last.startedAt ?? minT;
    if (maxT == minT) maxT = minT + (rows.length * 1000);
    start = minT;
    end = maxT + 1000;
    final spans = <TimelineSpan>[];
    for (final r in rows) {
      final s = r.startedAt ?? minT;
      final dur = (r.timeSeconds != null ? (r.timeSeconds! * 1000).round() : 800);
      final e = s + dur;
      spans.add(TimelineSpan(index: r.index, kind: r.kind, lane: _laneForKind(r.kind), start: s, end: e, isError: r.isError));
    }
    final boundaries = <TurnBoundary>[];
    for (int i = 1; i < rows.length; i++) {
      if (rows[i].turn != rows[i - 1].turn) {
        boundaries.add(TurnBoundary(turn: rows[i].turn, time: rows[i].startedAt ?? start));
      }
    }
    return TimelineModel(start: start, end: end, spans: spans, boundaries: boundaries);
  }
}

// ---------------------------------------------------------------------------
// TrajectoryScreen — new ledger-style chrome
// ---------------------------------------------------------------------------

class TrajectoryScreen extends ConsumerWidget {
  const TrajectoryScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final AsyncValue<Trajectory> async = ref.watch(
      trajectoryProvider(sessionId),
    );
    final SessionSummary? summary = ref.watch(
      sessionByIdProvider(SessionId(sessionId)),
    );
    final List<HistoryEntry> history = ref.watch(liveHistoryProvider(sessionId));
    final bool hasMore = ref.watch(liveHasMoreProvider(sessionId));
    final bool loadingOlder = ref.watch(liveLoadingOlderProvider(sessionId));

    return Scaffold(
      backgroundColor: aliases.bgLayer1,
      appBar: AppBar(
        backgroundColor: aliases.bgLayer1,
        title: Text(
          summary == null
              ? 'Trajectory · $sessionId'
              : summary.blank
              ? 'New session'
              : summary.displayTitle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        leading: IconButton(
          tooltip: 'Back to conversation',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/sessions/$sessionId'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () {
              ref.invalidate(trajectoryProvider(sessionId));
              ref.read(liveHistoryProvider(sessionId).notifier).replaceAll(history);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: async.when(
        data: (Trajectory trajectory) {
          final List<LedgerRow> rows = _ledgerFromHistory(history);
          final bool empty = rows.isEmpty && trajectory.turns.isEmpty;
          if (empty) {
            return _EmptyTrajectory(sessionId: sessionId, aliases: aliases);
          }
          final List<LedgerRow> effectiveRows = rows.isEmpty
              ? _rowsFromTrajectoryTurns(trajectory)
              : rows;
          return _TrajectoryPane(
            sessionId: sessionId,
            trajectory: trajectory,
            rows: effectiveRows,
            hasMore: hasMore,
            loadingOlder: loadingOlder,
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: aliases.labelTertiary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceMd),
              Text(
                'Loading trajectory…',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  color: aliases.labelSecondary,
                ),
              ),
            ],
          ),
        ),
        error: (Object err, StackTrace st) => _ErrorState(
          error: err.toString(),
          aliases: aliases,
          onRetry: () => ref.invalidate(trajectoryProvider(sessionId)),
        ),
      ),
    );
  }
}

List<LedgerRow> _rowsFromTrajectoryTurns(Trajectory trajectory) {
  final rows = <LedgerRow>[];
  int idx = 0;
  for (final turn in trajectory.turns) {
    rows.add(LedgerRow(
      index: idx++,
      kind: TrajectoryCellKind.user,
      text: turn.title.isEmpty ? 'Turn ${turn.ordinal}' : turn.title,
      previewMarkdown: turn.title,
      turn: turn.ordinal,
      group: 'Turn ${turn.ordinal}',
      turnStart: true,
    ));
    if (turn.summary != null && turn.summary!.isNotEmpty) {
      rows.add(LedgerRow(
        index: idx++,
        kind: TrajectoryCellKind.message,
        text: turn.summary!,
        previewMarkdown: turn.summary,
        turn: turn.ordinal,
        group: 'Turn ${turn.ordinal}',
      ));
    }
    for (final c in turn.toolCalls) {
      rows.add(LedgerRow(
        index: idx++,
        kind: TrajectoryCellKind.tool,
        text: '${c.toolName} · ${c.status.name}',
        result: c.result is String ? c.result as String : null,
        isError: c.status == ToolCallStatus.error,
        turn: turn.ordinal,
        group: 'Turn ${turn.ordinal}',
      ));
    }
    if (rows.isNotEmpty) {
      final last = rows.last;
      rows[rows.length - 1] = LedgerRow(
        index: last.index,
        kind: last.kind,
        text: last.text,
        previewMarkdown: last.previewMarkdown,
        turn: last.turn,
        group: last.group,
        turnStart: last.turnStart,
        turnEnd: true,
      );
    }
  }
  return rows;
}

class _TrajectoryPane extends ConsumerStatefulWidget {
  const _TrajectoryPane({
    required this.sessionId,
    required this.trajectory,
    required this.rows,
    required this.hasMore,
    required this.loadingOlder,
  });
  final String sessionId;
  final Trajectory trajectory;
  final List<LedgerRow> rows;
  final bool hasMore;
  final bool loadingOlder;

  @override
  ConsumerState<_TrajectoryPane> createState() => _TrajectoryPaneState();
}

class _TrajectoryPaneState extends ConsumerState<_TrajectoryPane> {
  bool actualDuration = false;
  bool actualTime = false;
  Set<int> collapsedTurns = {};
  Set<String> collapsedAssistants = {};
  String searchQuery = '';
  int? selectedIndex;
  _TimeRange? timelineSelection;
  int? pendingFocusIndex;
  final ScrollController _scrollController = ScrollController();

  String get timelineMode {
    if (actualDuration) return actualTime ? 'actual' : 'duration';
    return actualTime ? 'time' : 'sequence';
  }

  List<LedgerRow> get _filteredRows {
    if (searchQuery.trim().isEmpty) return widget.rows;
    final q = searchQuery.toLowerCase();
    return widget.rows.where((r) => r.text.toLowerCase().contains(q) || (r.previewMarkdown?.toLowerCase().contains(q) ?? false)).toList();
  }

  Set<int> get _searchMatchIndexes {
    if (searchQuery.trim().isEmpty) return {};
    final q = searchQuery.toLowerCase();
    return widget.rows
        .where((r) => r.text.toLowerCase().contains(q))
        .map((r) => r.index)
        .toSet();
  }

  List<LedgerRow> get _collapsedRows {
    final filtered = _filteredRows;
    final Map<int, List<LedgerRow>> byTurn = {};
    for (final r in filtered) {
      byTurn.putIfAbsent(r.turn, () => []).add(r);
    }
    final out = <LedgerRow>[];
    for (final r in filtered) {
      if (collapsedTurns.contains(r.turn)) {
        final turnRows = byTurn[r.turn]!;
        final first = turnRows.first;
        if (r.index != first.index) {
          if (r.index == turnRows[1].index) {
            final int steps = 1;
            final int toolCalls = turnRows.where((x) => x.kind == TrajectoryCellKind.tool || x.kind == TrajectoryCellKind.subtool).length;
            out.add(LedgerRow(
              index: r.index,
              kind: r.kind,
              text: '',
              turn: r.turn,
              group: r.group,
              isCollapsedSummary: true,
              collapsedSummary: '$steps step${steps == 1 ? '' : 's'} · $toolCalls tool call${toolCalls == 1 ? '' : 's'}',
            ));
          }
          continue;
        }
      }
      out.add(r);
    }
    return out;
  }

  Set<int>? get timelineFocusIndexes {
    final sel = timelineSelection;
    if (sel == null) return null;
    final model = deriveTimeline(widget.rows, timelineMode);
    if (model == null) return null;
    final s = sel.start;
    final e = sel.end;
    final result = <int>{};
    for (final span in model.spans) {
      if (span.end >= s && span.start <= e) result.add(span.index);
    }
    return result;
  }

  bool get allTurnsCollapsed {
    final collapsible = widget.rows.map((e) => e.turn).toSet().where((t) {
      final count = widget.rows.where((r) => r.turn == t).length;
      return count > 1;
    }).toSet();
    if (collapsible.isEmpty) return false;
    return collapsible.every((t) => collapsedTurns.contains(t));
  }

  bool get allAssistantsCollapsed {
    return collapsedAssistants.isNotEmpty;
  }

  void _toggleAllTurns() {
    setState(() {
      final collapsible = widget.rows.map((e) => e.turn).toSet().where((t) => widget.rows.where((r) => r.turn == t).length > 1).toSet();
      if (allTurnsCollapsed) {
        collapsedTurns = {};
      } else {
        collapsedTurns = Set<int>.from(collapsible);
      }
    });
  }

  void _toggleAllAssistants() {
    setState(() {
      if (allAssistantsCollapsed) {
        collapsedAssistants = {};
      } else {
        final ids = <String>{};
        for (int i = 0; i < widget.rows.length; i++) {
          final r = widget.rows[i];
          if (r.kind == TrajectoryCellKind.message) {
            final next = i + 1 < widget.rows.length ? widget.rows[i + 1] : null;
            if (next != null && (next.kind == TrajectoryCellKind.tool || next.kind == TrajectoryCellKind.subtool)) {
              ids.add('msg-${r.index}');
            }
          }
        }
        collapsedAssistants = ids;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final rows = _collapsedRows;
    final searchMatches = searchQuery.isEmpty ? null : _searchMatchIndexes;

    return Container(
      color: aliases.bgLayer1,
      child: Column(
        children: [
          _TrajectoryHeader(trajectory: widget.trajectory, aliases: aliases),
          Divider(height: 1, color: aliases.borderL2),
          _TrajectoryToolbar(
            actualDuration: actualDuration,
            onActualDurationChange: (v) {
              setState(() {
                actualDuration = v;
                timelineSelection = null;
              });
            },
            actualTime: actualTime,
            onActualTimeChange: (v) => setState(() {
              actualTime = v;
              timelineSelection = null;
            }),
            allTurnsCollapsed: allTurnsCollapsed,
            onToggleAllTurns: _toggleAllTurns,
            allAssistantsCollapsed: allAssistantsCollapsed,
            onToggleAllAssistants: _toggleAllAssistants,
            searchQuery: searchQuery,
            onSearchQueryChange: (q) => setState(() => searchQuery = q),
          ),
          Divider(height: 1, color: aliases.borderL2),
          _TrajectoryTimelineStrip(
            rows: widget.rows,
            mode: timelineMode,
            range: timelineSelection,
            hasEarlierRecords: widget.hasMore,
            onLoadEarlier: widget.hasMore
                ? () async {
                    await ref.read(liveHistoryProvider(widget.sessionId).notifier).loadOlder();
                    return true;
                  }
                : null,
            selectedIndex: selectedIndex,
            searchMatchIndexes: searchMatches,
            onRangeChange: (r) => setState(() => timelineSelection = r),
            onRecordSelect: (idx) {
              setState(() {
                timelineSelection = null;
                selectedIndex = idx;
              });
              _scrollToIndex(idx);
            },
            onRecordFocus: (idx) {
              setState(() => pendingFocusIndex = idx);
              _scrollToIndex(idx);
            },
          ),
          Divider(height: 1, color: aliases.borderL2),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final bool wide = constraints.maxWidth > 760;
              final ledger = _TrajectoryLedger(
                rows: rows,
                allRows: widget.rows,
                searchMatchIndexes: searchMatches,
                timelineFocusIndexes: timelineFocusIndexes,
                selectedIndex: selectedIndex,
                onSelectedIndexChange: (idx) => setState(() => selectedIndex = idx),
                onRecordSelect: (idx) {
                  final focus = timelineFocusIndexes;
                  if (focus != null && !focus.contains(idx)) {
                    setState(() => timelineSelection = null);
                  }
                  setState(() => selectedIndex = idx);
                },
                collapsedTurns: collapsedTurns,
                onToggleTurn: (turn) {
                  setState(() {
                    if (collapsedTurns.contains(turn)) collapsedTurns.remove(turn);
                    else collapsedTurns.add(turn);
                  });
                },
                historyLoading: false,
                olderHistoryLoading: widget.loadingOlder,
                hasOlderRecords: widget.hasMore,
                onLoadOlder: () => ref.read(liveHistoryProvider(widget.sessionId).notifier).loadOlder(),
                scrollController: _scrollController,
                pendingFocusIndex: pendingFocusIndex,
                onFocusConsumed: () => pendingFocusIndex = null,
              );
              if (wide && selectedIndex != null) {
                final LedgerRow selRow = widget.rows.firstWhere((r) => r.index == selectedIndex, orElse: () => rows.firstWhere((r) => r.index == selectedIndex, orElse: () => widget.rows.first));
                return Row(
                  children: [
                    Expanded(child: ledger),
                    Container(width: 1, color: aliases.borderL2),
                    SizedBox(
                      width: 380,
                      child: _DetailsPane(row: selRow, onClose: () => setState(() => selectedIndex = null)),
                    ),
                  ],
                );
              }
              return ledger;
            }),
          ),
          if (selectedIndex != null)
            LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth > 760) return const SizedBox.shrink();
              final LedgerRow selRow = widget.rows.firstWhere((r) => r.index == selectedIndex, orElse: () => rows.firstWhere((r) => r.index == selectedIndex, orElse: () => widget.rows.first));
              return _DetailsPane(row: selRow, onClose: () => setState(() => selectedIndex = null));
            }),
          _TrajectoryFooter(trajectory: widget.trajectory, rows: widget.rows),
        ],
      ),
    );
  }

  void _scrollToIndex(int idx) {
    final rows = _collapsedRows;
    final pos = rows.indexWhere((r) => r.index == idx);
    if (pos == -1) return;
    final offset = pos * 30.0;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: prefersReducedMotion(context) ? Duration.zero : const Duration(milliseconds: 180),
        curve: DswTokens.easeInOut,
      );
    }
  }
}

class _TimeRange {
  final int start;
  final int end;
  const _TimeRange(this.start, this.end);
}

class _TrajectoryToolbar extends StatelessWidget {
  const _TrajectoryToolbar({
    required this.actualDuration,
    required this.onActualDurationChange,
    required this.actualTime,
    required this.onActualTimeChange,
    required this.allTurnsCollapsed,
    required this.onToggleAllTurns,
    required this.allAssistantsCollapsed,
    required this.onToggleAllAssistants,
    required this.searchQuery,
    required this.onSearchQueryChange,
  });

  final bool actualDuration;
  final ValueChanged<bool> onActualDurationChange;
  final bool actualTime;
  final ValueChanged<bool> onActualTimeChange;
  final bool allTurnsCollapsed;
  final VoidCallback onToggleAllTurns;
  final bool allAssistantsCollapsed;
  final VoidCallback onToggleAllAssistants;
  final String searchQuery;
  final ValueChanged<String> onSearchQueryChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      height: 32,
      color: aliases.bgLayer1,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolbarToggle(
                label: 'Duration',
                pressed: actualDuration,
                tooltip: actualDuration ? 'Use equal width' : 'Use actual duration',
                onTap: () => onActualDurationChange(!actualDuration),
                icon: _ClockIcon(active: actualDuration),
              ),
              const SizedBox(width: 2),
              _ToolbarAction(
                label: 'Turns',
                pressed: allTurnsCollapsed,
                icon: Text(allTurnsCollapsed ? '⊞' : '⊟', style: TextStyle(fontSize: 14, color: aliases.labelTertiary, fontFamily: DswTokens.fontFamilyCode)),
                onTap: onToggleAllTurns,
              ),
              const SizedBox(width: 2),
              _ToolbarAction(
                label: 'Calls',
                pressed: allAssistantsCollapsed,
                icon: Text(allAssistantsCollapsed ? '⊞' : '⊟', style: TextStyle(fontSize: 14, color: aliases.labelTertiary, fontFamily: DswTokens.fontFamilyCode)),
                onTap: onToggleAllAssistants,
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 164,
            height: 22,
            decoration: BoxDecoration(
              color: aliases.bgLayer2,
              border: Border.all(color: aliases.borderL2),
              borderRadius: BorderRadius.circular(DswTokens.radiusXs),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Icon(Icons.search, size: 11, color: aliases.labelCaption),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: searchQuery)
                      ..selection = TextSelection.collapsed(offset: searchQuery.length),
                    onChanged: onSearchQueryChange,
                    style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search',
                      hintStyle: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelCaption),
                      contentPadding: EdgeInsets.zero,
                    ),
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

class _ToolbarToggle extends StatelessWidget {
  const _ToolbarToggle({required this.label, required this.pressed, required this.tooltip, required this.onTap, required this.icon});
  final String label;
  final bool pressed;
  final String tooltip;
  final VoidCallback onTap;
  final Widget icon;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DswTokens.radiusXs),
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: pressed ? aliases.interactiveBgHover : DswTokens.transparent,
            borderRadius: BorderRadius.circular(DswTokens.radiusXs),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: pressed ? aliases.labelPrimary : aliases.labelTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({required this.label, required this.pressed, required this.icon, required this.onTap});
  final String label;
  final bool pressed;
  final Widget icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DswTokens.radiusXs),
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary)),
          ],
        ),
      ),
    );
  }
}

class _ClockIcon extends StatelessWidget {
  const _ClockIcon({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: CustomPaint(painter: _ClockPainter()),
    );
  }
}

class _ClockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.25..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    paint.color = const Color(0xFF888888);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 5.25;
    canvas.drawCircle(center, radius, paint);
    final path = Path()
      ..moveTo(center.dx, center.dy - 3.25)
      ..lineTo(center.dx, center.dy)
      ..lineTo(center.dx + 2.25, center.dy + 1.5);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TrajectoryTimelineStrip extends StatefulWidget {
  const _TrajectoryTimelineStrip({
    required this.rows,
    required this.mode,
    required this.range,
    required this.hasEarlierRecords,
    required this.onLoadEarlier,
    required this.selectedIndex,
    required this.searchMatchIndexes,
    required this.onRangeChange,
    required this.onRecordSelect,
    required this.onRecordFocus,
  });

  final List<LedgerRow> rows;
  final String mode;
  final _TimeRange? range;
  final bool hasEarlierRecords;
  final Future<bool> Function()? onLoadEarlier;
  final int? selectedIndex;
  final Set<int>? searchMatchIndexes;
  final ValueChanged<_TimeRange?> onRangeChange;
  final ValueChanged<int> onRecordSelect;
  final ValueChanged<int> onRecordFocus;

  @override
  State<_TrajectoryTimelineStrip> createState() => _TrajectoryTimelineStripState();
}

class _TrajectoryTimelineStripState extends State<_TrajectoryTimelineStrip> {
  _TimeRange? _draft;
  double? _hoverFraction;
  int? _hoverRecord;
  bool _loadingEarlier = false;
  TimelineModel? _model;
  int? _viewportStart;
  int? _viewportEnd;
  bool _animateViewport = false;
  double? _dragAnchorClientX;
  int? _dragAnchorTime;
  int? _dragRecordIndex;

  @override
  void didUpdateWidget(covariant _TrajectoryTimelineStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows != widget.rows || oldWidget.mode != widget.mode) {
      _model = deriveTimeline(widget.rows, widget.mode);
    }
  }

  @override
  void initState() {
    super.initState();
    _model = deriveTimeline(widget.rows, widget.mode);
  }

  TimelineModel? get model => _model ?? deriveTimeline(widget.rows, widget.mode);

  int get fullDuration {
    final m = model;
    if (m == null) return 1;
    return (m.end - m.start).abs().clamp(1, 1 << 30);
  }

  int get domainStart {
    final m = model;
    if (m == null) return 0;
    if (_viewportStart != null && _viewportEnd != null) return _viewportStart!;
    return m.start;
  }

  int get domainDuration {
    final m = model;
    if (m == null) return 1;
    if (_viewportStart != null && _viewportEnd != null) return (_viewportEnd! - _viewportStart!).abs().clamp(1, 1 << 30);
    return (m.end - m.start).abs().clamp(1, 1 << 30);
  }

  double _fractionAt(double clientX, double width) {
    if (width <= 1) return 0;
    return (clientX / width).clamp(0.0, 1.0);
  }

  int? _recordIndexAt(Offset localPosition, double width) {
    final m = model;
    if (m == null) return null;
    final frac = _fractionAt(localPosition.dx, width);
    final time = domainStart + (frac * domainDuration).round();
    for (final s in m.spans) {
      if (time >= s.start && time <= s.end) return s.index;
    }
    return null;
  }

  void _commit(_TimeRange r) => widget.onRangeChange(r);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final TimelineModel? m = model;
    final bool reduced = prefersReducedMotion(context);
    if (m == null) {
      return Container(
        height: 50,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: aliases.borderL2))),
        child: Row(
          children: [
            Container(
              width: 44,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: aliases.borderL1)), color: aliases.bgLayer2),
              child: _LaneLabels(),
            ),
            Expanded(
              child: Stack(
                children: [
                  Center(child: Text('No timing data', style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelCaption))),
                  if (widget.hasEarlierRecords)
                    Positioned(left: 0, top: 0, bottom: 0, child: _EarlierHistoryButton(loading: _loadingEarlier, onLoad: widget.onLoadEarlier == null ? null : () async {
                      setState(() => _loadingEarlier = true);
                      try { await widget.onLoadEarlier!.call(); } finally { if (mounted) setState(() => _loadingEarlier = false); }
                    })),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final _TimeRange? visibleRange = _draft ?? widget.range;
    double? selLeft;
    double? selWidth;
    if (visibleRange != null) {
      selLeft = (visibleRange.start - domainStart) / domainDuration * 100;
      selWidth = (visibleRange.end - visibleRange.start) / domainDuration * 100;
    }

    return Container(
      height: 50,
      decoration: BoxDecoration(color: aliases.bgLayer2, border: Border(bottom: BorderSide(color: aliases.borderL2))),
      child: Row(
        children: [
          Container(
            width: 44,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: aliases.borderL1))),
            child: _LaneLabels(),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final double w = constraints.maxWidth;
              return Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final delta = event.scrollDelta.dy;
                    if (delta == 0) return;
                    setState(() {
                      _animateViewport = false;
                      final anchorFrac = _fractionAt(event.localPosition.dx, w);
                      final anchorTime = domainStart + (anchorFrac * domainDuration).round();
                      final nextDur = (domainDuration * (1 + delta * 0.0015)).round().clamp(20, fullDuration);
                      if (nextDur >= fullDuration * 0.999) {
                        _viewportStart = null;
                        _viewportEnd = null;
                        return;
                      }
                      final nextStart = (anchorTime - anchorFrac * nextDur).round().clamp(m.start, m.end - nextDur);
                      _viewportStart = nextStart;
                      _viewportEnd = nextStart + nextDur;
                    });
                  }
                },
                child: GestureDetector(
                  onPanStart: (details) {
                    final frac = _fractionAt(details.localPosition.dx, w);
                    final time = domainStart + (frac * domainDuration).round();
                    final rec = _recordIndexAt(details.localPosition, w);
                    setState(() {
                      _dragAnchorClientX = details.globalPosition.dx;
                      _dragAnchorTime = time;
                      _dragRecordIndex = rec;
                      _hoverFraction = frac;
                      _hoverRecord = rec;
                      _draft = _TimeRange(time, time);
                    });
                  },
                  onPanUpdate: (details) {
                    if (_dragAnchorTime == null) return;
                    final frac = _fractionAt(details.localPosition.dx, w);
                    final time = domainStart + (frac * domainDuration).round();
                    setState(() {
                      _hoverFraction = frac;
                      _hoverRecord = _recordIndexAt(details.localPosition, w);
                      _draft = _TimeRange(
                        _dragAnchorTime! <= time ? _dragAnchorTime! : time,
                        _dragAnchorTime! <= time ? time : _dragAnchorTime!,
                      );
                    });
                  },
                  onPanEnd: (details) {
                    if (_dragAnchorTime == null) return;
                    final draft = _draft;
                    final rec = _dragRecordIndex;
                    setState(() {
                      _draft = null;
                      _dragAnchorTime = null;
                      _dragAnchorClientX = null;
                    });
                    if (draft == null) return;
                    final double dragDx = (details.globalPosition.dx - (_dragAnchorClientX ?? details.globalPosition.dx)).abs();
                    final bool isClick = dragDx < 3 && (draft.end - draft.start).abs() < (fullDuration / m.spans.length).clamp(5, 1000);
                    if (isClick && rec != null) {
                      widget.onRangeChange(null);
                      widget.onRecordSelect(rec);
                      return;
                    }
                    final minDur = (fullDuration / m.spans.length).round().clamp(5, domainDuration);
                    _TimeRange effective = draft;
                    if ((effective.end - effective.start).abs() < minDur) {
                      final center = (effective.start + effective.end) ~/ 2;
                      effective = _TimeRange(center - minDur ~/ 2, center + minDur ~/ 2);
                    }
                    _commit(effective);
                    if (isClick) {
                      final point = effective.start;
                      TimelineSpan? nearest;
                      int best = 1 << 30;
                      for (final s in m.spans) {
                        final d = point < s.start ? s.start - point : point > s.end ? point - s.end : 0;
                        if (d < best) { best = d; nearest = s; }
                      }
                      if (nearest != null) widget.onRecordFocus(nearest.index);
                    }
                  },
                  onDoubleTap: () => widget.onRangeChange(null),
                  child: MouseRegion(
                    onHover: (e) {
                      final frac = _fractionAt(e.localPosition.dx, w);
                      setState(() {
                        _hoverFraction = frac;
                        _hoverRecord = _recordIndexAt(e.localPosition, w);
                      });
                    },
                    onExit: (_) => setState(() { _hoverFraction = null; _hoverRecord = null; }),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Stack(
                            children: [
                              for (final b in m.boundaries)
                                if (b.time >= domainStart && b.time <= domainStart + domainDuration)
                                  Positioned(
                                    left: (b.time - m.start) / fullDuration * w - (domainStart - m.start)/fullDuration * w,
                                    top: 0, bottom: 0,
                                    child: Container(width: 1, color: aliases.borderL2),
                                  ),
                            ],
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedContainer(
                            duration: _animateViewport && !reduced ? const Duration(milliseconds: 180) : Duration.zero,
                            curve: DswTokens.easeInOut,
                            transform: Matrix4.translationValues(-(domainStart - m.start) / fullDuration * w, 0, 0),
                            child: SizedBox(
                              width: w * fullDuration / domainDuration,
                              child: Stack(
                                children: [
                                  for (final span in m.spans)
                                    if (span.end >= domainStart && span.start <= domainStart + domainDuration || span.index == widget.selectedIndex)
                                      _TimelineSpanWidget(
                                        span: span,
                                        modelStart: m.start,
                                        fullDuration: fullDuration,
                                        isSelected: widget.selectedIndex == span.index,
                                        isHovered: _hoverRecord == span.index,
                                        isSearchMatch: widget.searchMatchIndexes == null ? null : widget.searchMatchIndexes!.contains(span.index),
                                        isTimelineSelected: widget.range == null ? null : (span.start <= widget.range!.end && span.end >= widget.range!.start),
                                        mode: widget.mode,
                                        w: w,
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_hoverFraction != null && _hoverRecord == null && _draft == null)
                          Positioned(
                            left: (_hoverFraction! * w).clamp(0, w - 2),
                            top: 0, bottom: 0,
                            child: Container(width: 2, color: aliases.stateBusinessPrimary),
                          ),
                        if (selLeft != null && selWidth != null)
                          Positioned(
                            left: selLeft / 100 * w,
                            width: (selWidth / 100 * w).clamp(1, w),
                            top: 0, bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: aliases.stateBusinessPrimary.withValues(alpha: _draft != null ? 0.18 : 0.12),
                                border: Border(
                                  left: BorderSide(color: aliases.stateBusinessPrimary, width: _draft != null ? 2 : 3),
                                  right: BorderSide(color: aliases.stateBusinessPrimary, width: _draft != null ? 2 : 3),
                                ),
                              ),
                            ),
                          ),
                        if (widget.hasEarlierRecords && domainStart == m.start)
                          Positioned(left: 0, top: 0, bottom: 0, child: _EarlierHistoryButton(loading: _loadingEarlier, onLoad: widget.onLoadEarlier == null ? null : () async {
                            setState(() => _loadingEarlier = true);
                            try { await widget.onLoadEarlier!.call(); } finally { if (mounted) setState(() => _loadingEarlier = false); }
                          })),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _LaneLabels extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Stack(
      children: [
        Positioned(right: 3, top: 7, child: Text('Input', style: TextStyle(fontSize: 10, height: 1, color: aliases.labelCaption))),
        Positioned(right: 3, top: 21, child: Text('Model', style: TextStyle(fontSize: 10, height: 1, color: aliases.labelCaption))),
        Positioned(right: 3, top: 35, child: Text('Tools', style: TextStyle(fontSize: 10, height: 1, color: aliases.labelCaption))),
      ],
    );
  }
}

class _EarlierHistoryButton extends StatelessWidget {
  const _EarlierHistoryButton({required this.loading, required this.onLoad});
  final bool loading;
  final Future<void> Function()? onLoad;
  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Tooltip(
      message: loading ? 'Loading earlier…' : 'Click to load earlier',
      child: InkWell(
        onTap: loading || onLoad == null ? null : () => onLoad!.call(),
        child: Container(
          width: 28,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [aliases.bgLayer2, aliases.bgLayer2.withValues(alpha: 0.0)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Text('…', style: TextStyle(fontSize: DswTokens.fontSizeXs13, color: aliases.labelSecondary)),
        ),
      ),
    );
  }
}

class _TimelineSpanWidget extends StatelessWidget {
  const _TimelineSpanWidget({
    required this.span,
    required this.modelStart,
    required this.fullDuration,
    required this.isSelected,
    required this.isHovered,
    required this.isSearchMatch,
    required this.isTimelineSelected,
    required this.mode,
    required this.w,
  });
  final TimelineSpan span;
  final int modelStart;
  final int fullDuration;
  final bool isSelected;
  final bool isHovered;
  final bool? isSearchMatch;
  final bool? isTimelineSelected;
  final String mode;
  final double w;

  Color _bg(DswAliases a) {
    if (span.isError) return a.stateErrorPrimary;
    return switch (span.kind) {
      TrajectoryCellKind.user => a.stateBusinessPrimary,
      TrajectoryCellKind.context => a.stateSuccessPrimary,
      TrajectoryCellKind.system => a.labelCaption,
      TrajectoryCellKind.compacted => a.labelTertiary,
      TrajectoryCellKind.message => a.brandPrimaryNewColor,
      TrajectoryCellKind.tool => a.stateWarnLabel,
      TrajectoryCellKind.subtool => a.stateWarnLabel.withValues(alpha: 0.8),
    };
  }

  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final bool equal = mode == 'time';
    final double left = (span.start - modelStart) / fullDuration * w;
    final double width = (span.end - span.start) / fullDuration * w;
    final double effWidth = width.clamp(2, w);
    final double gap = (effWidth * 0.08).clamp(0, 1);
    final double leftWithGap = left + gap;
    final double widthWithGap = (effWidth - 2 * gap).clamp(2, w);
    final double top = span.lane * 14.0 + 7;
    double opacity = 0.78;
    if (isTimelineSelected == false) opacity = 0.2;
    if (isSearchMatch == false) opacity = 0.14;
    if (isSelected) opacity = 1;
    if (isHovered && !isSelected) opacity = 1;

    BoxDecoration deco = BoxDecoration(
      color: _bg(aliases),
      borderRadius: BorderRadius.circular(1),
      boxShadow: isSelected
          ? [BoxShadow(color: aliases.bgLayer2, blurRadius: 0, spreadRadius: 1), BoxShadow(color: aliases.stateBusinessPrimary, blurRadius: 0, spreadRadius: 2)]
          : isHovered
              ? [BoxShadow(color: aliases.bgLayer2, blurRadius: 0, spreadRadius: 1), BoxShadow(color: aliases.stateBusinessPrimary.withValues(alpha: 0.8), blurRadius: 0, spreadRadius: 2)]
              : null,
    );

    final bool equalWidth = equal;
    final double boxWidth = equalWidth ? 8 : widthWithGap;
    final double boxLeft = equalWidth ? left : leftWithGap;

    return Positioned(
      left: boxLeft,
      top: top,
      child: Tooltip(
        message: '${span.kind.name} · ${span.isError ? 'error' : 'ok'}',
        waitDuration: const Duration(milliseconds: 500),
        child: Container(
          width: boxWidth,
          height: 8,
          decoration: deco.copyWith(color: deco.color?.withValues(alpha: opacity)),
        ),
      ),
    );
  }
}

class _TrajectoryLedger extends StatelessWidget {
  const _TrajectoryLedger({
    required this.rows,
    required this.allRows,
    required this.searchMatchIndexes,
    required this.timelineFocusIndexes,
    required this.selectedIndex,
    required this.onSelectedIndexChange,
    required this.onRecordSelect,
    required this.collapsedTurns,
    required this.onToggleTurn,
    required this.historyLoading,
    required this.olderHistoryLoading,
    required this.hasOlderRecords,
    required this.onLoadOlder,
    required this.scrollController,
    required this.pendingFocusIndex,
    required this.onFocusConsumed,
  });

  final List<LedgerRow> rows;
  final List<LedgerRow> allRows;
  final Set<int>? searchMatchIndexes;
  final Set<int>? timelineFocusIndexes;
  final int? selectedIndex;
  final ValueChanged<int?> onSelectedIndexChange;
  final ValueChanged<int> onRecordSelect;
  final Set<int> collapsedTurns;
  final ValueChanged<int> onToggleTurn;
  final bool historyLoading;
  final bool olderHistoryLoading;
  final bool hasOlderRecords;
  final Future<void> Function() onLoadOlder;
  final ScrollController scrollController;
  final int? pendingFocusIndex;
  final VoidCallback onFocusConsumed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool reduced = prefersReducedMotion(context);

    if (pendingFocusIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onFocusConsumed());
    }

    if (rows.isEmpty) {
      return Center(child: Text('No matching records', style: TextStyle(color: aliases.labelCaption, fontSize: DswTokens.fontSizeXs13)));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final bool compact = constraints.maxWidth < 620;
      return Column(
        children: [
          Container(
            height: 30,
            color: aliases.specificSidebarFill,
            child: Row(
              children: [
                Container(
                  width: 122,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: aliases.borderL2))),
                  child: Text('Event', style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary, fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: aliases.borderL2))),
                    child: Text('Content', style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
          if (historyLoading)
            Container(
              height: 30,
              color: aliases.bgLayer1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: aliases.stateBusinessPrimary)),
                  const SizedBox(width: 6),
                  Text('Loading…', style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelSecondary)),
                ],
              ),
            ),
          if (hasOlderRecords && !historyLoading)
            InkWell(
              onTap: olderHistoryLoading ? null : () => onLoadOlder(),
              child: Container(
                height: 29,
                color: aliases.bgLayer1,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (olderHistoryLoading) SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: aliases.labelSecondary)) else Icon(Icons.history, size: 12, color: aliases.labelSecondary),
                    const SizedBox(width: 6),
                    Text(olderHistoryLoading ? 'Loading…' : 'Load earlier', style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelSecondary)),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: rows.length,
              itemExtent: 30,
              itemBuilder: (context, i) {
                final row = rows[i];
                if (row.isCollapsedSummary) {
                  return _CollapsedSummaryRow(text: row.collapsedSummary ?? '…', onTap: () => onToggleTurn(row.turn));
                }
                final bool isSelected = selectedIndex == row.index;
                final bool isSearchDim = searchMatchIndexes != null && !searchMatchIndexes!.contains(row.index);
                final bool isTimelineDim = timelineFocusIndexes != null && !timelineFocusIndexes!.contains(row.index);
                final double opacity = isSearchDim ? 0.14 : isTimelineDim ? 0.24 : 1;
                return Opacity(
                  opacity: opacity,
                  child: _LedgerRowWidget(
                    row: row,
                    compact: compact,
                    isSelected: isSelected,
                    reduced: reduced,
                    onTap: () {
                      onRecordSelect(row.index);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _LedgerRowWidget extends StatelessWidget {
  const _LedgerRowWidget({required this.row, required this.compact, required this.isSelected, required this.reduced, required this.onTap});
  final LedgerRow row;
  final bool compact;
  final bool isSelected;
  final bool reduced;
  final VoidCallback onTap;

  Color _turnAccent(DswAliases a) => Color.lerp(a.bgLayer1, DswTokens.blue500, 0.22) ?? DswTokens.blue500;

  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final Duration hoverDur = reduced ? Duration.zero : const Duration(milliseconds: 120);
    final (_KindTagData tag, IconData? icon) = _kindTag(row.kind, aliases, compact);
    final bool showErrorRail = row.isError;

    return InkWell(
      onTap: onTap,
      hoverColor: aliases.interactiveBgHover,
      splashColor: aliases.interactiveBgHover,
      child: AnimatedContainer(
        duration: hoverDur,
        curve: DswTokens.easeInOut,
        height: 30,
        decoration: BoxDecoration(
          color: isSelected ? aliases.interactiveBgActive : DswTokens.transparent,
          border: Border(bottom: BorderSide(color: aliases.borderL1)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 122,
              child: Stack(
                children: [
                  Positioned(left: 0, top: row.turnStart ? -1 : 0, bottom: row.turnEnd ? 0 : -1, child: Container(width: 2, color: showErrorRail ? aliases.stateErrorPrimary.withValues(alpha: 0.22) : _turnAccent(aliases))),
                  if (isSelected) Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 3, color: showErrorRail ? aliases.stateErrorPrimary : aliases.stateBusinessPrimary)),
                  if (row.turnStart)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: aliases.bgModulePlatform, borderRadius: const BorderRadius.only(bottomRight: Radius.circular(2))),
                        child: Text(compact ? 'T${row.turn}' : 'Turn ${row.turn}', style: TextStyle(fontSize: 8, height: 10/8, fontFamily: DswTokens.fontFamilyCode, color: aliases.labelTertiary)),
                      ),
                    ),
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
                        curve: DswTokens.easeInOut,
                        width: compact ? 19 : 76,
                        height: 19,
                        child: _KindPill(tag: tag, icon: icon, compact: compact),
                      ),
                    ),
                  ),
                  if (row.groupStart)
                    Positioned(
                      left: 12 + (row.turn * 2).clamp(0, 24).toDouble(),
                      top: 12,
                      child: Container(width: 5, height: 5, decoration: BoxDecoration(color: aliases.labelCaption, shape: BoxShape.circle)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _RowContent(row: row, reduced: reduced),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTagData {
  final String label;
  final Color fg;
  final Color bg;
  const _KindTagData(this.label, this.fg, this.bg);
}

(_KindTagData, IconData?) _kindTag(TrajectoryCellKind kind, DswAliases a, bool compact) {
  switch (kind) {
    case TrajectoryCellKind.user:
      return (_KindTagData('USER', a.stateBusinessPrimary, a.stateBusinessTertiary), Icons.person_outline);
    case TrajectoryCellKind.context:
      return (_KindTagData('CONTEXT', a.stateSuccessPrimary, a.stateSuccessTertiary), Icons.info_outline);
    case TrajectoryCellKind.system:
      return (_KindTagData('SYSTEM', a.labelSecondary, a.bgModulePlatform), Icons.settings_outlined);
    case TrajectoryCellKind.compacted:
      return (_KindTagData('COMPACTED', a.labelSecondary, a.bgModulePlatform), Icons.compress);
    case TrajectoryCellKind.message:
      return (_KindTagData('ASSISTANT', a.brandPrimaryNewColor, Color.lerp(a.brandPrimaryNewColor, DswTokens.red400, 0.4)?.withValues(alpha: 0.15) ?? a.stateBusinessTertiary), Icons.auto_awesome);
    case TrajectoryCellKind.tool:
      return (_KindTagData('TOOL', a.stateWarnLabel, a.stateWarnTertiary), Icons.build_outlined);
    case TrajectoryCellKind.subtool:
      return (_KindTagData('SUBTOOL', a.stateWarnLabel.withValues(alpha: 0.62), a.stateWarnTertiary.withValues(alpha: 0.58)), Icons.build_outlined);
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.tag, required this.icon, required this.compact});
  final _KindTagData tag;
  final IconData? icon;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 5),
      decoration: BoxDecoration(color: tag.bg, borderRadius: BorderRadius.circular(DswTokens.radiusXs), border: Border.all(color: DswTokens.transparent)),
      alignment: Alignment.center,
      child: compact
          ? Icon(icon, size: 13, color: tag.fg)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 13, color: tag.fg),
                if (icon != null) const SizedBox(width: 4),
                Flexible(child: Text(tag.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.35, color: tag.fg))),
              ],
            ),
    );
  }
}

class _RowContent extends StatelessWidget {
  const _RowContent({required this.row, required this.reduced});
  final LedgerRow row;
  final bool reduced;
  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    if (row.kind == TrajectoryCellKind.tool || row.kind == TrajectoryCellKind.subtool) {
      final parts = row.text.split(' · ');
      final name = parts.isNotEmpty ? parts.first : row.text;
      final args = parts.length > 1 ? parts.sublist(1).join(' · ') : null;
      final bool isSub = row.kind == TrajectoryCellKind.subtool;
      return Padding(
        padding: EdgeInsets.only(left: isSub ? 22 : 0),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                text: TextSpan(
                  children: [
                    TextSpan(text: name, style: TextStyle(fontFamily: DswTokens.fontFamilyCode, fontSize: 12, color: aliases.labelPrimary)),
                    if (args != null) TextSpan(text: '  $args', style: TextStyle(fontFamily: DswTokens.fontFamilyCode, fontSize: 12, color: aliases.labelSecondary)),
                  ],
                ),
              ),
            ),
            if (row.result != null && row.result!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 12, color: aliases.labelCaption),
              const SizedBox(width: 8),
              Expanded(
                child: Text(row.result!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: DswTokens.fontFamilyCode, fontSize: 12, color: aliases.labelSecondary)),
              ),
            ],
          ],
        ),
      );
    }
    final String display = row.previewMarkdown ?? row.text;
    if (display.isEmpty) {
      return Text('—', style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary));
    }
    return Text(display, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelPrimary));
  }
}

class _CollapsedSummaryRow extends StatelessWidget {
  const _CollapsedSummaryRow({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: aliases.borderL1))),
        child: Row(
          children: [
            Text('…', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aliases.labelTertiary)),
            const SizedBox(width: 6),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: aliases.labelSecondary))),
          ],
        ),
      ),
    );
  }
}

class _TrajectoryFooter extends StatelessWidget {
  const _TrajectoryFooter({required this.trajectory, required this.rows});
  final Trajectory trajectory;
  final List<LedgerRow> rows;
  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final int turns = trajectory.turns.length;
    final int steps = rows.map((r) => '${r.turn}-${r.group}').toSet().length;
    return Container(
      height: 24,
      color: aliases.bgLayer2,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: Text(
        '$turns turn${turns == 1 ? '' : 's'} · $steps step${steps == 1 ? '' : 's'}',
        style: TextStyle(fontSize: 11, color: aliases.labelCaption),
      ),
    );
  }
}

class _TrajectoryHeader extends StatelessWidget {
  const _TrajectoryHeader({required this.trajectory, required this.aliases});
  final Trajectory trajectory;
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) {
    final int count = trajectory.turns.length;
    final bool running = trajectory.isRunning;
    final String durationLabel = _durationLabel(trajectory.totalDurationMs);
    return Container(
      color: aliases.bgLayer2,
      padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceLg, vertical: DswTokens.spaceMd),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: running ? aliases.stateSuccessTertiary : aliases.bgOverlay,
              borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              border: Border.all(color: running ? aliases.stateSuccessPrimary : aliases.borderL2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: running ? aliases.stateSuccessPrimary : aliases.labelTertiary, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(running ? 'Running' : 'Idle', style: TextStyle(fontSize: DswTokens.fontSizeXxs12, fontWeight: FontWeight.w600, color: running ? aliases.stateSuccessPrimary : aliases.labelSecondary)),
              ],
            ),
          ),
          const SizedBox(width: DswTokens.spaceMd),
          Text('$count turn${count == 1 ? '' : 's'}', style: TextStyle(fontSize: DswTokens.fontSizeS14, color: aliases.labelSecondary)),
          if (durationLabel.isNotEmpty) ...[
            const SizedBox(width: DswTokens.spaceSm),
            Text('· $durationLabel', style: TextStyle(fontSize: DswTokens.fontSizeS14, color: aliases.labelCaption)),
          ],
          const Spacer(),
          Text('Session ${trajectory.sessionId}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelCaption)),
        ],
      ),
    );
  }

  String _durationLabel(int? ms) {
    if (ms == null) return '';
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final int mins = ms ~/ 60000;
    final int secs = (ms % 60000) ~/ 1000;
    return '${mins}m ${secs}s';
  }
}

class _EmptyTrajectory extends StatelessWidget {
  const _EmptyTrajectory({required this.sessionId, required this.aliases});
  final String sessionId;
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 32, color: aliases.labelCaption),
            const SizedBox(height: DswTokens.spaceMd),
            Text('No turns yet', style: TextStyle(fontSize: DswTokens.fontSizeBase16, fontWeight: FontWeight.w600, color: aliases.labelPrimary)),
            const SizedBox(height: 6),
            Text('Trajectory for $sessionId is empty.\nSend a message to create the first turn.', textAlign: TextAlign.center, style: TextStyle(fontSize: DswTokens.fontSizeS14, color: aliases.labelSecondary)),
            const SizedBox(height: DswTokens.spaceLg),
            OutlinedButton.icon(onPressed: () => context.go('/sessions/$sessionId'), icon: const Icon(Icons.chat_bubble_outline, size: 16), label: const Text('Back to conversation')),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.aliases, required this.onRetry});
  final String error;
  final DswAliases aliases;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 28, color: aliases.stateErrorPrimary),
            const SizedBox(height: DswTokens.spaceSm),
            Text('Failed to load trajectory', style: TextStyle(fontSize: DswTokens.fontSizeS14, fontWeight: FontWeight.w600, color: aliases.labelPrimary)),
            const SizedBox(height: 4),
            SelectableText(error, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelSecondary)),
            const SizedBox(height: DswTokens.spaceMd),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

dynamic jsonContainerOf(dynamic value) {
  if (value is Map || value is List) return value;
  if (value is String) {
    final String trimmed = value.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is Map || decoded is List) return decoded;
    } on FormatException {}
  }
  return null;
}

String scalarResultText(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

class TrajectoryTimeline extends ConsumerWidget {
  const TrajectoryTimeline({super.key, required this.trajectory});
  final Trajectory trajectory;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = _rowsFromTrajectoryTurns(trajectory);
    return _TrajectoryTimelineStrip(
      rows: rows,
      mode: 'sequence',
      range: null,
      hasEarlierRecords: false,
      onLoadEarlier: null,
      selectedIndex: null,
      searchMatchIndexes: null,
      onRangeChange: (_) {},
      onRecordSelect: (_) {},
      onRecordFocus: (_) {},
    );
  }
}

// ---------------------------------------------------------------------------
// Details pane — mirrors TrajectoryTable details split (320-440, resizable)
// Simplified as bottom sheet with tabs: Overview / Rendered / Raw / Timing
// ---------------------------------------------------------------------------

class _DetailsPane extends StatefulWidget {
  const _DetailsPane({required this.row, required this.onClose});
  final LedgerRow row;
  final VoidCallback onClose;
  @override
  State<_DetailsPane> createState() => _DetailsPaneState();
}

class _DetailsPaneState extends State<_DetailsPane> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<String> get _tabs {
    final k = widget.row.kind;
    if (k == TrajectoryCellKind.system) return ['Overview', 'Raw'];
    if (k == TrajectoryCellKind.compacted) return ['Overview', 'Raw'];
    if (k == TrajectoryCellKind.message || k == TrajectoryCellKind.user || k == TrajectoryCellKind.context) {
      return ['Overview', 'Rendered', 'Raw'];
    }
    return ['Overview', 'Input', 'Output', 'Timing'];
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _DetailsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.index != widget.row.index || oldWidget.row.kind != widget.row.kind) {
      final newLen = _tabs.length;
      if (newLen != _tab.length) {
        _tab.dispose();
        _tab = TabController(length: newLen, vsync: this);
      } else {
        _tab.index = 0;
      }
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final row = widget.row;
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: aliases.bgLayer1,
        border: Border(top: BorderSide(color: aliases.borderL2)),
        boxShadow: [BoxShadow(color: aliases.bgMask1, blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: aliases.borderL2))),
            child: Row(
              children: [
                Container(width: 5, height: 5, decoration: BoxDecoration(color: row.isError ? aliases.stateErrorPrimary : aliases.labelTertiary, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(_kindLabel(row.kind), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: DswTokens.fontFamilyCode, color: aliases.labelPrimary)),
                const SizedBox(width: 8),
                Expanded(child: Text('#${row.index} · Turn ${row.turn}', style: TextStyle(fontSize: 11, fontFamily: DswTokens.fontFamilyCode, color: aliases.labelTertiary), overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: widget.onClose, tooltip: 'Close'),
              ],
            ),
          ),
          Container(
            height: 34,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: aliases.borderL2))),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              labelColor: aliases.stateBusinessPrimary,
              unselectedLabelColor: aliases.labelTertiary,
              indicatorColor: aliases.stateBusinessPrimary,
              indicatorWeight: 2,
              labelStyle: TextStyle(fontSize: DswTokens.fontSizeXs13, fontWeight: FontWeight.w500),
              tabs: [for (final t in _tabs) Tab(text: t)],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [for (final t in _tabs) _tabBody(t, row, aliases)],
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(TrajectoryCellKind k) => switch (k) {
        TrajectoryCellKind.system => 'SYSTEM',
        TrajectoryCellKind.user => 'USER',
        TrajectoryCellKind.context => 'CONTEXT',
        TrajectoryCellKind.compacted => 'COMPACTED',
        TrajectoryCellKind.message => 'ASSISTANT',
        TrajectoryCellKind.tool => 'TOOL',
        TrajectoryCellKind.subtool => 'SUBTOOL',
      };

  Widget _tabBody(String tab, LedgerRow row, DswAliases aliases) {
    switch (tab) {
      case 'Overview':
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _kv('Kind', _kindLabel(row.kind), aliases),
            _kv('Turn', '${row.turn}', aliases),
            _kv('Group', row.group, aliases),
            _kv('Started', row.startedAt != null ? DateTime.fromMillisecondsSinceEpoch(row.startedAt!).toIso8601String() : '—', aliases),
            _kv('Duration', row.timeSeconds != null ? '${(row.timeSeconds! * 1000).round()}ms' : '—', aliases),
            if (row.callId != null) _kv('CallId', row.callId!, aliases),
            if (row.isError) _kv('Status', 'Error', aliases, error: true),
            const SizedBox(height: 8),
            Text(row.text, style: TextStyle(fontSize: DswTokens.fontSizeXs13, color: aliases.labelPrimary)),
          ],
        );
      case 'Rendered':
        {
          final String md = row.outputDetail ?? row.previewMarkdown ?? row.text;
          if (md.isEmpty) return Center(child: Text('No content', style: TextStyle(color: aliases.labelTertiary, fontSize: DswTokens.fontSizeXs13)));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: DsMarkdown(data: md),
          );
        }
      case 'Raw':
        {
          final String raw = row.inputDetail ?? row.outputDetail ?? row.previewMarkdown ?? row.text;
          if (raw.isEmpty) return Center(child: Text('No payload', style: TextStyle(color: aliases.labelTertiary, fontSize: DswTokens.fontSizeXs13)));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SelectableText(raw, style: TextStyle(fontFamily: DswTokens.fontFamilyCode, fontSize: 12, height: 19/12, color: aliases.labelPrimary)),
          );
        }
      case 'Input':
        {
          final String raw = row.inputDetail ?? '';
          if (raw.isEmpty) return Center(child: Text('No input', style: TextStyle(color: aliases.labelTertiary, fontSize: DswTokens.fontSizeXs13)));
          final dynamic decoded = jsonContainerOf(raw) ?? raw;
          if (decoded is Map || decoded is List) {
            return SingleChildScrollView(padding: const EdgeInsets.all(14), child: DsJsonTree(data: decoded, initiallyExpanded: true));
          }
          return SingleChildScrollView(padding: const EdgeInsets.all(14), child: SelectableText(raw, style: TextStyle(fontFamily: DswTokens.fontFamilyCode, fontSize: 12, color: aliases.labelPrimary)));
        }
      case 'Output':
        {
          final String raw = row.result ?? row.outputDetail ?? '';
          if (raw.isEmpty) return Center(child: Text('No output', style: TextStyle(color: aliases.labelTertiary, fontSize: DswTokens.fontSizeXs13)));
          final dynamic decoded = jsonContainerOf(raw) ?? raw;
          if (decoded is Map || decoded is List) {
            return SingleChildScrollView(padding: const EdgeInsets.all(14), child: DsJsonTree(data: decoded, initiallyExpanded: true));
          }
          return SingleChildScrollView(padding: const EdgeInsets.all(14), child: SelectableText(raw, style: TextStyle(fontFamily: DswTokens.fontFamilyCode, fontSize: 12, color: aliases.labelPrimary)));
        }
      case 'Timing':
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _kv('Started', row.startedAt != null ? DateTime.fromMillisecondsSinceEpoch(row.startedAt!).toString() : '—', aliases),
            _kv('Duration', row.timeSeconds != null ? '${row.timeSeconds}s' : '—', aliases),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _kv(String k, String v, DswAliases a, {bool error = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(k, style: TextStyle(fontSize: DswTokens.fontSizeXs13, color: a.labelTertiary))),
          Expanded(child: Text(v, style: TextStyle(fontSize: DswTokens.fontSizeXs13, color: error ? a.stateErrorPrimary : a.labelPrimary))),
        ],
      ),
    );
  }
}

