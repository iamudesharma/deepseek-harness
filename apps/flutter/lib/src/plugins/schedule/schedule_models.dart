/// Schedule record model plus the portable catalog helpers — Dart port of
/// `packages/schedule/schedule/src/types.ts` (`ScheduleRecord`) and the pure
/// functions in `packages/client/ui-schedule/src/client/ScheduleCatalogAction.tsx`
/// (`formatScheduleFrequency`, `formatScheduleRelative`, `orderScheduleRecords`).
///
/// Rule math stays pure and deterministic: all helpers take an explicit `now`
/// ms clock (React reads `Date.now()` at the call site; tests inject it).
/// Local-time rendering is left to the widget via `scheduledDateTime`
/// (Material localizations), matching React's `Intl.DateTimeFormat` role.
library;

import 'locales.dart' show scheduleText;

/// Text face for catalog copy: key lookup plus `{name}` interpolation.
typedef ScheduleStrings =
    String Function(String key, [Map<String, Object?>? params]);

/// Binds [scheduleText] over a key-only translate face.
ScheduleStrings scheduleStrings(String Function(String key) t) {
  return (String key, [Map<String, Object?>? params]) =>
      scheduleText(t, key, params);
}

/// One durable reminder record (union member of `ScheduleRecord`).
class ScheduleRecord {
  /// Session-local stable identity.
  final String id;

  /// Rule discriminator: `after` | `at` | `every`.
  final String kind;

  /// Trimmed reminder content supplied at creation.
  final String prompt;

  /// Positive delay for `after` records.
  final int? afterSeconds;

  /// Fixed interval for `every` records (never below five minutes).
  final int? everySeconds;

  /// Anchor-aligned UTC target (RFC 3339); null when malformed.
  final DateTime? scheduledAt;

  /// Creates a record.
  const ScheduleRecord({
    required this.id,
    required this.kind,
    required this.prompt,
    this.afterSeconds,
    this.everySeconds,
    this.scheduledAt,
  });

  /// Whether the target is at or before [nowMs].
  bool isOverdue(int nowMs) {
    final target = scheduledAt;
    if (target == null) return false;
    return target.millisecondsSinceEpoch <= nowMs;
  }

  /// Tolerant decode: malformed entries return null and are skipped by
  /// [scheduleRecordsFromValues] (never a throw on host data).
  /// @param json - one `ScheduleRecord` wire map.
  static ScheduleRecord? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = json['kind'];
    final prompt = json['prompt'];
    if (id is! String || kind is! String || prompt is! String) return null;
    if (kind != 'after' && kind != 'at' && kind != 'every') return null;
    int? asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);
    DateTime? at;
    final rawAt = json['scheduledAt'];
    if (rawAt is String) {
      try {
        at = DateTime.parse(rawAt);
      } catch (_) {
        at = null;
      }
    }
    return ScheduleRecord(
      id: id,
      kind: kind,
      prompt: prompt,
      afterSeconds: asInt(json['afterSeconds']),
      everySeconds: asInt(json['everySeconds']),
      scheduledAt: at,
    );
  }
}

/// Decodes the `schedule` projection slice (`projections.values['schedule']`).
///
/// Mirrors `useProjection('schedule')`: absent or malformed slices yield an
/// empty list (the action renders nothing), never a throw.
/// @param values - session `projections.values` map, if present.
List<ScheduleRecord> scheduleRecordsFromValues(Map<String, dynamic>? values) {
  return scheduleRecordsFromList(values?['schedule']);
}

/// Decodes one raw projection value (snapshot slice or push frame payload).
///
/// @param raw - the `schedule` key's whole value, if present.
List<ScheduleRecord> scheduleRecordsFromList(Object? raw) {
  if (raw is! List) return const [];
  final out = <ScheduleRecord>[];
  for (final entry in raw) {
    if (entry is Map<String, dynamic>) {
      final record = ScheduleRecord.fromJson(entry);
      if (record != null) out.add(record);
    } else if (entry is Map) {
      final record = ScheduleRecord.fromJson(entry.cast<String, dynamic>());
      if (record != null) out.add(record);
    }
  }
  return List<ScheduleRecord>.unmodifiable(out);
}

/// Largest exact whole unit without rounding the durable interval.
///
/// `every` records pick the largest unit dividing `everySeconds`; one-shot
/// kinds render `frequency.once`. Port of `formatScheduleFrequency`.
String formatScheduleFrequency(ScheduleRecord record, ScheduleStrings t) {
  if (record.kind != 'every') return t('frequency.once');
  final every = record.everySeconds ?? 0;
  const units = [
    ('day', 86400),
    ('hour', 3600),
    ('minute', 60),
    ('second', 1),
  ];
  var selected = units.last;
  for (final candidate in units) {
    if (every % candidate.$2 == 0) {
      selected = candidate;
      break;
    }
  }
  final value = every ~/ selected.$2;
  final unit = t(
    'unit.${selected.$1}.${value == 1 ? 'one' : 'other'}',
    {'count': value},
  );
  return t('frequency.every', {'value': value, 'unit': unit});
}

/// Human relative target using the largest natural clock unit.
///
/// Exact port of `formatScheduleRelative` (ceil future, floor overdue,
/// minimum magnitude 1, exact-zero renders `relative.now`).
String formatScheduleRelative(
  ScheduleRecord record,
  int nowMs,
  ScheduleStrings t,
) {
  final target = record.scheduledAt;
  if (target == null) return t('relative.now');
  final difference = target.millisecondsSinceEpoch - nowMs;
  if (difference == 0) return t('relative.now');
  final absoluteSeconds = (difference.abs() / 1000).floor();
  const units = [
    ('day', 86400),
    ('hour', 3600),
    ('minute', 60),
    ('second', 1),
  ];
  var selected = units.last;
  for (final candidate in units) {
    if (absoluteSeconds >= candidate.$2) {
      selected = candidate;
      break;
    }
  }
  var value = difference > 0
      ? (difference / 1000 / selected.$2).ceil()
      : (difference.abs() / 1000 / selected.$2).floor();
  if (value < 1) value = 1;
  final unit = t(
    'unit.${selected.$1}.${value == 1 ? 'one' : 'other'}',
    {'count': value},
  );
  return t(
    difference > 0 ? 'relative.future' : 'relative.overdue',
    {'value': value, 'unit': unit},
  );
}

/// Overdue records first, then ascending target time; exact ties stay stable.
///
/// Port of `orderScheduleRecords`. Records with a malformed target sort last
/// (React's `NaN` comparisons keep them scheduled; Dart has no NaN epoch, so
/// null targets take the tail explicitly).
List<ScheduleRecord> orderScheduleRecords(
  List<ScheduleRecord> records,
  int nowMs,
) {
  final indexed = records.indexed.toList();
  indexed.sort((left, right) {
    final leftTime = left.$2.scheduledAt?.millisecondsSinceEpoch;
    final rightTime = right.$2.scheduledAt?.millisecondsSinceEpoch;
    final leftOverdue = leftTime != null && leftTime <= nowMs;
    final rightOverdue = rightTime != null && rightTime <= nowMs;
    if (leftOverdue != rightOverdue) return rightOverdue ? 1 : -1;
    if (leftTime == null && rightTime == null) return left.$1 - right.$1;
    if (leftTime == null) return 1;
    if (rightTime == null) return -1;
    return leftTime - rightTime != 0
        ? leftTime - rightTime
        : left.$1 - right.$1;
  });
  return List<ScheduleRecord>.unmodifiable(
    indexed.map((entry) => entry.$2),
  );
}
