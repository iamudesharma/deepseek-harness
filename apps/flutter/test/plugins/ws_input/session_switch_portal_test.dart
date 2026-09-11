/// Session-switch portal-lifetime probe: opening the trigger menu, then
/// switching the composer to a fresh session (the sidebar "+" flow) must
/// never trip `OverlayPortal`'s attach-target assertion, whether the state
/// is reused across the switch or torn down with the old session.
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/conversation_plugin.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/composer.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_shortcuts.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_plugin.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

/// Scripted `/` source: canned candidates, TextOutcome picks.
class _SwitchFakeSource extends InputTriggerSource {
  @override
  String get trigger => '/';

  @override
  String get name => 'command';

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async =>
      const [InputTriggerCandidate(name: 'plan', description: 'Plan mode')];

  @override
  PickOutcome? onPick(InputTriggerPick pick) =>
      TextOutcome('/${pick.candidate.name} ');
}

/// No-op settings face for the conversation plugin's policy scope.
class _NoopFace implements SettingsFace {
  @override
  Future<Map<String, Object?>> describe() async => const {};

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) async =>
      const {};
}

void main() {
  late TriggerSourceRegistry registry;

  setUp(() async {
    final client = WsInputRecordingClient();
    final host = PluginHost();
    host.provide('slots', host.slots);
    host.provide('connection', client);
    host.provide('sessions', SessionsService(client));
    host.provide('workspaces', WorkspacesService(client));
    host.provide('locale', LocaleService());
    host.provide('remote', RemoteEventBus());
    host.provide(
      'settingsScope',
      SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-conversation'),
    );
    host.slots.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'layout.center': SlotSpec(
            kind: SlotKind.single,
            scope: SlotScope.root,
          ),
        },
      ),
      (BuildContext context, dynamic props) => const SizedBox.shrink(),
    );
    host.register(ConversationPlugin());
    host.register(const InputTriggerPlugin());
    await host.activateAll();
    addTearDown(host.deactivateAll);
    registry = activatedRegistry!;
    registry.registerSource(_SwitchFakeSource());
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required String sessionId,
    required TextEditingController field,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () {},
              child: ConversationComposer(
                sessionId: sessionId,
                controller: field,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void seedSession(WidgetTester tester, String sid) {
    final context = tester.element(find.byType(Scaffold));
    final container = ProviderScope.containerOf(context);
    container.read(sessionsProvider.notifier).addSession(
          SessionSummary(
            sessionId: SessionId(sid),
            updatedAt: 0,
            running: false,
            blank: false,
          ),
        );
    container.read(sessionsProvider.notifier).setCurrent(SessionId(sid));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('plan'), findsOneWidget);
  }

  testWidgets('menu open across a same-composer session switch', (
    tester,
  ) async {
    final field = TextEditingController();
    await pumpComposer(tester, sessionId: 's-a', field: field);
    await tester.pumpAndSettle();
    seedSession(tester, 's-a');
    await tester.pump();
    await openMenu(tester);

    // Sidebar "+": fresh session becomes current; the composer widget takes
    // the new session id (state reuse path).
    seedSession(tester, 's-b');
    await tester.pump();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () {},
              child: ConversationComposer(
                sessionId: 's-b',
                controller: field,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu open across composer unmount', (tester) async {
    final field = TextEditingController();
    await pumpComposer(tester, sessionId: 's-a', field: field);
    await tester.pumpAndSettle();
    seedSession(tester, 's-a');
    await tester.pump();
    await openMenu(tester);

    // Whole subtree goes away (route pop / phase teardown) with the menu up.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
