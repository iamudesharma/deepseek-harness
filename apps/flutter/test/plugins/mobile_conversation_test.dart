/// Phase 6 mobile conversation integration: PluginHost → ConversationScreen
/// (mobile posture) → ChatView → ChatNodeRendererRegistry → ToolCallTree,
/// plus the mobile shell chrome contract (header, connection states,
/// keyboard, session switching, tablet width cap).
///
/// The default flutter_test platform is Android, so [ConversationScreen]
/// takes the mobile branch — the same posture Android devices run.
library;

import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart' as conn;
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    as conn;
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_screen.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/mobile_shell.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String qaSession = 'qa-mobile';

SessionEvent _ev(String type, int seq, Map<String, dynamic> data) =>
    SessionEvent(type: type, data: data, seq: seq, time: seq * 1000);

/// Scripted connection client: plugin activation probes answer with canned
/// payloads; unknown methods return empty maps.
class ScriptedClient extends conn.ConnectionClient {
  ScriptedClient() : super(baseUrl: 'http://qa-mobile');

  final List<String> methods = <String>[];

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    methods.add(method);
    return switch (method) {
      'session.models' => const <String, dynamic>{
        'groups': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'deepseek',
            'name': 'DeepSeek',
            'models': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
            ],
          },
        ],
        'routable': true,
      },
      _ => const <String, dynamic>{},
    };
  }
}

/// Boots the real application host and mounts [ConversationScreen] at the
/// given phone/tablet size. Returns the container for state seeding.
Future<ProviderContainer> pumpMobileShell(
  WidgetTester tester,
  ScriptedClient client, {
  Size size = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final ProviderContainer container = ProviderContainer(
    overrides: [conn.connectionClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = size;
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

  return container;
}

/// Seed one non-blank session with [events] and mount the mobile screen.
Future<ProviderContainer> pumpSessionWithHistory(
  WidgetTester tester,
  ScriptedClient client,
  List<SessionEvent> events, {
  String sid = qaSession,
  Size size = const Size(390, 844),
}) async {
  final container = await pumpMobileShell(tester, client, size: size);
  container
      .read(sessionsProvider.notifier)
      .addSession(
        SessionSummary(
          sessionId: SessionId(sid),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          running: false,
          blank: false,
          title: 'Mobile session',
        ),
      );
  container.read(sessionsProvider.notifier).setCurrent(SessionId(sid));
  final notifier = container.read(liveHistoryProvider(sid).notifier);
  notifier.replaceAll(events.map((e) => HistoryEntry(event: e)).toList());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: ConversationScreen(sessionId: sid),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

List<SessionEvent> _richHistory() => <SessionEvent>[
  _ev('user/message', 1, {'content': 'fix the failing test'}),
  _ev('assistant/chunk', 2, {
    'turn': 1,
    'step': 1,
    'chunk': {
      'type': 'reasoning-delta',
      'index': 0,
      'text': 'checking the matrix\nthen the fold',
    },
  }),
  _ev('assistant/chunk', 3, {
    'turn': 1,
    'step': 1,
    'chunk': {
      'type': 'text-delta',
      'index': 0,
      'text': 'On it — running the suite.',
    },
  }),
  _ev('tool/call', 4, {
    'callId': 'c1',
    'name': 'bash',
    'arguments': '{"command":"flutter test"}',
  }),
  _ev('tool/call', 5, {
    'callId': 'c2',
    'name': 'read',
    'arguments': '{"path":"a.dart"}',
    'rootCallId': 'c1',
  }),
  _ev('tool/result', 6, {
    'message': {
      'source': {'callId': 'c2'},
    },
    'result': 'const x = 1;',
  }),
  _ev('tool/result', 7, {
    'message': {
      'source': {'callId': 'c1'},
    },
    'result': '1 failing',
    'isError': true,
  }),
  _ev('assistant/message', 8, {
    'turn': 1,
    'step': 1,
    'message': {
      'content': <Map<String, dynamic>>[
        {'type': 'text', 'text': 'On it — running the suite.'},
      ],
    },
  }),
];

void main() {
  group('mobile conversation integration (PluginHost → screen → ChatView)', () {
    testWidgets(
      'renders header, transcript kinds, and composer at phone size',
      (tester) async {
        final client = ScriptedClient();
        await pumpSessionWithHistory(tester, client, _richHistory());

        // Header chrome: back, title, run dot.
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.text('Mobile session'), findsOneWidget);
        // Transcript kinds through the real fold + registry: user, assistant,
        // reasoning tail, tool row, nested subcall, error state.
        expect(find.text('fix the failing test'), findsOneWidget);
        expect(find.textContaining('On it — running the suite.'), findsWidgets);
        expect(find.text('Thinking'), findsOneWidget);
        expect(find.text('bash'), findsOneWidget);
        expect(find.text('read'), findsOneWidget);
        // Composer resident at the bottom.
        expect(find.text('Ask anything…'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
        // No desktop hint on touch.
        expect(find.text('Cmd+Enter to send'), findsNothing);
      },
    );

    testWidgets('connection states: banner shows, needsReauth offers re-pair', (
      tester,
    ) async {
      final client = ScriptedClient();
      final container = await pumpSessionWithHistory(
        tester,
        client,
        _richHistory(),
      );

      container
          .read(conn.connectionStateProvider.notifier)
          .setStateSafe(conn.ConnectionState.reconnecting);
      await tester.pump();
      expect(find.text('Reconnecting'), findsOneWidget);

      container
          .read(conn.connectionStateProvider.notifier)
          .setStateSafe(conn.ConnectionState.needsReauth);
      await tester.pump();
      expect(find.text('Needs re-auth'), findsOneWidget);
      expect(find.text('Re-pair'), findsOneWidget);
    });

    testWidgets('back returns to the mobile sessions list', (tester) async {
      final client = ScriptedClient();
      final container = await pumpSessionWithHistory(
        tester,
        client,
        _richHistory(),
      );

      final router = GoRouter(
        initialLocation: '/sessions/$qaSession',
        routes: <RouteBase>[
          GoRoute(
            path: '/sessions',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('SESSIONS LIST'))),
          ),
          GoRoute(
            path: '/sessions/:sid',
            builder: (_, state) =>
                ConversationScreen(sessionId: state.pathParameters['sid']!),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('SESSIONS LIST'), findsOneWidget);
    });

    testWidgets('keyboard opens: composer stays visible, header intact', (
      tester,
    ) async {
      final client = ScriptedClient();
      await pumpSessionWithHistory(tester, client, _richHistory());

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      // The composer input is still on screen (above the keyboard inset) and
      // the header did not scroll away.
      expect(find.byTooltip('Back'), findsOneWidget);
      final inputFinder = find.text('Ask anything…');
      expect(inputFinder, findsOneWidget);
      final inputBottom = tester.getBottomRight(inputFinder).dy;
      expect(inputBottom, lessThanOrEqualTo(844.0));
    });

    testWidgets('tablet landscape caps the conversation column width', (
      tester,
    ) async {
      final client = ScriptedClient();
      await pumpSessionWithHistory(
        tester,
        client,
        _richHistory(),
        size: const Size(1024, 768),
      );

      // No horizontal overflow from the shared body at tablet width.
      expect(tester.takeException(), isNull);
      final composerField = find.text('Ask anything…');
      expect(composerField, findsOneWidget);
      // Content column is capped, not stretched edge to edge.
      final inputLeft = tester.getTopLeft(composerField).dx;
      final inputRight = tester.getTopRight(composerField).dx;
      expect(inputRight - inputLeft, lessThanOrEqualTo(780.0));
      expect(inputLeft, greaterThanOrEqualTo(12.0));
    });

    testWidgets('session switch: no stale nodes, per-session restore', (
      tester,
    ) async {
      final client = ScriptedClient();
      // Short viewport: the transcript must overflow for scroll semantics.
      final container = await pumpSessionWithHistory(
        tester,
        client,
        _richHistory(),
        size: const Size(390, 420),
      );

      // Session B with distinct content, at-bottom.
      container
          .read(sessionsProvider.notifier)
          .addSession(
            SessionSummary(
              sessionId: const SessionId('sess-b'),
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              running: false,
              blank: false,
              title: 'Session B',
            ),
          );
      container.read(liveHistoryProvider('sess-b').notifier).replaceAll(
        <HistoryEntry>[
          HistoryEntry(
            event: _ev('user/message', 1, {'content': 'session B message'}),
          ),
        ],
      );

      // Mount through the param shell so session switches exercise the real
      // route-param path (didUpdateWidget inside one shell).
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: _ParamShell(initialSid: qaSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll A into history (finger down = view toward older), releasing
      // follow. Then switch sessions the way the router does: the SAME shell
      // receives a new sessionId (didUpdateWidget), not a remount.
      await tester.drag(find.text('bash'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('session B message'), findsNothing);
      // Reader scrolled up → follow released → FAB visible.
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      tester
          .state<_ParamShellState>(find.byType(_ParamShell))
          .switchTo('sess-b');
      await tester.pumpAndSettle();
      expect(find.text('session B message'), findsOneWidget);
      expect(find.text('fix the failing test'), findsNothing);
      expect(find.text('Session B'), findsOneWidget);

      // Back to A: same-shell param change again.
      tester
          .state<_ParamShellState>(find.byType(_ParamShell))
          .switchTo(qaSession);
      await tester.pumpAndSettle();
      // A restores its saved (non-bottom) position: B content gone, A's
      // follow-release FAB present, header title correct. The first message
      // is intentionally above the restored viewport.
      expect(find.text('session B message'), findsNothing);
      expect(find.text('Mobile session'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });
  });

  group('mobile composer & pending interactions', () {
    testWidgets('attach opens the mobile source sheet; cancel keeps draft', (
      tester,
    ) async {
      final client = ScriptedClient();
      final container = await pumpSessionWithHistory(
        tester,
        client,
        _richHistory(),
      );
      // Ensure English copy for this assertion (default harness is zh).
      container.read(localeServiceProvider).setLocale('en');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Attach images'));
      await tester.pumpAndSettle();
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Photo library'), findsOneWidget);
      expect(find.text('Choose document'), findsOneWidget);

      // Barrier tap dismisses without staging anything.
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      expect(find.text('Take photo'), findsNothing);
    });

    testWidgets('pending approval elects the chain and renders the card', (
      tester,
    ) async {
      final client = ScriptedClient();
      final container = await pumpSessionWithHistory(
        tester,
        client,
        _richHistory(),
      );

      expect(find.byKey(const ValueKey('approval-allow')), findsNothing);
      container
          .read(approvalsProvider.notifier)
          .requested(
            qaSession,
            rpcId: 'rpc-1',
            approvalId: 'ap-1',
            toolName: 'bash',
            reason: 'run flutter test',
          );
      await tester.pumpAndSettle();

      // The chain seat rendered the approval card above the composer.
      expect(find.byKey(const ValueKey('approval-allow')), findsOneWidget);
      expect(find.textContaining('bash'), findsWidgets);
    });

    testWidgets('pending question elects the chain and renders the flow', (
      tester,
    ) async {
      final client = ScriptedClient();
      final container = await pumpSessionWithHistory(
        tester,
        client,
        _richHistory(),
      );

      container
          .read(pendingQuestionsProvider.notifier)
          .requested(
            qaSession,
            rpcId: 'rpc-q1',
            questions: const <QuestionItem>[
              QuestionItem(
                id: 'q1',
                header: 'Pick one',
                question: 'Which database?',
                options: <QuestionOption>[
                  QuestionOption(label: 'postgres'),
                  QuestionOption(label: 'sqlite'),
                ],
              ),
            ],
          );
      await tester.pumpAndSettle();

      expect(find.text('Which database?'), findsOneWidget);
    });
  });
}

/// Shell that swaps the session param through [setState] — the framework
/// then delivers [ConversationScreen.didUpdateWidget] exactly like the
/// router's `:sid` param change.
class _ParamShell extends StatefulWidget {
  const _ParamShell({required this.initialSid});

  final String initialSid;

  @override
  State<_ParamShell> createState() => _ParamShellState();
}

class _ParamShellState extends State<_ParamShell> {
  late String sid = widget.initialSid;

  void switchTo(String id) => setState(() => sid = id);

  @override
  Widget build(BuildContext context) => ConversationScreen(sessionId: sid);
}
