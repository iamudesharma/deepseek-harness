import 'dart:math' show max;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../features/conversation/message_provider.dart' show liveHistoryProvider;
import '../locales.dart';

/// Minimal subagent view — mirrors the catalog row shape `SubagentCatalogAction`
/// renders while its authoritative snapshot hydrates (label, running bit,
/// parent lineage from the shared sessions list).
class SubagentView {
  /// Stable subagent id.
  final String id;

  /// Parent session id that spawned this subagent.
  final String parentSessionId;

  /// Display label / task.
  final String label;

  /// Whether the subagent is still running.
  final bool running;

  /// Child session title when the host projection carries one.
  final String? preview;

  /// Wall time ms.
  final int updatedAt;

  /// Summed durable token-usage buckets (`tokenUsage` projection row), or
  /// `null` when the host row is absent or malformed. Missing means
  /// unavailable — never zero-filled, so callers omit the metrics row.
  final int? tokenTotal;

  /// Settled active-turn milliseconds (`subagentTiming.settledMs`), or `null`
  /// when the host row is absent or malformed.
  final int? timingSettledMs;

  /// Open-interval start of the timing row, kept paired with [timingActiveThrough].
  final int? timingActiveSince;

  /// Open-interval end of the timing row (last event time the fold saw).
  final int? timingActiveThrough;

  /// Creates a subagent view.
  const SubagentView({
    required this.id,
    required this.parentSessionId,
    required this.label,
    required this.running,
    this.preview,
    required this.updatedAt,
    this.tokenTotal,
    this.timingSettledMs,
    this.timingActiveSince,
    this.timingActiveThrough,
  });
}

/// Transcript line for a subagent child session, folded from the child's
/// durable event window (`user/message` / `assistant/message` / `tool/call`).
class SubagentTranscriptEntry {
  /// Line id (event seq).
  final String id;

  /// Role — `user` | `assistant` | `tool`.
  final String role;

  /// Text content.
  final String content;

  /// Wall time ms.
  final int time;

  /// Creates an entry.
  const SubagentTranscriptEntry({
    required this.id,
    required this.role,
    required this.content,
    required this.time,
  });
}

/// Subagent children of [parentSessionId] — derived from the shared sessions
/// list (`origin == 'subagent'`, oldest first), the same summary-known shape
/// React renders while the descriptor-backed catalog hydrates. No fixtures:
/// an unconnected boot shows the empty state, never invented rows.
final subagentsFamilyProvider = Provider.family<List<SubagentView>, String>((
  ref,
  parentSessionId,
) {
  final SessionsState sessions = ref.watch(sessionsProvider);
  final List<SubagentView> children =
      sessions.byId.values
          .where(
            (s) =>
                s.origin == 'subagent' &&
                s.parentSessionId != null &&
                s.parentSessionId!.value == parentSessionId,
          )
          .map((s) {
            final Map<String, dynamic>? values = s.projections?.values;
            final SubagentTimingRow timing = readSubagentTiming(
              values?['subagentTiming'],
            );
            return SubagentView(
              id: s.sessionId.value,
              parentSessionId: parentSessionId,
              label: s.title ?? s.sessionId.value,
              running: s.running,
              updatedAt: s.updatedAt,
              tokenTotal: subagentTokenTotal(values?['tokenUsage']),
              timingSettledMs: timing.settledMs,
              timingActiveSince: timing.activeSince,
              timingActiveThrough: timing.activeThrough,
            );
          })
          .toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  return children;
});

/// Legacy alias over the current session's children so existing watches keep
/// compiling; new code should watch [subagentsFamilyProvider] with the
/// screen's own parent id.
final subagentsProvider = Provider<List<SubagentView>>((ref) {
  final String? current = ref.watch(currentSessionIdProvider)?.value;
  if (current == null) return const [];
  return ref.watch(subagentsFamilyProvider(current));
});

/// First text line of one event payload (content string, block list, or
/// bare `text`/`message` field).
String _eventText(Map<String, dynamic> data) {
  final dynamic content = data['content'];
  if (content is String && content.isNotEmpty) return content;
  if (content is List) {
    for (final block in content) {
      if (block is Map) {
        final String? t =
            block['text'] as String? ?? block['content'] as String?;
        if (t != null && t.isNotEmpty) return t;
      } else if (block is String && block.isNotEmpty) {
        return block;
      }
    }
  }
  return (data['text'] as String?) ??
      (data['message'] as String?) ??
      (data['prompt'] as String?) ??
      '';
}

/// Folds one history window into transcript rows in event order.
List<SubagentTranscriptEntry> transcriptFromHistory(
  List<HistoryEntry> entries,
) {
  final List<SubagentTranscriptEntry> rows = [];
  for (final HistoryEntry entry in entries) {
    switch (entry.event.type) {
      case 'user/message':
        final String text = _eventText(entry.event.data);
        if (text.isNotEmpty) {
          rows.add(
            SubagentTranscriptEntry(
              id: '${entry.event.seq}',
              role: 'user',
              content: text,
              time: entry.event.time,
            ),
          );
        }
      case 'assistant/message':
        final String text = _eventText(entry.event.data);
        if (text.isNotEmpty) {
          rows.add(
            SubagentTranscriptEntry(
              id: '${entry.event.seq}',
              role: 'assistant',
              content: text,
              time: entry.event.time,
            ),
          );
        }
      case 'tool/call':
        final String name = entry.event.data['name'] as String? ?? 'tool';
        rows.add(
          SubagentTranscriptEntry(
            id: '${entry.event.seq}',
            role: 'tool',
            content: name,
            time: entry.event.time,
          ),
        );
    }
  }
  return rows;
}

/// Transcript of one subagent child session — read from the child's
/// authoritative `liveHistoryProvider` (session/follow snapshot), not
/// `session/page` probe. When the child's follow snapshot has not yet
/// arrived the transcript is empty until the window lands.
final subagentTranscriptProvider =
    FutureProvider.family<List<SubagentTranscriptEntry>, String>((
      ref,
      childSessionId,
    ) async {
      final live = ref.watch(liveHistoryProvider(childSessionId));
      if (live.isEmpty) return const <SubagentTranscriptEntry>[];
      return transcriptFromHistory(live);
    });

/// Selected subagent id — null means list view.
final selectedSubagentProvider = StateProvider<String?>((ref) => null);

/// Reads one `{key}` template from the `subagent` namespace dictionaries.
String _fill(String template, Map<String, Object> values) {
  var out = template;
  values.forEach((key, value) {
    out = out.replaceAll('{$key}', '$value');
  });
  return out;
}

/// Sums the four disjoint durable provider-usage buckets of one `tokenUsage`
/// projection row (`uncachedInputTokens + outputTokens + cacheReadTokens +
/// cacheWriteTokens`), mirroring `tokenTotal` in
/// `SubagentHeaderLineage.tsx`.
///
/// Returns `null` when the row is absent or malformed — missing means
/// unavailable, never zero — so callers omit the metrics row instead of
/// fabricating a `0 tok` claim. Token counts are never folded from history
/// events here: the token-meter replacement/retry accounting cannot be
/// reproduced from the transcript fold, and refolding would miscount.
int? subagentTokenTotal(dynamic usage) {
  if (usage is! Map) return null;
  var total = 0;
  for (final key in const [
    'uncachedInputTokens',
    'outputTokens',
    'cacheReadTokens',
    'cacheWriteTokens',
  ]) {
    final value = usage[key];
    if (value is! num || value < 0 || !value.isFinite) return null;
    total += value.toInt();
  }
  return total;
}

/// One validated `subagentTiming` projection row. All fields `null` means the
/// host row is absent or malformed (unavailable, not zero).
class SubagentTimingRow {
  /// Creates a validated timing row.
  const SubagentTimingRow({this.settledMs, this.activeSince, this.activeThrough});

  /// Settled base milliseconds (`settledMs`).
  final int? settledMs;

  /// Open-interval start, always paired with [activeThrough].
  final int? activeSince;

  /// Open-interval end (last event time the fold saw).
  final int? activeThrough;
}

/// Validates one `subagentTiming` projection value (`settledMs` plus the
/// paired `active:{since,through}` interval), mirroring the `activityDuration`
/// read in `SubagentHeaderLineage.tsx`. A half-present interval or a negative
/// bucket folds to unavailable; the timing fold is descriptor-gated host-side
/// and cannot be derived from the transcript rows here.
SubagentTimingRow readSubagentTiming(dynamic timing) {
  if (timing is! Map) return const SubagentTimingRow();
  final settled = timing['settledMs'];
  if (settled is! num || settled < 0 || !settled.isFinite) {
    return const SubagentTimingRow();
  }
  final active = timing['active'];
  if (active == null) return SubagentTimingRow(settledMs: settled.toInt());
  if (active is! Map) return const SubagentTimingRow();
  final since = active['since'];
  final through = active['through'];
  if (since is! num ||
      through is! num ||
      since < 0 ||
      through < 0 ||
      !since.isFinite ||
      !through.isFinite) {
    return const SubagentTimingRow();
  }
  return SubagentTimingRow(
    settledMs: settled.toInt(),
    activeSince: since.toInt(),
    activeThrough: through.toInt(),
  );
}

/// Exact whole-millisecond active-turn duration for one catalog row, mirroring
/// `activityDuration` in `SubagentHeaderLineage.tsx`: the settled base plus
/// the open interval closed at [nowMs] while [running], else at the last
/// event time the fold saw. Returns `null` when the timing row is unavailable.
int? subagentActiveDurationMs({
  required int? settledMs,
  required int? activeSince,
  required int? activeThrough,
  required bool running,
  required int nowMs,
}) {
  if (settledMs == null) return null;
  if (activeSince == null) return settledMs;
  final end = running ? nowMs : activeThrough ?? nowMs;
  return settledMs + max(0, end - activeSince);
}

/// Compact token count sharing the conversation stats-strip shape, mirroring
/// `formatTokens` in `SubagentHeaderLineage.tsx` through the `subagent`
/// namespace `tokens.*` templates.
String formatSubagentTokens(int value, [Map<String, String>? dict]) {
  final d = dict ?? kSubagentEn;
  String scaled(double next) {
    if (next >= 100) return '${next.round()}';
    final rounded = (next * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.round()}'
        : '$rounded';
  }

  if (value < 1000) return '$value';
  if (value < 1000000) {
    return _fill(d['tokens.thousand']!, {'value': scaled(value / 1000)});
  }
  return _fill(d['tokens.million']!, {'value': scaled(value / 1000000)});
}

class _DurationParts {
  const _DurationParts({
    required this.seconds,
    required this.minutes,
    required this.hours,
    required this.days,
    required this.totalMinutes,
    required this.totalHours,
  });

  final int seconds;
  final int minutes;
  final int hours;
  final int days;
  final int totalMinutes;
  final int totalHours;
}

_DurationParts _splitDuration(int ms) {
  final totalSeconds = (max(0, ms) / 1000).floor();
  final totalMinutes = totalSeconds ~/ 60;
  final totalHours = totalMinutes ~/ 60;
  return _DurationParts(
    seconds: totalSeconds % 60,
    minutes: totalMinutes % 60,
    hours: totalHours % 24,
    days: totalHours ~/ 24,
    totalMinutes: totalMinutes,
    totalHours: totalHours,
  );
}

String _pad2(int value) => '$value'.padLeft(2, '0');

/// Formats a duration with decreasing visual precision at larger scales,
/// mirroring `formatDuration` in `SubagentHeaderLineage.tsx` through the
/// `subagent` namespace `duration.*` templates.
String formatSubagentDuration(int ms, [Map<String, String>? dict]) {
  final d = dict ?? kSubagentEn;
  final parts = _splitDuration(ms);
  if (parts.days >= 365) {
    final years = parts.days ~/ 365;
    final months = (parts.days % 365) ~/ 30;
    return months == 0
        ? _fill(d['duration.years']!, {'years': years})
        : _fill(d['duration.yearsMonths']!, {'years': years, 'months': months});
  }
  if (parts.days >= 30) {
    final months = parts.days ~/ 30;
    final days = parts.days % 30;
    return days == 0
        ? _fill(d['duration.months']!, {'months': months})
        : _fill(d['duration.monthsDays']!, {'months': months, 'days': days});
  }
  if (parts.days > 0) {
    return parts.hours == 0
        ? _fill(d['duration.days']!, {'days': parts.days})
        : _fill(d['duration.daysHours']!, {
            'days': parts.days,
            'hours': parts.hours,
          });
  }
  if (parts.totalHours > 0) {
    return _fill(d['duration.hours']!, {
      'hours': parts.totalHours,
      'minutes': _pad2(parts.minutes),
      'seconds': _pad2(parts.seconds),
    });
  }
  if (parts.totalMinutes > 0) {
    return _fill(d['duration.minutes']!, {
      'minutes': parts.totalMinutes,
      'seconds': _pad2(parts.seconds),
    });
  }
  return _fill(d['duration.seconds']!, {'seconds': parts.seconds});
}

/// One metrics line for a catalog/screen row (`tokens · duration`), mirroring
/// the `metrics` join in `SubagentHeaderLineage.tsx`. Returns `null` when
/// neither projection row is present — the row then renders no metrics line
/// instead of a fabricated zero. [nowMs] closes the open timing interval of a
/// running child; pass a fixed clock in tests.
String? subagentMetricsLabel(
  SubagentView view, {
  required int nowMs,
  Map<String, String>? dict,
}) {
  return _joinMetrics(
    tokenTotal: view.tokenTotal,
    settledMs: view.timingSettledMs,
    activeSince: view.timingActiveSince,
    activeThrough: view.timingActiveThrough,
    running: view.running,
    nowMs: nowMs,
    dict: dict,
  );
}

/// Metrics line for a raw [SessionSummary] row (the header catalog menu holds
/// summaries, not views) — same join and same unavailable-means-omitted rule.
String? subagentMetricsForSummary(
  SessionSummary summary, {
  required int nowMs,
  Map<String, String>? dict,
}) {
  final Map<String, dynamic>? values = summary.projections?.values;
  final SubagentTimingRow timing = readSubagentTiming(values?['subagentTiming']);
  return _joinMetrics(
    tokenTotal: subagentTokenTotal(values?['tokenUsage']),
    settledMs: timing.settledMs,
    activeSince: timing.activeSince,
    activeThrough: timing.activeThrough,
    running: summary.running,
    nowMs: nowMs,
    dict: dict,
  );
}

String? _joinMetrics({
  required int? tokenTotal,
  required int? settledMs,
  required int? activeSince,
  required int? activeThrough,
  required bool running,
  required int nowMs,
  Map<String, String>? dict,
}) {
  final d = dict ?? kSubagentEn;
  final String? tokenMetric = tokenTotal == null
      ? null
      : _fill(d['tokens.total']!, {'value': formatSubagentTokens(tokenTotal, d)});
  final int? durationMs = subagentActiveDurationMs(
    settledMs: settledMs,
    activeSince: activeSince,
    activeThrough: activeThrough,
    running: running,
    nowMs: nowMs,
  );
  final String? durationMetric = durationMs == null
      ? null
      : formatSubagentDuration(durationMs, d);
  final parts = [tokenMetric, durationMetric].whereType<String>().toList();
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}
