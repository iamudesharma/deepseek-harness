import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart';
import 'package:dsh_flutter/src/plugins/skill/locales.dart';
import 'package:dsh_flutter/src/plugins/skill/skill_catalog.dart';
import 'package:dsh_flutter/src/plugins/skill/skill_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

/// Fake typed client: records skill.list calls, optionally failing per key.
class _FakeSkillClient extends ConnectionClient {
  _FakeSkillClient({Set<String>? failFor})
    : _failFor = Set.of(failFor ?? const <String>{}),
      super(baseUrl: '');

  final Set<String> _failFor;
  final List<String> calls = <String>[];

  @override
  Future<Map<String, dynamic>> skillList({required String sessionId}) async {
    calls.add(sessionId);
    if (_failFor.contains(sessionId)) {
      throw Exception('skill.list failed for $sessionId');
    }
    return {
      'skills': [
        {
          'name': 'review',
          'description': 'Review code',
          'modelInvocable': true,
        },
        {
          'name': 'refactor',
          'description': 'Refactor code',
          'modelInvocable': false,
        },
      ],
    };
  }
}

void main() {
  test(
    'activation provides the skills service, dictionaries, and keyed tool row',
    () async {
      final host = wsAgentHost();
      addTearDown(host.deactivateAll);
      final controller = host.service<ConversationController>('conversation')!;

      host.register(const SkillPlugin());
      await host.activateAll();

      final locale = host.service<LocaleService>('locale')!;
      expect(locale.bind(kSkillNamespace)('row.instructions'), '说明');
      locale.setLocale('en');
      expect(locale.bind(kSkillNamespace)('row.instructions'), 'Instructions');

      expect(host.service<SkillCatalog>(kSkillsServiceName), isNotNull);
      expect(controller.renderers.resolve(kSkillNodeKey), isNotNull);
    },
  );

  test(
    'catalog: one session costs one RPC across concurrent candidate reads',
    () async {
      final client = _FakeSkillClient();
      final catalog = SkillCatalog(connection: client);
      const key = SessionId('s-1');

      final results = await Future.wait([
        catalog.candidates(key, query: 're'),
        catalog.candidates(key, query: ''),
      ]);

      expect(client.calls, ['s-1']);
      expect(results.first.map((e) => e.name).toList(), ['review', 'refactor']);
      expect(results.last, hasLength(2));
    },
  );

  test('catalog: candidates filter by query prefix', () async {
    final catalog = SkillCatalog(connection: _FakeSkillClient());

    final matches = await catalog.candidates(
      const SessionId('s'),
      query: 'ref',
    );

    expect(matches.map((e) => e.name), ['refactor']);
  });

  test('catalog: distinct sessions fetch independently', () async {
    final client = _FakeSkillClient();
    final catalog = SkillCatalog(connection: client);

    await catalog.candidates(const SessionId('a'));
    await catalog.candidates(const SessionId('b'));

    expect(client.calls, ['a', 'b']);
  });

  test(
    'catalog: a failed fetch does not poison the key — next read retries',
    () async {
      final client = _FakeSkillClient(failFor: {'bad'});
      final catalog = SkillCatalog(connection: client);
      const key = SessionId('bad');

      await expectLater(catalog.candidates(key), throwsA(isA<Exception>()));
      expect(catalog.lexicon(key), isNull);

      client._failFor.remove(key);
      await catalog.candidates(key);

      expect(client.calls.where((c) => c == 'bad'), hasLength(2));
      expect(catalog.lexicon(key), ['review', 'refactor']);
    },
  );

  test('lexicon listeners fire on settlement and invalidation', () async {
    final catalog = SkillCatalog(connection: _FakeSkillClient());
    const key = SessionId('s-9');

    var notifications = 0;
    final stop = catalog.subscribeLexicon(key, () => notifications++);

    await catalog.candidates(key);
    expect(notifications, 1);

    catalog.invalidate(key);
    expect(notifications, 2);
    expect(catalog.lexicon(key), isNull);

    stop();
    catalog.invalidate(key);
    expect(notifications, 2); // unsubscribed — no further delivery
  });

  test("pick lands the plain '/name ' literal", () {
    const entry = SkillEntry(name: 'review');
    expect(
      SkillCatalog(connection: _FakeSkillClient()).pickText(entry),
      '/review ',
    );
  });

  test("'/' source: candidates filter the catalog and mark user-only rows", () async {
    final host = wsAgentHost(client: _FakeSkillClient());
    addTearDown(host.deactivateAll);
    host.register(const SkillPlugin());
    await host.activateAll();

    final inputTriggers = host.service<TriggerSourceRegistry>('inputTriggers')!;
    final source = inputTriggers
        .sources('/')
        .singleWhere((s) => s.name == kSkillSourceName);

    final candidates = await source.candidates(
      'sess-1',
      const CandidateRequest(query: 'ref', position: TriggerPosition.leading),
    );
    expect(candidates.map((c) => c.name), ['refactor']);
    // The user-only marker rides the menu description (React `menu.userOnly`).
    expect(candidates.single.description, 'user-only · Refactor code');

    // The pick lands the plain-text reference literal.
    final outcome = source.onPick(
      InputTriggerPick(
        candidate: candidates.single,
        sessionId: 'sess-1',
        position: TriggerPosition.leading,
        via: 'menu',
        span: const TokenSpan(start: 0, end: 1, draftRev: 0),
      ),
    );
    expect(outcome, isA<TextOutcome>());
    expect((outcome as TextOutcome).text, '/refactor ');
  });

  test(
    "'/' source: lexicon reads and subscriptions ride the catalog",
    () async {
      final client = _FakeSkillClient();
      final host = wsAgentHost(client: client);
      addTearDown(host.deactivateAll);
      host.register(const SkillPlugin());
      await host.activateAll();

      final inputTriggers = host.service<TriggerSourceRegistry>(
        'inputTriggers',
      )!;
      final source = inputTriggers
          .sources('/')
          .singleWhere((s) => s.name == kSkillSourceName);

      // Not warm yet — the synchronous roll reports null rather than a stale list.
      expect(source.lexicon('sess-lex'), isNull);

      var notifications = 0;
      final stop = source.subscribeLexicon('sess-lex', () => notifications++);
      source.warm('sess-lex');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(source.lexicon('sess-lex'), ['review', 'refactor']);
      stop?.call();

      // Deactivation removes the source from the registry.
      host.deactivate('ui-skill');
      expect(
        inputTriggers.sources('/').where((s) => s.name == kSkillSourceName),
        isEmpty,
      );
    },
  );

  test('user-only marker rides the menu description', () {
    const userOnly = SkillEntry(
      name: 'refactor',
      description: 'Refactor code',
      modelInvocable: false,
    );
    const modelFacing = SkillEntry(
      name: 'review',
      description: 'Review code',
      modelInvocable: true,
    );
    expect(userOnly.menuDescription, 'user-only · Refactor code');
    expect(modelFacing.menuDescription, 'Review code');
  });

  test("agent-preset/selected remote event invalidates that session's cached catalog", () async {
    final client = _FakeSkillClient();
    final host = wsAgentHost(client: client);
    addTearDown(host.deactivateAll);
    host.register(const SkillPlugin());
    await host.activateAll();

    final catalog = host.service<SkillCatalog>(kSkillsServiceName)!;
    await catalog.candidates(const SessionId('sess-1'));
    expect(client.calls, ['sess-1']);

    // Same key stays cached…
    await catalog.candidates(const SessionId('sess-1'));
    expect(client.calls, ['sess-1']);

    // …until the preset switch for that session drops exactly it.
    host.service<RemoteEventBus>('remote')!.dispatch('agent-preset/selected', [
      'sess-1',
      'preset-x',
    ]);
    await catalog.candidates(const SessionId('sess-1'));
    expect(client.calls, ['sess-1', 'sess-1']);

    // Other keys were untouched by the same event.
    await catalog.candidates(const SessionId('other'));
    expect(client.calls, ['sess-1', 'sess-1', 'other']);
  });

  test(
    'deactivation clears the cache and detaches the remote listener',
    () async {
      final client = _FakeSkillClient();
      final host = wsAgentHost(client: client);
      host.register(const SkillPlugin());
      await host.activateAll();
      final catalog = host.service<SkillCatalog>(kSkillsServiceName)!;

      await catalog.candidates(const SessionId('sess-2'));
      host.deactivateAll();

      // The plugin-owned unsubscriber ran clearAll: a fresh activation (new
      // catalog instance) proves nothing stale leaked through the bus either.
      expect(catalog.lexicon(const SessionId('sess-2')), isNull);
      final clientCallsBefore = client.calls.length;

      final host2 = wsAgentHost(client: client);
      addTearDown(host2.deactivateAll);
      host2.register(const SkillPlugin());
      await host2.activateAll();
      final fresh = host2.service<SkillCatalog>(kSkillsServiceName)!;
      await fresh.candidates(const SessionId('sess-3'));

      expect(client.calls.length, clientCallsBefore + 1);
    },
  );
}
