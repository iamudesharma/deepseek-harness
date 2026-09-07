import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/locales.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/chat_view.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _en(String key) => const {
      'message.turnProcess.toolCalls.one': '{count} tool call',
      'message.turnProcess.toolCalls.other': '{count} tool calls',
      'message.turnProcess.messages.one': '{count} message',
      'message.turnProcess.messages.other': '{count} messages',
      'message.turnProcess.subagents.one': '{count} subagent',
      'message.turnProcess.subagents.other': '{count} subagents',
      'message.turnProcess.thoughtForAWhile': 'Thought for a while',
      'message.turnProcess.separator': ' · ',
    }[key] ??
    key;

void main() {
  group('turn-process group label (React TurnProcessNodeView parity)', () {
    test('counts label matches React format', () {
      expect(
        formatTurnProcessLabel(
          toolCallCount: 3,
          messageCount: 1,
          subagentCount: 0,
          t: _en,
        ),
        '3 tool calls · 1 message',
      );
    });

    test('singular forms', () {
      expect(
        formatTurnProcessLabel(
          toolCallCount: 1,
          messageCount: 0,
          subagentCount: 0,
          t: _en,
        ),
        '1 tool call',
      );
    });

    test('subagents join the label', () {
      expect(
        formatTurnProcessLabel(
          toolCallCount: 0,
          messageCount: 2,
          subagentCount: 1,
          t: _en,
        ),
        '2 messages · 1 subagent',
      );
    });

    test('empty counts fall back to the thought line', () {
      expect(
        formatTurnProcessLabel(
          toolCallCount: 0,
          messageCount: 0,
          subagentCount: 0,
          t: _en,
        ),
        'Thought for a while',
      );
    });
  });

  group('grouped tool suppression', () {
    test('hides settled grouped tools only while collapsed', () {
      const grouped = {1};
      const settled = {1, 2};
      expect(
        hideGroupedTool(
          turn: 1,
          groupedTurns: grouped,
          settledTurns: settled,
          openTurns: const {},
        ),
        isTrue,
      );
      expect(
        hideGroupedTool(
          turn: 1,
          groupedTurns: grouped,
          settledTurns: settled,
          openTurns: const {1},
        ),
        isFalse,
      );
      // Live (tail-less) turn keeps streaming rows openly.
      expect(
        hideGroupedTool(
          turn: 2,
          groupedTurns: grouped,
          settledTurns: settled,
          openTurns: const {},
        ),
        isFalse,
      );
      // Unknown turn never suppresses.
      expect(
        hideGroupedTool(
          turn: null,
          groupedTurns: grouped,
          settledTurns: settled,
          openTurns: const {},
        ),
        isFalse,
      );
    });
  });

  group('chat anchor order (React orderedVisibleChatNodes parity)', () {
    test('request-anchored system row sorts before its user bubble', () {
      final user = UserMessageNode(
        key: 'u8',
        sourceSeqs: const [8],
        text: 'hi',
      );
      final system = SystemPromptNode(
        key: 'system-12',
        sourceSeqs: const [12],
        text: 'prompt',
        anchorSeq: 5,
      );
      final ordered = stableChatOrder(
        [user, system],
        (n) => chatNodeOrderKey(n),
      );
      expect(ordered.map((n) => n.key), ['system-12', 'u8']);
    });

    test('event order is stable otherwise', () {
      final a = UserMessageNode(key: 'a', sourceSeqs: const [8], text: 'x');
      final b = UserMessageNode(key: 'b', sourceSeqs: const [9], text: 'y');
      expect(
        stableChatOrder([a, b], chatNodeOrderKey).map((n) => n.key),
        ['a', 'b'],
      );
    });
  });

  group('settled turn grouping in ChatView (React TurnProcess parity)', () {
    SessionEvent ev(String type, int seq, Map<String, dynamic> data) =>
        SessionEvent(type: type, data: data, seq: seq, time: seq * 1000);

    ProviderContainer containerWithHistory(
      String sid,
      List<SessionEvent> events,
    ) {
      final c = ProviderContainer();
      c.read(sessionsProvider.notifier).addSession(
            SessionSummary(
              sessionId: SessionId(sid),
              updatedAt: 0,
              running: false,
              blank: false,
            ),
          );
      c.read(liveHistoryProvider(sid).notifier).replaceAll(
            events
                .map((e) => HistoryEntry(event: e, view: null))
                .toList(),
          );
      return c;
    }

    List<SessionEvent> settledTurn() => [
          ev('turn/start', 5, {'turn': 1}),
          ev('step/start', 7, {'turn': 1, 'step': 1}),
          ev('user/message', 8, {
            'content': 'hi',
            'source': {'kind': 'user'},
          }),
          ev('tool/call', 13, {
            'turn': 1,
            'step': 1,
            'callId': 'c1',
            'name': 'bash',
            'arguments': '{}',
          }),
          ev('tool/result', 14, {
            'turn': 1,
            'step': 1,
            'message': {
              'source': {'callId': 'c1'},
            },
            'result': 'ok',
          }),
          ev('tool/call', 15, {
            'turn': 1,
            'step': 1,
            'callId': 'c2',
            'name': 'read',
            'arguments': '{}',
          }),
          ev('tool/result', 16, {
            'turn': 1,
            'step': 1,
            'message': {
              'source': {'callId': 'c2'},
            },
            'result': 'file',
          }),
          ev('assistant/message', 20, {
            'turn': 1,
            'step': 1,
            'message': {
              'content': [
                {'type': 'text', 'text': 'done'},
              ],
            },
          }),
          ev('turn/end', 21, {'turn': 1}),
        ];

    Widget wrapChat(String sid, ProviderContainer c) =>
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(
              body: SizedBox(height: 800, child: ChatView(sessionId: sid)),
            ),
          ),
        );

    testWidgets('settled turn collapses tools behind the counts row',
        (tester) async {
      const sid = 'grouped-turn';
      final c = containerWithHistory(sid, settledTurn());
      addTearDown(c.dispose);
      await tester.pumpWidget(wrapChat(sid, c));
      await tester.pumpAndSettle();
      // Group row carries the React counts label through real dictionaries.
      expect(find.text('2 tool calls'), findsOneWidget);
      // Member tool rows hide while the group stays collapsed.
      expect(find.text('Bash'), findsNothing);
      expect(find.text('Read'), findsNothing);
    });

    testWidgets('expanding the group reveals member tool rows',
        (tester) async {
      const sid = 'grouped-turn-expand';
      final c = containerWithHistory(sid, settledTurn());
      addTearDown(c.dispose);
      await tester.pumpWidget(wrapChat(sid, c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 tool calls'));
      await tester.pumpAndSettle();
      expect(find.text('Bash'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
    });
  });
}
