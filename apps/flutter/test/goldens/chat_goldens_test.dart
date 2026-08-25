import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/chat_view.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEvent _ev(String type, int seq, Map<String, dynamic> data) =>
    SessionEvent(type: type, data: data, seq: seq, time: seq * 1000);

ProviderContainer _containerWithEvents(String sid, List<SessionEvent> events, {bool running = false}) {
  final c = ProviderContainer();
  c.read(sessionsProvider.notifier).addSession(SessionSummary(sessionId: SessionId(sid), updatedAt: 0, running: running, blank: false, title: 'Session $sid'));
  c.read(liveHistoryProvider(sid).notifier).replaceAll(events.map((e) => HistoryEntry(event: e, view: null)).toList());
  return c;
}

Future<void> _pumpChat(WidgetTester tester, String sid, List<SessionEvent> events, String goldenName, {bool running = false}) async {
  final c = _containerWithEvents(sid, events, running: running);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: ChatView(sessionId: sid),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await expectLater(find.byType(ChatView), matchesGoldenFile('goldens/$goldenName.png'));
}

void main() {
  group('Chat goldens', () {
    testWidgets('chat with assistant text', (tester) async {
      await _pumpChat(
        tester,
        'gold-assistant',
        [
          _ev('user/message', 1, {'content': 'Hello'}),
          _ev('assistant/chunk', 2, {'turn': 1, 'step': 1, 'chunk': {'type': 'text-delta', 'index': 0, 'text': 'Hi there, how can I help?'}}),
          _ev('assistant/message', 3, {'turn': 1, 'step': 1, 'message': {'content': [{'type': 'text', 'text': 'Hi there, how can I help?'}]}}),
        ],
        'chat_assistant_text',
      );
    });

    testWidgets('chat with Think', (tester) async {
      await _pumpChat(
        tester,
        'gold-think',
        [
          _ev('turn/start', 1, {'turn': 1}),
          _ev('step/start', 2, {'turn': 1, 'step': 1}),
          _ev('assistant/chunk', 3, {'turn': 1, 'step': 1, 'chunk': {'type': 'reasoning-delta', 'index': 0, 'text': 'Thinking about the answer\nSecond line of thought\nThird line'}}),
          _ev('assistant/chunk', 4, {'turn': 1, 'step': 1, 'chunk': {'type': 'text-delta', 'index': 0, 'text': 'The answer is 42.'}}),
          _ev('assistant/message', 5, {'turn': 1, 'step': 1, 'message': {'content': [{'type': 'text', 'text': 'The answer is 42.'}]}}),
        ],
        'chat_think',
        running: true,
      );
    });

    testWidgets('chat with Bash', (tester) async {
      await _pumpChat(
        tester,
        'gold-bash',
        [
          _ev('user/message', 1, {'content': 'Run ls'}),
          _ev('tool/call', 2, {'callId': 'c1', 'name': 'bash', 'arguments': '{"command":"ls -la"}'}),
          _ev('tool/result', 3, {'message': {'source': {'callId': 'c1'}}, 'result': 'total 8\ndrwxr-xr-x 2 user group 4096 May 1 12:00 folder\n-rw-r--r-- 1 user group 123 May 1 12:00 file.txt'}),
        ],
        'chat_bash',
      );
    });

    testWidgets('chat with Read', (tester) async {
      await _pumpChat(
        tester,
        'gold-read',
        [
          _ev('user/message', 1, {'content': 'Read file'}),
          _ev('tool/call', 2, {'callId': 'c1', 'name': 'read', 'arguments': '{"path":"lib/main.dart"}'}),
          _ev('tool/result', 3, {'message': {'source': {'callId': 'c1'}}, 'result': 'void main() {\n  print("hello");\n}\n'}),
        ],
        'chat_read',
      );
    });

    testWidgets('chat with Search', (tester) async {
      await _pumpChat(
        tester,
        'gold-search',
        [
          _ev('user/message', 1, {'content': 'Search'}),
          _ev('tool/call', 2, {'callId': 'c1', 'name': 'grep', 'arguments': '{"pattern":"foo"}'}),
          _ev('tool/result', 3, {'message': {'source': {'callId': 'c1'}}, 'result': 'lib/a.dart:10: foo bar\nlib/b.dart:20: baz foo'}),
        ],
        'chat_search',
      );
    });

    testWidgets('tool error', (tester) async {
      await _pumpChat(
        tester,
        'gold-tool-error',
        [
          _ev('user/message', 1, {'content': 'Run failing command'}),
          _ev('tool/call', 2, {'callId': 'c1', 'name': 'bash'}),
          _ev('tool/result', 3, {'message': {'source': {'callId': 'c1'}}, 'result': 'permission denied', 'isError': true}),
        ],
        'chat_tool_error',
      );
    });

    testWidgets('nested subcall', (tester) async {
      await _pumpChat(
        tester,
        'gold-subcall',
        [
          _ev('turn/start', 1, {'turn': 1}),
          _ev('tool/call', 2, {'callId': 'root-1', 'name': 'run-code'}),
          _ev('tool/code-dispatch-start', 3, {'rootCallId': 'root-1', 'parentCallId': 'root-1', 'subCallId': 'root-1:code:1', 'name': 'bash', 'arguments': '{"command":"ls"}'}),
          _ev('tool/code-dispatch', 4, {'rootCallId': 'root-1', 'parentCallId': 'root-1:code:1', 'subCallId': 'root-1:code:1:code:1', 'name': 'inner', 'content': 'deep result'}),
        ],
        'chat_nested_subcall',
      );
    });

    testWidgets('two steps', (tester) async {
      await _pumpChat(
        tester,
        'gold-two-steps',
        [
          _ev('turn/start', 1, {'turn': 1}),
          _ev('step/start', 2, {'turn': 1, 'step': 1}),
          _ev('assistant/chunk', 3, {'turn': 1, 'step': 1, 'chunk': {'type': 'text-delta', 'index': 0, 'text': 'First step thinking'}}),
          _ev('assistant/message', 4, {'turn': 1, 'step': 1, 'message': {'content': [{'type': 'text', 'text': 'First step thinking'}]}}),
          _ev('tool/call', 5, {'callId': 'c1', 'name': 'bash'}),
          _ev('tool/result', 6, {'message': {'source': {'callId': 'c1'}}, 'result': 'ok'}),
          _ev('step/end', 7, {'turn': 1, 'step': 1}),
          _ev('step/start', 8, {'turn': 1, 'step': 2}),
          _ev('assistant/chunk', 9, {'turn': 1, 'step': 2, 'chunk': {'type': 'text-delta', 'index': 0, 'text': 'Second step'}}),
          _ev('assistant/message', 10, {'turn': 1, 'step': 2, 'message': {'content': [{'type': 'text', 'text': 'Second step'}]}}),
          _ev('tool/call', 11, {'callId': 'c2', 'name': 'read'}),
          _ev('tool/result', 12, {'message': {'source': {'callId': 'c2'}}, 'result': 'file content'}),
          _ev('step/end', 13, {'turn': 1, 'step': 2}),
        ],
        'chat_two_steps',
      );
    });

    testWidgets('multiple steps', (tester) async {
      final events = <SessionEvent>[];
      int seq = 1;
      for (int s = 1; s <= 4; s++) {
        events.add(_ev('step/start', seq++, {'turn': 1, 'step': s}));
        events.add(_ev('assistant/chunk', seq++, {'turn': 1, 'step': s, 'chunk': {'type': 'text-delta', 'index': 0, 'text': 'Step $s'}}));
        events.add(_ev('assistant/message', seq++, {'turn': 1, 'step': s, 'message': {'content': [{'type': 'text', 'text': 'Step $s'}]}}));
        events.add(_ev('tool/call', seq++, {'callId': 'c$s', 'name': s % 2 == 0 ? 'read' : 'bash'}));
        events.add(_ev('tool/result', seq++, {'message': {'source': {'callId': 'c$s'}}, 'result': 'result $s'}));
        events.add(_ev('step/end', seq++, {'turn': 1, 'step': s}));
      }
      await _pumpChat(tester, 'gold-multi', events, 'chat_multiple_steps');
    });

    testWidgets('active streaming state', (tester) async {
      await _pumpChat(
        tester,
        'gold-streaming',
        [
          _ev('user/message', 1, {'content': 'Stream test'}),
          _ev('assistant/chunk', 2, {'turn': 1, 'step': 1, 'chunk': {'type': 'text-delta', 'index': 0, 'text': 'Streaming...'}}),
          _ev('assistant/chunk', 3, {'turn': 1, 'step': 1, 'chunk': {'type': 'reasoning-delta', 'index': 0, 'text': 'Thinking line 1\nThinking line 2'}}),
          _ev('tool/call', 4, {'callId': 'c1', 'name': 'bash'}),
        ],
        'chat_streaming',
        running: true,
      );
    });

    testWidgets('final settled state', (tester) async {
      await _pumpChat(
        tester,
        'gold-settled',
        [
          _ev('user/message', 1, {'content': 'Final test'}),
          _ev('assistant/chunk', 2, {'turn': 1, 'step': 1, 'chunk': {'type': 'text-delta', 'index': 0, 'text': 'Answer'}}),
          _ev('assistant/message', 3, {'turn': 1, 'step': 1, 'message': {'content': [{'type': 'text', 'text': 'Answer'}]}}),
          _ev('tool/call', 4, {'callId': 'c1', 'name': 'read'}),
          _ev('tool/result', 5, {'message': {'source': {'callId': 'c1'}}, 'result': 'file data'}),
        ],
        'chat_settled',
      );
    });
  });
}
