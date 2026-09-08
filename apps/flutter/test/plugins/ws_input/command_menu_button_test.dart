/// `+` command-menu trigger tests — the composer button opens the Host
/// command catalog over the shared overlay without touching the draft.
library;

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

/// Scripted `/` source named exactly like production's command group.
class PlusFakeCommandSource extends InputTriggerSource {
  final List<String> picked = [];

  @override
  TriggerChar get trigger => '/';

  @override
  String get name => 'command';

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async {
    return const [
      InputTriggerCandidate(name: 'compact', description: 'Compact history'),
      InputTriggerCandidate(name: 'model', description: 'Select model'),
    ];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    picked.add(pick.candidate.name);
    return TextOutcome('/${pick.candidate.name} ');
  }

  @override
  void warm(String sessionId) {}
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
  }) async => const {};
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
    registry.registerSource(PlusFakeCommandSource());
  });

  Future<TextEditingController> pumpComposer(WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () {},
              child: ConversationComposer(
                sessionId: 's-plus',
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    final container = ProviderScope.containerOf(context);
    container
        .read(sessionsProvider.notifier)
        .addSession(
          SessionSummary(
            sessionId: const SessionId('s-plus'),
            updatedAt: 0,
            running: false,
            blank: false,
            title: 'Plus fixture',
          ),
        );
    container
        .read(sessionsProvider.notifier)
        .setCurrent(const SessionId('s-plus'));
    await tester.pump();
    return controller;
  }

  Future<void> settleMenu(WidgetTester tester, String text) async {
    for (var i = 0; i < 20 && find.text(text).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('plus button opens the full command catalog', (tester) async {
    final field = await pumpComposer(tester);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('compact'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await settleMenu(tester, 'compact');

    expect(find.text('compact'), findsOneWidget);
    expect(find.text('model'), findsOneWidget);
    expect(find.text('Compact history'), findsOneWidget);
    // The launcher never mutates the draft (React toggleSource parity).
    expect(field.text, isEmpty);
  });

  testWidgets('plus button toggles the open menu closed', (tester) async {
    await pumpComposer(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await settleMenu(tester, 'compact');
    expect(find.text('compact'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('compact'), findsNothing);
  });

  testWidgets('menu pick splices the command token', (tester) async {
    final field = await pumpComposer(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await settleMenu(tester, 'compact');

    await tester.tap(find.text('compact'));
    await tester.pumpAndSettle();
    expect(field.text, '/compact ');
    expect(find.text('model'), findsNothing);
  });

  testWidgets('plus menu is disabled while sending is impossible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () {},
              child: ConversationComposer(
                sessionId: 's-plus',
                controller: TextEditingController(),
                enabled: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
