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

  test(
    'token total sums the four durable buckets; absent is unavailable, not zero',
    () {
      expect(subagentTokenTotal(null), isNull);
      expect(subagentTokenTotal(const <String, dynamic>{}), isNull);
      // A missing bucket is malformed, not zero.
      expect(
        subagentTokenTotal(const {
          'uncachedInputTokens': 1,
          'outputTokens': 2,
          'cacheReadTokens': 3,
        }),
        isNull,
      );
      expect(
        subagentTokenTotal(const {
          'uncachedInputTokens': 1000,
          'outputTokens': 500,
          'cacheReadTokens': 10,
          'cacheWriteTokens': 5,
        }),
        1515,
      );
      // Negative or non-numeric buckets never fabricate a total.
      expect(
        subagentTokenTotal(const {
          'uncachedInputTokens': -1,
          'outputTokens': 0,
          'cacheReadTokens': 0,
          'cacheWriteTokens': 0,
        }),
        isNull,
      );
      expect(
        subagentTokenTotal(const {
          'uncachedInputTokens': '1',
          'outputTokens': 0,
          'cacheReadTokens': 0,
          'cacheWriteTokens': 0,
        }),
        isNull,
      );
    },
  );

  test('active duration closes the open interval at now while running', () {
    // Settled-only row: no open interval to close.
    expect(
      subagentActiveDurationMs(
        settledMs: 2000,
        activeSince: null,
        activeThrough: null,
        running: false,
        nowMs: 9999,
      ),
      2000,
    );
    // Running: settled + (now - since).
    expect(
      subagentActiveDurationMs(
        settledMs: 1000,
        activeSince: 5000,
        activeThrough: 6000,
        running: true,
        nowMs: 8000,
      ),
      4000,
    );
    // Stopped: settled + (through - since), independent of now.
    expect(
      subagentActiveDurationMs(
        settledMs: 1000,
        activeSince: 5000,
        activeThrough: 6000,
        running: false,
        nowMs: 80000,
      ),
      2000,
    );
    // No timing row: unavailable, never zero.
    expect(
      subagentActiveDurationMs(
        settledMs: null,
        activeSince: null,
        activeThrough: null,
        running: false,
        nowMs: 8000,
      ),
      isNull,
    );
    // A half-present interval folds to unavailable at the reader.
    final half = readSubagentTiming(const {
      'settledMs': 1000,
      'active': {'since': 5000},
    });
    expect(half.settledMs, isNull);
  });

  test('token formatting compacts at K/M like the stats strip', () {
    expect(formatSubagentTokens(999), '999');
    expect(formatSubagentTokens(1500), '1.5K');
    expect(formatSubagentTokens(100000), '100K');
    expect(formatSubagentTokens(2500000), '2.5M');
  });

  test('duration formatting decreases precision at larger scales', () {
    expect(formatSubagentDuration(4000), '4s');
    expect(formatSubagentDuration(90000), '1m 30s');
    expect(formatSubagentDuration(3723000), '1h 02m 03s');
    expect(formatSubagentDuration(90000000), '1d 1h');
  });

  test('metrics label joins tokens and duration; unavailable omits', () {
    const bare = SubagentView(
      id: 'c',
      parentSessionId: 'p',
      label: 'l',
      running: false,
      updatedAt: 0,
    );
    expect(subagentMetricsLabel(bare, nowMs: 0), isNull);

    const timed = SubagentView(
      id: 'c',
      parentSessionId: 'p',
      label: 'l',
      running: false,
      updatedAt: 0,
      tokenTotal: 1515,
      timingSettledMs: 4000,
    );
    expect(subagentMetricsLabel(timed, nowMs: 99999), '1.5K tok · 4s');
  });

  test('provider derives metrics from projection rows present on disk', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const parent = SessionId('sess-parent');
    const child = SessionId('sess-child');
    container.read(sessionsProvider.notifier).addSession(_summary(parent));
    container.read(sessionsProvider.notifier).addSession(
      SessionSummary(
        sessionId: child,
        updatedAt: 1000,
        running: false,
        blank: false,
        parentSessionId: parent,
        origin: 'subagent',
        projections: const SessionProjectionsBlock(
          asOfSeq: 3,
          values: {
            'tokenUsage': {
              'uncachedInputTokens': 100,
              'outputTokens': 50,
              'cacheReadTokens': 10,
              'cacheWriteTokens': 5,
            },
            'subagentTiming': {'settledMs': 2000},
          },
        ),
      ),
    );

    final views = container.read(subagentsFamilyProvider('sess-parent'));
    expect(views, hasLength(1));
    expect(views.single.tokenTotal, 165);
    expect(views.single.timingSettledMs, 2000);
    expect(subagentMetricsLabel(views.single, nowMs: 9999), '165 tok · 2s');
  });

  testWidgets('header catalog menu shows projection metrics only when present', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const parent = SessionId('sess-parent');
    const child = SessionId('sess-child');
    const plain = SessionId('sess-plain');
    SessionSummary metered(SessionId id) => SessionSummary(
      sessionId: id,
      updatedAt: 1000,
      running: false,
      blank: false,
      title: 'Metered child',
      parentSessionId: parent,
      origin: 'subagent',
      projections: const SessionProjectionsBlock(
        asOfSeq: 3,
        values: {
          'tokenUsage': {
            'uncachedInputTokens': 1000,
            'outputTokens': 500,
            'cacheReadTokens': 0,
            'cacheWriteTokens': 0,
          },
          'subagentTiming': {'settledMs': 4000},
        },
      ),
    );
    container.read(sessionsProvider.notifier).addSession(_summary(parent));
    container.read(sessionsProvider.notifier).addSession(metered(child));
    container
        .read(sessionsProvider.notifier)
        .addSession(_summary(plain, parent: parent));
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

    await tester.tap(find.text('2 subagents'));
    await tester.pumpAndSettle();

    // The metered row carries its on-disk metrics; the row without host
    // rows renders no fabricated `0 tok` line.
    expect(find.text('1.5K tok · 4s'), findsOneWidget);
    expect(find.textContaining('tok'), findsOneWidget);
  });

  testWidgets('screen tiles show projection metrics only when present', (
    tester,
  ) async {
    const parent = SessionId('sess-parent');
    const childA = SessionId('sess-a');
    const childB = SessionId('sess-b');
    final state = SessionsState(
      byId: {
        parent: const SessionSummary(
          sessionId: parent,
          updatedAt: 900,
          running: false,
          blank: false,
        ),
        childA: const SessionSummary(
          sessionId: childA,
          updatedAt: 1100,
          running: false,
          blank: false,
          title: 'Metered task',
          parentSessionId: parent,
          origin: 'subagent',
          projections: SessionProjectionsBlock(
            asOfSeq: 3,
            values: {
              'tokenUsage': {
                'uncachedInputTokens': 2000000,
                'outputTokens': 500000,
                'cacheReadTokens': 0,
                'cacheWriteTokens': 0,
              },
              'subagentTiming': {'settledMs': 90000},
            },
          ),
        ),
        childB: const SessionSummary(
          sessionId: childB,
          updatedAt: 1200,
          running: false,
          blank: false,
          title: 'Unmetered task',
          parentSessionId: parent,
          origin: 'subagent',
        ),
      },
    );

    await tester.pumpWidget(
      _screenApp(const SubagentScreen(sessionId: 'sess-parent'), state: state),
    );
    await tester.pumpAndSettle();

    expect(find.text('2.5M tok · 1m 30s'), findsOneWidget);
    // Exactly one metrics line: the unmetered tile omits it, never zeroes it.
    expect(find.textContaining('tok'), findsOneWidget);
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
