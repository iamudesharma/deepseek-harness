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

    test('tool rows carry raw args verbatim like React summarizeCall', () {
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
      // React trajectory never derives per-tool summaries: the ledger shows
      // the raw args string (chat cards own the semantic summaries).
      expect(rows.single.text.contains('{"todos"'), isTrue);
      expect(rows.single.inputDetail ?? '', contains('in_progress'));
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

  group('React detail parity: folded tools, curated rows, schemas', () {
    test('tool call and result fold into one row with result preview', () {
      final rows = ledgerFromHistory([
        _ev('tool/call', 16, {
          'turn': 1,
          'step': 1,
          'callId': 'c1',
          'name': 'bash',
          'args': '{"command":"pwd && ls -la"}',
        }),
        _ev('tool/result', 17, {
          'turn': 1,
          'step': 1,
          'message': {
            'source': {'callId': 'c1'},
            'content': [
              {
                'type': 'tool-result',
                'toolCallId': 'c1',
                'content': [
                  {'type': 'text', 'text': '/tmp\ntotal 2'}
                ]
              }
            ]
          }
        }),
      ]);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.kind.name, 'tool');
      expect(row.text, startsWith('bash '));
      expect(row.text.contains('pwd'), isTrue);
      expect(row.inputDetail ?? '', contains('ls -la'));
      expect(row.outputDetail ?? '', contains('total 2'));
      expect(row.resultPreview ?? '', contains('total 2'));
      expect(row.running, isFalse);
      expect(row.timeSeconds, isNotNull);
    });

    test('unpaired tool call stays running with null duration', () {
      final rows = ledgerFromHistory([
        _ev('tool/call', 5, {
          'turn': 1,
          'step': 2,
          'callId': 'live-1',
          'name': 'read',
          'args': '{"file_path":"/x"}',
        }),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.running, isTrue);
      expect(rows.single.timeSeconds, isNull);
      expect(rows.single.outputDetail, isNull);
    });

    test('control-plane noise rows are dropped', () {
      final rows = ledgerFromHistory([
        _ev('permission/preset', 0, {}),
        _ev('sandbox/mode', 1, {}),
        _ev('approval/policy', 2, {}),
        _ev('agent/inbox/spliced', 3, {}),
        _ev('session/title', 4, {}),
        _ev('user/message', 5, {
          'content': 'hi',
          'source': {'kind': 'user'}
        }),
      ]);
      expect(rows.map((r) => r.kind.name), ['user']);
      expect(rows.single.text, 'hi');
    });

    test('text-less assistant driving tools labels tool call only', () {
      final rows = ledgerFromHistory([
        _ev('assistant/message', 20, {
          'turn': 1,
          'step': 2,
          'message': {
            'content': [
              {'type': 'tool-call', 'id': 'c9', 'name': 'read'}
            ]
          }
        }),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.toolCallOnly, isTrue);
      expect(rows.single.text, '(tool call only)');
      expect(rows.single.childCallIds, ['c9']);
    });

    test('chunk deltas accumulate into one tail row per unsettled step', () {
      final rows = ledgerFromHistory([
        _ev('assistant/chunk', 3, {
          'turn': 1,
          'step': 1,
          'chunk': {'text': 'Hel'},
        }),
        _ev('assistant/chunk', 4, {
          'turn': 1,
          'step': 1,
          'chunk': {'text': 'lo'},
        }),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.text, 'Hello');
      expect(rows.single.running, isTrue);
    });

    test('chunks vanish when the step settles', () {
      final rows = ledgerFromHistory([
        _ev('assistant/chunk', 3, {
          'turn': 1,
          'step': 1,
          'chunk': {'text': 'Hel'},
        }),
        _ev('assistant/message', 5, {
          'turn': 1,
          'step': 1,
          'message': {
            'content': [
              {'type': 'text', 'text': 'Hello settled'}
            ]
          }
        }),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.text, 'Hello settled');
      expect(rows.single.running, isFalse);
    });

    test('request header projects Initial System Prompt with schema', () {
      final rows = ledgerFromHistory([
        _ev('request/header', 12, {
          'reason': 'initial',
          'header': {
            'system': 'You are helpful',
            'tools': [
              {
                'name': 'bash',
                'description': 'Run a shell command',
                'parameters': {'type': 'object'}
              }
            ]
          }
        }),
        _ev('tool/call', 16, {
          'turn': 1,
          'step': 1,
          'callId': 'c1',
          'name': 'bash',
          'args': '{}',
        }),
      ]);
      final system =
          rows.where((r) => r.kind.name == 'system').toList();
      expect(system, hasLength(1));
      expect(system.single.text, 'Initial System Prompt');
      expect(system.single.promptDetail, 'You are helpful');
      final tool = rows.where((r) => r.kind.name == 'tool').toList();
      expect(tool, hasLength(1));
      expect(tool.single.schemaDescription, 'Run a shell command');
      expect(tool.single.schemaParameters ?? '', contains('object'));
    });

    test('assistant usage and source survive the fold', () {
      final rows = ledgerFromHistory([
        _ev('assistant/message', 15, {
          'turn': 1,
          'step': 1,
          'usage': {'inputTokens': 9051, 'outputTokens': 121},
          'message': {
            'content': [
              {'type': 'text', 'text': 'Hi!'}
            ]
          }
        }),
        _ev('user/message', 8, {
          'content': 'hi',
          'source': {'kind': 'user', 'rpcId': 'r1'}
        }),
      ]);
      final assistant =
          rows.where((r) => r.kind.name == 'message').single;
      expect(assistant.outputTokens, 121);
      expect(assistant.inputTokens, 9051);
      final user = rows.where((r) => r.kind.name == 'user').single;
      expect(user.messageSource ?? '', contains('r1'));
    });

    test('ledger preview caps at 512 chars with ellipsis', () {
      final long = List.filled(600, 'w').join(' ');
      final rows = ledgerFromHistory([
        _ev('user/message', 5, {
          'content': long,
          'source': {'kind': 'user'}
        }),
      ]);
      expect(rows.single.text.length, lessThanOrEqualTo(513));
      expect(rows.single.text.endsWith('…'), isTrue);
      expect(rows.single.inputDetail, long);
    });
  });
}
