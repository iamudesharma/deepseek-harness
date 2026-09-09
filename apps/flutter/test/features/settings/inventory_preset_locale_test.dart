import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show LocaleService, localeServiceProvider;
import 'package:dsh_flutter/src/features/settings/inventory_tab.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/locales.dart'
    show kAgentPresetNamespace, kAgentPresetZh, kAgentPresetEn;
import 'package:dsh_flutter/src/plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart'
    show kInventoryNamespace, kInventoryZh, kInventoryEn;
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection fake answering `pluginInventory.list` with one shipped system
/// preset (host metadata name in Chinese, as the real `preset.yml` ships)
/// plus one user preset.
class _FakeInventoryClient extends ConnectionClient {
  _FakeInventoryClient() : super(baseUrl: '');

  @override
  Future<Map<String, dynamic>> pluginInventoryList() async {
    return <String, dynamic>{
      'entries': const [],
      'agentPresets': const [
        {
          'id': 'standard',
          'trust': 'system',
          'name': '标准模式',
          'isDefault': true,
          'rows': [],
        },
        {
          'id': 'mine',
          'trust': 'user',
          'name': '我的预设',
          'isDefault': false,
          'rows': [],
        },
      ],
    };
  }
}

Future<void> _pumpInventory(
  WidgetTester tester, {
  String localeId = 'en',
}) async {
  final container = ProviderContainer(
    overrides: [
      connectionClientProvider.overrideWithValue(_FakeInventoryClient()),
    ],
  );
  addTearDown(container.dispose);
  final LocaleService locale = container.read(localeServiceProvider);
  locale.register(kInventoryNamespace, {
    'zh': kInventoryZh,
    'en': kInventoryEn,
  });
  locale.register(kAgentPresetNamespace, {
    'zh': kAgentPresetZh,
    'en': kAgentPresetEn,
  });
  locale.setLocale(localeId);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          extensions: const [
            DswThemeExtension(aliases: DswTokens.lightAliases),
          ],
        ),
        home: const Scaffold(
          body: InventoryTab(aliases: DswTokens.lightAliases),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('system preset name follows the UI locale, user names pass through', (
    tester,
  ) async {
    await _pumpInventory(tester, localeId: 'en');

    // Shipped `standard` resolves through the agent-preset dictionary, so
    // the English UI never shows the preset.yml metadata name.
    expect(find.text('Standard mode (default)'), findsOneWidget);
    expect(find.text('标准模式 (default)'), findsNothing);
    // User-authored metadata is never translated, in either direction.
    await tester.tap(find.text('Standard mode (default)'));
    await tester.pumpAndSettle();
    expect(find.text('我的预设'), findsOneWidget);
  });

  testWidgets('Chinese UI shows the shipped metadata name with local suffix', (
    tester,
  ) async {
    await _pumpInventory(tester, localeId: 'zh');

    expect(find.text('标准模式（默认）'), findsOneWidget);
    expect(find.text('Standard mode（默认）'), findsNothing);
  });
}
