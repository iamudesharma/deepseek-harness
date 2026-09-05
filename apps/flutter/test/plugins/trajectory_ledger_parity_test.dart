import 'dart:convert';

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/trajectory/ui/trajectory_screen.dart'
    show ledgerFromHistory;
import 'package:flutter_test/flutter_test.dart';

HistoryEntry _ev(String type, int seq, [Map<String, dynamic>? data]) {
  return HistoryEntry(
    event: SessionEvent(
      type: type,
      data: data ?? const {},
      seq: seq,
      time: seq * 1000,
    ),
  );
}

void main() {
  group('ledgerFromHistory React parity', () {
    test('skips step brackets, end-seed, and todo/write echoes', () {
      final rows = ledgerFromHistory([
        _ev('turn/start', 1, {'turn': 1}),
        _ev('step/start', 2, {'turn': 1, 'step': 1}),
        _ev('user/message', 3, {
          'content': 'hi',
          'source': {'kind': 'user'}
        }),
        _ev('step/end', 4, {'turn': 1, 'step': 1}),
        _ev('todo/write', 5, {'todos': []}),
        _ev('session/end-seed', 6, {}),
      ]);
      final types = rows.map((r) => r.text).toList();
      expect(
          types.any((t) => t.contains('step/start') || t.contains('step/end')),
          isFalse);
      expect(types.any((t) => t.contains('end-seed')), isFalse);
      expect(rows.any((r) => r.kind.name == 'user'), isTrue);
    });

    test('todo_write summarizes, not raw JSON', () {
      final rows = ledgerFromHistory([
        _ev('tool/call', 1, {
          'name': 'todo_write',
          'args': jsonEncode({
            'todos': [
              {'content': 'A', 'status': 'completed'},
              {'content': 'B', 'status': 'in_progress'},
            ]
          }),
          'callId': 'c1',
          'turn': 1,
        }),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.text, contains('todo_write'));
      expect(rows.single.text, contains('1/2 completed'));
      expect(rows.single.text.contains('{"todos"'), isFalse);
    });

    test('assistant markdown stripped in ledger text, kept in preview',
        () {
      final rows = ledgerFromHistory([
        _ev('assistant/message', 1, {
          'turn': 1,
          'step': 1,
          'message': {
            'content': [
              {'type': 'text', 'text': 'both **load** and **runtime**'}
            ]
          }
        }),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.text.contains('**'), isFalse);
      expect(rows.single.text, contains('load'));
      expect(rows.single.previewMarkdown ?? '', contains('**load**'));
    });
  });
}
