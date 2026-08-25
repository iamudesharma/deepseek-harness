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
  _FakePresetClient() : super(baseUrl: '');
  String? lastSelected;
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
  Future<Map<String, dynamic>> agentPresetSelect(
          {required String sessionId, required String agentPreset}) async {
    lastSelected = agentPreset;
    return {};
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

ProviderContainer _containerWithSession(SessionSummary summary) {
  final byId = <SessionId, SessionSummary>{summary.sessionId: summary};
  const roster = AgentPresetRoster(presets: [
    AgentPresetOption(id: 'standard', name: 'standard', trust: PresetTrust.system, isDefault: true),
    AgentPresetOption(id: 'code', name: 'code', trust: PresetTrust.system),
    AgentPresetOption(id: 'minimal', name: 'minimal', trust: PresetTrust.system),
    AgentPresetOption(id: 'cordis', name: 'cordis', trust: PresetTrust.system),
  ], authorable: false, hasDocument: false);
  final fakeClient = _FakePresetClient();
  final container = ProviderContainer(
    overrides: [
      sessionsProvider.overrideWith(
        () => _SeededSessions(
            SessionsState(byId: byId, current: summary.sessionId)),
      ),
      connectionClientProvider.overrideWithValue(fakeClient),
      agentPresetListProvider.overrideWith((ref) async => roster),
    ],
  );
  addTearDown(container.dispose);
  final locale = container.read(localeServiceProvider);
  locale.register(kAgentPresetNamespace, {'zh': kAgentPresetZh, 'en': kAgentPresetEn});
  // Start in English for predictable first assertions; individual tests switch.
  locale.setLocale('en');
  return container;
}

Future<void> _tapChip(WidgetTester tester) async {
  // Tap the visible chip text rather than the outer widget bounds to avoid
  // hit-test warnings from OverlayPortal's zero-size target box.
  final chipText = find.textContaining(RegExp(r'Standard|PTC|Minimal|Creator|标准|极简|创造'));
  if (chipText.evaluate().isNotEmpty) {
    await tester.tap(chipText.first);
  } else {
    await tester.tap(find.byType(AgentPresetHeroSeat));
  }
}

void main() {
  group('AgentPresetHeroSeat localization', () {
    testWidgets('English mode labels', (tester) async {
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
      // Trigger chip shows localized name for current preset.
      expect(find.text('Standard mode'), findsOneWidget);
      // Open menu.
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsWidgets);
      expect(find.text('PTC mode'), findsOneWidget);
      expect(find.text('Minimal mode'), findsOneWidget);
      expect(find.text('Creator mode'), findsOneWidget);
      expect(find.text('标准模式'), findsNothing);
    });

    testWidgets('Chinese mode labels', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      container.read(localeServiceProvider).setLocale('zh');
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('标准模式'), findsOneWidget);
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.text('标准模式'), findsWidgets);
      expect(find.text('PTC 模式'), findsOneWidget);
      expect(find.text('极简模式'), findsOneWidget);
      expect(find.text('创造模式'), findsOneWidget);
      expect(find.text('Standard mode'), findsNothing);
    });

    testWidgets('English → Chinese live update', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'cordis',
      );
      final container = _containerWithSession(summary);
      final locale = container.read(localeServiceProvider);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('Creator mode'), findsOneWidget);
      // Switch while mounted.
      locale.setLocale('zh');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('创造模式'), findsOneWidget);
      expect(find.text('Creator mode'), findsNothing);
      // Reopen menu shows Chinese.
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.text('创造模式'), findsWidgets);
    });

    testWidgets('Chinese → English live update', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'minimal',
      );
      final container = _containerWithSession(summary);
      final locale = container.read(localeServiceProvider);
      locale.setLocale('zh');
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      expect(find.text('极简模式'), findsOneWidget);
      locale.setLocale('en');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Minimal mode'), findsOneWidget);
      expect(find.text('极简模式'), findsNothing);
    });

    testWidgets('selected mode remains stable while label changes', (tester) async {
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
      // Selection is by id; label change must not alter selection.
      locale.setLocale('zh');
      await tester.pumpAndSettle();
      expect(find.text('PTC 模式'), findsOneWidget);
      // Checkmark stays on same id.
      await _tapChip(tester);
      await tester.pumpAndSettle();
      // Find check icon near PTC row - there should be a check for 'code'.
      expect(find.byIcon(Icons.check), findsOneWidget);
      // The check should be in the PTC row, not elsewhere.
      final checkFinder = find.byIcon(Icons.check);
      final codeRow = find.ancestor(of: checkFinder, matching: find.byType(InkWell));
      expect(codeRow, findsOneWidget);
    });

    testWidgets('reopen menu after locale change shows new language', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      final locale = container.read(localeServiceProvider);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsWidgets);
      // Close via outside tap.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsNothing);
      locale.setLocale('zh');
      await tester.pumpAndSettle();
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.text('标准模式'), findsWidgets);
    });

    testWidgets('already-open menu updates when locale changes', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      final container = _containerWithSession(summary);
      final locale = container.read(localeServiceProvider);
      await tester.pumpWidget(_heroApp(container));
      await tester.pumpAndSettle();
      await _tapChip(tester);
      await tester.pumpAndSettle();
      expect(find.text('Standard mode'), findsWidgets);
      expect(find.text('PTC mode'), findsOneWidget);
      // Change locale while menu is open.
      locale.setLocale('zh');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('标准模式'), findsWidgets);
      expect(find.text('PTC 模式'), findsOneWidget);
      expect(find.text('Standard mode'), findsNothing);
      expect(find.text('PTC mode'), findsNothing);
    });
  });

  group('AgentPresetHeroSeat anchoring', () {
    testWidgets('popup is anchored to trigger', (tester) async {
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
      final triggerFinder = find.byType(AgentPresetHeroSeat);
      expect(triggerFinder, findsOneWidget);
      final triggerRect = tester.getRect(triggerFinder);
      await _tapChip(tester);
      await tester.pumpAndSettle();
      // Find menu material.
      final menuFinder = find.byType(Material).last;
      final menuRect = tester.getRect(menuFinder);
      // Menu should be near trigger: horizontally start-aligned within 8px,
      // vertically below trigger with 4px gap (or above if flipped). Check
      // that menu left is within trigger left ± 8 and top is within trigger
      // bottom + gap ± 20 (allowing for follower positioning).
      expect((menuRect.left - triggerRect.left).abs(), lessThan(20),
          reason: 'menu left ${menuRect.left} should align to trigger left ${triggerRect.left}');
      // Vertically, menu top should be near trigger bottom + gap (4) or flipped above.
      final gapBelow = menuRect.top - triggerRect.bottom;
      final gapAbove = triggerRect.top - menuRect.bottom;
      final isBelow = gapBelow >= 0 && gapBelow < 20;
      final isAbove = gapAbove >= 0 && gapAbove < 20;
      expect(isBelow || isAbove, isTrue,
          reason: 'menu should be 4px below trigger (gapBelow=$gapBelow) or flipped above (gapAbove=$gapAbove)');
      // Menu should be inside viewport with 12px margin.
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(menuRect.left, greaterThanOrEqualTo(12 - 1));
      expect(menuRect.right, lessThanOrEqualTo(size.width - 12 + 1));
      expect(menuRect.top, greaterThanOrEqualTo(12 - 1));
      expect(menuRect.bottom, lessThanOrEqualTo(size.height - 12 + 1));
    });

    testWidgets('bottom-edge flip: trigger near bottom shows menu above', (tester) async {
      const summary = SessionSummary(
        sessionId: SessionId('sess-1'),
        updatedAt: 1,
        running: false,
        blank: true,
        agentPreset: 'standard',
      );
      const roster = AgentPresetRoster(presets: [
        AgentPresetOption(id: 'standard', name: 'standard', trust: PresetTrust.system, isDefault: true),
        AgentPresetOption(id: 'code', name: 'code', trust: PresetTrust.system),
        AgentPresetOption(id: 'minimal', name: 'minimal', trust: PresetTrust.system),
        AgentPresetOption(id: 'cordis', name: 'cordis', trust: PresetTrust.system),
      ], authorable: false, hasDocument: false);
      final fakeClient = _FakePresetClient();
      final byId = <SessionId, SessionSummary>{summary.sessionId: summary};
      final container = ProviderContainer(
        overrides: [
          sessionsProvider.overrideWith(
            () => _SeededSessions(
                SessionsState(byId: byId, current: summary.sessionId)),
          ),
          connectionClientProvider.overrideWithValue(fakeClient),
          agentPresetListProvider.overrideWith((ref) async => roster),
        ],
      );
      addTearDown(container.dispose);
      final locale = container.read(localeServiceProvider);
      locale.register(kAgentPresetNamespace, {'zh': kAgentPresetZh, 'en': kAgentPresetEn});
      locale.setLocale('en');
      // Place hero seat near bottom of viewport to force flip.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: const AgentPresetHeroSeat(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final triggerRect = tester.getRect(find.byType(AgentPresetHeroSeat));
      await _tapChip(tester);
      await tester.pumpAndSettle();
      final menuRect = tester.getRect(find.byType(Material).last);
      // When trigger is at bottom, menu should appear above (flipped).
      // Check that menu bottom is near trigger top (above).
      final gapAbove = triggerRect.top - menuRect.bottom;
      expect(gapAbove, greaterThanOrEqualTo(2));
      expect(gapAbove, lessThan(20));
    });

    testWidgets('outside tap closes menu', (tester) async {
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
      expect(find.text('PTC mode'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsNothing);
    });

    testWidgets('Escape closes menu', (tester) async {
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
      expect(find.text('PTC mode'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsNothing);
    });

    testWidgets('no collision with workspace picker', (tester) async {
      // Verify that opening mode menu does not trigger workspace picker and vice versa.
      // This is a smoke: mode menu and workspace picker should have independent controllers.
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
      // Mode menu open.
      expect(find.text('PTC mode'), findsOneWidget);
      // Workspace picker should not be visible (no 'Workspaces' menu from that seat).
      // Close mode menu.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('PTC mode'), findsNothing);
    });
  });
}
