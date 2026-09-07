import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show localeServiceProvider;
import 'package:dsh_flutter/src/features/settings_general/widgets/language_row.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection fake recording Typert calls; mirrors the FakeClient in
/// `test/plugins/ws_surfaces/host_fixture.dart`.
class _FakeClient extends ConnectionClient {
  /// Creates the fake; [journal] receives each wire call in issue order so
  /// tests can interleave service publications with wire traffic.
  _FakeClient({this.journal}) : super(baseUrl: '');

  /// Shared ordering ledger (optional).
  final List<String>? journal;

  final List<String> calls = [];
  Map<String, Object?> describeAnswer = const <String, dynamic>{};
  Object? mutateError;
  String? mutatedNs;
  List<Map<String, dynamic>>? mutatedOps;
  int? mutatedExpectedRevision;

  @override
  Future<Map<String, dynamic>> settingsDescribe() async {
    calls.add('settings.describe');
    journal?.add('settings.describe');
    return describeAnswer;
  }

  @override
  Future<Map<String, dynamic>> settingsMutate({
    required String ns,
    required List<Map<String, dynamic>> ops,
    int? expectedRevision,
  }) async {
    calls.add('settings.mutate');
    journal?.add('settings.mutate');
    mutatedNs = ns;
    mutatedOps = ops;
    mutatedExpectedRevision = expectedRevision;
    if (mutateError != null) throw mutateError!;
    return const <String, dynamic>{};
  }
}

/// Client whose describe face always fails (wire-down arm).
class _FailingDescribeClient extends ConnectionClient {
  _FailingDescribeClient() : super(baseUrl: '');

  @override
  Future<Map<String, dynamic>> settingsDescribe() async =>
      throw StateError('wire down');
}

Map<String, Object?> _describeAnswer({String? preference, int revision = 2}) =>
    {
      'namespaces': [
        {
          'ns': 'locale',
          'value': {'preference': preference},
          'revision': revision,
        },
      ],
    };

void main() {
  group('LanguageRowController (createLanguageRowStore analog)', () {
    test('initial state carries the shipped en/zh options', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(languageRowProvider);
      expect(state.active, '');
      expect(state.revision, -1);
      expect(state.loading, isFalse);
      expect(state.options.map((o) => o.id), ['en', 'zh']);
      expect(state.options.map((o) => o.label), ['English', '中文']);
    });

    test('sync drops snapshots at or below the current revision', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(languageRowProvider.notifier);
      controller.sync('zh', const [
        LanguageOptionRow(id: 'zh', label: '中文'),
      ], 3);
      expect(container.read(languageRowProvider).active, 'zh');
      expect(container.read(languageRowProvider).revision, 3);

      // Stale duplicates are dropped by the revision guard.
      controller.sync('en', const [
        LanguageOptionRow(id: 'en', label: 'English'),
      ], 3);
      expect(container.read(languageRowProvider).active, 'zh');

      controller.sync('en', const [
        LanguageOptionRow(id: 'en', label: 'English'),
      ], 4);
      expect(container.read(languageRowProvider).active, 'en');
    });

    test('load reads the locale namespace off settings.describe', () async {
      final client = _FakeClient()
        ..describeAnswer = _describeAnswer(preference: 'zh', revision: 7);
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await container.read(languageRowProvider.notifier).load();

      final state = container.read(languageRowProvider);
      expect(client.calls, ['settings.describe']);
      expect(state.active, 'zh');
      expect(state.revision, 7);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
    });

    test('load records wire errors on state and clears loading', () async {
      final container = ProviderContainer(
        overrides: [
          connectionClientProvider.overrideWithValue(_FailingDescribeClient()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(languageRowProvider.notifier).load();

      final state = container.read(languageRowProvider);
      expect(state.loading, isFalse);
      expect(state.error, isNotNull);
    });

    test(
      'setLocale writes ns locale set preference with revision guard',
      () async {
        final client = _FakeClient()
          ..describeAnswer = _describeAnswer(preference: 'en', revision: 5);
        final container = ProviderContainer(
          overrides: [connectionClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);
        await container.read(languageRowProvider.notifier).load();
        client.calls.clear();

        final err = await container
            .read(languageRowProvider.notifier)
            .setLocale('zh');

        expect(err, isNull);
        // Guard describe → mutate → confirming re-sync describe.
        expect(
          client.calls,
          containsAllInOrder(['settings.describe', 'settings.mutate']),
        );
        expect(client.calls.last, 'settings.describe');
        expect(container.read(languageRowProvider).active, 'zh');
      },
    );

    test(
      'setLocale rolls back the optimistic update when mutate fails',
      () async {
        final client = _FakeClient()
          ..describeAnswer = _describeAnswer(preference: 'en', revision: 5)
          ..mutateError = StateError('conflict');
        final container = ProviderContainer(
          overrides: [connectionClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);
        await container.read(languageRowProvider.notifier).load();

        final err = await container
            .read(languageRowProvider.notifier)
            .setLocale('zh');

        expect(err, isNotNull);
        final state = container.read(languageRowProvider);
        expect(state.active, 'en');
        expect(state.revision, 5);
        expect(state.error, isNotNull);
      },
    );

    test(
      'setLocale publishes through LocaleService before persisting',
      () async {
        final journal = <String>[];
        final client = _FakeClient(journal: journal)
          ..describeAnswer = _describeAnswer(preference: 'en', revision: 5);
        final container = ProviderContainer(
          overrides: [connectionClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);

        final service = container.read(localeServiceProvider);
        service.onChanged(() => journal.add('publish:${service.locale}'));
        service.register('probe', {
          'zh': {'greeting': '你好'},
          'en': {'greeting': 'Hello'},
        });
        final controller = container.read(languageRowProvider.notifier);
        await controller.load();
        // Land on en so the switch under test moves the service for real
        // (the service boots on zh; the row's describe read alone does not).
        await controller.setLocale('en');
        journal.clear();

        final err = await controller.setLocale('zh');

        // React order: publish the snapshot change first, then the durable
        // write — persistence is a consequence, not the switch mechanism.
        expect(err, isNull);
        expect(journal.first, 'publish:zh');
        expect(journal[1], 'settings.describe');
        expect(service.locale, 'zh');
        expect(service.bind('probe')('greeting'), '你好');
        // Mutate carries ns 'locale', the preference set op, and the describe
        // revision as fence.
        expect(client.mutatedNs, 'locale');
        expect(client.mutatedOps, [
          {
            'op': 'set',
            'path': ['preference'],
            'value': 'zh',
          },
        ]);
        expect(client.mutatedExpectedRevision, 5);
      },
    );

    test('setLocale rolls back BOTH controller state and LocaleService '
        'when mutate fails', () async {
      final client = _FakeClient()
        ..describeAnswer = _describeAnswer(preference: 'en', revision: 5);
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      final service = container.read(localeServiceProvider);
      var publications = 0;
      service.onChanged(() => publications++);
      final controller = container.read(languageRowProvider.notifier);
      await controller.load();

      // Land on en first so the failing switch has a real publication to undo.
      expect(await controller.setLocale('en'), isNull);
      expect(service.locale, 'en');
      publications = 0;
      final landedRevision = container.read(languageRowProvider).revision;

      client.mutateError = StateError('conflict');
      final err = await controller.setLocale('zh');

      expect(err, isNotNull);
      // The failed switch published once and republished en once (rollback).
      expect(publications, 2);
      expect(service.locale, 'en');
      final state = container.read(languageRowProvider);
      expect(state.active, 'en');
      expect(state.revision, landedRevision);
      expect(state.error, isNotNull);
    });

    test(
      'unknown id keeps the previous locale and surfaces the ArgumentError',
      () async {
        final client = _FakeClient()
          ..describeAnswer = _describeAnswer(preference: 'en', revision: 5);
        final container = ProviderContainer(
          overrides: [connectionClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);

        final service = container.read(localeServiceProvider);
        service.register('probe', {
          'zh': {'greeting': '你好'},
          'en': {'greeting': 'Hello'},
        });
        final controller = container.read(languageRowProvider.notifier);
        await controller.load();
        // Land on en so "previous locale" is a real service state.
        await controller.setLocale('en');
        client.calls.clear();
        final landedRevision = container.read(languageRowProvider).revision;

        final err = await controller.setLocale('xx');

        // LocaleService's registered-id check fires before any wire traffic;
        // the row restores its optimistic state around it.
        expect(err, contains('locale is not registered'));
        expect(service.locale, 'en');
        expect(client.calls, isEmpty);
        final state = container.read(languageRowProvider);
        expect(state.active, 'en');
        expect(state.revision, landedRevision);
        expect(state.error, isNotNull);
      },
    );
  });

  testWidgets('LanguageRow renders title and selector placeholder', (
    tester,
  ) async {
    final client = _FakeClient()
      ..describeAnswer = _describeAnswer(preference: '', revision: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectionClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          theme: ThemeData(
            extensions: const [
              DswThemeExtension(aliases: DswTokens.lightAliases),
            ],
          ),
          home: const Scaffold(body: LanguageRow()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Title mirrors React t('language.title'); the seeded settings.locale
    // dictionary answers in the service's default locale (zh).
    expect(find.text('语言'), findsOneWidget);
    // No preference yet → DsSelect shows its placeholder (common vocabulary).
    expect(find.byType(DsSelect), findsOneWidget);
    expect(find.text('请选择'), findsOneWidget);
    expect(client.calls, contains('settings.describe'));
  });

  testWidgets('LanguageRow shows the active locale label after sync', (
    tester,
  ) async {
    final client = _FakeClient()
      ..describeAnswer = _describeAnswer(preference: 'zh', revision: 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectionClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          theme: ThemeData(
            extensions: const [
              DswThemeExtension(aliases: DswTokens.lightAliases),
            ],
          ),
          home: const Scaffold(body: LanguageRow()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The selector displays the option label for the synced id.
    expect(find.text('中文'), findsOneWidget);
  });
}
