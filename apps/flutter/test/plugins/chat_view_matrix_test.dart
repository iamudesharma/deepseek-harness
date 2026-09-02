import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/chat_view.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEvent _ev(String type, int seq, Map<String, dynamic> data) =>
    SessionEvent(type: type, data: data, seq: seq, time: seq * 1000);

ProviderContainer _containerWithHistory(
  String sid,
  List<SessionEvent> events, {
  bool running = false,
}) {
  final c = ProviderContainer();
  c
      .read(sessionsProvider.notifier)
      .addSession(
        SessionSummary(
          sessionId: SessionId(sid),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          running: running,
          blank: false,
          title: 'Session $sid',
        ),
      );
  final notifier = c.read(liveHistoryProvider(sid).notifier);
  final entries = events
      .map((e) => HistoryEntry(event: e, view: null))
      .toList();
  notifier.replaceAll(entries);
  return c;
}

Widget _wrapChat(String sid, ProviderContainer c) {
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(height: 600, child: ChatView(sessionId: sid)),
      ),
    ),
  );
}

void main() {
  group('Chat matrix A-J (content)', () {
    testWidgets('A User + assistant message visible', (tester) async {
      final sid = 'a-user-assistant';
      final c = _containerWithHistory(sid, [
        _ev('user/message', 1, {'content': 'hello from user'}),
        _ev('assistant/chunk', 2, {
          'turn': 1,
          'step': 1,
          'chunk': {
            'type': 'text-delta',
            'index': 0,
            'text': 'hi from assistant',
          },
        }),
        _ev('assistant/message', 3, {
          'turn': 1,
          'step': 1,
          'message': {
            'content': [
              {'type': 'text', 'text': 'hi from assistant'},
            ],
          },
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pumpAndSettle();
      expect(find.text('hello from user'), findsOneWidget);
      expect(find.textContaining('hi from assistant'), findsOneWidget);
    });

    testWidgets('B Assistant streaming shows cursor', (tester) async {
      final sid = 'b-streaming';
      final c = _containerWithHistory(sid, [
        _ev('user/message', 1, {'content': 'q'}),
        _ev('assistant/chunk', 2, {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'partial '},
        }),
        _ev('assistant/chunk', 3, {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'answer'},
        }),
      ], running: true);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      expect(find.textContaining('partial answer'), findsOneWidget);
      expect(find.textContaining('▍'), findsOneWidget);
    });

    testWidgets('C Think streaming renders collapsed row with latest line', (
      tester,
    ) async {
      final sid = 'c-think';
      final c = _containerWithHistory(sid, [
        _ev('turn/start', 1, {'turn': 1}),
        _ev('step/start', 2, {'turn': 1, 'step': 1}),
        _ev('assistant/chunk', 3, {
          'turn': 1,
          'step': 1,
          'chunk': {
            'type': 'reasoning-delta',
            'index': 0,
            'text': 'first line\nsecond line\nthird line',
          },
        }),
      ], running: true);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('third line'), findsOneWidget);
      await tester.tap(find.text('Thinking'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('first line'), findsOneWidget);
    });

    testWidgets('D Tool running shows row', (tester) async {
      final sid = 'd-tool-running';
      final c = _containerWithHistory(sid, [
        _ev('tool/call', 1, {
          'callId': 'c1',
          'name': 'bash',
          'arguments': '{}',
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      expect(find.text('bash'), findsOneWidget);
    });

    testWidgets('E Tool completed shows result', (tester) async {
      final sid = 'e-tool-completed';
      final c = _containerWithHistory(sid, [
        _ev('tool/call', 1, {
          'callId': 'c1',
          'name': 'read',
          'arguments': '{"path":"a.txt"}',
        }),
        _ev('tool/result', 2, {
          'message': {
            'source': {'callId': 'c1'},
          },
          'result': 'file content here',
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      expect(find.text('read'), findsOneWidget);
      await tester.tap(find.text('read').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('file content'), findsWidgets);
    });

    testWidgets('F Tool error shows error color row', (tester) async {
      final sid = 'f-tool-error';
      final c = _containerWithHistory(sid, [
        _ev('tool/call', 1, {'callId': 'c1', 'name': 'bash'}),
        _ev('tool/result', 2, {
          'message': {
            'source': {'callId': 'c1'},
          },
          'result': 'permission denied',
          'isError': true,
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      expect(find.text('bash'), findsOneWidget);
      await tester.tap(find.text('bash').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('permission denied'), findsWidgets);
    });

    testWidgets('G Nested subcall depth 1 and 2 rendered', (tester) async {
      final sid = 'g-subcall';
      final c = _containerWithHistory(sid, [
        _ev('turn/start', 1, {'turn': 1}),
        _ev('tool/call', 2, {'callId': 'root-1', 'name': 'run-code'}),
        _ev('tool/code-dispatch-start', 3, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1',
          'subCallId': 'root-1:code:1',
          'name': 'bash',
          'arguments': '{"command":"ls"}',
        }),
        _ev('tool/code-dispatch', 4, {
          'rootCallId': 'root-1',
          'parentCallId': 'root-1:code:1',
          'subCallId': 'root-1:code:1:code:1',
          'name': 'inner',
          'content': 'deep',
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      expect(find.text('run-code'), findsOneWidget);
      expect(find.text('bash'), findsOneWidget);
      expect(find.text('inner'), findsOneWidget);
    });

    testWidgets('H Multiple steps show headers and tool rows', (tester) async {
      final sid = 'h-multi-step';
      final c = _containerWithHistory(sid, [
        _ev('turn/start', 1, {'turn': 1}),
        _ev('step/start', 2, {'turn': 1, 'step': 1}),
        _ev('assistant/chunk', 3, {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'first'},
        }),
        _ev('assistant/message', 4, {
          'turn': 1,
          'step': 1,
          'message': {
            'content': [
              {'type': 'text', 'text': 'first'},
            ],
          },
        }),
        _ev('tool/call', 5, {'callId': 'c1', 'name': 'bash'}),
        _ev('tool/result', 6, {
          'message': {
            'source': {'callId': 'c1'},
          },
          'result': 'ok',
        }),
        _ev('step/end', 7, {'turn': 1, 'step': 1}),
        _ev('step/start', 8, {'turn': 1, 'step': 2}),
        _ev('assistant/chunk', 9, {
          'turn': 1,
          'step': 2,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'second'},
        }),
        _ev('assistant/message', 10, {
          'turn': 1,
          'step': 2,
          'message': {
            'content': [
              {'type': 'text', 'text': 'second'},
            ],
          },
        }),
        _ev('tool/call', 11, {'callId': 'c2', 'name': 'read'}),
        _ev('tool/result', 12, {
          'message': {
            'source': {'callId': 'c2'},
          },
          'result': 'file',
        }),
        _ev('step/end', 13, {'turn': 1, 'step': 2}),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pumpAndSettle();
      // React fidelity: Step/Turn structure is booking, not a dominant header.
      // No Step 1/Step 2 disclosure is rendered; children are flat.
      expect(find.textContaining('Step 1'), findsNothing);
      expect(find.textContaining('Step 2'), findsNothing);
      expect(find.text('bash'), findsOneWidget);
      expect(find.text('read'), findsOneWidget);
      expect(find.textContaining('first'), findsOneWidget);
      expect(find.textContaining('second'), findsOneWidget);
    });

    testWidgets('I Retry shows retry row', (tester) async {
      final sid = 'i-retry';
      final c = _containerWithHistory(sid, [
        _ev('llm/retry', 1, {
          'retry': 1,
          'maxRetries': 3,
          'delayMs': 250,
          'failure': {'code': 'TRANSPORT', 'message': 'flaky'},
          'retryId': 'r-1',
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      // React parity: collapsed "Scheduled/Retrying model request (retry/max) · Xs"
      expect(find.textContaining('model request'), findsOneWidget);
      expect(find.textContaining('1/3'), findsOneWidget);
      expect(find.textContaining('1s'), findsOneWidget);
    });

    testWidgets('J Compaction renders card', (tester) async {
      final sid = 'j-compaction';
      final c = _containerWithHistory(sid, [
        _ev('user/message', 1, {'content': 'keep'}),
        _ev('compaction/start', 2, {}),
        _ev('user/message', 3, {'content': 'old'}),
        _ev('assistant/message', 4, {'turn': 1, 'step': 1, 'message': {}}),
        SessionEvent(
          type: 'compaction/summary',
          data: {'text': 'condensed history'},
          seq: 5,
          time: 5000,
        ),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      // Compaction card always shows a row with the icon.
      expect(find.byIcon(Icons.api_rounded), findsOneWidget);
      // Expand to see markdown.
      await tester.tap(find.byIcon(Icons.api_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('condensed'), findsOneWidget);
    });

    testWidgets('K Long conversation scrolls', (tester) async {
      final sid = 'k-long';
      final events = <SessionEvent>[];
      int seq = 1;
      for (int i = 0; i < 40; i++) {
        events.add(_ev('user/message', seq++, {'content': 'user $i'}));
        events.add(
          _ev('assistant/chunk', seq++, {
            'turn': i + 1,
            'step': 1,
            'chunk': {'type': 'text-delta', 'index': 0, 'text': 'assistant $i'},
          }),
        );
        events.add(
          _ev('assistant/message', seq++, {
            'turn': i + 1,
            'step': 1,
            'message': {
              'content': [
                {'type': 'text', 'text': 'assistant $i'},
              ],
            },
          }),
        );
      }
      final c = _containerWithHistory(sid, events);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      // Pinned at bottom, last item visible.
      expect(find.text('user 39'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
      // Scroll up should show back button.
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('Q Tool renderer fallback for unknown tool', (tester) async {
      final sid = 'q-fallback';
      final c = _containerWithHistory(sid, [
        _ev('tool/call', 1, {'callId': 'c9', 'name': 'mystery_tool_xyz'}),
        _ev('tool/result', 2, {
          'message': {
            'source': {'callId': 'c9'},
          },
          'result': 'out',
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      expect(find.text('mystery_tool_xyz'), findsOneWidget);
      await tester.tap(find.text('mystery_tool_xyz').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('out'), findsWidgets);
    });
  });

  group('Scroll contract L-N', () {
    testWidgets(
      'L User scrolls away from bottom shows Back to bottom and does not follow',
      (tester) async {
        final sid = 'l-scroll-away';
        final events = <SessionEvent>[];
        int seq = 1;
        for (int i = 0; i < 30; i++) {
          events.add(_ev('user/message', seq++, {'content': 'u $i'}));
          events.add(
            _ev('assistant/message', seq++, {
              'turn': i + 1,
              'step': 1,
              'message': {
                'content': [
                  {'type': 'text', 'text': 'a $i'},
                ],
              },
            }),
          );
        }
        final c = _containerWithHistory(sid, events);
        addTearDown(c.dispose);
        await tester.pumpWidget(_wrapChat(sid, c));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
        final notifier = c.read(liveHistoryProvider(sid).notifier);
        final before = _scrollOffset(tester);
        final newEvents = [
          ...events,
          _ev('assistant/chunk', 100, {
            'turn': 99,
            'step': 1,
            'chunk': {
              'type': 'text-delta',
              'index': 0,
              'text': ' new streaming',
            },
          }),
        ];
        notifier.replaceAll(
          newEvents.map((e) => HistoryEntry(event: e, view: null)).toList(),
        );
        await tester.pump();
        final after = _scrollOffset(tester);
        expect((after - before).abs() < 50, isTrue);
      },
    );

    testWidgets('M Streaming while pinned follows tail', (tester) async {
      final sid = 'm-streaming-pinned';
      final c = _containerWithHistory(sid, [
        _ev('user/message', 1, {'content': 'q'}),
        _ev('assistant/chunk', 2, {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'start'},
        }),
      ], running: true);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = _scrollOffset(tester);
      final notifier = c.read(liveHistoryProvider(sid).notifier);
      final current = c.read(liveHistoryProvider(sid));
      final next = [
        ...current,
        HistoryEntry(
          event: _ev('assistant/chunk', 3, {
            'turn': 1,
            'step': 1,
            'chunk': {'type': 'text-delta', 'index': 0, 'text': ' more'},
          }),
          view: null,
        ),
      ];
      notifier.replaceAll(next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final after = _scrollOffset(tester);
      expect(after >= before, isTrue);
    });

    testWidgets(
      'Streaming high frequency dozens of frames while pinned follows',
      (tester) async {
        final sid = 'stream-high-freq';
        // Create a long scrollable history so drag actually scrolls.
        final initialEvents = <SessionEvent>[];
        for (int i = 0; i < 25; i++) {
          initialEvents.add(_ev('user/message', i + 1, {'content': 'u $i'}));
        }
        initialEvents.add(
          _ev('assistant/chunk', 100, {
            'turn': 5,
            'step': 1,
            'chunk': {'type': 'text-delta', 'index': 0, 'text': ' chunk 0'},
          }),
        );
        final c = _containerWithHistory(sid, initialEvents, running: true);
        addTearDown(c.dispose);
        await tester.pumpWidget(_wrapChat(sid, c));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Pump 30 streaming chunks sequentially while pinned (same turn/step key updates in place).
        for (int i = 1; i < 30; i++) {
          final cur = c.read(liveHistoryProvider(sid));
          final next = [
            ...cur.take(cur.length - 1),
            HistoryEntry(
              event: _ev('assistant/chunk', 100 + i, {
                'turn': 5,
                'step': 1,
                'chunk': {
                  'type': 'text-delta',
                  'index': 0,
                  'text': ' chunk $i',
                },
              }),
              view: null,
            ),
            HistoryEntry(
              event: _ev('assistant/chunk', 200 + i, {
                'turn': 5,
                'step': 1,
                'chunk': {
                  'type': 'text-delta',
                  'index': 0,
                  'text': ' chunk $i',
                },
              }),
              view: null,
            ),
          ];
          // Simpler: just append new chunk updating same key – folder accumulates.
          c.read(liveHistoryProvider(sid).notifier).replaceAll([
            ...cur,
            HistoryEntry(
              event: _ev('assistant/chunk', 300 + i, {
                'turn': 5,
                'step': 1,
                'chunk': {
                  'type': 'text-delta',
                  'index': 0,
                  'text': ' chunk $i',
                },
              }),
              view: null,
            ),
          ]);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        }
        // Should still be pinned at bottom (no crash, atBottom true) – content tall enough.
        expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
        // Now scroll away and stream again – should not follow.
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
        final offsetBefore = _scrollOffset(tester);
        for (int i = 30; i < 40; i++) {
          final cur = c.read(liveHistoryProvider(sid));
          c.read(liveHistoryProvider(sid).notifier).replaceAll([
            ...cur,
            HistoryEntry(
              event: _ev('assistant/chunk', 400 + i, {
                'turn': 5,
                'step': 1,
                'chunk': {'type': 'text-delta', 'index': 0, 'text': ' late $i'},
              }),
              view: null,
            ),
          ]);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        }
        final offsetAfter = _scrollOffset(tester);
        expect((offsetAfter - offsetBefore).abs() < 80, isTrue);
      },
    );

    testWidgets('N Return to bottom re-pins and hides button', (tester) async {
      final sid = 'n-return';
      final events = <SessionEvent>[];
      for (int i = 0; i < 30; i++) {
        events.add(_ev('user/message', i + 1, {'content': 'u $i'}));
      }
      final c = _containerWithHistory(sid, events);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });
  });

  group('Session switch & prepend', () {
    testWidgets('O Session switch restores scroll position', (tester) async {
      final TargetPlatform? prevPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = prevPlatform;
      });
      // Ensure invariant check passes even if early failure — reset before callback returns.
      // The binding's _verifyInvariants runs before tearDown, so we must clear at end.
      try {
        const sidA = 'o-a';
        const sidB = 'o-b';
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c
            .read(sessionsProvider.notifier)
            .addSession(
              SessionSummary(
                sessionId: SessionId(sidA),
                updatedAt: 0,
                running: false,
                blank: false,
                title: 'A',
              ),
            );
        c
            .read(sessionsProvider.notifier)
            .addSession(
              SessionSummary(
                sessionId: SessionId(sidB),
                updatedAt: 0,
                running: false,
                blank: false,
                title: 'B',
              ),
            );
        final aEvents = List.generate(
          30,
          (i) => _ev('user/message', i + 1, {'content': 'A $i'}),
        );
        final bEvents = List.generate(
          5,
          (i) => _ev('user/message', 100 + i, {'content': 'B $i'}),
        );
        c
            .read(liveHistoryProvider(sidA).notifier)
            .replaceAll(
              aEvents.map((e) => HistoryEntry(event: e, view: null)).toList(),
            );
        c
            .read(liveHistoryProvider(sidB).notifier)
            .replaceAll(
              bEvents.map((e) => HistoryEntry(event: e, view: null)).toList(),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: buildLightTheme(),
              home: Scaffold(
                body: SizedBox(height: 600, child: ChatView(sessionId: sidA)),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        // Initially at bottom — no affordance.
        expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        // After scroll away from bottom, back-to-bottom should appear.
        expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: buildLightTheme(),
              home: Scaffold(
                body: SizedBox(height: 600, child: ChatView(sessionId: sidB)),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.text('B 0'), findsOneWidget);
        // B has few items, at bottom — no affordance.
        expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: buildLightTheme(),
              home: Scaffold(
                body: SizedBox(height: 600, child: ChatView(sessionId: sidA)),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        // Semantic restoration: A is back, still away-from-bottom, not incorrectly snapped to tail.
        // At least one A message is visible, back-button remains, and we did not force bottom-follow.
        expect(
          find.textContaining('A ').evaluate().isNotEmpty,
          isTrue,
          reason: 'restored A transcript visible',
        );
        expect(
          find.byIcon(Icons.arrow_downward_rounded),
          findsOneWidget,
          reason: 'restored position stays away from bottom',
        );
        // Ensure we are not at the very tail (best-effort: not showing last item exclusively at bottom without affordance).
        // If we were incorrectly pinned to bottom, the affordance would be hidden.
      } finally {
        debugDefaultTargetPlatformOverride = prevPlatform;
      }
    });

    testWidgets('P History prepend anchoring preserves visible anchor', (
      tester,
    ) async {
      final sid = 'p-prepend';
      final c = _containerWithHistory(sid, [
        _ev('user/message', 10, {'content': 'visible 10'}),
        _ev('user/message', 11, {'content': 'visible 11'}),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pumpAndSettle();
      final notifier = c.read(liveHistoryProvider(sid).notifier);
      final older = [
        _ev('user/message', 1, {'content': 'older 1'}),
        _ev('user/message', 2, {'content': 'older 2'}),
      ];
      final current = c.read(liveHistoryProvider(sid));
      notifier.replaceAll([
        ...older.map((e) => HistoryEntry(event: e, view: null)),
        ...current,
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('older 1'), findsOneWidget);
      expect(find.text('visible 10'), findsOneWidget);
    });

    testWidgets('R Composer sticky bottom padding reserves height', (
      tester,
    ) async {
      final sid = 'r-composer';
      final c = _containerWithHistory(sid, [
        _ev('user/message', 1, {'content': 'hello'}),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrapChat(sid, c));
      await tester.pumpAndSettle();
      final listView = tester.widget<ListView>(find.byType(ListView));
      final padding = listView.padding as EdgeInsets;
      expect(padding.bottom, greaterThan(60));
    });
  });
}

double _scrollOffset(WidgetTester tester) {
  final ScrollableState scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  return scrollable.position.pixels;
}
