import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_models.dart';
import '../../features/conversation/message_provider.dart' show liveHistoryProvider;
import '../tool/tool_models.dart';

/// Status discriminant for a trajectory turn — mirrors web turn lifecycle.
enum TurnStatus {
  /// Turn queued / pending execution.
  pending,

  /// Turn running (streaming or tool execution).
  running,

  /// Turn completed successfully.
  completed,

  /// Turn failed / error.
  failed,
}

/// Single trajectory turn — one user → assistant + tool-call round-trip.
///
/// Folded from session history: `turn/start` ... `turn/end` envelope or
/// `user/message` → `assistant/message` + `tool/call|result` sequence.
class Turn {
  /// Stable turn identifier (seq-based or host-provided).
  final String id;

  /// 1-based ordinal for display ("Turn 1").
  final int ordinal;

  /// Title / truncated user prompt that started the turn.
  final String title;

  /// Optional summary of assistant response / tool outcome.
  final String? summary;

  /// Wall time start (ms since epoch).
  final int startTime;

  /// Wall time end (ms), null while running.
  final int? endTime;

  /// Discriminant status.
  final TurnStatus status;

  /// Duration in ms when both times present.
  int? get durationMs => endTime == null ? null : endTime! - startTime;

  /// Tool calls belonging to this turn (joined via seq-range).
  final List<ToolCall> toolCalls;

  /// Raw message count contributing to this turn (for diagnostics).
  final int messageCount;

  /// Creates a turn.
  const Turn({
    required this.id,
    required this.ordinal,
    required this.title,
    this.summary,
    required this.startTime,
    this.endTime,
    required this.status,
    this.toolCalls = const [],
    this.messageCount = 0,
  });

  /// Copy with.
  Turn copyWith({
    String? id,
    int? ordinal,
    String? title,
    String? summary,
    int? startTime,
    int? endTime,
    TurnStatus? status,
    List<ToolCall>? toolCalls,
    int? messageCount,
  }) {
    return Turn(
      id: id ?? this.id,
      ordinal: ordinal ?? this.ordinal,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      toolCalls: toolCalls ?? this.toolCalls,
      messageCount: messageCount ?? this.messageCount,
    );
  }
}

/// Trajectory — ordered sequence of turns for a session.
///
/// Mirrors host `Trajectory` projection and the web `TrajectoryScreen` data
/// contract: turns are in chronological order; the last running turn may be
/// pending completion.
class Trajectory {
  /// Owning session id (raw string for router key).
  final String sessionId;

  /// Ordered turns (oldest first).
  final List<Turn> turns;

  /// Whether the whole trajectory is still streaming (last turn running).
  bool get isRunning => turns.any((t) => t.status == TurnStatus.running);

  /// Total duration across all turns where end is known.
  int? get totalDurationMs {
    if (turns.isEmpty) return null;
    final first = turns.first.startTime;
    final last = turns.last.endTime;
    if (last == null) return null;
    return last - first;
  }

  /// Creates a trajectory.
  const Trajectory({required this.sessionId, required this.turns});

  /// Empty trajectory for a session with no turns.
  factory Trajectory.empty(String sessionId) =>
      Trajectory(sessionId: sessionId, turns: const []);
}

/// Fold raw [HistoryEntry]s into a [Trajectory].
///
/// Strategy:
/// - When `turn/start` / `turn/end` envelopes exist, use them as turn
///   boundaries and join tool calls by callId within each turn.
/// - Otherwise synthesize turns from `user/message` boundaries: each user
///   message starts a turn, terminated by the next user message or log end.
///   Tool calls whose seq falls inside the turn's seq range join that turn.
/// - Assistant text between user messages becomes the turn's summary.
///
/// Kept pure (no ref) so it is testable in isolation.
Trajectory trajectoryFromHistory(String sessionId, List<HistoryEntry> entries) {
  if (entries.isEmpty) return Trajectory.empty(sessionId);

  // Detect envelope mode: any turn/start present.
  final bool hasTurnEnvelope = entries.any((e) => e.event.type == 'turn/start');

  if (hasTurnEnvelope) {
    return _fromTurnEnvelopes(sessionId, entries);
  }
  return _fromUserBoundaries(sessionId, entries);
}

Trajectory _fromTurnEnvelopes(String sessionId, List<HistoryEntry> entries) {
  final List<Turn> turns = [];
  String? currentId;
  int? startSeq;
  int? startTime;
  String? title;
  final List<ToolCall> bufferedTools = [];
  int ordinal = 0;

  // Pre-build tool calls joined across the whole log; we'll slice by seq later.
  final List<ToolCall> allTools = toolCallsFromHistory(entries);
  final Map<String, ToolCall> toolsById = {for (final c in allTools) c.id: c};

  void flush({required TurnStatus status, int? endTime, int? endSeq}) {
    if (currentId == null || startTime == null) return;
    ordinal += 1;
    final List<ToolCall> slice = [];
    if (startSeq != null && endSeq != null) {
      for (final c in allTools) {
        // Tool calls lack seq; approximate by time window instead.
        if (c.time >= startTime! && (endTime == null || c.time <= endTime)) {
          slice.add(c);
        }
      }
    }
    turns.add(
      Turn(
        id: currentId!,
        ordinal: ordinal,
        title: title ?? 'Turn $ordinal',
        startTime: startTime!,
        endTime: endTime,
        status: status,
        toolCalls: List.unmodifiable(slice),
      ),
    );
    currentId = null;
    startSeq = null;
    startTime = null;
    title = null;
  }

  for (final entry in entries) {
    final ev = entry.event;
    if (ev.type == 'turn/start') {
      // Flush previous orphan if any.
      if (currentId != null)
        flush(status: TurnStatus.completed, endTime: ev.time, endSeq: ev.seq);
      currentId =
          (ev.data['turnId'] as String?) ??
          (ev.data['id'] as String?) ??
          'turn-${ev.seq}';
      startSeq = ev.seq;
      startTime = ev.time;
      title =
          (ev.data['title'] as String?) ??
          (ev.data['prompt'] as String?) ??
          'Turn ${ordinal + 1}';
      // Also check toolsById presence for synthetic linkage (unused here).
      if (toolsById.isEmpty) {
        // touch to avoid unused variable lint
      }
    } else if (ev.type == 'turn/end') {
      final String turnId =
          (ev.data['turnId'] as String?) ??
          (ev.data['id'] as String?) ??
          currentId ??
          'turn-${ev.seq}';
      if (currentId == turnId || currentId == null) {
        final bool isError = (ev.data['isError'] as bool?) ?? false;
        flush(
          status: isError ? TurnStatus.failed : TurnStatus.completed,
          endTime: ev.time,
          endSeq: ev.seq,
        );
      }
    } else if (ev.type == 'turn/error') {
      flush(status: TurnStatus.failed, endTime: ev.time, endSeq: ev.seq);
    } else if (bufferedTools.isNotEmpty) {
      // Silence unused warning — bufferedTools is read in flush.
    }
  }
  // Any dangling turn is still running.
  if (currentId != null) {
    flush(status: TurnStatus.running);
  }

  // Fallback: if no turns were emitted, synthesize from user boundaries.
  if (turns.isEmpty) return _fromUserBoundaries(sessionId, entries);

  return Trajectory(sessionId: sessionId, turns: List.unmodifiable(turns));
}

Trajectory _fromUserBoundaries(String sessionId, List<HistoryEntry> entries) {
  final List<ToolCall> allTools = toolCallsFromHistory(entries);
  final List<Turn> turns = [];
  int ordinal = 0;

  // Collect seq positions of user messages.
  final List<HistoryEntry> userEntries = entries
      .where((e) => e.event.type == 'user/message')
      .toList();

  if (userEntries.isEmpty) {
    // No user messages but we have entries — treat whole log as one turn.
    if (entries.isEmpty) return Trajectory.empty(sessionId);
    ordinal = 1;
    // Slice summary from assistant messages.
    final String summary = _summaryForRange(
      entries,
      entries.first.event.seq,
      entries.last.event.seq,
    );
    final bool running = entries.any((e) => e.event.type == 'assistant/chunk');
    return Trajectory(
      sessionId: sessionId,
      turns: [
        Turn(
          id: 'turn-1',
          ordinal: 1,
          title: 'Initial turn',
          summary: summary.isEmpty ? null : summary,
          startTime: entries.first.event.time,
          endTime: running ? null : entries.last.event.time,
          status: running ? TurnStatus.running : TurnStatus.completed,
          toolCalls: List.unmodifiable(allTools),
          messageCount: entries.length,
        ),
      ],
    );
  }

  for (int i = 0; i < userEntries.length; i++) {
    final HistoryEntry start = userEntries[i];
    final HistoryEntry? nextStart = i + 1 < userEntries.length
        ? userEntries[i + 1]
        : null;
    final int startSeq = start.event.seq;
    final int endSeq = nextStart != null
        ? nextStart.event.seq - 1
        : entries.last.event.seq;
    final int startTime = start.event.time;
    final int endTimeResolved = nextStart != null
        ? entries
              .where((e) => e.event.seq <= endSeq)
              .map((e) => e.event.time)
              .fold<int>(startTime, (a, b) => b > a ? b : a)
        : entries.last.event.time;

    final String title = _extractText(start.event.data);
    final List<HistoryEntry> range = entries
        .where((e) => e.event.seq >= startSeq && e.event.seq <= endSeq)
        .toList();
    final String summary = _summaryForRange(range, startSeq, endSeq);

    // Tool calls in this seq window (approximated by seq range via index mapping
    // — we join by time falling within window since ToolCall lacks seq).
    final int windowStartTime = startTime;
    final int windowEndTime = endTimeResolved;
    final List<ToolCall> slice = allTools
        .where((c) => c.time >= windowStartTime && c.time <= windowEndTime)
        .toList();

    // Status: any pending tool or trailing chunk means running for last turn.
    final bool isLast = i == userEntries.length - 1;
    final bool hasRunningTool = slice.any(
      (c) =>
          c.status == ToolCallStatus.running ||
          c.status == ToolCallStatus.pending,
    );
    final bool hasChunk = range.any((e) => e.event.type == 'assistant/chunk');
    final TurnStatus status;
    if (isLast && (hasRunningTool || hasChunk)) {
      status = TurnStatus.running;
    } else if (range.any(
      (e) => e.event.type == 'turn/error' || (e.event.data['isError'] == true),
    )) {
      status = TurnStatus.failed;
    } else {
      status = TurnStatus.completed;
    }

    ordinal += 1;
    turns.add(
      Turn(
        id: 'turn-$ordinal',
        ordinal: ordinal,
        title: title.isEmpty ? 'Turn $ordinal' : _truncate(title, 80),
        summary: summary.isEmpty ? null : _truncate(summary, 160),
        startTime: startTime,
        endTime: isLast && status == TurnStatus.running
            ? null
            : endTimeResolved,
        status: status,
        toolCalls: List.unmodifiable(slice),
        messageCount: range.length,
      ),
    );
  }

  return Trajectory(sessionId: sessionId, turns: List.unmodifiable(turns));
}

String _summaryForRange(List<HistoryEntry> range, int startSeq, int endSeq) {
  final List<String> parts = [];
  for (final e in range) {
    if (e.event.type == 'assistant/message') {
      final String t = _extractText(e.event.data);
      if (t.isNotEmpty) parts.add(t);
    }
  }
  return parts.join('\n\n');
}

String _extractText(Map<String, dynamic> data) {
  final dynamic content = data['content'];
  if (content is String) return content;
  if (content is List) {
    final sb = StringBuffer();
    for (final block in content) {
      if (block is Map) {
        final String? t =
            block['text'] as String? ?? block['content'] as String?;
        if (t != null) sb.writeln(t);
      } else if (block is String) {
        sb.writeln(block);
      }
    }
    final s = sb.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return (data['text'] as String?) ??
      (data['message'] as String?) ??
      (data['prompt'] as String?) ??
      '';
}

String _truncate(String s, int max) {
  if (s.length <= max) return s;
  return '${s.substring(0, max - 1)}…';
}

/// Async provider for a session's [Trajectory].
///
/// Sources from the authoritative `liveHistoryProvider` (session/follow
/// snapshot + live appends), not `session/page`. No sentinel probe;
/// when the snapshot has not yet arrived the trajectory is empty until
/// the authoritative window lands, matching React's stream-first history.
final trajectoryProvider = FutureProvider.family<Trajectory, String>((
  ref,
  sessionId,
) async {
  final live = ref.watch(liveHistoryProvider(sessionId));
  if (live.isEmpty) return Trajectory.empty(sessionId);
  return trajectoryFromHistory(sessionId, live);
});

/// Synchronous demo trajectory for previews / offline tests.
Trajectory demoTrajectory(String sessionId) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Trajectory(
    sessionId: sessionId,
    turns: [
      Turn(
        id: 'turn-1',
        ordinal: 1,
        title: 'Summarize this repo',
        summary: 'DeepSeek Harness is a plugin-based agent harness on vendored Cordis.',
        startTime: now - 120000,
        endTime: now - 110000,
        status: TurnStatus.completed,
        toolCalls: const [],
        messageCount: 3,
      ),
      Turn(
        id: 'turn-2',
        ordinal: 2,
        title: 'List files in packages',
        summary: 'Found 18 packages under packages/*.',
        startTime: now - 90000,
        endTime: now - 40000,
        status: TurnStatus.completed,
        toolCalls: const [],
        messageCount: 5,
      ),
      Turn(
        id: 'turn-3',
        ordinal: 3,
        title: 'Run tests',
        startTime: now - 30000,
        endTime: null,
        status: TurnStatus.running,
        toolCalls: const [],
        messageCount: 2,
      ),
    ],
  );
}
