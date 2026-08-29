import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show LocaleService, localeServiceProvider;
import 'package:dsh_flutter/src/features/settings/settings_screen.dart';
import 'package:dsh_flutter/src/plugins/conversation/locales.dart'
    show kConversationNamespace, kConversationZh, kConversationEn;
import 'package:dsh_flutter/src/plugins/settings/children/general/general_settings_plugin.dart'
    show kSettingsNamespace, kSettingsZh, kSettingsEn;
import 'package:dsh_flutter/src/plugins/settings/children/models/models_settings_plugin.dart'
    show kModelsNamespace, kModelsZh, kModelsEn;
import 'package:dsh_flutter/src/plugins/settings/children/plugins/plugins_settings_plugin.dart'
    show kPluginsNamespace, kPluginsZh, kPluginsEn;
import 'package:dsh_flutter/src/plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart'
    show kInventoryNamespace, kInventoryZh, kInventoryEn;
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection fake answering `settings.describe` from a canned document;
/// mirrors the FakeClient in `test/plugins/ws_surfaces/host_fixture.dart`.
class _FakeClient extends ConnectionClient {
  _FakeClient() : super(baseUrl: '');

  final List<String> calls = [];
  Map<String, Object?> describeAnswer = const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> settingsDescribe() async {
    calls.add('settings.describe');
    return describeAnswer;
  }

  @override
  Future<Map<String, dynamic>> settingsMutate({
    required String ns,
    required List<Map<String, dynamic>> ops,
    int? expectedRevision,
  }) async {
    calls.add('settings.mutate');
    return const <String, dynamic>{};
  }

  @override
  Future<List<Map<String, dynamic>>> llmProviders() async => const [];

  @override
  Future<Map<String, dynamic>> credentialsDescribe(List<String> refs) async =>
      const <String, dynamic>{};
}

Map<String, Object?> _settingsDocument() => {
  'namespaces': [
    {
      'ns': 'locale',
      'value': {'preference': 'en'},
      'revision': 1,
    },
    {
      'ns': 'conversation',
      'value': {'busyEnter': 'queue'},
      'revision': 1,
    },
    {'ns': 'ui-theme', 'value': <String, dynamic>{}, 'revision': 1},
  ],
};

Future<void> _pumpScreen(WidgetTester tester, _FakeClient client) async {
  final container = ProviderContainer(
    overrides: [connectionClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  // Production registers these namespaces from the settings-children
  // plugins' `apply()` (and conversation's Enter-row copy from its own
  // plugin); this harness pumps the screen directly, so mirror the
  // registrations and pin the locale to the English expectations below.
  final LocaleService locale = container.read(localeServiceProvider);
  locale.register(kSettingsNamespace, {'zh': kSettingsZh, 'en': kSettingsEn});
  locale.register(kModelsNamespace, {'zh': kModelsZh, 'en': kModelsEn});
  locale.register(kPluginsNamespace, {'zh': kPluginsZh, 'en': kPluginsEn});
  locale.register(kInventoryNamespace, {
    'zh': kInventoryZh,
    'en': kInventoryEn,
  });
  locale.register(kConversationNamespace, {
    'zh': kConversationZh,
    'en': kConversationEn,
  });
  locale.setLocale('en');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          extensions: const [
            DswThemeExtension(aliases: DswTokens.lightAliases),
          ],
        ),
        home: const SettingsScreen(),
      ),
    ),
  );
  // Post-frame loads (LanguageRow / BusyEnter) resolve against the fake.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hosts the four settings tabs', (tester) async {
    await _pumpScreen(tester, _FakeClient());

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('General'), findsWidgets);
    expect(find.text('Models'), findsWidgets);
    expect(find.text('Plugins'), findsWidgets);
    expect(find.text('Inventory'), findsWidgets);
  });

  testWidgets('General tab renders the language row over the Host document', (
    tester,
  ) async {
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    expect(client.calls, contains('settings.describe'));
    expect(find.text('Language'), findsOneWidget);
    // The synced preference label shows in the selector.
    expect(find.text('English'), findsOneWidget);
    // Enter-behavior row rides the same document (ns conversation).
    expect(find.text('Enter behavior while busy'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
  });

  testWidgets('General tab carries notifications and workspace sections', (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeClient());

    // Sections below the fold live in the tab's lazy ListView.
    await tester.dragUntilVisible(
      find.text('Enable notifications'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.text('Enable notifications'), findsOneWidget);
    expect(find.byType(Switch), findsAtLeastNWidgets(1));

    await tester.dragUntilVisible(
      find.text('Workspace directory'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.text('Workspace directory'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('DeepSeek Harness'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.text('DeepSeek Harness'), findsOneWidget);
  });

  testWidgets('Models tab shows the provider key editor', (tester) async {
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Models').first);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Enter your API keys to use models from the following providers.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Plugins tab lists the plugin toggles', (tester) async {
    await _pumpScreen(tester, _FakeClient());

    await tester.tap(find.text('Plugins').first);
    await tester.pumpAndSettle();

    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('Filesystem'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
  });

  testWidgets('Inventory tab renders the inventory table', (tester) async {
    await _pumpScreen(tester, _FakeClient());

    await tester.tap(find.text('Inventory').first);
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('ReadFile'), findsOneWidget);
    expect(find.text('Bash'), findsOneWidget);
  });
}
