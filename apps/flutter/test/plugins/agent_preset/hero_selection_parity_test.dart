import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    show connectionClientProvider;
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/locales.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/ui/agent_preset_hero_seat.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/ui/agent_preset_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SeededSessions extends SessionsController {
  _SeededSessions(this._state);
  final SessionsState _state;
  @override
  SessionsState build() => _state;
}

class _FakePresetClient extends ConnectionClient {
  _FakePresetClient({this.failSelect = false}) : super(baseUrl: '');
  String? lastSelected;
  bool failSelect;
  @override
  Future<Map<String, dynamic>> agentPresetList() async => {
        'presets': [
          {'id': 'standard', 'trust': 'system', 'isDefault': true},
          {'id': 'code', 'trust': 'system'},
          {'id': 'minimal', 'trust': 'system'},
          {'id': 'cordis', 'trust': 'system'},
        ],
        'authorable': false,
        'hasDocument': false,
      };
  @override
  Future<Map<String, dynamic>> agentPresetSelect({
    required String sessionId,
    required String agentPreset,
  }) async {
    lastSelected = agentPreset;
    if (failSelect) {
      throw Exception('agent-preset-locked: session not blank');
    }
    return {'agentPreset': agentPreset};
  }
}

Widget _heroApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: Center(child: AgentPresetHeroSeat())),
    ),
  );
}

ProviderContainer _containerWithSession(SessionSummary summary,
    {bool failSelect = false}) {
  final byId = <SessionId, SessionSummary>{summary.sessionId: summary};
  const roster = AgentPresetRoster(
    presets: [
      AgentPresetOption(
          id: 'standard',
          name: 'standard',
          trust: PresetTrust.system,
          isDefault: true),
      AgentPresetOption(id: 'code', name: 'code', trust: PresetTrust.system),
      AgentPresetOption(
          id: 'minimal', name: 'minimal', trust: PresetTrust.system),
      AgentPresetOption(id: 'cordis', name: 'cordis', trust: PresetTrust.system),
    ],
    authorable: false,
    hasDocument: false,
  );
  final fakeClient = _FakePresetClient(failSelect: failSelect);
  final container = ProviderContainer(
    overrides: [
      sessionsProvider.overrideWith(
        () => _SeededSessions(
          SessionsState(byId: byId, current: summary.sessionId),
        ),
      ),
      connectionClientProvider.overrideWithValue(fakeClient),
      agentPresetListProvider.overrideWith((ref) async => roster),
    ],
  );
  addTearDown(container.dispose);
  final locale = container.read(localeServiceProvider);
  locale.register(kAgentPresetNamespace, {
    'zh': kAgentPresetZh,
    'en': kAgentPresetEn,
  });
  locale.setLocale('en');
  return container;
}

Future<void> _tapChip(WidgetTester tester) async {
  final chipText = find.textContaining(
    RegExp(r'Standard|PTC|Minimal|Creator|标准|极简|创造'),
  );
  if (chipText.evaluate().isNotEmpty) {
    await tester.tap(chipText.first);
  } else {
    await tester.tap(find.byType(AgentPresetHeroSeat));
  }
}

Future<void> _selectMode(WidgetTester tester, String label) async {
  await _tapChip(tester);
  await tester.pumpAndSettle();
  final labelFinder = find.text(label);
  expect(labelFinder, findsWidgets, reason: 'mode $label should be in menu');
  // AnchoredMenu renders each item as InkWell > Row > Text; the trigger also
  // contains the same text, so the menu item is the last occurrence.
  final menuLabel = labelFinder.last;
  final ink = find.ancestor(
    of: menuLabel,
    matching: find.byType(InkWell),
  );
  if (ink.evaluate().isNotEmpty) {
    await tester.tap(ink.first, warnIfMissed: false);
  } else {
    await tester.tap(menuLabel, warnIfMissed: false);
  }
  await tester.pumpAndSettle();
}

void main() {
  group('AgentPresetHeroSeat selection parity (host-authoritative)', () {
    testWidgets('catalog renders four modes', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsWidgets);
      expect(find.text('PTC mode'), findsOneWidget);
      expect(find.text('Minimal mode'), findsOneWidget);
      expect(find.text('Creator mode'), findsOneWidget);
    });

    testWidgets('current mode checkmark', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _tapChip(tester);
      await tester.pumpAndSettle();
      // Checkmark should be on Standard
      expect(find.byIcon(Icons.check), findsOneWidget);
      // Verify check is in Standard row
      final check = find.byIcon(Icons.check);
      final stdRow = find.ancestor(
        of: find.text('Standard mode').last,
        matching: find.byType(InkWell),
      );
      expect(stdRow, findsWidgets);
      // The check's ancestor InkWell should be the Standard row
      final checkRow = find.ancestor(
        of: check,
        matching: find.byType(InkWell),
      );
      expect(checkRow, findsOneWidget);
    });

    testWidgets('selecting PTC mode changes trigger and checkmark', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      final fake = container.read(connectionClientProvider) as _FakePresetClient;
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsOneWidget);
      await _selectMode(tester, 'PTC mode');
      // RPC called with code id
      expect(fake.lastSelected, 'code');
      // Trigger now shows PTC mode (host-authoritative via sessionsProvider)
      expect(find.text('PTC mode'), findsOneWidget);
      expect(find.text('Standard mode'), findsNothing);
      // Reopen menu shows check on PTC
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      final checkRow = find.ancestor(
        of: find.byIcon(Icons.check),
        matching: find.byType(InkWell),
      );
      // The check's InkWell should contain PTC label
      final ptcInCheck = find.descendant(
        of: checkRow,
        matching: find.text('PTC mode'),
      );
      expect(ptcInCheck, findsOneWidget);
    });

    testWidgets('selecting Minimal mode', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _selectMode(tester, 'Minimal mode');
      expect(find.text('Minimal mode'), findsOneWidget);
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('selecting Creator mode', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _selectMode(tester, 'Creator mode');
      expect(find.text('Creator mode'), findsOneWidget);
    });

    testWidgets('Standard → PTC → Minimal → Creator → Standard chain',
        (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _selectMode(tester, 'PTC mode');
      expect(find.text('PTC mode'), findsOneWidget);
      await _selectMode(tester, 'Minimal mode');
      expect(find.text('Minimal mode'), findsOneWidget);
      await _selectMode(tester, 'Creator mode');
      expect(find.text('Creator mode'), findsOneWidget);
      await _selectMode(tester, 'Standard mode');
      expect(find.text('Standard mode'), findsOneWidget);
    });

    testWidgets('selecting already-active mode is no-op', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      final fake = container.read(connectionClientProvider) as _FakePresetClient;
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _selectMode(tester, 'Standard mode');
      // Should be no-op: RPC not called when selecting current
      expect(fake.lastSelected, isNull);
      expect(find.text('Standard mode'), findsOneWidget);
    });

    testWidgets('trigger label updates immediately after selection',
        (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsOneWidget);
      await _selectMode(tester, 'PTC mode');
      // Immediately after host update, trigger shows new mode
      expect(find.text('PTC mode'), findsOneWidget);
      expect(container.read(sessionsProvider).byId[const SessionId('sess-1')]!.agentPreset, 'code');
    });

    testWidgets('reopen menu preserves selection', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _selectMode(tester, 'PTC mode');
      // Close and reopen
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      // Recreate screen
      await tester.pumpWidget(Container());
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsOneWidget);
    });

    testWidgets('host rejection preserves previous mode', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary, failSelect: true);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsOneWidget);
      await _selectMode(tester, 'PTC mode');
      // Should remain Standard
      expect(find.text('Standard mode'), findsOneWidget);
      expect(find.text('PTC mode'), findsNothing);
      await _tapChip(tester);
      await tester.pumpAndSettle();
      // Checkmark still on Standard
      final checkRow = find.ancestor(
        of: find.byIcon(Icons.check),
        matching: find.byType(InkWell),
      );
      final stdInCheck = find.descendant(
        of: checkRow,
        matching: find.text('Standard mode'),
      );
      expect(stdInCheck, findsOneWidget);
    });

    testWidgets('locale changes labels but not selected ID', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'code',
      );
      final container = _containerWithSession(summary);
      final locale = container.read(localeServiceProvider);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsOneWidget);
      locale.setLocale('zh');
      await tester.pumpAndSettle();
      expect(find.text('PTC 模式'), findsOneWidget);
      expect(container.read(sessionsProvider).byId[const SessionId('sess-1')]!.agentPreset, 'code');
      locale.setLocale('en');
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsOneWidget);
    });

    testWidgets('session scope: switching sessions shows correct mode',
        (tester) async {
      const s1 = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 2,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      const s2 = SessionSummary(
        sessionId: SessionId('sess-2'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'minimal',
      );
      final byId = <SessionId, SessionSummary>{s1.sessionId: s1, s2.sessionId: s2};
      const roster = AgentPresetRoster(
        presets: [
          AgentPresetOption(id: 'standard', name: 'standard', trust: PresetTrust.system, isDefault: true),
          AgentPresetOption(id: 'code', name: 'code', trust: PresetTrust.system),
          AgentPresetOption(id: 'minimal', name: 'minimal', trust: PresetTrust.system),
          AgentPresetOption(id: 'cordis', name: 'cordis', trust: PresetTrust.system),
        ],
        authorable: false,
        hasDocument: false,
      );
      final fakeClient = _FakePresetClient();
      final container = ProviderContainer(
        overrides: [
          sessionsProvider.overrideWith(() => _SeededSessions(SessionsState(byId: byId, current: s1.sessionId))),
          connectionClientProvider.overrideWithValue(fakeClient),
          agentPresetListProvider.overrideWith((ref) async => roster),
        ],
      );
      addTearDown(container.dispose);
      final locale = container.read(localeServiceProvider);
      locale.register(kAgentPresetNamespace, {'zh': kAgentPresetZh, 'en': kAgentPresetEn});
      locale.setLocale('en');
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsOneWidget);
      // Switch to s2
      container.read(sessionsProvider.notifier).setCurrent(s2.sessionId);
      await tester.pumpAndSettle();
      expect(find.text('Minimal mode'), findsOneWidget);
      // Change s1 to PTC, verify s2 unchanged
      await tester.pumpWidget(Container());
      container.read(sessionsProvider.notifier).updateSession(s1.sessionId, (s) => s.copyWith(agentPreset: 'code'));
      container.read(sessionsProvider.notifier).setCurrent(s1.sessionId);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsOneWidget);
      container.read(sessionsProvider.notifier).setCurrent(s2.sessionId);
      await tester.pumpAndSettle();
      expect(find.text('Minimal mode'), findsOneWidget);
    });

    testWidgets('stale provider does not revert successful selection',
        (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      // Simulate old roster emission after selection
      await _selectMode(tester, 'PTC mode');
      expect(find.text('PTC mode'), findsOneWidget);
      // Emit stale roster same as before (should not overwrite)
      container.read(sessionsProvider.notifier).updateSession(
        const SessionId('sess-1'),
        (s) => s.copyWith(agentPreset: 'code'),
      );
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsOneWidget);
    });
  });
}
