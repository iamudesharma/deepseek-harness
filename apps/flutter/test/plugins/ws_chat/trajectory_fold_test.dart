/// Focused coverage for the trajectory history fold
/// (`trajectoryFromHistory`): turn-envelope mode, user-boundary fallback,
/// status derivation, and tool-call joining by time window.
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/trajectory/trajectory_provider.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryEntry _entry(String type, Map<String, dynamic> data, int seq, int time) =>
    HistoryEntry(event: SessionEvent(type: type, data: data, seq: seq, time: time));

void main() {
  test('empty history yields an empty trajectory', () {
    final t = trajectoryFromHistory('s-1', const []);
    expect(t.sessionId, 's-1');
    expect(t.turns, isEmpty);
    expect(t.isRunning, isFalse);
    expect(t.totalDurationMs, isNull);
  });

  test('turn envelopes bound turns; isError marks the turn failed', () {
    final entries = [
      _entry('turn/start', {'turnId': 't1', 'title': 'First'}, 1, 1000),
      _entry('assistant/message', {'content': 'working'}, 2, 1100),
      _entry('turn/end', {'turnId': 't1'}, 3, 2000),
      _entry('turn/start', {'turnId': 't2', 'title': 'Second'}, 4, 3000),
      _entry('turn/end', {'turnId': 't2', 'isError': true}, 5, 3500),
    ];

    final t = trajectoryFromHistory('s-1', entries);

    expect(t.turns, hasLength(2));
    expect(t.turns[0].id, 't1');
    expect(t.turns[0].ordinal, 1);
    expect(t.turns[0].title, 'First');
    expect(t.turns[0].status, TurnStatus.completed);
    expect(t.turns[0].durationMs, 1000);
    expect(t.turns[1].status, TurnStatus.failed);
  });

  test('a dangling turn envelope stays running at the log tail', () {
    final entries = [
      _entry('turn/start', {'turnId': 't9', 'title': 'Open'}, 1, 500),
      _entry('assistant/message', {'content': 'still going'}, 2, 600),
    ];

    final t = trajectoryFromHistory('s-1', entries);

    expect(t.turns.single.status, TurnStatus.running);
    expect(t.turns.single.endTime, isNull);
    expect(t.isRunning, isTrue);
  });

  test('without envelopes, user messages start turns and assistant text becomes summary', () {
    final entries = [
      _entry('user/message', {'content': 'Summarize the repo'}, 1, 1000),
      _entry('tool/call', {'name': 'read'}, 2, 1500),
      _entry('tool/result', {}, 3, 1600),
      _entry('assistant/message', {'content': 'It is a plugin harness.'}, 4, 2000),
      _entry('user/message', {'content': 'Now list packages'}, 5, 5000),
      _entry('assistant/chunk', {'text': '…'}, 6, 5500),
    ];

    final t = trajectoryFromHistory('s-1', entries);

    expect(t.turns, hasLength(2));
    expect(t.turns[0].title, contains('Summarize'));
    expect(t.turns[0].summary, 'It is a plugin harness.');
    expect(t.turns[0].status, TurnStatus.completed);
    // Tool calls inside the window join the owning turn.
    expect(t.turns[0].toolCalls.map((c) => c.toolName), ['read']);
    // The trailing chunk keeps the last turn running.
    expect(t.turns[1].status, TurnStatus.running);
    expect(t.isRunning, isTrue);
  });

  test('no user messages folds the whole log into one initial turn', () {
    final entries = [
      _entry('assistant/message', {'content': 'hello'}, 1, 100),
      _entry('assistant/message', {'content': 'world'}, 2, 200),
    ];

    final t = trajectoryFromHistory('s-1', entries);

    expect(t.turns, hasLength(1));
    expect(t.turns.single.id, 'turn-1');
    expect(t.turns.single.summary, 'hello\n\nworld');
    expect(t.turns.single.status, TurnStatus.completed);
  });
}
