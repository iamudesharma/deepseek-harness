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
            'name': 'Standard mode',
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
      expect(
        find.text('Standard mode'),
        findsWidgets,
      ); // row label + roster card
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
    expect(method, 'agentPreset.read');
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

    expect(client.calls, hasLength(1));
    final (method, payload) = client.calls.single;
    expect(method, 'agentPreset.copy');
    expect(payload['from'], 'standard');
    expect(payload['agentPreset'], 'standard-copy');
    expect(payload['name'], 'My copy');
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
    expect(method, 'agentPreset.remove');
    expect(payload['agentPreset'], 'mine');
  });
}

/// Fake typed client for the management section: `agentPreset.list` serves a
/// fixed roster; the generic carrier records read/copy/remove calls and
/// replies from one scripted map (field-asserted, not string-matched).
class _FakePresetClient extends ConnectionClient {
  _FakePresetClient({required this.roster, this.authorable = true})
    : super(baseUrl: '');

  final List<Map<String, dynamic>> roster;
  final bool authorable;
  final List<(String, Map<String, dynamic>)> calls =
      <(String, Map<String, dynamic>)>[];
  Object? Function(String method, Map<String, dynamic> payload)? onCall;

  @override
  Future<Map<String, dynamic>> agentPresetList() async => {
    'presets': roster,
    'authorable': authorable,
    'hasDocument': true,
  };

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
      'agentPreset.read' => {
        'agentPreset': payload['agentPreset'],
        'trust': 'system',
        'content': '# preset composition\ncat: standard',
      },
      'agentPreset.copy' => {'agentPreset': payload['agentPreset']},
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
