import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_screen.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/failure_display.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeComposerSuccessClient extends ConnectionClient {
  _FakeComposerSuccessClient() : super(baseUrl: 'http://fake');
  final List<({String sessionId, String content, String mode})> sent = [];
  @override
  Future<void> sendMessage({
    required SessionId sessionId,
    required String content,
    String mode = 'queue',
    String? clientTimeZone,
    List<Map<String, dynamic>> images = const [],
  }) async {
    sent.add((sessionId: sessionId.value, content: content, mode: mode));
  }
}

SessionSummary _fakeSummary(String id, {bool blank = false, String? title}) {
  return SessionSummary(
    sessionId: SessionId(id),
    updatedAt: DateTime.now().millisecondsSinceEpoch,
    running: false,
    blank: blank,
    title: title ?? 'Session $id',
  );
}

Widget _wrapConversation(
  String sessionId, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: ConversationScreen(sessionId: sessionId),
    ),
  );
}

void main() {
  group('ConversationScreen', () {
    testWidgets('shows session not found guard when session id unknown', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapConversation('unknown-id'));
      await tester.pumpAndSettle();
      expect(find.text('Session not found'), findsOneWidget);
      // Both AppBar title "Session unknown-id" and body "No session matches "unknown-id"" contain id
      expect(find.text('Session unknown-id'), findsOneWidget);
      expect(find.textContaining('No session matches'), findsOneWidget);
    });

    testWidgets('shows blank session guard with composer hint', (tester) async {
      // Desktop contract under test: the strict header hides while blank.
      // (The mobile shell intentionally keeps the title visible for
      // orientation — covered by the mobile shell suite.)
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final sid = 'blank-1';
      final summary = _fakeSummary(sid, blank: true);
      final container = ProviderContainer(
        overrides: [
          sessionsProvider.overrideWith(() {
            final c = SessionsController();
            // We'll seed via addSession after build; use manual seeding via container override is tricky.
            // Instead override sessionsProvider to return state with our summary directly.
            return c;
          }),
        ],
      );
      // Seed via container then pump with ProviderScope override that provides same controller state.
      // Simpler: use ProviderScope override that returns prepared SessionsState via overriding sessionsProvider with a fixed value? SessionsProvider is NotifierProvider, so we need to override with a provider that supplies state.
      // Easiest: use ProviderScope with sessionsProvider overridden via overrideWithValue is for Provider, not Notifier. For NotifierProvider we can override via overrideWith(() => controller) but we need to pre-seed.
      // We'll create a custom provider override that returns a controller pre-seeded.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith(() {
              final ctrl = SessionsController();
              // Defer seeding until build? Actually controller build runs before we can add.
              // So we schedule seeding via microtask and pump. Instead we can use a ProviderContainer to seed then override sessionsProvider with a fixed value provider via a custom implementation:
              // Workaround: override currentSessionProvider etc is not needed; we override sessionsProvider via a Notifier that seeds in build.
              return ctrl;
            }),
          ],
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Builder(
              builder: (context) {
                // Seed inside builder via ref? Instead we use UncontrolledProviderScope with container.
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      container.dispose();

      // Alternative approach: pump with UncontrolledProviderScope and a container we pre-seeded.
      final seeded = ProviderContainer();
      addTearDown(seeded.dispose);
      seeded.read(sessionsProvider.notifier).addSession(summary);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: seeded,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Blank is a hero PHASE of the same ConversationColumn shell (React
      // ConversationRoot hero): header chrome HIDES while blank
      // (ConversationSession.tsx:72-77 `hideChrome && css.headerHidden`),
      // fish headline + workspace row show, and the resident composer rides
      // inside the centered hero stack.
      expect(find.text('New session'), findsNothing);
      expect(find.text('Into the Unknown'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Ask anything…'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('renders message list empty state when no messages', (
      tester,
    ) async {
      final sid = 's-empty';
      final summary = _fakeSummary(sid, blank: false);
      final container = ProviderContainer(
        overrides: [
          // Override messageListProvider to return empty list immediately
          messageListProvider.overrideWith((ref, arg) async => <Message>[]),
        ],
      );
      container.read(sessionsProvider.notifier).addSession(summary);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );
      // Allow one build frame plus the post-frame sync into the controller.
      // pumpAndSettle hangs on AiChatWidget's internal ticker — use bounded pumps.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // AiChatWidget owns empty state now; the old MessageList _EmptyState
      // ("No messages yet", "Start the conversation below.", "Cmd+Enter…")
      // no longer renders. Check that the app bar and the input are present.
      expect(find.text('Session $sid'), findsOneWidget);
      expect(find.text('Ask anything…'), findsOneWidget);
    });

    testWidgets('folds live history into node bubbles', (tester) async {
      final sid = 's-with-msgs';
      final summary = _fakeSummary(sid, blank: false);
      final container = ProviderContainer(overrides: []);
      container.read(sessionsProvider.notifier).addSession(summary);
      container.read(liveHistoryProvider(sid).notifier).replaceAll([
        HistoryEntry(
          event: SessionEvent.fromJson({
            'type': 'user/message',
            'seq': 1,
            'time': 0,
            'data': {'content': 'Hello there'},
          }),
          view: null,
        ),
        HistoryEntry(
          event: SessionEvent.fromJson({
            'type': 'assistant/chunk',
            'seq': 2,
            'time': 0,
            'data': {
              'turn': 1,
              'step': 1,
              'chunk': {'text': 'Hi! How can I help?'},
            },
          }),
          view: null,
        ),
        HistoryEntry(
          event: SessionEvent.fromJson({
            'type': 'assistant/message',
            'seq': 3,
            'time': 0,
            'data': {'turn': 1, 'step': 1, 'message': {}},
            'sourceEventSeqs': [2],
          }),
          view: null,
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('Hi! How can I help?'), findsOneWidget);
      expect(find.text('Session $sid'), findsOneWidget);
    });

    testWidgets('composer empty input does not submit', (tester) async {
      final sid = 's-disabled';
      final summary = _fakeSummary(sid, blank: false);
      final container = ProviderContainer(
        overrides: [
          messageListProvider.overrideWith((ref, arg) async => <Message>[]),
        ],
      );
      container.read(sessionsProvider.notifier).addSession(summary);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Ask anything…'), findsOneWidget);
      expect(
        container.read(composerControllerProvider(sid)).canSubmit,
        isFalse,
      );
      expect(
        container.read(composerControllerProvider(sid)).isSending,
        isFalse,
      );
    });

    testWidgets('composer attachments controller stores staged files', (
      tester,
    ) async {
      final sid = 's-attach';
      final summary = _fakeSummary(sid, blank: false);
      final container = ProviderContainer(
        overrides: [
          messageListProvider.overrideWith((ref, arg) async => <Message>[]),
        ],
      );
      container.read(sessionsProvider.notifier).addSession(summary);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No attachments initially; stage one via controller (picker UI is package-owned and tested upstream).
      expect(
        container.read(composerControllerProvider(sid)).attachments,
        isEmpty,
      );
      container.read(composerControllerProvider(sid).notifier).addAttachments([
        const ComposerAttachment(name: 'attachment-doc.pdf'),
      ]);
      expect(
        container.read(composerControllerProvider(sid)).attachments.length,
        1,
      );
    });

    testWidgets('shows turn-error banner from folded history', (tester) async {
      final sid = 's-error';
      final summary = _fakeSummary(sid, blank: false);
      final container = ProviderContainer(overrides: []);
      container.read(sessionsProvider.notifier).addSession(summary);
      container.read(liveHistoryProvider(sid).notifier).replaceAll([
        HistoryEntry(
          event: SessionEvent.fromJson({
            'type': 'user/message',
            'seq': 1,
            'time': 0,
            'data': {'content': 'go'},
          }),
          view: null,
        ),
        HistoryEntry(
          event: SessionEvent.fromJson({
            'type': 'turn/end',
            'seq': 2,
            'time': 0,
            'data': {
              'reason': {
                'kind': 'error',
                'error': {'type': 'ModelError', 'message': 'provider exploded'},
              },
            },
          }),
          view: null,
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // TurnErrorNode projects the verbatim provider message (React parity).
      expect(find.textContaining('provider exploded'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('composer submit records via carrier client', (tester) async {
      final sid = 's-composer';
      final summary = _fakeSummary(sid, blank: false);
      final client = _FakeComposerSuccessClient();
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(client)],
      );
      container.read(sessionsProvider.notifier).addSession(summary);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );

      final ctrl = container.read(composerControllerProvider(sid).notifier);
      ctrl.setText('hello composer');
      await ctrl.submit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(client.sent, hasLength(1));
      expect(client.sent.single.content, 'hello composer');
      expect(client.sent.single.mode, 'queue');
      expect(container.read(composerControllerProvider(sid)).text, isEmpty);
    });
  });
}
