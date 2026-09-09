import 'package:dsh_flutter/src/core/connection/connection_client.dart';
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
import 'package:dsh_flutter/src/plugins/agent_preset/locales.dart'
    show kAgentPresetNamespace, kAgentPresetZh, kAgentPresetEn;
import 'package:dsh_flutter/src/plugins/permission_presets/locales.dart'
    show
        kPermissionSettingsNamespace,
        kPermissionSettingsZh,
        kPermissionSettingsEn;
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection fake answering `settings.describe` from a canned document;
/// mirrors the FakeClient in `test/plugins/ws_surfaces/host_fixture.dart`.
class _FakeClient extends ConnectionClient {
  _FakeClient() : super(baseUrl: '');

  final List<String> calls = [];
  final List<Map<String, Object?>> mutates = [];
  Map<String, Object?> describeAnswer = const <String, dynamic>{};
  List<Map<String, dynamic>> inventoryEntries = const [];
  List<Map<String, dynamic>> inventoryPresets = const [];
  List<Map<String, dynamic>> presetRoster = const [];
  List<Map<String, dynamic>> liveProviders = const [];
  List<Map<String, dynamic>> configurableProviders = const [];
  final List<(String, Map<String, dynamic>)> presetWrites = [];

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
    mutates.add({'ns': ns, 'ops': ops, 'expectedRevision': expectedRevision});
    // Echo back the namespace as writable ready to keep form available.
    return <String, dynamic>{
      'namespace': {
        'ns': ns,
        'value': <String, dynamic>{for (final op in ops) if (op['path'] is List && (op['path'] as List).isNotEmpty) (op['path'] as List).first as String: op['value']},
        'base': <String, dynamic>{},
        'user': <String, dynamic>{for (final op in ops) if (op['op'] == 'set') (op['path'] as List).first as String: op['value']},
        'revision': 2,
        'writable': true,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> pluginInventoryList() async {
    calls.add('pluginInventory.list');
    return <String, dynamic>{
      'entries': inventoryEntries,
      if (inventoryPresets.isNotEmpty) 'agentPresets': inventoryPresets,
    };
  }

  @override
  Future<Map<String, dynamic>> agentPresetList() async {
    calls.add('agentPresets.list');
    return <String, dynamic>{'presets': presetRoster, 'authorable': true};
  }

  @override
  Future<bool> settingsCanOpenAgentPresetDirectory() async => false;

  @override
  Future<Map<String, dynamic>> settingsUpdate({
    required String ns,
    required Map<String, dynamic> patch,
    int? expectedRevision,
  }) async {
    presetWrites.add(('settings/update', {'ns': ns, 'patch': patch}));
    return {'ns': ns, 'value': patch, 'revision': 2};
  }

  @override
  Future<List<Map<String, dynamic>>> llmListProviders() async => liveProviders;

  @override
  Future<List<Map<String, dynamic>>> llmListConfigurableProviders() async =>
      configurableProviders;

  @override
  Future<Map<String, dynamic>> credentialsDescribe(List<String> refs) async =>
      const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> sessionModelCatalog() async {
    calls.add('session/modelCatalog');
    return <String, dynamic>{'groups': [], 'failures': []};
  }
}

Map<String, Object?> _settingsDocument() => {
  'writable': true,
  // The shipped welcome notice is acknowledged, so the shell-level
  // onboarding overlay stays hidden (mirrors the completed step).
  'namespaces': [
    {
      'ns': 'ui-onboarding',
      'value': {'welcomeNoticeVersion': '2026-08-13.1'},
      'revision': 1,
    },
    {
      'ns': 'locale',
      'value': {'preference': 'en'},
      'revision': 1,
    },
    {
      'ns': 'ui-conversation',
      'value': {'busyEnter': 'queue'},
      'revision': 1,
    },
    {
      'ns': 'ui-chat',
      'value': {'transcriptView': 'compact'},
      'revision': 1,
    },
    {
      'ns': 'permission',
      'value': {'defaultPreset': 'workspace-write'},
      'revision': 1,
      'writable': true,
      'schema': {
        'type': 'object',
        'dict': {
          'defaultPreset': {
            'type': 'union',
            'list': [
              {
                'type': 'const',
                'value': 'read-only',
                'meta': {'description': 'Read Only'},
              },
              {
                'type': 'const',
                'value': 'workspace-write',
                'meta': {'description': 'Workspace Write'},
              },
              {
                'type': 'const',
                'value': 'danger-full-access',
                'meta': {'description': 'Full access'},
              },
            ],
          },
        },
      },
    },
    {'ns': 'ui-theme', 'value': <String, dynamic>{}, 'revision': 1},
    {'ns': 'shell', 'value': <String, dynamic>{}, 'revision': 1, 'writable': true},
    {'ns': 'agent-loop', 'value': <String, dynamic>{}, 'revision': 1, 'writable': true},
    {'ns': 'subagent-model-selection', 'value': <String, dynamic>{'enabled': false}, 'revision': 1, 'writable': true},
    {'ns': 'web-search-deepseek', 'value': <String, dynamic>{}, 'revision': 1, 'writable': true},
  ],
};

List<Map<String, dynamic>> _inventorySnapshot() => [
  {'entryId': 'readfile', 'moduleName': 'ReadFile', 'enabled': true, 'fiberPhase': 'active'},
  {'entryId': 'bash', 'moduleName': 'Bash', 'enabled': true, 'fiberPhase': 'active'},
  {'entryId': 'webfetch', 'moduleName': 'WebFetch', 'enabled': true, 'fiberPhase': 'active'},
];

List<Map<String, dynamic>> _inventoryPresets() => [
  {
    'id': 'ptc',
    'name': 'PTC mode',
    'isDefault': true,
    'rows': [
      {'entryId': null, 'moduleName': 'SessionChat', 'enabled': true, 'fiberPhase': 'active'},
      {'entryId': null, 'moduleName': 'ConditionalTool', 'enabled': 'conditional', 'condition': 'isDesktop', 'fiberPhase': null},
    ],
  },
  {
    'id': 'minimal',
    'name': 'Minimal',
    'isDefault': false,
    'rows': [
      {'entryId': null, 'moduleName': 'SessionChat', 'enabled': true, 'fiberPhase': 'active'},
    ],
  },
];

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeClient client, {
  String localeId = 'en',
}) async {
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
  locale.register(kAgentPresetNamespace, {
    'zh': kAgentPresetZh,
    'en': kAgentPresetEn,
  });
  locale.register(kPermissionSettingsNamespace, {
    'zh': kPermissionSettingsZh,
    'en': kPermissionSettingsEn,
  });
  locale.register(kConversationNamespace, {
    'zh': kConversationZh,
    'en': kConversationEn,
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
        home: const SettingsScreen(),
      ),
    ),
  );
  // Post-frame loads (LanguageRow / BusyEnter) resolve against the fake.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hosts the five settings tabs', (tester) async {
    await _pumpScreen(tester, _FakeClient());

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('General'), findsWidgets);
    expect(find.text('Models'), findsWidgets);
    expect(find.text('Plugins'), findsWidgets);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.text('Agent presets'), findsWidgets);
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
    // Enter-behavior row rides the same document (ns ui-conversation).
    await tester.dragUntilVisible(
      find.text('Enter behavior while busy'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.text('Enter behavior while busy'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
  });

  testWidgets('General tab accepts map-shaped settings namespaces', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = <String, Object?>{
        'namespaces': <String, Object?>{
          'locale': <String, Object?>{
            'ns': 'locale',
            'value': <String, Object?>{'preference': 'en'},
            'revision': 1,
          },
          'ui-conversation': <String, Object?>{
            'ns': 'ui-conversation',
            'value': <String, Object?>{'busyEnter': 'steer'},
            'revision': 1,
          },
          'ui-onboarding': <String, Object?>{
            'ns': 'ui-onboarding',
            'value': <String, Object?>{'welcomeNoticeVersion': '2026-08-13.1'},
            'revision': 1,
          },
        },
      };

    await _pumpScreen(tester, client);

    await tester.dragUntilVisible(
      find.text('Enter behavior while busy'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.text('Enter behavior while busy'), findsOneWidget);
    expect(find.text('Steer'), findsOneWidget);
  });

  testWidgets('General tab carries notifications and workspace sections', (
    tester,
  ) async {
    // Acknowledged onboarding keeps the shell overlay hidden so the
    // below-fold sections stay reachable.
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

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

  testWidgets('Plugins tab lists the plugin cards (parity with React)', (tester) async {
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Plugins').first);
    await tester.pumpAndSettle();

    // Live cards: Shell, Agent loop, Subagent, Web search — Filesystem/LSP etc are not separate settings cards.
    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('Agent loop'), findsOneWidget);
    expect(find.text('Subagent'), findsOneWidget);
    expect(find.text('Web search'), findsOneWidget);
    // Intro copy mirrors React.
    expect(find.text('Configure and inspect the plugins installed in this deployment.'), findsWidgets);
  });

  testWidgets('Inventory tab renders the grid inventory', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = _settingsDocument()
      ..inventoryEntries = _inventorySnapshot();
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Inventory').first);
    await tester.pumpAndSettle();

    expect(find.text('Plugin list'), findsWidgets);
    expect(find.text('Search plugins'), findsOneWidget);
    expect(find.text('ReadFile'), findsOneWidget);
    expect(find.text('Bash'), findsOneWidget);
  });

  testWidgets('Inventory shows session group open with preset switcher', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = _settingsDocument()
      ..inventoryEntries = _inventorySnapshot()
      ..inventoryPresets = _inventoryPresets();
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Inventory').first);
    await tester.pumpAndSettle();

    // Session group (React parity): open by default, switcher on default preset.
    expect(find.text('Session plugins'), findsOneWidget);
    expect(
      find.text('Composed per session by agent presets · 2 plugins'),
      findsOneWidget,
    );
    expect(find.text('PTC mode (default)'), findsOneWidget);
    expect(find.text('SessionChat'), findsOneWidget);
    expect(find.text('ConditionalTool'), findsOneWidget);
    expect(find.text('Conditional'), findsOneWidget);
    // Global group collapses when a roster is present.
    expect(find.text('Global plugins'), findsOneWidget);
    expect(find.text('ReadFile'), findsNothing);
  });

  testWidgets('Inventory global group expands and marks preset-provided rows', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = _settingsDocument()
      ..inventoryEntries = [
        {'entryId': 'g-chat', 'moduleName': 'SessionChat', 'enabled': false, 'fiberPhase': null},
        {'entryId': 'g-bad', 'moduleName': 'BrokenMod', 'enabled': true, 'fiberPhase': 'failed'},
        {'entryId': 'g-ok', 'moduleName': 'OkMod', 'enabled': true, 'fiberPhase': 'active'},
      ]
      ..inventoryPresets = _inventoryPresets();
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Inventory').first);
    await tester.pumpAndSettle();

    // Failed count rides the collapsed global subtitle.
    expect(find.textContaining('1 failed'), findsOneWidget);
    // Expand the global group.
    await tester.tap(find.text('Global plugins'));
    await tester.pumpAndSettle();

    // Failures float first and carry the Failed tag.
    expect(find.text('BrokenMod'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
    // Globally-disabled but preset-enabled row is marked, not plain Disabled.
    expect(find.text('Enabled via presets'), findsOneWidget);
  });

  testWidgets('Inventory search forces groups open and surfaces other presets', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = _settingsDocument()
      ..inventoryEntries = _inventorySnapshot()
      ..inventoryPresets = _inventoryPresets();
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Inventory').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'SessionChat');
    await tester.pumpAndSettle();

    // Search opens the collapsed global-adjacent session rows and points at
    // matches sitting in unselected presets.
    expect(find.textContaining('more matches in other presets'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);
  });

  testWidgets('Agent presets tab manages the roster like React', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = _settingsDocument()
      ..presetRoster = [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
          'description': 'Full coding agent.',
        },
        {'id': 'minimal', 'trust': 'system', 'name': 'Minimal mode'},
      ];
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Agent presets').first);
    await tester.pumpAndSettle();

    // Intro plus Built-in group with the In-use badge on the default.
    expect(find.textContaining('plugin composition'), findsOneWidget);
    expect(find.text('Built-in'), findsWidgets);
    expect(find.text('Standard mode'), findsOneWidget);
    expect(find.text('In use'), findsWidgets);
    expect(find.text('Minimal mode'), findsOneWidget);
  });

  testWidgets('Agent presets tab pick persists the host default', (tester) async {
    final client = _FakeClient()
      ..describeAnswer = _settingsDocument()
      ..presetRoster = [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
        },
        {'id': 'minimal', 'trust': 'system', 'name': 'Minimal mode'},
      ];
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Agent presets').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set as default'));
    await tester.pumpAndSettle();

    // The pick rode settings/update agent-presets {default} — the host
    // resolves it at session creation, so new sessions follow app-wide.
    expect(client.presetWrites, hasLength(1));
    final (method, payload) = client.presetWrites.single;
    expect(method, 'settings/update');
    expect(payload['ns'], 'agent-presets');
    expect(payload['patch'], {'default': 'minimal'});
  });

  testWidgets('General tab renders the React General rows', (tester) async {
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    // React `settings.general.item` order: permission, language, appearance,
    // font-size, transcript-view, busy-enter.
    expect(find.text('Permission'), findsOneWidget);
    expect(find.text('Workspace Write'), findsOneWidget);
    expect(
      find.text('Choose the default permission mode for new sessions'),
      findsOneWidget,
    );
    expect(find.text('Font size'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('Conversation display'), findsOneWidget);
    expect(find.text('Compact'), findsOneWidget);
  });

  testWidgets('Font-size stepper writes ui-theme with a revision fence', (
    tester,
  ) async {
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    await tester.tap(find.bySemanticsLabel('Increase font size'));
    await tester.pumpAndSettle();

    final fontWrites = client.mutates.where((m) => m['ns'] == 'ui-theme');
    expect(fontWrites, hasLength(1));
    final write = fontWrites.single;
    expect(write['ops'], [
      {
        'op': 'set',
        'path': ['fontSize'],
        'value': 15,
      },
    ]);
    expect(write['expectedRevision'], 1);
    expect(find.text('15'), findsOneWidget);
  });

  testWidgets('Busy-enter writes the ui-conversation namespace, not conversation', (
    tester,
  ) async {
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    await tester.dragUntilVisible(
      find.text('Queue'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Steer').last);
    await tester.pumpAndSettle();

    final enterWrites = client.mutates.where(
      (m) => (m['ops'] as List).any(
        (op) => (op['path'] as List).contains('busyEnter'),
      ),
    );
    expect(enterWrites, hasLength(1));
    expect(enterWrites.single['ns'], 'ui-conversation');
  });

  testWidgets('Permission full-access pick passes the risk gate', (
    tester,
  ) async {
    // Laptop-tall viewport: the confirmation dialog is long and React's
    // modal has no scroll container, so short windows clip its footer.
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    await tester.tap(find.text('Workspace Write'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full access').last);
    await tester.pumpAndSettle();

    // RiskConfirmation gate mirrors React: acknowledge before Enable.
    expect(find.text('Enable Full access?'), findsOneWidget);
    await tester.tap(
      find.text('I understand the risks and want to continue'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable Full access'));
    await tester.pumpAndSettle();

    final permWrites = client.mutates.where((m) => m['ns'] == 'permission');
    expect(permWrites, hasLength(1));
    expect(permWrites.single['ops'], [
      {
        'op': 'set',
        'path': ['defaultPreset'],
        'value': 'danger-full-access',
      },
    ]);
  });

  testWidgets('Models editor copy resolves through the models locale', (
    tester,
  ) async {
    final doc = _settingsDocument()..['namespaces'] = [
      ...(_settingsDocument()['namespaces'] as List),
      {
        'ns': 'llm-deepseek',
        'value': <String, dynamic>{},
        'revision': 1,
        'writable': true,
      },
    ];
    final client = _FakeClient()
      ..describeAnswer = doc
      ..liveProviders = [
        {'id': 'llm-deepseek', 'name': 'DeepSeek'},
      ]
      ..configurableProviders = [
        {
          'provider': 'llm-deepseek',
          'displayName': 'DeepSeek',
          'settingsNs': 'llm-deepseek',
          'settingsPath': <String>[],
        },
      ];
    await _pumpScreen(tester, client, localeId: 'zh');

    await tester.tap(find.text('模型').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // Editor labels ride the settings.models dictionaries, not hardcoded copy.
    expect(find.text('API 密钥'), findsOneWidget);
    expect(find.text('自定义设置'), findsOneWidget);
    // Model rows mount the shared ModelListEditor behind the Customized
    // disclosure (inherited catalog state when nothing is stored).
    await tester.tap(find.text('自定义设置'));
    await tester.pumpAndSettle();
    expect(find.text('模型目录'), findsOneWidget);
    expect(
      find.text('模型选择器中将不显示任何模型；目录外 ID 仍可直接发送。'),
      findsOneWidget,
    );
  });

  testWidgets('Welcome notice blocks until acknowledged', (tester) async {
    // Fresh Host without the shipped acknowledgement: the shell-level
    // onboarding overlay shows the internal-testing notice.
    final doc = _settingsDocument()..['namespaces'] = [
      for (final ns in _settingsDocument()['namespaces'] as List)
        if ((ns as Map)['ns'] != 'ui-onboarding') ns,
    ];
    final client = _FakeClient()..describeAnswer = doc;
    await _pumpScreen(tester, client);

    expect(find.text('Internal Testing Notice'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // The notice body scrolls in place on short viewports; bring the
    // acknowledgement into view like a user would (scoped to the dialog's
    // own scrollable — the General ListView sits underneath the mask).
    final dialogScroll = find.ancestor(
      of: find.text('Internal Testing Notice'),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.dragUntilVisible(
      find.text('Continue'),
      dialogScroll,
      const Offset(0, -200),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final ackWrites = client.mutates.where(
      (m) => m['ns'] == 'ui-onboarding',
    );
    expect(ackWrites, hasLength(1));
    expect(ackWrites.single['ops'], [
      {
        'op': 'set',
        'path': ['welcomeNoticeVersion'],
        'value': '2026-08-13.1',
      },
    ]);
    expect(find.text('Internal Testing Notice'), findsNothing);
  });

  testWidgets('Transcript selector writes the ui-chat namespace', (
    tester,
  ) async {
    final client = _FakeClient()..describeAnswer = _settingsDocument();
    await _pumpScreen(tester, client);

    await tester.dragUntilVisible(
      find.text('Compact'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    // dragUntilVisible stops at cache-extent visibility; bring the trigger
    // fully on-screen so the tap lands on the DsSelect anchor.
    await tester.ensureVisible(find.text('Compact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal').last);
    await tester.pumpAndSettle();

    final viewWrites = client.mutates.where((m) => m['ns'] == 'ui-chat');
    expect(viewWrites, hasLength(1));
    expect(viewWrites.single['ops'], [
      {
        'op': 'set',
        'path': ['transcriptView'],
        'value': 'normal',
      },
    ]);
  });
}
