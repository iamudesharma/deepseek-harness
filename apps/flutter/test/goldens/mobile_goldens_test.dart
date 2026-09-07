/// Mobile conversation goldens — phone-viewport (390×844) references for the
/// Phase 6 surface: transcript kinds, composer, pending-interaction cards,
/// and the input-trigger/model menus. Desktop/Web goldens are untouched; a
/// shared-widget change that legitimately moves these must be deliberate.
library;

import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart' as conn;
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_screen.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String sid = 'golden-mobile';

SessionEvent _ev(String type, int seq, Map<String, dynamic> data) =>
    SessionEvent(type: type, data: data, seq: seq, time: seq * 1000);

class _ScriptedClient extends conn.ConnectionClient {
  _ScriptedClient() : super(baseUrl: 'http://golden-mobile');

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    return switch (method) {
      'session.models' => const <String, dynamic>{
        'groups': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'deepseek',
            'name': 'DeepSeek',
            'models': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
              <String, dynamic>{
                'id': 'deepseek-reasoner',
                'name': 'DeepSeek Reasoner',
                'reasoning': <String, dynamic>{
                  'defaultEffort': 'medium',
                  'efforts': <Map<String, dynamic>>[
                    {'id': 'low', 'name': 'Low'},
                    {'id': 'medium', 'name': 'Medium'},
                    {'id': 'high', 'name': 'High'},
                  ],
                },
              },
            ],
          },
        ],
        'routable': true,
      },
      _ => const <String, dynamic>{},
    };
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<SessionEvent> events = const [],
  bool blank = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final container = ProviderContainer(
    overrides: [
      conn.connectionClientProvider.overrideWithValue(_ScriptedClient()),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  PluginHost? host;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          host ??= buildAppHost(ref);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  await host!.activateAll();
  addTearDown(host!.deactivateAll);

  container
      .read(sessionsProvider.notifier)
      .addSession(
        SessionSummary(
          sessionId: SessionId(sid),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          running: false,
          blank: blank,
          title: blank ? 'New session' : 'Golden session',
        ),
      );
  container.read(sessionsProvider.notifier).setCurrent(SessionId(sid));
  if (events.isNotEmpty) {
    container
        .read(liveHistoryProvider(sid).notifier)
        .replaceAll(events.map((e) => HistoryEntry(event: e)).toList());
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        debugShowCheckedModeBanner: false,
        home: ConversationScreen(sessionId: sid),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('blank hero', (tester) async {
    await _pump(tester, blank: true);
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_blank_hero.png'),
    );
  });

  testWidgets('user + assistant', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'fix the failing test'}),
        _ev('assistant/message', 2, {
          'turn': 1,
          'step': 1,
          'message': {
            'content': <Map<String, dynamic>>[
              {'type': 'text', 'text': 'On it.'},
            ],
          },
        }),
      ],
    );
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_user_assistant.png'),
    );
  });

  testWidgets('thinking row', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'q'}),
        _ev('assistant/chunk', 2, {
          'turn': 1,
          'step': 1,
          'chunk': {
            'type': 'reasoning-delta',
            'index': 0,
            'text': 'line one\nline two',
          },
        }),
      ],
    );
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_thinking.png'),
    );
  });

  testWidgets('tool running', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'run'}),
        _ev('tool/call', 2, {
          'callId': 'c1',
          'name': 'bash',
          'arguments': '{"command":"flutter test"}',
        }),
      ],
    );
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_tool_running.png'),
    );
  });

  testWidgets('tool completed', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'run'}),
        _ev('tool/call', 2, {
          'callId': 'c1',
          'name': 'read',
          'arguments': '{"path":"a.dart"}',
        }),
        _ev('tool/result', 3, {
          'message': {
            'source': {'callId': 'c1'},
          },
          'result': 'const x = 1;',
        }),
      ],
    );
    await tester.tap(find.text('read').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_tool_completed.png'),
    );
  });

  testWidgets('tool error', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'run'}),
        _ev('tool/call', 2, {'callId': 'c1', 'name': 'bash'}),
        _ev('tool/result', 3, {
          'message': {
            'source': {'callId': 'c1'},
          },
          'result': 'permission denied',
          'isError': true,
        }),
      ],
    );
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_tool_error.png'),
    );
  });

  testWidgets('nested subcall', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'run'}),
        _ev('tool/call', 2, {
          'callId': 'root',
          'name': 'bash',
          'arguments': '{"command":"make"}',
        }),
        _ev('tool/call', 3, {
          'callId': 'sub',
          'name': 'read',
          'arguments': '{}',
          'rootCallId': 'root',
        }),
        _ev('tool/result', 4, {
          'message': {
            'source': {'callId': 'sub'},
          },
          'result': 'ok',
        }),
        _ev('tool/result', 5, {
          'message': {
            'source': {'callId': 'root'},
          },
          'result': 'done',
        }),
      ],
    );
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_nested_subcall.png'),
    );
  });

  testWidgets('approval card', (tester) async {
    final container = await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'run'}),
      ],
    );
    container
        .read(approvalsProvider.notifier)
        .requested(
          sid,
          rpcId: 'r1',
          approvalId: 'a1',
          toolName: 'bash',
          reason: 'flutter test',
        );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_approval.png'),
    );
  });

  testWidgets('question card', (tester) async {
    final container = await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'q'}),
      ],
    );
    container
        .read(pendingQuestionsProvider.notifier)
        .requested(
          sid,
          rpcId: 'r2',
          questions: const <QuestionItem>[
            QuestionItem(
              id: 'q1',
              question: 'Which database?',
              options: <QuestionOption>[
                QuestionOption(label: 'postgres'),
                QuestionOption(label: 'sqlite'),
              ],
            ),
          ],
        );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_question.png'),
    );
  });

  testWidgets('composer focused', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'hello'}),
      ],
    );
    await tester.tap(find.text('Ask anything…'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_composer.png'),
    );
  });

  testWidgets('input trigger menu', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'hi'}),
      ],
    );
    await tester.tap(find.text('Ask anything…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_input_trigger.png'),
    );
  });

  testWidgets('model menu', (tester) async {
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'hi'}),
      ],
    );
    await tester.tap(find.byIcon(Icons.memory_outlined));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_model_menu.png'),
    );
  });

  testWidgets('landscape narrow layout', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    await _pump(
      tester,
      events: [
        _ev('user/message', 1, {'content': 'landscape message'}),
        _ev('assistant/message', 2, {
          'turn': 1,
          'step': 1,
          'message': {
            'content': <Map<String, dynamic>>[
              {'type': 'text', 'text': 'reply'},
            ],
          },
        }),
      ],
    );
    await expectLater(
      find.byType(ConversationScreen),
      matchesGoldenFile('goldens/mobile_landscape.png'),
    );
  });
}
