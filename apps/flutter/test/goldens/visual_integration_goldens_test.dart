/// Visual-integration goldens (manual-QA visual pass regression gate).
///
/// Pins the composed surfaces fixed in the 2026-08-28 visual pass:
/// the blank-session hero shell (hero chrome + workspace row + agent-preset
/// seat + resident composer as ONE centered stack), the composer tool row
/// carrying access + plan + model + send inside the card, and the `/`
/// trigger menu anchored to the composer card's top edge.
library;

import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart' as conn;
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/column.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/permission_session_provider.dart';
import 'package:dsh_flutter/src/plugins/plan/ui/plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String qaSession = 's-golden';

class GoldenClient extends conn.ConnectionClient {
  GoldenClient() : super(baseUrl: 'http://qa-host');

  @override
  Future<Map<String, dynamic>> callMethod(
      String method, Map<String, dynamic> payload) async {
    if (method == 'commands/list' ||
        method == 'command.list' ||
        method == 'fileReferences/list' ||
        method == 'reference.list' ||
        method == 'sessionReferenceResolver/candidates' ||
        method == 'sessionReferenceResolver.candidates') {
      return const <String, dynamic>{
        'commands': [
          {'name': 'plan', 'description': 'Plan mode'},
        ],
      };
    }
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> skillList({required String sessionId}) async {
    return const <String, dynamic>{'skills': <Object?>[]};
  }

  @override
  Future<Map<String, dynamic>> agentPresetList() async {
    return const <String, dynamic>{
      'presets': [
        {'id': 'standard', 'name': 'Standard mode', 'trust': 'system', 'isDefault': true},
      ],
      'authorable': false,
    };
  }

  @override
  Future<Map<String, dynamic>> sessionModels(
      {required String sessionId}) async {
    return const <String, dynamic>{
      'groups': [
        {
          'id': 'deepseek',
          'name': 'DeepSeek',
          'models': [
            {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
          ],
        },
      ],
      'routable': true,
    };
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool blank,
}) async {
  final container = ProviderContainer(
    overrides: [
      // Plugins resolve the carrier through this provider; serve the
      // scripted double so catalog warmups never touch the network.
      conn.connectionClientProvider.overrideWithValue(GoldenClient()),
    ],
  );
  addTearDown(container.dispose);

  PluginHost? host;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(builder: (context, ref, _) {
      host ??= buildAppHost(ref);
      return const SizedBox.shrink();
    }),
  ));
  await tester.pump();
  final PluginHost activeHost = host!;
  await activeHost.activateAll();
  addTearDown(activeHost.deactivateAll);

  container.read(sessionsProvider.notifier).addSession(SessionSummary(
        sessionId: const SessionId(qaSession),
        updatedAt: 0,
        running: false,
        blank: blank,
        title: 'Golden session',
      ));
  container.read(sessionsProvider.notifier).setCurrent(const SessionId(qaSession));
  // Seed the permission projection so the composer tool row always has its
  // access chip (blank hero never appears without it). Without this the
  // `PermissionSeat` would show its placeholder and the golden would drift.
  container.read(permissionSelectProvider(qaSession).notifier).state =
      const PermissionSelect(
    options: [PresetOption(value: 'workspace-write', name: 'workspace-write')],
    currentValue: 'workspace-write',
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const Scaffold(body: ConversationColumn(sessionId: qaSession)),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
}

void main() {
  testWidgets('blank-session hero shell', (tester) async {
    _setViewport(tester, const Size(1280, 800));
    await _pump(tester, blank: true);
    await expectLater(
      find.byType(ConversationColumn),
      matchesGoldenFile('goldens/composer_hero_shell.png'),
    );
  });

  testWidgets('composer tool row with access + plan + model + send',
      (tester) async {
    _setViewport(tester, const Size(1280, 800));
    final container = await _pump(tester, blank: false);
    // Surface both projection-fed seats.
    container.read(planProvider.notifier).enter();
    container.read(permissionSelectProvider(qaSession).notifier).state =
        const PermissionSelect(
      options: [PresetOption(value: 'default', name: 'Default')],
      currentValue: 'default',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConversationColumn),
      matchesGoldenFile('goldens/composer_tool_row.png'),
    );
  });

  testWidgets("slash menu anchored above the composer card", (tester) async {
    _setViewport(tester, const Size(1280, 800));
    await _pump(tester, blank: false);
    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    // Menu candidates settle asynchronously (command.list round-trip);
    // bounded pumps keep this deterministic.
    for (var i = 0;
        i < 20 && find.text('plan').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    // The menu mounts in the ROOT Overlay (above the navigator), so the
    // capture must span the whole app, not the column subtree.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/composer_slash_menu.png'),
    );
  });

  testWidgets('mode menu anchored to hero chip', (tester) async {
    _setViewport(tester, const Size(1280, 800));
    await _pump(tester, blank: true);
    // Open the mode menu via the hero chip. The chip label is the preset
    // name; tap it to show the portal-anchored menu.
    final chipFinder = find.text('Standard mode');
    // Fallback to hero seat type if text not found due to locale timing.
    final target = chipFinder.evaluate().isNotEmpty ? chipFinder : find.byType(ConversationColumn);
    await tester.tap(target.first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/mode_menu.png'),
    );
  });
}
