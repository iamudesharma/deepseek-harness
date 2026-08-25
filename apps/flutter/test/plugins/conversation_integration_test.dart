import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/failure_display.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEventEnvelope e(String type, int seq, Map<String, Object?> data,
        {List<int>? sources, bool ignorable = false, Object? surfaceOp}) =>
    SessionEventEnvelope.fromJson({
      'type': type,
      'seq': seq,
      'time': 0,
      'data': data,
      if (sources != null) 'sourceEventSeqs': sources,
      if (surfaceOp != null) 'surfaceOp': surfaceOp,
      if (ignorable) 'ignorable': true,
    });

void main() {
  group('Session title contract (projection)', () {
    test('decodes title from projections.values.title', () {
      final s = SessionSummary.fromJson({
        'sessionId': 's-1',
        'updatedAt': 0,
        'running': false,
        'blank': false,
        'projections': {
          'asOfSeq': 10,
          'values': {'title': 'My Plan Session'}
        }
      });
      expect(s.title, 'My Plan Session');
      expect(s.displayTitle, 'My Plan Session');
    });

    test('blank session falls back to New session, not id', () {
      final s = SessionSummary.fromJson({
        'sessionId': 'session-xyz-123',
        'updatedAt': 0,
        'running': false,
        'blank': true,
        'projections': {'asOfSeq': -1, 'values': {}}
      });
      expect(s.title, isNull);
      expect(s.blank, isTrue);
      // UI layer shows 'New session' for blank, not id
    });

    test('no title falls back to cwd basename then id', () {
      final s1 = SessionSummary.fromJson({
        'sessionId': 's-2',
        'updatedAt': 0,
        'running': false,
        'blank': false,
        'cwd': '/home/user/my-project',
        'projections': {'asOfSeq': 0, 'values': {}}
      });
      expect(s1.displayTitle, 'my-project');

      final s2 = SessionSummary.fromJson({
        'sessionId': 's-3',
        'updatedAt': 0,
        'running': false,
        'blank': false,
        'projections': {'asOfSeq': 0, 'values': {}}
      });
      expect(s2.displayTitle, 's-3');
    });

    test('withTitle allows null clearing', () {
      const s = SessionSummary(sessionId: SessionId('s-1'), updatedAt: 0, running: false, blank: false, title: 'Old');
      expect(s.withTitle(null).title, isNull);
      expect(s.withTitle('New').title, 'New');
    });
  });

  group('User message rendering', () {
    test('Hello → Hi renders both in order', () {
      final f = ConversationNodeFolder()
        ..add(e('turn/start', 1, {'turn': 1}))
        ..add(e('user/message', 2, {
          'content': [
            {'type': 'text', 'text': 'Hello'}
          ],
          'id': 'm1',
          'source': {'kind': 'user'}
        }))
        ..add(e('assistant/message', 3, {'turn': 1, 'step': 1}, sources: []));
      final nodes = f.snapshot().nodes;
      // Should have UserMessageNode and AssistantNode, in order, no markers
      expect(nodes.whereType<UserMessageNode>().single.text, 'Hello');
      expect(nodes.whereType<AssistantNode>(), hasLength(1));
      final lines = f.snapshot().toTranscriptLines();
      expect(lines.any((l) => l.contains('user') && l.contains('Hello')), isTrue);
      // No leaked marker labels
      expect(lines.any((l) => l.contains('turn/start') || l.contains('end-seed')), isFalse);
    });

    test('failed turn still renders user message + error', () {
      final f = ConversationNodeFolder()
        ..add(e('turn/start', 1, {'turn': 1}))
        ..add(e('user/message', 2, {
          'content': [
            {'type': 'text', 'text': 'do thing'}
          ]
        }))
        ..add(e('step/start', 3, {'turn': 1, 'step': 1}))
        ..add(e('step/end', 4, {'turn': 1, 'step': 1}))
        ..add(e('turn/end', 5, {
          'reason': {
            'kind': 'error',
            'error': {'type': 'server_error', 'message': 'Model is unavailable.'}
          }
        }));
      final nodes = f.snapshot().nodes;
      expect(nodes.whereType<UserMessageNode>().single.text, 'do thing');
      expect(nodes.whereType<TurnErrorNode>().single.friendly, contains('Model is unavailable'));
      // No extra assistant fake message
      expect(nodes.whereType<AssistantNode>(), isEmpty);
    });
  });

  group('Internal markers not visible', () {
    test('turn/start and end-seed produce no visible rows', () {
      final f = ConversationNodeFolder()
        ..add(e('turn/start', 1, {'turn': 1}))
        ..add(e('session/end-seed', 2, {}))
        ..add(e('user/message', 3, {'content': 'hi'}));
      final lines = f.snapshot().toTranscriptLines();
      expect(lines.any((l) => l.contains('turn/start')), isFalse);
      expect(lines.any((l) => l.contains('end-seed')), isFalse);
      expect(f.snapshot().nodes.whereType<MarkerNode>(), isEmpty);
    });

    test('compaction/start alone not rendered, summary replaces bracket', () {
      final f = ConversationNodeFolder()
        ..add(e('user/message', 1, {'content': 'keep'}))
        ..add(e('compaction/start', 2, {}))
        ..add(e('user/message', 3, {'content': 'old'}))
        ..add(e('assistant/message', 4, {'turn': 1, 'step': 1}, sources: []))
        ..add(e('compaction/summary', 5, {'text': 'condensed'}));
      final nodes = f.snapshot().nodes;
      expect(nodes.whereType<MarkerNode>(), isEmpty);
      expect(nodes.whereType<CompactionNode>().single.text, 'condensed');
    });

    test('todo/write never renders', () {
      final f = ConversationNodeFolder()
        ..add(e('todo/write', 1, {'todos': []}))
        ..add(e('request/header', 2, {}))
        ..add(e('plan/mode', 3, {'active': true}));
      expect(f.snapshot().nodes, isEmpty);
    });
  });

  group('Step rendering', () {
    test('empty step produces no visible group', () {
      final f = ConversationNodeFolder()
        ..add(e('turn/start', 1, {'turn': 1}))
        ..add(e('step/start', 2, {'turn': 1, 'step': 1}))
        ..add(e('step/end', 3, {'turn': 1, 'step': 1}));
      expect(f.snapshot().nodes.whereType<StepGroupNode>(), isEmpty);
    });

    test('non-empty step emits settled group with tool count', () {
      final f = ConversationNodeFolder()
        ..add(e('step/start', 1, {'turn': 1, 'step': 1}))
        ..add(e('tool/call', 2, {'callId': 'c1', 'name': 'bash'}))
        ..add(e('tool/result', 3, {'message': {'callId': 'c1'}, 'result': 'ok'}))
        ..add(e('step/end', 4, {'turn': 1, 'step': 1}));
      final g = f.snapshot().nodes.whereType<StepGroupNode>().single;
      expect(g.settled, isTrue);
      expect(g.summary, contains('Step 1'));
      expect(g.summary, contains('1 tool'));
      expect(g.children, hasLength(1));
    });

    test('multi-step turn has distinct keys', () {
      final f = ConversationNodeFolder()
        ..add(e('turn/start', 1, {'turn': 1}))
        ..add(e('step/start', 2, {'turn': 1, 'step': 1}))
        ..add(e('tool/call', 3, {'callId': 'c1', 'name': 'bash'}))
        ..add(e('tool/result', 4, {'message': {'callId': 'c1'}}))
        ..add(e('step/end', 5, {'turn': 1, 'step': 1}))
        ..add(e('step/start', 6, {'turn': 1, 'step': 2}))
        ..add(e('tool/call', 7, {'callId': 'c2', 'name': 'grep'}))
        ..add(e('tool/result', 8, {'message': {'callId': 'c2'}}))
        ..add(e('step/end', 9, {'turn': 1, 'step': 2}));
      final groups = f.snapshot().nodes.whereType<StepGroupNode>().toList();
      expect(groups, hasLength(2));
      expect(groups[0].key, isNot(groups[1].key));
      expect(groups[0].step, 1);
      expect(groups[1].step, 2);
    });

    test('streaming assistant via chunk produces streaming node inside step', () {
      final f = ConversationNodeFolder()
        ..add(e('step/start', 1, {'turn': 1, 'step': 1}))
        ..add(e('assistant/chunk', 2, {'turn': 1, 'step': 1, 'chunk': {'text': 'Hel'}}))
        ..add(e('assistant/chunk', 3, {'turn': 1, 'step': 1, 'chunk': {'text': 'lo'}}));
      // In-flight assistant is inside open group children
      final group = f.snapshot().nodes.whereType<StepGroupNode>().single;
      expect(group.children.whereType<AssistantNode>().single.text, 'Hello');
      expect(group.children.whereType<AssistantNode>().single.streaming, isTrue);
    });
  });

  group('Turn error presentation', () {
    test('maps error code and preserves message under correct turn', () {
      final f = ConversationNodeFolder()
        ..add(e('user/message', 1, {'content': 'hi'}))
        ..add(e('turn/end', 2, {
          'reason': {
            'kind': 'error',
            'error': {'code': 'RATE_LIMIT', 'type': 'FreeUsageLimitError', 'message': 'Rate limit exceeded. Please try again later.'}
          }
        }));
      final err = f.snapshot().nodes.whereType<TurnErrorNode>().single;
      expect(err.errorCode, 'RATE_LIMIT');
      expect(err.friendly, contains('Rate limit exceeded'));
      // No fake assistant
      expect(f.snapshot().nodes.whereType<AssistantNode>(), isEmpty);
    });

    test('400 server_error still shows friendly not raw JSON', () {
      final mapped = displayFailureMessage({'type': 'server_error', 'message': 'Error from provider (Console): Upstream request failed: Model is unavailable.'});
      expect(mapped.friendly, contains('Model is unavailable'));
      expect(mapped.friendly, isNot(contains('"type"')));
    });
  });

  group('Compaction and structural', () {
    test('structural events still affect state without rendering', () {
      final f = ConversationNodeFolder()
        ..add(e('turn/start', 10, {'turn': 5}))
        ..add(e('user/message', 11, {'content': 'q'}));
      // turn/start set internal _turn but produced no row
      expect(f.snapshot().nodes.whereType<UserMessageNode>().single.text, 'q');
    });
  });

  group('Required matrix: full turn lifecycle', () {
    test('A: normal: user -> assistant', () {
      final f = ConversationNodeFolder()
        ..add(e('user/message', 1, {'content': 'hello'}))
        ..add(e('assistant/message', 2, {'turn': 1, 'step': 1}, sources: []));
      expect(f.snapshot().nodes.map((n) => n.runtimeType).toList(), [UserMessageNode, AssistantNode]);
    });

    test('B: failed: user -> error', () {
      final f = ConversationNodeFolder()
        ..add(e('user/message', 1, {'content': 'fail'}))
        ..add(e('turn/end', 2, {'reason': {'kind': 'error', 'error': {'message': 'boom'}}}));
      expect(f.snapshot().nodes.whereType<UserMessageNode>(), hasLength(1));
      expect(f.snapshot().nodes.whereType<TurnErrorNode>(), hasLength(1));
    });

    test('C: streaming: user -> partial -> settled', () {
      final f = ConversationNodeFolder()
        ..add(e('user/message', 1, {'content': 'stream'}))
        ..add(e('assistant/chunk', 2, {'turn': 1, 'step': 1, 'chunk': {'text': 'part'}}))
        ..add(e('assistant/message', 3, {'turn': 1, 'step': 1}, sources: [2]));
      final a = f.snapshot().nodes.whereType<AssistantNode>().single;
      expect(a.streaming, isFalse);
      expect(a.text, 'part');
    });

    test('D: tool: user -> tool -> assistant', () {
      final f = ConversationNodeFolder()
        ..add(e('user/message', 1, {'content': 'tool'}))
        ..add(e('tool/call', 2, {'callId': 'c1', 'name': 'bash'}))
        ..add(e('tool/result', 3, {'message': {'callId': 'c1'}, 'result': 'out'}))
        ..add(e('assistant/message', 4, {'turn': 1, 'step': 1}, sources: []));
      expect(f.snapshot().nodes.whereType<ToolNode>().single.status.name, 'success');
    });

    test('F: plan/mode does not create visible row', () {
      final f = ConversationNodeFolder()
        ..add(e('plan/mode', 1, {'active': true}))
        ..add(e('user/message', 2, {'content': 'hi'}));
      expect(f.snapshot().nodes.whereType<MarkerNode>(), isEmpty);
      expect(f.snapshot().nodes.whereType<UserMessageNode>(), hasLength(1));
    });

    test('H: raw markers never leak text', () {
      final f = ConversationNodeFolder()
        ..add(e('turn/start', 1, {'turn': 1}))
        ..add(e('session/end-seed', 2, {}))
        ..add(e('compaction/start', 3, {}))
        ..add(e('user/message', 4, {'content': 'hi'}));
      final transcript = f.snapshot().toTranscriptLines().join('\n');
      expect(transcript, isNot(contains('turn/start')));
      expect(transcript, isNot(contains('end-seed')));
      expect(transcript, isNot(contains('compaction/start')));
    });
  });
}
