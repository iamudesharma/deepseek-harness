import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/failure_display.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEventEnvelope _event(String type, int seq, Map<String, Object?> data,
    {List<int>? sources, bool ignorable = false}) =>
    SessionEventEnvelope.fromJson({
      'type': type,
      'seq': seq,
      'time': 0,
      'data': data,
      if (sources != null) 'sourceEventSeqs': sources,
      if (ignorable) 'ignorable': true,
    });

void main() {
  group('ConversationNodeFolder determinism', () {
    final script = [
      _event('turn/start', 1, {'turn': 1}),
      _event('user/message', 2, {'content': 'go'}, sources: []),
      _event('assistant/chunk', 3, {'turn': 1, 'step': 1, 'chunk': {'text': 'Hel'}}),
      _event('assistant/chunk', 4, {'turn': 1, 'step': 1, 'chunk': {'text': 'lo'}}),
      _event('assistant/message', 5, {'turn': 1, 'step': 1, 'message': {}},
          sources: [3, 4]),
      _event('tool/call', 6, {'callId': 'c1', 'name': 'bash', 'arguments': '{}'}),
      _event('tool/result', 7, {
        'message': {'callId': 'c1'},
        'result': 'ok',
      }),
      _event('turn/end', 8, {
        'reason': {
          'kind': 'error',
          'error': {'type': 'ModelError', 'message': 'boom'},
        },
      }),
    ];

    test('same stream folds to identical snapshots across runs', () {
      final a = ConversationNodeFolder()..forEach(script);
      final b = ConversationNodeFolder()..forEach(script);
      expect(a.toLines(), b.toLines());
    });

    test('streaming tail updates in-flight node until settled message lands',
        () {
      final folder = ConversationNodeFolder()..forEach(script.take(4));
      expect(folder.toLines().where((l) => l.startsWith('assistant')).single,
          contains('(streaming) Hello'));

      folder.add(script[4]);
      final settled = folder
          .toLines()
          .where((l) => l.startsWith('assistant'))
          .join('\n');
      expect(settled, contains('Hello'));
      expect(settled, isNot(contains('(streaming)')));
      final node = folder.snapshot().nodes.whereType<AssistantNode>().single;
      expect(node.sourceSeqs, [3, 4]);
    });

    test('chunk after settle throws — settled nodes never mutate', () {
      final folder = ConversationNodeFolder()..forEach(script.take(5));
      expect(() => folder.add(script[2]),
          throwsA(predicate((e) => e is StateError && e.message.contains('settled'))));
    });

    test('tool lifecycle: running → result settles with status + payload + seqs',
        () {
      final folder = ConversationNodeFolder()..forEach(script.take(7));
      final tool = folder.snapshot().nodes.whereType<ToolNode>().single;
      expect(tool.status, ToolNodeStatus.success);
      expect(tool.result, 'ok');
      expect(tool.sourceSeqs, [6, 7]);
    });

    test('tool/result reads canonical source.callId identity', () {
      final folder = ConversationNodeFolder()
        ..add(_event('turn/start', 1, {'turn': 1}))
        ..add(_event('tool/call', 2, {'callId': 'canon-1', 'name': 'bash'}))
        ..add(_event('tool/result', 3, {
          'turn': 1,
          'step': 1,
          'message': {
            'role': 'user',
            'source': {'kind': 'tool', 'callId': 'canon-1'},
            'content': [
              {
                'type': 'tool-result',
                'toolCallId': 'canon-1',
                'content': [
                  {'type': 'text', 'text': 'out'},
                ],
                'isError': false,
              },
            ],
          },
        }));
      final tool = folder.snapshot().nodes.whereType<ToolNode>().single;
      expect(tool.status, ToolNodeStatus.success);
      expect(tool.sourceSeqs, [2, 3]);
    });

    test('code-dispatch folds nested subcalls under the root call', () {      final folder = ConversationNodeFolder()
        ..add(_event('turn/start', 1, {'turn': 1}))
        ..add(_event('tool/call', 2,
            {'callId': 'root-1', 'name': 'run-code'}))
        ..add(_event('tool/code-dispatch-start', 3, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'root-1:code:1',
          'name': 'node',
          'arguments': {'script': 'a'},
        }))
        ..add(_event('tool/code-dispatch', 4, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'root-1:code:1',
          'name': 'node',
          'isError': false,
          'content': [{'type': 'text', 'text': 'ok-out'}],
        }))
        ..add(_event('tool/code-dispatch-start', 5, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'root-1:code:2',
          'name': 'node',
          'arguments': {'script': 'b'},
        }))
        ..add(_event('tool/code-dispatch', 6, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'root-1:code:2',
          'name': 'node',
          'isError': true,
          'content': [{'type': 'text', 'text': 'boom'}],
        }));
      final tool = folder.snapshot().nodes.whereType<ToolNode>().single;
      expect(tool.subCalls, hasLength(2));
      expect(tool.subCalls[0].subCallId, 'root-1:code:1');
      expect(tool.subCalls[0].result, contains('ok-out'));
      expect(tool.subCalls[0].isError, isFalse);
      expect(tool.subCalls[1].isError, isTrue);
      // Dispatches update in place; the parent stays a single surface node.
      expect(folder.snapshot().nodes.whereType<ToolNode>().length, 1);
      // Unknown roots fail loud like unknown results.
      expect(
        () => folder.add(_event('tool/code-dispatch', 7,
            {'rootCallId': 'ghost', 'subCallId': 'g:1', 'name': 'x'})),
        throwsA(predicate((e) => e is StateError && '$e'.contains('ghost'))),
      );
    });

    test('nested subcalls depth 2 and 3 are folded recursively', () {
      final folder = ConversationNodeFolder()
        ..add(_event('turn/start', 1, {'turn': 1}))
        ..add(_event('tool/call', 2, {'callId': 'root-1', 'name': 'run-code'}))
        ..add(_event('tool/code-dispatch-start', 3, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'root-1:code:1',
          'name': 'bash',
          'arguments': {'command': 'ls'},
        }))
        ..add(_event('tool/code-dispatch-start', 4, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1:code:1',
          'subCallId': 'root-1:code:1:code:1',
          'name': 'inner',
          'arguments': {},
        }))
        ..add(_event('tool/code-dispatch', 5, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1:code:1',
          'subCallId': 'root-1:code:1:code:1',
          'name': 'inner',
          'isError': false,
          'content': [{'type': 'text', 'text': 'deep-out'}],
        }))
        ..add(_event('tool/code-dispatch-start', 6, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1:code:1:code:1',
          'subCallId': 'root-1:code:1:code:1:code:1',
          'name': 'deep',
          'arguments': {},
        }))
        ..add(_event('tool/code-dispatch', 7, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1:code:1:code:1',
          'subCallId': 'root-1:code:1:code:1:code:1',
          'name': 'deep',
          'isError': true,
          'content': [{'type': 'text', 'text': 'deep-err'}],
        }));
      final tool = folder.snapshot().nodes.whereType<ToolNode>().single;
      expect(tool.subCalls, hasLength(1));
      final lvl1 = tool.subCalls[0];
      expect(lvl1.subCallId, 'root-1:code:1');
      expect(lvl1.children, hasLength(1));
      final lvl2 = lvl1.children[0];
      expect(lvl2.subCallId, 'root-1:code:1:code:1');
      expect(lvl2.children, hasLength(1));
      final lvl3 = lvl2.children[0];
      expect(lvl3.subCallId, 'root-1:code:1:code:1:code:1');
      expect(lvl3.isError, isTrue);
      expect(lvl3.result, contains('deep-err'));
    });

    test('turn error folds friendly copy through displayFailureMessage', () {
      final folder = ConversationNodeFolder()..forEach(script);
      final errorLine =
          folder.toLines().singleWhere((l) => l.startsWith('turn-error'));
      expect(errorLine, contains('boom'));
    });
  });

  group('refusal and extensions', () {
    test('unknown required event refuses reconstruction', () {
      final folder = ConversationNodeFolder();
      expect(
        () => folder.add(_event('agent-team/journal', 1, {})),
        throwsA(predicate(
            (e) => e is StateError && e.message.contains('refusing'))),
      );
    });

    test('ignorable plugin extension is skipped silently', () {
      final folder = ConversationNodeFolder()
        ..add(_event('plugin/heartbeat', 1, {}, ignorable: true))
        ..add(_event('user/message', 2, {'content': 'hi'}, sources: []));
      expect(folder.toLines(), ['user u2 hi']);
    });
  });

  group('remaining families', () {
    test('llm/retry-started marks its correlated attempt started', () {
      final folder = ConversationNodeFolder()
        ..add(_event('llm/retry', 1, {
          'retryId': 'r-9',
          'retry': 2,
          'maxRetries': 3,
          'delayMs': 250,
          'failure': {'code': 'TRANSPORT', 'message': 'flaky'},
        }))
        ..add(_event('llm/retry-started', 2, {'retryId': 'r-9', 'retry': 2}));
      expect(folder.toLines().single, contains('retry #2'));
      expect(folder.toLines().single, contains('started'));
      // An uncorrelated started is a no-op (React: no attempt to mark).
      final empty = ConversationNodeFolder()
        ..add(_event('llm/retry-started', 3, {'retryId': 'r-x', 'retry': 2}));
      expect(empty.snapshot().nodes, isEmpty);
    });

    test('max-tokens turn end surfaces the dedicated failure line', () {
      final folder = ConversationNodeFolder()
        ..add(_event('turn/end', 1, {
          'reason': {'kind': 'max-tokens'},
        }));
      expect(folder.toLines().single, contains('max tokens reached'));
    });
  });

  test('displayFailureMessage keeps non-AUTH verbatim and collapses AUTH', () {
    final verbatim = displayFailureMessage({
      'type': 'ModelError',
      'message': '401 ModelError: promotion ended',
    });
    expect(verbatim.friendly, 'This turn failed\n401 ModelError: promotion ended');

    final auth = displayFailureMessage({
      'code': 'AUTH',
      'message': 'sk-secret-leak',
    });
    expect(auth.friendly, 'This turn failed\nAPI key is invalid');
    expect(auth.raw, contains('sk-secret-leak')); // raw stays for Details
  });

  group('step grouping and summary', () {
    test('events fold into a StepGroupNode with computed summary', () {
      final folder = ConversationNodeFolder()
        ..add(_event('turn/start', 1, {'turn': 1}))
        ..add(_event('step/start', 2, {'turn': 1, 'step': 1}))
        ..add(_event('assistant/message', 3,
            {'turn': 1, 'step': 1, 'message': {}}, sources: []))
        ..add(_event('tool/call', 4, {'callId': 'c9', 'name': 'bash'}))
        ..add(_event('tool/result', 5, {
          'message': {'callId': 'c9'},
          'result': 'done',
        }))
        ..add(_event('step/end', 6, {'turn': 1, 'step': 1}));

      final groups =
          folder.snapshot().nodes.whereType<StepGroupNode>().toList();
      expect(groups, hasLength(1));
      final g = groups.single;
      expect(g.settled, isTrue);
      expect(g.children, hasLength(2)); // assistant + tool call (result settles it)
      expect(g.summary, contains('Step 1'));
      expect(g.summary, contains('1 tool'));
    });

    test('grouping is deterministic across replay', () {
      List<ConversationNode> run() {
        final folder = ConversationNodeFolder()
          ..add(_event('turn/start', 1, {'turn': 1}))
          ..add(_event('step/start', 2, {'turn': 1, 'step': 1}))
          ..add(_event('assistant/chunk', 3,
              {'turn': 1, 'chunk': {'text': 'x'}}))
          ..add(_event('step/end', 4, {'turn': 1, 'step': 1}));
        return folder.snapshot().nodes;
      }

      final a = run();
      final b = run();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].key, b[i].key);
        expect(a[i].sourceSeqs, b[i].sourceSeqs);
      }
    });
  });

  group('compaction surface-replace', () {
    test('summary replaces bracket-compact range and cites shadowed seqs', () {
      final folder = ConversationNodeFolder()
        ..add(_event('user/message', 1, {'content': 'go'}, sources: []))
        ..add(_event('compaction/start', 2, {}))
        ..add(_event('user/message', 3, {'content': 'old'}, sources: []))
        ..add(_event('assistant/message', 4,
            {'turn': 1, 'step': 1, 'message': {}}, sources: []))
        ..add(SessionEventEnvelope.fromJson({
          'type': 'compaction/summary',
          'seq': 5,
          'time': 0,
          'data': {'text': 'condensed history'},
        }));

      final nodes = folder.snapshot().nodes;
      // Pre-compaction user(1) survives.
      expect(nodes.whereType<UserMessageNode>().map((n) => n.text),
          ['go']);
      final compactions =
          nodes.whereType<CompactionNode>().toList();
      expect(compactions, hasLength(1));
      expect(compactions.single.text, 'condensed history');
      // Source mapping: bracket marker + every shadowed node seq + summary
      // event. The assistant message cited NO sources (present-empty array,
      // known-empty stream) so it cannot be shadow-cited — contract-exact.
      expect(compactions.single.sourceSeqs, containsAll([2, 3, 5]));
      expect(
          compactions.single.sourceSeqs.contains(4), isFalse);
    });

    test('React packet pair: summary is log-only until checkpoint replace', () {
      // Real React stream: compaction/summary with shadowedSeqs + token count
      // is immediately followed by a user/message carrying a replace surfaceOp.
      // The summary itself must produce NO surface node; the checkpoint does.
      final folder = ConversationNodeFolder()
        ..add(_event('user/message', 1, {'content': 'keep'}, sources: []))
        ..add(_event('user/message', 2, {'content': 'shadow-me'}, sources: []))
        ..add(SessionEventEnvelope.fromJson({
          'type': 'compaction/summary',
          'seq': 3,
          'time': 0,
          'data': {
            'summary': [
              {'type': 'text', 'text': 'condensed history'},
            ],
            'shadowedSeqs': [2],
            'shadowedTokenCount': 512,
          },
        }))
        // Checkpoint user/message quoting the summary with a replace op on
        // surface node indices [1,1] (the alpha-me bubble).
        ..add(SessionEventEnvelope.fromJson({
          'type': 'user/message',
          'seq': 4,
          'time': 0,
          'data': {
            'content': [
              {'type': 'text', 'text': 'condensed history'},
            ],
          },
          'surfaceOp': {'op': 'replace', 'start': 1, 'end': 1},
        }))
        ..add(_event('compaction/end', 5, {}));

      final nodes = folder.snapshot().nodes;
      final compactions = nodes.whereType<CompactionNode>().toList();
      expect(compactions, hasLength(1));
      expect(compactions.single.text, 'condensed history');
      expect(compactions.single.shadowedTokenCount, 512);
      expect(compactions.single.shadowedItemCount, 1);
      // Source mapping: summary seq + checkpoint seq + shadowed seq.
      expect(compactions.single.sourceSeqs, containsAll([3, 4, 2]));
      // The shadowed user bubble was removed; pre-shadowed bubble survives.
      final users = nodes.whereType<UserMessageNode>().map((n) => n.text);
      expect(users, ['keep']);
    });

    test('compact checkpoint without pending still creates marker (window cut)', () {
      final folder = ConversationNodeFolder()
        ..add(_event('user/message', 1, {'content': 'keep'}, sources: []))
        ..add(SessionEventEnvelope.fromJson({
          'type': 'user/message',
          'seq': 2,
          'time': 0,
          'data': {
            'content': [
              {'type': 'text', 'text': 'checkpoint'},
            ],
            'source': {'kind': 'plugin', 'plugin': 'compact', 'compactionId': 'c1'},
          },
          'surfaceOp': {'op': 'replace', 'start': 0, 'end': 0},
          'sourceEventSeqs': [1],
        }));
      final nodes = folder.snapshot().nodes;
      expect(nodes.whereType<CompactionNode>(), hasLength(1));
      // Summary outside window => text empty, counts 0
      expect(nodes.whereType<CompactionNode>().single.text, isEmpty);
    });

    test('React packet pair without a checkpoint leaves summary pending', () {
      // A summary that declares shadowed payload but is NOT followed by a
      // replace-op checkpoint creates no surface node (React: log-only).
      final folder = ConversationNodeFolder()
        ..add(_event('user/message', 1, {'content': 'go'}, sources: []))
        ..add(SessionEventEnvelope.fromJson({
          'type': 'compaction/summary',
          'seq': 2,
          'time': 0,
          'data': {
            'summary': [{'type': 'text', 'text': 'condensed history'}],
            'shadowedSeqs': [1],
            'shadowedTokenCount': 128,
          },
        }))
        ..add(_event('compaction/end', 3, {}));

      final nodes = folder.snapshot().nodes;
      expect(nodes.whereType<CompactionNode>(), isEmpty);
      // The original bubble stays.
      expect(nodes.whereType<UserMessageNode>().map((n) => n.text), ['go']);
    });

    test('legacy bracket-trio behavior is preserved without shadowedSeqs', () {
      // Without shadowedSeqs the fold keeps the bracket-trio immediate
      // collapse — no behavioral regression for legacy fixtures.
      final folder = ConversationNodeFolder()
        ..add(_event('user/message', 1, {'content': 'go'}, sources: []))
        ..add(_event('compaction/start', 2, {}))
        ..add(_event('user/message', 3, {'content': 'old'}, sources: []))
        ..add(_event('assistant/message', 4,
            {'turn': 1, 'step': 1, 'message': {}}, sources: []))
        ..add(SessionEventEnvelope.fromJson({
          'type': 'compaction/summary',
          'seq': 5,
          'time': 0,
          'data': {'text': 'condensed history'},
        }));

      final nodes = folder.snapshot().nodes;
      expect(nodes.whereType<CompactionNode>(), hasLength(1));
      expect(nodes.whereType<UserMessageNode>().map((n) => n.text), ['go']);
      expect(nodes.whereType<CompactionNode>().single.text,
          'condensed history');
    });
  });
}

extension on ConversationNodeFolder {
  void forEach(Iterable<SessionEventEnvelope> events) {
    for (final e in events) {
      add(e);
    }
  }

  List<String> toLines() => snapshot().toTranscriptLines();
}
