/// Workspace/Session row label helpers — port of
/// `packages/client/ui-workspace/src/client/rows/Rows.tsx:createdLabel`,
/// `packages/client/ui-workspace/src/client/tree.ts:relativeTime`,
/// and `workspaceLabel`.
///
/// All pure functions, injected `now` for determinism in tests.
/// Dart port keeps the same compact bucket vocabulary as the TS
/// `RelativeTimeUnit` (now/minutes/hours/days/months/years) and the same
/// formatting contract the dictionaries consume.

/// Structured relative time bucket.
class RelativeTime {
  const RelativeTime({required this.unit, required this.n});
  final String unit; // 'now' | 'minutes' | 'hours' | 'days' | 'months' | 'years'
  final int n;
}

/// Compact relative time for session rows.
/// Mirrors `tree.ts:relativeTime`.
RelativeTime relativeTime(int updatedAt, int now) {
  const int min = 60000;
  const int hour = 3600000;
  const int day = 86400000;
  final int diff = (now - updatedAt).clamp(0, 1 << 62);
  if (diff < min) return const RelativeTime(unit: 'now', n: 0);
  if (diff < hour) return RelativeTime(unit: 'minutes', n: diff ~/ min);
  if (diff < day) return RelativeTime(unit: 'hours', n: diff ~/ hour);
  if (diff < 30 * day) return RelativeTime(unit: 'days', n: diff ~/ day);
  if (diff < 365 * day) return RelativeTime(unit: 'months', n: diff ~/ (30 * day));
  return RelativeTime(unit: 'years', n: diff ~/ (365 * day));
}

/// Localized compact label ("now"/"5m"/"3h"/"2d" …).
/// Pass through to dictionaries in production; this is the `en` fallback.
String timeLabel(int updatedAt, int now) {
  final r = relativeTime(updatedAt, now);
  if (r.unit == 'now') return 'now';
  if (r.unit == 'minutes') return '${r.n}m';
  if (r.unit == 'hours') return '${r.n}h';
  if (r.unit == 'days') return '${r.n}d';
  if (r.unit == 'months') return '${r.n}mo';
  return '${r.n}y';
}

/// Hover time label — distance wrapped in ago template, now stays bare.
/// Mirrors `Rows.tsx:hoverTimeLabel`.
String hoverTimeLabel(int updatedAt, int now) {
  final r = relativeTime(updatedAt, now);
  if (r.unit == 'now') return 'now';
  final base = timeLabel(updatedAt, now);
  return '$base ago';
}

/// Absolute creation time label — dictionary `date.ymd` + `hover.created`
/// contract without browser locale (mirrors `Rows.tsx:createdLabel`).
///
/// Uses dictionary templates:
/// - `date.ymd` = "{y}/{m}/{d}" or "{y}-{m}-{d}" depending on locale
/// - `hover.created` = "Created {time}"
///
/// This Dart helper returns the formatted wall time directly for en:
/// "Created 2024/08/24 14:30". Callers that go through locale should
/// instead compose via their `t('date.ymd', …)` + `t('hover.created', …)`.
String createdLabel(int createdAtMillis) {
  final d = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  String pad2(int v) => v.toString().padLeft(2, '0');
  final date = '${d.year}/${d.month}/${d.day}';
  final time = '${pad2(d.hour)}:${pad2(d.minute)}';
  return 'Created $date $time';
}

/// Workspace display label: basename of the path (both separators accepted).
/// Ungrouped bucket fallback mirrors `tree.ts:workspaceLabel`.
String workspaceLabel(String? cwd) {
  if (cwd == null || cwd.isEmpty) return 'Ungrouped';
  final base = cwd.replaceAll(RegExp(r'[/\\]+$'), '').split(RegExp(r'[/\\]')).last;
  if (base.isNotEmpty) return base;
  return cwd;
}
