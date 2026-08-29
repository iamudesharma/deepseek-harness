import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:dsh_flutter/src/plugins/subagent/locales.dart';
import 'package:dsh_flutter/src/plugins/subagent/subagent_link.dart';
import 'package:dsh_flutter/src/plugins/subagent/subagent_plugin.dart';
import 'package:dsh_flutter/src/plugins/subagent/ui/subagent_catalog_action.dart';
import 'package:dsh_flutter/src/plugins/subagent/ui/subagent_provider.dart';
import 'package:dsh_flutter/src/plugins/subagent/ui/subagent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

void main() {
  test('activation provides the subagents link service', () async {
    final host = wsAgentHost();
    addTearDown(host.deactivateAll);

    final opened = <SessionId>[];
    final link = SubagentLink(
      selectSession: opened.add,
      refreshParent: (_) async {},
    );
    host.register(SubagentPlugin(link: link));

    await host.activateAll();

    expect(host.service<SubagentLink>('subagents'), same(link));
  });

  test('header catalog action installs once the hole is declared and leaves on deactivation', () async {
    final host = wsAgentHost();
    addTearDown(host.deactivateAll);

    declareHeaderActionsHole(host);
    host.register(
      SubagentPlugin(
        link: SubagentLink(selectSession: (_) {}, refreshParent: (_) async {}),
      ),
    );

    await host.activateAll();

    final winners = host.slots.winnersOfSlot(
      'conversation.session.header.actions',
    );
    expect(winners, hasLength(1));
    expect(winners.single.options.id, kSubagentCatalogId);
    expect(winners.single.options.order, 10);

    host.deactivate(kSubagentPluginId);
    expect(
      host.slots.winnersOfSlot('conversation.session.header.actions'),
      isEmpty,
    );
  });

  test('activation registers the chat-node keyed renderer', () async {
    final host = wsAgentHost();
    addTearDown(host.deactivateAll);

    final controller = host.service<ConversationController>('conversation')!;
    host.register(
      SubagentPlugin(
        link: SubagentLink(selectSession: (_) {}, refreshParent: (_) async {}),
      ),
    );

    await host.activateAll();

    expect(controller.renderers.resolve(kSubagentNodeKey), isNotNull);
    expect(controller.renderers.resolve('tool'), isNull);
  });

  test('dictionaries register under the subagent namespace and leave with the plugin', () async {
    final host = wsAgentHost();
    addTearDown(host.deactivateAll);

    final locale = host.service<LocaleService>('locale')!;
    host.register(
      SubagentPlugin(
        link: SubagentLink(selectSession: (_) {}, refreshParent: (_) async {}),
      ),
    );
    await host.activateAll();

    expect(locale.bind(kSubagentNamespace)('tree.aria'), '子代理会话');
    locale.setLocale('en');
    expect(locale.bind(kSubagentNamespace)('tree.aria'), 'Subagent sessions');
    // zh is the key-set source of truth; en mirrors every key.
    expect(kSubagentEn.keys.toSet(), kSubagentZh.keys.toSet());

    host.deactivate(kSubagentPluginId);
    // Fallback ladder ends at the key itself once dictionaries are gone.
    expect(locale.bind(kSubagentNamespace)('tree.aria'), 'tree.aria');
  });

  test(
    'runtime link: openChild selects the child row in the shared sessions list',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const parent = SessionId('sess-parent');
      const child = SessionId('sess-child');
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary(parent));
      notifier.addSession(_summary(child, parent: parent));

      final refreshed = <SessionId>[];
      final link = SubagentLink(
        selectSession: (id) =>
            container.read(sessionsProvider.notifier).setCurrent(id),
        refreshParent: (parent) async => refreshed.add(parent),
      );

      expect(container.read(sessionsProvider).current, isNull);
      await link.refresh(parent);
      expect(refreshed, [parent]);

      link.openChild(
        SubagentAddress(parentSessionId: parent, childSessionId: child),
      );
      expect(container.read(sessionsProvider).current, child);
    },
  );

  test(
    'runtime link: unknown child ids are ignored by the controller guard',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const parent = SessionId('sess-parent');
      container.read(sessionsProvider.notifier).addSession(_summary(parent));

      final link = SubagentLink(
        selectSession: (id) =>
            container.read(sessionsProvider.notifier).setCurrent(id),
        refreshParent: (_) async {},
      );
      link.openChild(
        SubagentAddress(
          parentSessionId: parent,
          childSessionId: const SessionId('ghost'),
        ),
      );

      expect(container.read(sessionsProvider).current, isNull);
    },
  );

  test('runtime link: opening a child closes the originating catalog', () {
    const parent = SessionId('p');
    const child = SessionId('c');
    final link = SubagentLink(
      selectSession: (_) {},
      refreshParent: (_) async {},
    );

    link.setCatalogOpen(parent, true);
    expect(link.isCatalogOpen(parent), isTrue);

    link.openChild(
      SubagentAddress(parentSessionId: parent, childSessionId: child),
    );
    expect(link.isCatalogOpen(parent), isFalse);
  });

  testWidgets(
    'header catalog action: picking a child navigates through the link',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const parent = SessionId('sess-parent');
      const child = SessionId('sess-child');
      container.read(sessionsProvider.notifier).addSession(_summary(parent));
      container
          .read(sessionsProvider.notifier)
          .addSession(_summary(child, parent: parent));
      container.read(sessionsProvider.notifier).setCurrent(parent);

      final link = SubagentLink(
        selectSession: (id) =>
            container.read(sessionsProvider.notifier).setCurrent(id),
        refreshParent: (_) async {},
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: SubagentCatalogAction(link: link)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger shows the summary-derived count; untitled children fall back
      // to their session id as the row label.
      await tester.tap(find.text('1 subagent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sess-child'));
      await tester.pumpAndSettle();

      expect(container.read(sessionsProvider).current, child);
    },
  );

  testWidgets('header catalog action hides without evidence of children', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const parent = SessionId('sess-solo');
    container.read(sessionsProvider.notifier).addSession(_summary(parent));
    container.read(sessionsProvider.notifier).setCurrent(parent);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SubagentCatalogAction(
              link: SubagentLink(
                selectSession: (_) {},
                refreshParent: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // React visibility rule: a childless session never shows the trigger.
    expect(find.byTooltip('Subagent sessions'), findsNothing);
  });

  testWidgets('screen lists summary-derived children and never fixtures', (
    tester,
  ) async {
    const parent = SessionId('sess-parent');
    const childA = SessionId('sess-a');
    const childB = SessionId('sess-b');
    SessionSummary childSummary(
      SessionId id,
      bool running,
      String title,
      int updated,
    ) => SessionSummary(
      sessionId: id,
      updatedAt: updated,
      running: running,
      blank: false,
      title: title,
      parentSessionId: parent,
      origin: 'subagent',
    );
    final state = SessionsState(
      byId: {
        parent: const SessionSummary(
          sessionId: parent,
          updatedAt: 900,
          running: false,
          blank: false,
        ),
        childA: childSummary(childA, true, 'Research task', 1100),
        childB: childSummary(childB, false, 'Fix lint', 1200),
      },
    );

    await tester.pumpWidget(
      _screenApp(const SubagentScreen(sessionId: 'sess-parent'), state: state),
    );
    await tester.pumpAndSettle();

    // Real summary-derived rows render with host titles and live states.
    expect(find.text('Research task'), findsOneWidget);
    expect(find.text('Fix lint'), findsOneWidget);
    expect(find.text('2 subagents'), findsOneWidget);
    expect(find.text('1 running'), findsOneWidget);

    // Opening a child swaps to the transcript view.
    await tester.tap(find.text('Research task'));
    await tester.pumpAndSettle();
    expect(find.text('Explore'), findsOneWidget);
  });

  testWidgets('screen shows the empty state for a session without subagents', (
    tester,
  ) async {
    const parent = SessionId('sess-solo');
    await tester.pumpWidget(
      _screenApp(
        const SubagentScreen(sessionId: 'sess-solo'),
        state: SessionsState(
          byId: {
            parent: const SessionSummary(
              sessionId: parent,
              updatedAt: 900,
              running: false,
              blank: false,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No subagents'), findsOneWidget);
  });

  test('transcript fold maps user/assistant/tool events in seq order', () {
    final entries = [
      HistoryEntry(
        event: const SessionEvent(
          type: 'user/message',
          data: {'content': 'hello'},
          seq: 1,
          time: 1000,
        ),
      ),
      HistoryEntry(
        event: const SessionEvent(
          type: 'tool/call',
          data: {'name': 'read'},
          seq: 2,
          time: 1100,
        ),
      ),
      HistoryEntry(
        event: const SessionEvent(
          type: 'assistant/message',
          data: {
            'content': [
              {'type': 'text', 'text': 'done'},
            ],
          },
          seq: 3,
          time: 1200,
        ),
      ),
      HistoryEntry(
        event: const SessionEvent(
          type: 'turn/start',
          data: {},
          seq: 4,
          time: 1300,
        ),
      ),
    ];

    final rows = transcriptFromHistory(entries);

    expect(rows.map((r) => r.role), ['user', 'tool', 'assistant']);
    expect(rows.map((r) => r.content), ['hello', 'read', 'done']);
    expect(rows.map((r) => r.id), ['1', '2', '3']);
  });
}

/// Sessions controller seeded at build so the screen reads a stable snapshot
/// (ProviderScope-override pattern from the agent-preset screen tests).
class _SeededSessions extends SessionsController {
  _SeededSessions(this._state);
  final SessionsState _state;

  @override
  SessionsState build() => _state;
}

/// Screen harness: seeded sessions plus the transcript face stubbed at the
/// provider seam (its fold rules are covered directly above).
Widget _screenApp(Widget child, {required SessionsState state}) =>
    ProviderScope(
      overrides: [
        sessionsProvider.overrideWith(() => _SeededSessions(state)),
        subagentTranscriptProvider.overrideWith(
          (ref, id) => Future.value(const [
            SubagentTranscriptEntry(
              id: '1',
              role: 'user',
              content: 'Explore',
              time: 1000,
            ),
          ]),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

SessionSummary _summary(SessionId id, {SessionId? parent}) => SessionSummary(
  sessionId: id,
  updatedAt: 1000,
  running: false,
  blank: true,
  parentSessionId: parent,
  origin: parent != null ? 'subagent' : null,
);
