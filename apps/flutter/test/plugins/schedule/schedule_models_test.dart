import 'package:dsh_flutter/src/plugins/schedule/locales.dart';
import 'package:dsh_flutter/src/plugins/schedule/schedule_models.dart';
import 'package:flutter_test/flutter_test.dart';

String _en(String key, [Map<String, Object?>? params]) {
  var out = kScheduleEn[key]!;
  params?.forEach((name, value) {
    out = out.replaceAll('{$name}', '$value');
  });
  return out;
}

ScheduleRecord _record({
  String id = 'r1',
  String kind = 'every',
  String prompt = 'Standup',
  int? everySeconds,
  required String scheduledAt,
}) {
  return ScheduleRecord(
    id: id,
    kind: kind,
    prompt: prompt,
    everySeconds: everySeconds,
    scheduledAt: DateTime.parse(scheduledAt),
  );
}

void main() {
  final t = scheduleStrings(_en);

  group('formatScheduleFrequency', () {
    test('one-shot kinds render once', () {
      final record = _record(kind: 'after', scheduledAt: '2026-09-10T12:00:00Z');
      expect(formatScheduleFrequency(record, t), 'Once');
    });

    test('picks the largest exact whole unit', () {
      expect(
        formatScheduleFrequency(
          _record(everySeconds: 86400, scheduledAt: '2026-09-10T12:00:00Z'),
          t,
        ),
        'Every 1 day',
      );
      expect(
        formatScheduleFrequency(
          _record(everySeconds: 3600, scheduledAt: '2026-09-10T12:00:00Z'),
          t,
        ),
        'Every 1 hour',
      );
      expect(
        formatScheduleFrequency(
          _record(everySeconds: 300, scheduledAt: '2026-09-10T12:00:00Z'),
          t,
        ),
        'Every 5 minutes',
      );
    });

    test('non-divisible interval falls back to seconds', () {
      expect(
        formatScheduleFrequency(
          _record(everySeconds: 90, scheduledAt: '2026-09-10T12:00:00Z'),
          t,
        ),
        'Every 90 seconds',
      );
    });
  });

  group('formatScheduleRelative', () {
    test('exact zero renders due now', () {
      const now = 1700000000000;
      final record = _record(
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(
          now,
          isUtc: true,
        ).toIso8601String(),
      );
      expect(formatScheduleRelative(record, now, t), 'Due now');
    });

    test('future rounds up to the largest natural unit', () {
      const now = 1700000000000;
      final record = _record(
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(
          now + 2 * 3600 * 1000,
          isUtc: true,
        ).toIso8601String(),
      );
      expect(formatScheduleRelative(record, now, t), 'in 2 hours');
    });

    test('overdue rounds down with overdue template', () {
      const now = 1700000000000;
      final record = _record(
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(
          now - 30 * 60 * 1000,
          isUtc: true,
        ).toIso8601String(),
      );
      expect(formatScheduleRelative(record, now, t), '30 minutes overdue');
    });
  });

  group('orderScheduleRecords', () {
    test('overdue first, then ascending, stable ties', () {
      const now = 1700000000000;
      String at(int ms) => DateTime.fromMillisecondsSinceEpoch(
        ms,
        isUtc: true,
      ).toIso8601String();
      final future = _record(
        id: 'future',
        scheduledAt: at(now + 3600000),
      );
      final overdueOld = _record(
        id: 'overdue-old',
        scheduledAt: at(now - 7200000),
      );
      final overdueNew = _record(
        id: 'overdue-new',
        scheduledAt: at(now - 60000),
      );
      final tieA = _record(id: 'tie-a', scheduledAt: at(now + 1000));
      final tieB = _record(id: 'tie-b', scheduledAt: at(now + 1000));
      final ordered = orderScheduleRecords(
        [future, tieB, overdueNew, tieA, overdueOld],
        now,
      );
      expect(
        ordered.map((r) => r.id),
        ['overdue-old', 'overdue-new', 'tie-b', 'tie-a', 'future'],
      );
    });
  });

  group('ScheduleRecord.fromJson', () {
    test('decodes an every record', () {
      final record = ScheduleRecord.fromJson({
        'id': 's1',
        'kind': 'every',
        'prompt': 'Sync',
        'everySeconds': 300,
        'scheduledAt': '2026-09-10T12:05:00.000Z',
      });
      expect(record?.id, 's1');
      expect(record?.everySeconds, 300);
      expect(record?.scheduledAt?.toUtc().toIso8601String(),
          '2026-09-10T12:05:00.000Z');
    });

    test('rejects missing identity, unknown kind, keeps bad date as null', () {
      expect(ScheduleRecord.fromJson({'kind': 'at'}), isNull);
      expect(
        ScheduleRecord.fromJson({
          'id': 'x',
          'kind': 'someday',
          'prompt': 'p',
        }),
        isNull,
      );
      final badDate = ScheduleRecord.fromJson({
        'id': 'x',
        'kind': 'at',
        'prompt': 'p',
        'scheduledAt': 'not-a-date',
      });
      expect(badDate?.scheduledAt, isNull);
    });
  });

  group('scheduleRecordsFromValues', () {
    test('absent or non-list slices yield empty', () {
      expect(scheduleRecordsFromValues(null), isEmpty);
      expect(scheduleRecordsFromValues({}), isEmpty);
      expect(scheduleRecordsFromValues({'schedule': 'nope'}), isEmpty);
    });

    test('skips malformed entries', () {
      final records = scheduleRecordsFromValues({
        'schedule': [
          {
            'id': 'ok',
            'kind': 'at',
            'prompt': 'Hi',
            'scheduledAt': '2026-09-10T12:00:00Z',
          },
          {'kind': 'at'},
          'junk',
        ],
      });
      expect(records.map((r) => r.id), ['ok']);
    });
  });

  group('locales', () {
    test('en mirrors every zh key', () {
      expect(Set.of(kScheduleEn.keys), Set.of(kScheduleZh.keys));
    });
  });
}
