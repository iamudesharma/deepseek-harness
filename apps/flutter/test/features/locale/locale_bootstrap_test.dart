/// Bootstrap adoption wiring: `CoreServicesPlugin` provides the shared
/// [LocaleService] from `localeServiceProvider` and applies the persisted
/// `locale` preference to it at activation — the reload half of the React
/// locale contract (`packages/client/locale/src/client/index.ts` constructor
/// scope adoption).
library;

import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart'
    show CoreServicesPlugin, ShellServices;
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show localeServiceProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection fake answering settings.describe from a canned document.
class _FakeClient extends ConnectionClient {
  _FakeClient() : super(baseUrl: '');

  Map<String, Object?> describeAnswer = const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> settingsDescribe() async => describeAnswer;

  @override
  Future<Map<String, dynamic>> settingsMutate({
    required String ns,
    required List<Map<String, dynamic>> ops,
    int? expectedRevision,
  }) async => const <String, dynamic>{};
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
  testWidgets('CoreServicesPlugin adopts the persisted preference into the '
      'activated locale service', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = _describeAnswer(preference: 'en', revision: 2);
    final container = ProviderContainer(
      overrides: [connectionClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final service = container.read(localeServiceProvider);
    service.register('probe', {
      'zh': {'greeting': '你好'},
      'en': {'greeting': 'Hello'},
    });

    // Capture a WidgetRef so CoreServicesPlugin boots exactly as it does
    // inside DshApp, minus the unrelated plugins.
    WidgetRef? widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) {
            widgetRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final host = PluginHost();
    // Same service seeding as buildAppHost, minus the unrelated plugins.
    host.provide('slots', host.slots);
    host.provide('connection', container.read(connectionClientProvider));
    host.register(CoreServicesPlugin(ShellServices(widgetRef!)));
    addTearDown(host.deactivateAll);
    await host.activateAll();

    // Adoption is unawaited inside apply; drive microtasks to settlement.
    for (var i = 0; i < 10 && service.locale != 'en'; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(service.locale, 'en');
    expect(service.bind('probe')('greeting'), 'Hello');
  });
}
