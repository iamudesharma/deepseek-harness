/// Locale propagation end-to-end: every user-visible string on the pumped
/// surfaces flows through the shared [LocaleService] dictionaries, so one
/// `setLocale` publish flips the hero chip, the sidebar chrome, and the
/// settings labels at once — and flips them back.
///
/// React contract under test (`packages/client/locale/src/client/index.ts`):
/// the Language row publishes the snapshot change through the activated
/// service, and every bound-dictionary consumer re-renders without a
/// restart. This harness pumps the REAL application (`DshApp` →
/// `buildAppHost` → `PluginHost.activateAll`) over a stubbed carrier, exactly
/// like `business_host_test.dart`.
library;

import 'package:dsh_flutter/main.dart' show DshApp;
import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart'
    show activeSlotsProvider;
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    show connectionClientProvider;
import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show LocaleService, localeServiceProvider;
import 'package:dsh_flutter/src/plugins/agent_preset/locales.dart';
import 'package:dsh_flutter/src/plugins/conversation/locales.dart';
import 'package:dsh_flutter/src/plugins/deliverables/locales.dart';
import 'package:dsh_flutter/src/plugins/goal/locales.dart';
import 'package:dsh_flutter/src/plugins/jobs/locales.dart';
import 'package:dsh_flutter/src/plugins/model_selection/locales.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/locales.dart';
import 'package:dsh_flutter/src/plugins/plan/locales.dart';
import 'package:dsh_flutter/src/plugins/settings/children/general/general_settings_plugin.dart';
import 'package:dsh_flutter/src/plugins/settings/children/models/models_settings_plugin.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugins/plugins_settings_plugin.dart';
import 'package:dsh_flutter/src/plugins/skill/locales.dart';
import 'package:dsh_flutter/src/plugins/subagent/locales.dart';
import 'package:dsh_flutter/src/plugins/user_questions/locales.dart';
import 'package:dsh_flutter/src/plugins/workflow_run/locales.dart';
import 'package:dsh_flutter/src/plugins/workspace/locales.dart';
import 'package:dsh_flutter/src/routing/app_router.dart' show appRouterProvider;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plugins/ws_input/host_fixture.dart' show WsInputRecordingClient;

/// Every namespace this pass touches must keep zh/en key parity — the
/// fallback chain reads either dictionary, so a missing key would silently
/// leak the other language's copy.
void main() {
  test('touched namespaces keep zh and en key sets identical', () {
    final pairs = <String, List<Map<String, String>>>{
      // The Dart shell folds React's separate `sidebar` chrome keys into
      // the workspace namespace (see workspace/locales.dart).
      'workspace': [kWorkspaceZh, kWorkspaceEn],
      'settings': [kSettingsZh, kSettingsEn],
      'models': [kModelsZh, kModelsEn],
      'plugins': [kPluginsZh, kPluginsEn],
      'inventory': [kInventoryZh, kInventoryEn],
      'settings.permission': [kPermissionSettingsZh, kPermissionSettingsEn],
      'permission.access': [kPermissionAccessZh, kPermissionAccessEn],
      'plan': [kPlanZh, kPlanEn],
      'skill': [kSkillZh, kSkillEn],
      'goal': [kGoalZh, kGoalEn],
      'deliverables': [kDeliverablesZh, kDeliverablesEn],
      'job': [kJobZh, kJobEn],
      'workflowRun': [kWorkflowRunZh, kWorkflowRunEn],
      'question': [kQuestionZh, kQuestionEn],
      'conversation': [kConversationZh, kConversationEn],
      'model': [kModelZh, kModelEn],
      'subagent': [kSubagentZh, kSubagentEn],
      'settings.agentPreset': [kAgentPresetZh, kAgentPresetEn],
    };
    for (final entry in pairs.entries) {
      expect(
        entry.value[0].keys.toSet(),
        entry.value[1].keys.toSet(),
        reason: '${entry.key}: zh and en key sets must match',
      );
    }
  });

  test('bind falls back entry namespace → common vocabulary → key itself', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final LocaleService service = container.read(localeServiceProvider);
    final t = service.bind('some.unregistered.namespace');
    // Unknown key everywhere falls back to the key itself.
    expect(t('totally.missing'), 'totally.missing');
    // Unknown key in the entry namespace but present in the shared
    // vocabulary resolves through the common fallback step.
    expect(t('cancel'), '取消');
    service.setLocale('en');
    expect(t('cancel'), 'Cancel');
  });

  testWidgets('one setLocale publish flips hero chip, sidebar, and settings copy '
      'immediately, and flips them back (desktop 1440)', (tester) async {
    final TargetPlatform? prev = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = prev);
    try {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final client = WsInputRecordingClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionClientProvider.overrideWithValue(client)],
          child: const DshApp(),
        ),
      );

      final element = tester.element(find.byType(DshApp));
      final container = ProviderScope.containerOf(element);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (container.read(activeSlotsProvider) != null) break;
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        container.read(activeSlotsProvider),
        isNotNull,
        reason: 'host activation completed',
      );

      // Service default drives the whole shell before any preference lands.
      expect(container.read(localeServiceProvider).locale, 'zh');

      // Hero + sidebar render their dictionary copy.
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('工作区'),
        findsWidgets,
        reason: 'hero picker chip label (workspace.section.workspaces)',
      );
      expect(
        find.text('新建会话'),
        findsOneWidget,
        reason: 'New session button (sidebar.session.new.label)',
      );

      // Settings surface: same shell, other route — navigation rides the app's
      // own router, like the sidebar's Settings link.
      await _navigate(tester, container, '/settings');
      expect(
        find.text('语言'),
        findsOneWidget,
        reason: 'Language row title (settings.locale.language.title)',
      );
      expect(
        find.text('通用'),
        findsWidgets,
        reason: 'General tab (settings.general.nav)',
      );
      expect(
        find.text('繁忙时 Enter 键行为'),
        findsOneWidget,
        reason: 'Enter-behavior row (conversation.settings.enter.title)',
      );

      // THE FLIP — the exact publish path LanguageRow.setLocale uses:
      // LocaleService.setLocale, no restart, no re-activation.
      container.read(localeServiceProvider).setLocale('en');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Language'), findsOneWidget);
      expect(find.text('General'), findsWidgets);
      expect(find.text('Enter behavior while busy'), findsOneWidget);

      // Back to the hero: chip + sidebar switched too.
      await _navigate(tester, container, '/');
      expect(find.text('Workspaces'), findsWidgets);
      expect(find.text('New session'), findsOneWidget);

      // FLIP BACK — restore matches the initial state.
      container.read(localeServiceProvider).setLocale('zh');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('工作区'), findsWidgets);
      expect(find.text('新建会话'), findsOneWidget);

      await _navigate(tester, container, '/settings');
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('通用'), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = prev;
    }
  });

  testWidgets('locale flip also works in mobile shell (390 width)', (
    tester,
  ) async {
    final TargetPlatform? prev = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = prev);
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final client = WsInputRecordingClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionClientProvider.overrideWithValue(client)],
          child: const DshApp(),
        ),
      );

      final element = tester.element(find.byType(DshApp));
      final container = ProviderScope.containerOf(element);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (container.read(activeSlotsProvider) != null) break;
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(container.read(activeSlotsProvider), isNotNull);

      await tester.pump(const Duration(milliseconds: 50));
      // Mobile: hero chip still locale-sensitive, sidebar button hidden behind mobile shell.
      expect(find.text('工作区'), findsWidgets);
      // Desktop-only sidebar element must NOT appear in mobile shell.
      expect(find.text('新建会话'), findsNothing);

      container.read(localeServiceProvider).setLocale('en');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Workspaces'), findsWidgets);
      expect(find.text('New session'), findsNothing);

      container.read(localeServiceProvider).setLocale('zh');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('工作区'), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = prev;
    }
  });
}

Future<void> _navigate(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  container.read(appRouterProvider).go(location);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}
