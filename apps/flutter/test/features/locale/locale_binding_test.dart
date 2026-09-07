/// Locale switching end-to-end at the app seam: MaterialApp's `locale:`
/// binding and the bound-dictionary consumers both flip on one
/// [LanguageRowController.setLocale] call without a restart.
///
/// React contract under test (`packages/client/locale/src/client/index.ts`):
/// Language row → `setLocale` publishes the snapshot → all subscribed
/// renderers rebuild. Boot adoption of the persisted preference is covered in
/// `locale_bootstrap_test.dart`.
library;

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show localeServiceProvider, materialLocaleProvider, localeRevisionProvider;
import 'package:dsh_flutter/src/features/locale/locale_preference.dart';
import 'package:dsh_flutter/src/features/settings_general/widgets/language_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection fake recording Typert calls (same shape as the fake in
/// `test/features/settings_general/language_row_test.dart`).
class _FakeClient extends ConnectionClient {
  _FakeClient() : super(baseUrl: '');

  Map<String, Object?> describeAnswer = const <String, dynamic>{};
  Object? mutateError;

  @override
  Future<Map<String, dynamic>> settingsDescribe() async => describeAnswer;

  @override
  Future<Map<String, dynamic>> settingsMutate({
    required String ns,
    required List<Map<String, dynamic>> ops,
    int? expectedRevision,
  }) async {
    if (mutateError != null) throw mutateError!;
    return const <String, dynamic>{};
  }
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

const Map<String, Map<String, String>> _probeDicts = {
  'zh': {'greeting': '你好'},
  'en': {'greeting': 'Hello'},
};

/// A bound-dictionary consumer: revision watch + live bind read, the same
/// channel the directory-browser flow uses for its injected translate.
class _BoundProbe extends ConsumerWidget {
  const _BoundProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeRevisionProvider);
    final t = ref.read(localeServiceProvider).bind('probe');
    return Column(
      children: [
        Text(t('greeting'), key: const Key('bound')),
        Builder(
          builder: (BuildContext context) => Text(
            Localizations.localeOf(context).languageCode,
            key: const Key('localeOf'),
          ),
        ),
      ],
    );
  }
}

/// The production MaterialApp seam under test: `locale:` fed from
/// [materialLocaleProvider], exactly as `_buildRoot` wires it.
class _AppShell extends ConsumerWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    locale: ref.watch(materialLocaleProvider),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: Scaffold(body: const _BoundProbe()),
  );
}

String _boundText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('bound'))).data!;

String _localeOfText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('localeOf'))).data!;

void main() {
  group('materialLocaleProvider', () {
    test('maps the active id onto Flutter locales and follows switches', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(materialLocaleProvider), const Locale('zh'));
      container.read(localeServiceProvider).setLocale('en');
      expect(container.read(materialLocaleProvider), const Locale('en'));
    });
  });

  group('app-shell locale switching', () {
    testWidgets('one setLocale flips BOTH the bound string and '
        'Localizations.localeOf consumers without a restart', (tester) async {
      final client = _FakeClient();
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      container.read(localeServiceProvider).register('probe', _probeDicts);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _AppShell(),
        ),
      );
      await tester.pumpAndSettle();

      // Service default drives the whole shell before any preference lands.
      expect(_boundText(tester), '你好');
      expect(_localeOfText(tester), 'zh');

      final err = await container
          .read(languageRowProvider.notifier)
          .setLocale('en');
      await tester.pumpAndSettle();

      expect(err, isNull);
      expect(_boundText(tester), 'Hello');
      expect(_localeOfText(tester), 'en');
      expect(container.read(materialLocaleProvider), const Locale('en'));
    });

    testWidgets('a failed durable write republishes the previous language', (
      tester,
    ) async {
      final client = _FakeClient()..mutateError = StateError('conflict');
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      container.read(localeServiceProvider).register('probe', _probeDicts);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _AppShell(),
        ),
      );
      await tester.pumpAndSettle();

      final err = await container
          .read(languageRowProvider.notifier)
          .setLocale('en');
      await tester.pumpAndSettle();

      expect(err, isNotNull);
      expect(_boundText(tester), '你好');
      expect(_localeOfText(tester), 'zh');
      expect(container.read(languageRowProvider).error, isNotNull);
    });
  });

  group('restart simulation', () {
    test(
      'boot adoption applies the persisted preference to a fresh service',
      () async {
        final client = _FakeClient()
          ..describeAnswer = _describeAnswer(preference: 'en', revision: 3);
        final container = ProviderContainer(
          overrides: [connectionClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);

        final service = container.read(localeServiceProvider);
        service.register('probe', _probeDicts);
        expect(service.locale, 'zh');

        await adoptPersistedLocale(client, service);

        expect(service.locale, 'en');
        expect(service.bind('probe')('greeting'), 'Hello');
      },
    );
  });
}
