import 'dart:convert';

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/todo_panel.dart';
import 'package:dsh_flutter/src/plugins/deliverables/deliverables_mentions.dart'
    show producedPathsForTurn;
import 'package:flutter_test/flutter_test.dart';

HistoryEntry _toolCall({
  required int seq,
  required String name,
  required Map<String, dynamic> args,
  int turn = 1,
}) {
  return HistoryEntry(
    event: SessionEvent(
      type: 'tool/call',
      data: {
        'name': name,
        'args': jsonEncode(args),
        'callId': 'c$seq',
        'turn': turn,
      },
      seq: seq,
      time: seq * 1000,
    ),
  );
}

HistoryEntry _toolResult({
  required int seq,
  required String callId,
  bool isError = false,
}) {
  return HistoryEntry(
    event: SessionEvent(
      type: 'tool/result',
      data: {
        'message': {
          'source': {'callId': callId},
          'content': [
            {'type': 'text', 'text': 'ok'}
          ],
        },
        if (isError) 'isError': true,
      },
      seq: seq,
      time: seq * 1000,
    ),
  );
}

void main() {
  group('currentTodosFromHistory', () {
    test('returns last todo_write list', () {
      final history = [
        _toolCall(seq: 1, name: 'todo_write', args: {
          'todos': [
            {'content': 'A', 'status': 'completed'},
            {'content': 'B', 'status': 'in_progress'},
          ]
        }),
        _toolCall(seq: 2, name: 'bash', args: {'command': 'ls'}),
        _toolCall(seq: 3, name: 'todo_write', args: {
          'todos': [
            {'content': 'A', 'status': 'completed'},
            {'content': 'B', 'status': 'completed'},
            {'content': 'C', 'status': 'pending'},
          ]
        }),
      ];
      final todos = currentTodosFromHistory(history);
      expect(todos.map((t) => t.content), ['A', 'B', 'C']);
      expect(todos.last.status, 'pending');
    });

    test('empty when no todo_write', () {
      expect(currentTodosFromHistory([]), isEmpty);
    });
  });

  group('producedPathsForTurn', () {
    test('write + success yields path, error excluded', () {
      final history = [
        _toolCall(seq: 1, name: 'write', args: {
          'file_path': 'src/App.jsx',
          'content': 'x',
        }),
        _toolResult(seq: 2, callId: 'c1'),
        _toolCall(seq: 3, name: 'write', args: {
          'file_path': 'bad.txt',
          'content': 'x',
        }),
        _toolResult(seq: 4, callId: 'c3', isError: true),
      ];
      expect(producedPathsForTurn(history, turn: 1), ['src/App.jsx']);
    });

    test('dedupes write then edit same path', () {
      final history = [
        _toolCall(seq: 1, name: 'write', args: {
          'file_path': 'a.txt',
          'content': 'x',
        }),
        _toolResult(seq: 2, callId: 'c1'),
        HistoryEntry(
          event: SessionEvent(
            type: 'tool/call',
            data: {
              'name': 'edit',
              'args': jsonEncode({
                'file_path': 'a.txt',
                'old_string': 'x',
                'new_string': 'y',
              }),
              'callId': 'c3',
              'turn': 1,
            },
            seq: 3,
            time: 3000,
          ),
        ),
        _toolResult(seq: 4, callId: 'c3'),
      ];
      expect(producedPathsForTurn(history, turn: 1), ['a.txt']);
    });
  });
}
