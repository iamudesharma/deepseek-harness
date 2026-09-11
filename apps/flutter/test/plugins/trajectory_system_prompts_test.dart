import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/trajectory/trajectory_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trajectory `systemPrompts` fold vectors (React
/// `TrajectorySnapshot.systemPrompts` parity).
HistoryEntry _entry(
  String type,
  Map<String, dynamic> data,
  int seq,
  int time,
) => HistoryEntry(
  event: SessionEvent(type: type, data: data, seq: seq, time: time),
);

Map<String, dynamic> _systemData(String text) => {
  'turn': 0,
  'step': 0,
  'message': {
    'role': 'system',
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

void main() {
  test('system/message events fold to trajectory systemPrompts', () {
    final entries = [
      _entry('system/message', _systemData('Be brief.'), 0, 100),
      _entry('turn/start', {'turnId': 't1'}, 1, 1000),
      _entry('user/message', {'content': 'hi'}, 2, 1100),
      _entry('system/message', _systemData('Be very brief.'), 6, 2000),
      _entry('turn/end', {'turnId': 't1'}, 7, 3000),
    ];
    final t = trajectoryFromHistory('s-1', entries);
    expect(t.turns, hasLength(1));
    expect(t.systemPrompts, hasLength(2));
    expect(t.systemPrompts[0].seq, 0);
    expect(t.systemPrompts[0].text, 'Be brief.');
    expect(t.systemPrompts[0].update, isFalse);
    expect(t.systemPrompts[1].text, 'Be very brief.');
    expect(t.systemPrompts[1].update, isTrue);
  });

  test('empty system content records a removal prompt', () {
    final entries = [
      _entry('system/message', _systemData('Be brief.'), 0, 100),
      _entry('system/message', {
        'message': {'role': 'system', 'content': []},
      }, 6, 2000),
    ];
    final t = trajectoryFromHistory('s-1', entries);
    expect(t.systemPrompts, hasLength(2));
    expect(t.systemPrompts[1].text, isEmpty);
  });

  test('histories without system events carry no prompts', () {
    final entries = [
      _entry('turn/start', {'turnId': 't1'}, 1, 1000),
      _entry('turn/end', {'turnId': 't1'}, 2, 2000),
    ];
    final t = trajectoryFromHistory('s-1', entries);
    expect(t.systemPrompts, isEmpty);
  });
}
