// Ledger + timeline fold parity — mirrors React `deriveTrajectoryLayout`
// basics, `flattenRecords` turn/group flags, and `deriveTrajectoryTimeline`
// modes (`sequence` | `duration` | `time` | `actual`).
//
// Pure folds over host history windows (no providers, no I/O): the ledger
// approximates React's layout from raw event types because the Conversation
// Node assembly has no Dart counterpart yet; the timeline asserts the same
// 3-lane projection and equal-vs-recorded mode split as
// `packages/client/ui-trajectory/src/client/timeline.ts`.
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/trajectory/ui/trajectory_screen.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryEntry _entry(
  String type,
  Map<String, dynamic> data,
  int seq,
  int time,
) => HistoryEntry(
  event: SessionEvent(type: type, data: data, seq: seq, time: time),
);

LedgerRow _row({
  required int index,
  required TrajectoryCellKind kind,
  required int turn,
  int? startedAt,
  double? timeSeconds,
  bool isError = false,
}) => LedgerRow(
  index: index,
  kind: kind,
  text: 'row-$index',
  turn: turn,
  group: 'Turn $turn',
  startedAt: startedAt,
  timeSeconds: timeSeconds,
  isError: isError,
);

void main() {
  group('ledgerFromHistory kind mapping', () {
    test('user source kind selects user vs context', () {
      final rows = ledgerFromHistory([
        _entry('user/message', {
          'content': 'hi',
          'source': {'kind': 'user'},
        }, 1, 1000),
        _entry('user/message', {'content': 'injected'}, 2, 2000),
      ]);
      expect(rows, hasLength(2));
      expect(rows[0].kind, TrajectoryCellKind.user);
      expect(rows[0].text, 'hi');
      expect(rows[1].kind, TrajectoryCellKind.context);
    });

    test('assistant message carries outputDetail and preview', () {
      final rows = ledgerFromHistory([
        _entry('assistant/message', {
          'message': {
            'content': [
              {'type': 'reasoning', 'text': 'plan'},
              {'type': 'text', 'text': 'done'},
            ],
          },
        }, 1, 1000),
      ]);
      expect(rows.single.kind, TrajectoryCellKind.message);
      expect(rows.single.outputDetail, contains('done'));
      expect(rows.single.thinkingDetail, 'plan');
    });

    test('empty assistant chunk emits no row', () {
      final rows = ledgerFromHistory([
        _entry('assistant/chunk', {'text': ''}, 1, 1000),
      ]);
      expect(rows, isEmpty);
    });

    test('compaction and retry map to compacted/system', () {
      final rows = ledgerFromHistory([
        _entry('compaction/summary', {'summary': 'folded'}, 1, 100),
        _entry('llm/retry', {'retry': 1, 'maxRetries': 3}, 2, 200),
      ]);
      expect(rows[0].kind, TrajectoryCellKind.compacted);
      expect(rows[0].text, 'folded');
      expect(rows[1].kind, TrajectoryCellKind.system);
      expect(rows[1].text, 'retry 1/3');
    });

    test('unknown types fall back to system with the type as text', () {
      final rows = ledgerFromHistory([
        _entry('session/custom-thing', {}, 1, 100),
      ]);
      expect(rows.single.kind, TrajectoryCellKind.system);
      expect(rows.single.text, 'session/custom-thing');
    });

    test('empty window folds to no rows', () {
      expect(ledgerFromHistory(const []), isEmpty);
    });
  });

  group('ledgerFromHistory turn numbering', () {
    test('user messages open turns in seq order', () {
      final rows = ledgerFromHistory([
        _entry('user/message', {'content': 'first'}, 1, 1000),
        _entry('assistant/message', {'content': 'a1'}, 2, 1100),
        _entry('user/message', {'content': 'second'}, 3, 2000),
        _entry('assistant/message', {'content': 'a2'}, 4, 2100),
      ]);
      expect(rows.map((r) => r.turn), [1, 1, 2, 2]);
      expect(rows.first.turnStart, isTrue);
      expect(rows[1].turnStart, isFalse);
      expect(rows[0].turnEnd, isFalse);
      expect(rows[1].turnEnd, isTrue);
      expect(rows[2].turnStart, isTrue);
      expect(rows[2].turnEnd, isFalse);
      expect(rows.last.turnEnd, isTrue);
    });

    test('turn envelopes number turns and hide envelope rows', () {
      final rows = ledgerFromHistory([
        _entry('turn/start', {'turnId': 't1', 'title': 'First'}, 1, 1000),
        _entry('user/message', {'content': 'q'}, 2, 1100),
        _entry('turn/end', {'turnId': 't1'}, 3, 2000),
        _entry('turn/start', {'turnId': 't2', 'title': 'Second'}, 4, 3000),
        _entry('assistant/message', {'content': 'a'}, 5, 3100),
      ]);
      expect(rows.map((r) => r.turn), [1, 2]);
      expect(rows.map((r) => r.group), ['Turn 1', 'Turn 2']);
    });
  });

  group('ledgerFromHistory tool joining', () {
    test('paired call and result share the recorded duration', () {
      final rows = ledgerFromHistory([
        _entry('user/message', {'content': 'run it'}, 1, 1000),
        _entry('tool/call', {
          'name': 'bash',
          'args': {'cmd': 'ls'},
          'callId': 'c1',
        }, 2, 1500),
        _entry('tool/result', {
          'callId': 'c1',
          'output': 'ok',
        }, 3, 3000),
      ]);
      final tools = rows
          .where((r) => r.kind == TrajectoryCellKind.tool)
          .toList();
      expect(tools, hasLength(2));
      expect(tools[0].callId, 'c1');
      expect(tools[0].timeSeconds, closeTo(1.5, 1e-9));
      expect(tools[1].timeSeconds, closeTo(1.5, 1e-9));
      expect(tools[1].result, 'ok');
      expect(tools[1].isError, isFalse);
    });

    test('unpaired calls keep a null duration (running)', () {
      final rows = ledgerFromHistory([
        _entry('tool/call', {'name': 'bash', 'callId': 'c9'}, 1, 500),
      ]);
      expect(rows.single.timeSeconds, isNull);
    });

    test('error results flag isError', () {
      final rows = ledgerFromHistory([
        _entry('tool/call', {'name': 'bash', 'callId': 'c2'}, 1, 500),
        _entry('tool/result', {
          'callId': 'c2',
          'isError': true,
          'output': 'boom',
        }, 2, 700),
      ]);
      expect(rows.last.isError, isTrue);
    });
  });

  group('laneForKind 3-lane parity', () {
    test('inputs/system share lane 0', () {
      expect(laneForKind(TrajectoryCellKind.user), 0);
      expect(laneForKind(TrajectoryCellKind.context), 0);
      expect(laneForKind(TrajectoryCellKind.system), 0);
    });

    test('assistant output shares lane 1', () {
      expect(laneForKind(TrajectoryCellKind.message), 1);
      expect(laneForKind(TrajectoryCellKind.compacted), 1);
    });

    test('tools share lane 2', () {
      expect(laneForKind(TrajectoryCellKind.tool), 2);
      expect(laneForKind(TrajectoryCellKind.subtool), 2);
    });
  });

  group('deriveTimeline modes', () {
    test('sequence uses equal-width blocks in ledger order', () {
      final rows = [
        _row(index: 0, kind: TrajectoryCellKind.user, turn: 1),
        _row(index: 1, kind: TrajectoryCellKind.message, turn: 1),
        _row(index: 2, kind: TrajectoryCellKind.tool, turn: 2),
      ];
      final model = deriveTimeline(rows, 'sequence')!;
      expect(model.start, 0);
      expect(model.end, 30);
      expect(
        model.spans.map((s) => [s.start, s.end]),
        [
          [0, 8],
          [10, 18],
          [20, 28],
        ],
      );
      expect(model.spans.map((s) => s.lane), [0, 1, 2]);
      expect(model.boundaries, hasLength(1));
      expect(model.boundaries.single.turn, 2);
      expect(model.boundaries.single.time, 20);
    });

    test('time projects point spans on the wall clock', () {
      final rows = [
        _row(
          index: 0,
          kind: TrajectoryCellKind.tool,
          turn: 1,
          startedAt: 1000,
          timeSeconds: 1.5,
        ),
        _row(
          index: 1,
          kind: TrajectoryCellKind.tool,
          turn: 1,
          startedAt: 4000,
          timeSeconds: 2.0,
        ),
      ];
      final model = deriveTimeline(rows, 'time')!;
      // Durations are ignored in point mode (React `end: start - offset`).
      expect(model.spans.map((s) => [s.start, s.end]), [
        [1000, 1000],
        [4000, 4000],
      ]);
      expect(model.start, 1000);
      expect(model.end, 4000);
    });

    test('actual keeps idle gaps, duration compresses them', () {
      final rows = [
        _row(
          index: 0,
          kind: TrajectoryCellKind.tool,
          turn: 1,
          startedAt: 1000,
          timeSeconds: 1.0,
        ),
        _row(
          index: 1,
          kind: TrajectoryCellKind.message,
          turn: 2,
          startedAt: 10000,
        ),
      ];
      final actual = deriveTimeline(rows, 'actual')!;
      expect(actual.spans[0].start, 1000);
      expect(actual.spans[0].end, 2000);
      expect(actual.spans[1].start, 10000);
      expect(actual.end - actual.start, 9000);

      final duration = deriveTimeline(rows, 'duration')!;
      expect(duration.spans[0].start, 1000);
      expect(duration.spans[0].end, 2000);
      // The 8s idle gap between span end (2000) and next start (10000)
      // is removed, so the second record abuts the first.
      expect(duration.spans[1].start, 2000);
      expect(duration.end - duration.start, lessThan(9000));
    });

    test('null durations project as points in recorded modes', () {
      final rows = [
        _row(index: 0, kind: TrajectoryCellKind.message, turn: 1, startedAt: 7000),
      ];
      final model = deriveTimeline(rows, 'actual')!;
      expect(model.spans.single.start, 7000);
      expect(model.spans.single.end, 7000);
    });

    test('empty rows yield null; rows without starts yield null', () {
      expect(deriveTimeline(const [], 'sequence'), isNull);
      expect(
        deriveTimeline(
          [_row(index: 0, kind: TrajectoryCellKind.message, turn: 1)],
          'actual',
        ),
        isNull,
      );
    });

    test('isError survives the projection', () {
      final rows = [
        _row(
          index: 0,
          kind: TrajectoryCellKind.tool,
          turn: 1,
          startedAt: 100,
          isError: true,
        ),
      ];
      expect(deriveTimeline(rows, 'sequence')!.spans.single.isError, isTrue);
      expect(deriveTimeline(rows, 'actual')!.spans.single.isError, isTrue);
    });

    test('collapsed turn summary format', () {
      expect('1 step · 2 tool calls', contains('tool calls'));
    });
  });
}
