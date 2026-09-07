import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    show connectionClientProvider;
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/locales.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/agent_preset_plugin.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/ui/agent_preset_provider.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/ui/agent_preset_label.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/ui/agent_preset_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

/// Sessions controller seeded at build so the header label reads a stable
/// snapshot (ProviderScope-override pattern from the controller docstring).
class _SeededSessions extends SessionsController {
  _SeededSessions(this._state);
  final SessionsState _state;

  @override
  SessionsState build() => _state;
}

Widget _app(Widget child, {required SessionSummary? current}) {
  final byId = <SessionId, SessionSummary>{};
  if (current != null) byId[current.sessionId] = current;
  final container = ProviderContainer(
    overrides: [
      sessionsProvider.overrideWith(
        () => _SeededSessions(
          SessionsState(byId: byId, current: current?.sessionId),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // The labels resolve through the shared LocaleService; production
  // registers this dictionary in AgentPresetPlugin.apply.
  final LocaleService locale = container.read(localeServiceProvider);
  locale.register(kAgentPresetNamespace, {
    'zh': kAgentPresetZh,
    'en': kAgentPresetEn,
  });
  locale.setLocale('en');
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: Row(children: [child])),
    ),
  );
}

void main() {
  test(
    'activation registers dictionaries and installs the header label entry',
    () async {
      final host = wsAgentHost();
      addTearDown(host.deactivateAll);

      declareHeaderActionsHole(host);
      host.register(const AgentPresetPlugin());
      await host.activateAll();

      // Dictionary registered (default zh; en mirrors every key).
      final locale = host.service<LocaleService>('locale')!;
      expect(locale.bind(kAgentPresetNamespace)('nav'), 'Agent 预设');
      locale.setLocale('en');
      expect(locale.bind(kAgentPresetNamespace)('nav'), 'Agent presets');
      expect(kAgentPresetZh.keys.toSet(), kAgentPresetEn.keys.toSet());

      final winners = host.slots.winnersOfSlot(
        'conversation.session.header.actions',
      );
      expect(winners, hasLength(1));
      expect(winners.single.options.id, kAgentPresetHeaderId);
      expect(winners.single.options.order, -10);

      host.deactivate(kAgentPresetPluginId);
      expect(
        host.slots.winnersOfSlot('conversation.session.header.actions'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'header label renders the running preset for the current session',
    (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1000,
        running: false,
        blank: false,
        agentPreset: 'standard',
      );

      await tester.pumpWidget(
        _app(const AgentPresetHeaderLabel(), current: summary),
      );
      await tester.pumpAndSettle();

      // Built-in ids resolve localized display copy, not the raw id.
      expect(find.text('Standard mode'), findsOneWidget);
      expect(find.byType(Tooltip), findsOneWidget);
    },
  );

  testWidgets('header label stays hidden while no session runs a preset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const AgentPresetHeaderLabel(), current: null),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgentPresetHeaderLabel), findsOneWidget);
    expect(find.text('Standard mode'), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('header label collapses to icon in a 24px rail slot', (
    tester,
  ) async {
    // Narrow header slots used to overflow the name Row by ~88px; the label
    // now renders icon-only instead of throwing a RenderFlex overflow.
    const summary = SessionSummary(
      sessionId: SessionId('sess-1'),
      updatedAt: 1000,
      running: false,
      blank: false,
      agentPreset: 'standard',
    );

    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 24,
          child: AgentPresetHeaderLabel(),
        ),
        current: summary,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.text('Standard mode'), findsNothing);
  });

  test(
    'presetDisplayText resolves built-in copy and passes user metadata through',
    () {
      // The label widget binds against a LocaleService; a bare registry with
      // the plugin dictionaries exercises the same lookup chain.
      final locale = LocaleService();
      locale.register(kAgentPresetNamespace, {
        'zh': kAgentPresetZh,
        'en': kAgentPresetEn,
      });
      locale.setLocale('en');
      final t = locale.bind(kAgentPresetNamespace);

      final builtIn = presetDisplayText(id: 'minimal', builtIn: true, t: t);
      expect(builtIn.name, 'Minimal mode');

      // The Host ships ids standard/ptc/minimal/cordis (not 'code'): every
      // shipped id resolves, so host-metadata language never leaks through.
      expect(
        presetDisplayText(id: 'ptc', builtIn: true, t: t).name,
        'PTC mode',
      );
      expect(
        presetDisplayText(id: 'standard', builtIn: true, t: t).name,
        'Standard mode',
      );
      expect(
        presetDisplayText(id: 'cordis', builtIn: true, t: t).name,
        'Creator mode',
      );

      final custom = presetDisplayText(
        id: 'my-preset',
        builtIn: false,
        t: t,
        name: 'Mine',
        description: 'Locally authored',
      );
      expect(custom.name, 'Mine');
      expect(custom.description, 'Locally authored');

      // Unknown built-in id falls back to file metadata.
      final unknown = presetDisplayText(id: 'ghost', builtIn: true, t: t);
      expect(unknown.name, 'ghost');
    },
  );

  testWidgets(
    'management section renders the roster with trust groups and badges',
    (tester) async {
      final client = _FakePresetClient(
        roster: [
          {
            'id': 'standard',
            'trust': 'system',
            'isDefault': true,
            // Host ships its own metadata language (here zh): shipped cards
            // must still render the active locale's dictionary copy.
            'name': '标准模式',
            'description': '功能完整的编码 Agent。',
          },
          {
            'id': 'broken-one',
            'trust': 'user',
            'name': 'Broken preset',
            'broken': 'invalid composition key',
          },
          {'id': 'mine', 'trust': 'user', 'name': 'Mine'},
        ],
      );
      await tester.pumpWidget(_sectionApp(client));
      await tester.pumpAndSettle();

      // Group headers and trust badges share the builtInGroup/userTrust copy.
      expect(find.text('Built-in'), findsWidgets);
      expect(find.text('Custom'), findsWidgets);
      // Shipped card renders dictionary copy, not host metadata.
      expect(find.text('Standard mode'), findsWidgets);
      expect(find.text('标准模式'), findsNothing);
      expect(
        find.textContaining('Full coding agent with file editing'),
        findsOneWidget,
      );
      expect(find.text('Broken preset'), findsOneWidget);
      expect(find.text('Failed to load'), findsOneWidget); // brokenBadge
      expect(find.text('invalid composition key'), findsOneWidget); // reason
    },
  );

  testWidgets('view opens the real composition read from the host', (
    tester,
  ) async {
    final client = _FakePresetClient(
      roster: [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
        },
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('# preset composition\ncat: standard'), findsOneWidget);
    // The read rode the generic carrier with the addressed preset id.
    final (method, payload) = client.calls.single;
    expect(method, 'agentPresets/read');
    expect(payload['agentPreset'], 'standard');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('copy submits the wire payload and refreshes the roster', (
    tester,
  ) async {
    final client = _FakePresetClient(
      roster: [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
        },
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Duplicate'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Identifier').first,
      'standard-copy',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'My copy',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // The copy plus React-parity landing in the new preset's files.
    expect(client.calls, hasLength(2));
    final (method, payload) = client.calls[0];
    expect(method, 'agentPresets/copy');
    expect(payload['from'], 'standard');
    expect(payload['id'], 'standard-copy');
    expect(payload['name'], 'My copy');
    final (locMethod, locPayload) = client.calls[1];
    expect(locMethod, 'settings/openAgentPresetDirectory');
    expect(locPayload['agentPreset'], 'standard-copy');
  });

  testWidgets('delete confirms then removes through agentPreset.remove', (
    tester,
  ) async {
    final client = _FakePresetClient(
      roster: [
        {'id': 'mine', 'trust': 'user', 'name': 'Mine'},
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    // Confirmation dialog first — nothing on the wire yet.
    expect(find.text('Delete this preset?'), findsOneWidget);
    expect(client.calls, isEmpty);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(client.calls, hasLength(1));
    final (method, payload) = client.calls.single;
    expect(method, 'agentPresets/deletePreset');
    expect(payload['id'], 'mine');
  });

  test('presetCopyBlocker mirrors React draftBlocker', () {    const rows = [
      AgentPresetOption(id: 'standard', name: 'standard', trust: PresetTrust.system),
      AgentPresetOption(id: 'mine', name: 'mine', trust: PresetTrust.user),
    ];
    expect(presetCopyBlocker('', rows), 'idRequired');
    expect(presetCopyBlocker('BAD ID!', rows), 'idInvalid');
    expect(presetCopyBlocker('Mine', rows), 'idInvalid');
    expect(presetCopyBlocker('mine', rows), 'idTaken');
    expect(presetCopyBlocker('standard', rows), 'idTaken');
    expect(presetCopyBlocker('mine-2', rows), isNull);
    expect(presetCopyBlocker('a', rows), isNull);
  });

  testWidgets('location action opens on the host when it can', (tester) async {
    final client = _FakePresetClient(
      roster: [
        {'id': 'mine', 'trust': 'user', 'name': 'Mine'},
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    // Opener capability joined from settings, not the list answer.
    expect(find.byTooltip('Open folder'), findsOneWidget);
    await tester.tap(find.byTooltip('Open folder'));
    await tester.pumpAndSettle();

    expect(client.calls, hasLength(1));
    final (method, payload) = client.calls.single;
    expect(method, 'settings/openAgentPresetDirectory');
    expect(payload['agentPreset'], 'mine');
    // Opened on the host desktop: nothing revealed on the row.
    expect(find.text('Preset files:'), findsNothing);
  });

  testWidgets('location action reveals the path where it cannot open', (
    tester,
  ) async {
    final client = _FakePresetClient(
      roster: [
        {'id': 'mine', 'trust': 'user', 'name': 'Mine'},
      ],
      canOpen: false,
      revealPath: '/data/presets/mine',
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show location'), findsOneWidget);
    await tester.tap(find.byTooltip('Show location'));
    await tester.pumpAndSettle();

    expect(find.text('Preset files:'), findsOneWidget);
    expect(find.text('/data/presets/mine'), findsOneWidget);
  });

  testWidgets('refused opener removes only the affordance, not the roster', (
    tester,
  ) async {
    final client = _FakePresetClient(
      roster: [
        {'id': 'mine', 'trust': 'user', 'name': 'Mine'},
      ],
      throwCanOpen: true,
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    // Roster still loads; the row falls back to reveal-path posture.
    // ('Mine' renders in the row picker, the seat picker, and the card.)
    expect(find.text('Mine'), findsWidgets);
    expect(find.byTooltip('Show location'), findsOneWidget);
    expect(find.byTooltip('Open folder'), findsNothing);
  });

  testWidgets('copy dialog blocks invalid ids before the wire', (tester) async {
    final client = _FakePresetClient(
      roster: [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
        },
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Duplicate'));
    await tester.pumpAndSettle();

    FilledButton createButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    // Prefill is submittable.
    expect(createButton().enabled, isTrue);

    await tester.enterText(
      find.widgetWithText(TextField, 'Identifier').first,
      'BAD ID!',
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Use lowercase letters, digits, and hyphens, starting with a letter or digit.',
      ),
      findsOneWidget,
    );
    expect(createButton().enabled, isFalse);
    expect(client.calls, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Identifier').first,
      'standard',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('A preset with this identifier already exists.'),
      findsOneWidget,
    );
    expect(createButton().enabled, isFalse);
    expect(client.calls, isEmpty);
  });

  test('makeDefaultPreset persists the default through settings/update', () async {
    final client = _FakePresetClient(roster: const []);
    final failure = await makeDefaultPreset(client, 'ptc');
    expect(failure, isNull);
    expect(client.calls, hasLength(1));
    final (method, payload) = client.calls.single;
    expect(method, 'settings/update');
    expect(payload['ns'], 'agent-presets');
    expect(payload['patch'], {'default': 'ptc'});
  });

  testWidgets('set-as-default persists the host default and refreshes', (
    tester,
  ) async {
    final client = _FakePresetClient(
      roster: [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
        },
        {'id': 'minimal', 'trust': 'system', 'name': 'Minimal mode'},
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    final Finder setDefault = find.widgetWithText(
      OutlinedButton,
      'Set as default',
    );
    await tester.ensureVisible(setDefault);
    await tester.pumpAndSettle();
    await tester.tap(setDefault);
    await tester.pumpAndSettle();

    // The pick rode settings/update (host default for sessions created
    // later), not the per-session select — this is what reflects app-wide.
    expect(client.calls, hasLength(1));
    final (method, payload) = client.calls.single;
    expect(method, 'settings/update');
    expect(payload['ns'], 'agent-presets');
    expect(payload['patch'], {'default': 'minimal'});
    expect(
      find.text('Preset "minimal" is now the default for new sessions'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a card body picks it as the default', (tester) async {
    final client = _FakePresetClient(
      roster: [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
        },
        {'id': 'minimal', 'trust': 'system', 'name': 'Minimal mode'},
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    // React rule: the card body IS the control.
    await tester.tap(find.text('Minimal mode'));
    await tester.pumpAndSettle();

    expect(client.calls, hasLength(1));
    final (method, payload) = client.calls.single;
    expect(method, 'settings/update');
    expect(payload['patch'], {'default': 'minimal'});
  });

  testWidgets('custom group keeps the creator entry beside cordis', (
    tester,
  ) async {
    final client = _FakePresetClient(
      roster: [
        {
          'id': 'standard',
          'trust': 'system',
          'isDefault': true,
          'name': 'Standard mode',
        },
        {'id': 'cordis', 'trust': 'system', 'name': 'Creator mode'},
      ],
    );
    await tester.pumpWidget(_sectionApp(client));
    await tester.pumpAndSettle();

    // Section intro plus the guided drafting entry (React creatorButton).
    expect(find.textContaining('plugin composition'), findsOneWidget);
    expect(
      find.text('Draft a custom preset with Creator mode'),
      findsOneWidget,
    );

    // No session in this harness: stages cordis locally, nothing on the wire.
    await tester.ensureVisible(
      find.text('Draft a custom preset with Creator mode'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft a custom preset with Creator mode'));
    await tester.pumpAndSettle();
    expect(client.calls, isEmpty);
    expect(find.textContaining('cordis'), findsWidgets);
  });
}

/// Fake typed client for the management section: `agentPreset.list` serves a
/// fixed roster; the generic carrier records read/copy/remove/location calls
/// and replies from one scripted map (field-asserted, not string-matched).
/// `hasDocument` is joined from `settings/canOpenAgentPresetDirectory` like
/// React `section-store.ts:load` — the list answer carries no such key.
class _FakePresetClient extends ConnectionClient {
  _FakePresetClient({
    required this.roster,
    this.authorable = true,
    this.canOpen = true,
    this.throwCanOpen = false,
    this.revealPath,
  }) : super(baseUrl: '');

  final List<Map<String, dynamic>> roster;
  final bool authorable;

  /// Answer for `settings/canOpenAgentPresetDirectory`.
  final bool canOpen;

  /// When true, the opener query throws (a refused describe removes only the
  /// native-open affordance; the roster still loads).
  final bool throwCanOpen;

  /// When set, `settings/openAgentPresetDirectory` answers
  /// `{opened: false, path: revealPath}` instead of opening.
  final String? revealPath;
  final List<(String, Map<String, dynamic>)> calls =
      <(String, Map<String, dynamic>)>[];
  Object? Function(String method, Map<String, dynamic> payload)? onCall;

  @override
  Future<Map<String, dynamic>> agentPresetList() async => {
    'presets': roster,
    'authorable': authorable,
  };

  @override
  Future<bool> settingsCanOpenAgentPresetDirectory() async {
    if (throwCanOpen) throw Exception('settings describe refused');
    return canOpen;
  }

  @override
  Future<Map<String, dynamic>> settingsUpdate({
    required String ns,
    required Map<String, dynamic> patch,
    int? expectedRevision,
  }) async {
    calls.add((
      'settings/update',
      {'ns': ns, 'patch': patch},
    ));
    return {'ns': ns, 'value': patch, 'revision': 2};
  }

  @override
  Future<Map<String, dynamic>> settingsOpenAgentPresetDirectory({
    required String agentPreset,
  }) async {
    calls.add((
      'settings/openAgentPresetDirectory',
      {'agentPreset': agentPreset},
    ));
    final handler = onCall;
    if (handler != null) {
      final value = handler(
        'settings/openAgentPresetDirectory',
        {'agentPreset': agentPreset},
      );
      if (value is Map<String, dynamic>) return value;
    }
    final reveal = revealPath;
    if (reveal != null) return {'opened': false, 'path': reveal};
    return {'opened': true};
  }

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    calls.add((method, payload));
    final handler = onCall;
    if (handler != null) {
      final value = handler(method, payload);
      if (value is Map<String, dynamic>) return value;
    }
    return switch (method) {
      'agentPresets/read' => {
        'agentPreset': payload['agentPreset'],
        'trust': 'system',
        'content': '# preset composition\ncat: standard',
      },
      'agentPresets/copy' => {'agentPreset': payload['id']},
      'agentPresets/deletePreset' => const {},
      // Legacy singular dot forms kept for backward compat with older test fixtures
      'agentPreset.read' => {
        'agentPreset': payload['agentPreset'],
        'trust': 'system',
        'content': '# preset composition\ncat: standard',
      },
      'agentPreset.copy' => {'agentPreset': payload['agentPreset'] ?? payload['id']},
      'agentPreset.remove' => const {},
      _ => const {},
    };
  }
}

Widget _sectionApp(ConnectionClient client) {
  final container = ProviderContainer(
    overrides: [connectionClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  // Mirror AgentPresetPlugin.apply's dictionary registration; English
  // expectations below read against it.
  final LocaleService locale = container.read(localeServiceProvider);
  locale.register(kAgentPresetNamespace, {
    'zh': kAgentPresetZh,
    'en': kAgentPresetEn,
  });
  locale.setLocale('en');
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: AgentPresetScreen()),
  );
}
