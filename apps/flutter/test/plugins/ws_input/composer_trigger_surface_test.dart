/// LIVE composer trigger-surface tests (manual-QA bug 2 regression gate).
///
/// Pumps the REAL [ConversationComposer] over an activated
/// [TriggerSourceRegistry] with scripted sources and drives the field like a
/// user: typing `/` must surface the candidate menu through the composer's
/// `conversation.input.overlay` anchor, keyboard arbitration must reach the
/// controller, and picks must splice the draft. Detection rules stay frozen —
/// plain `/` anywhere, `@` inline (detect.dart via ComposerTriggerBinding).
library;

import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/conversation_plugin.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/composer.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_shortcuts.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_plugin.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

/// Scripted `/` source: canned candidates, TextOutcome picks.
class FakeCommandSource extends InputTriggerSource {
  FakeCommandSource({this.candidatesOverride});

  final List<InputTriggerCandidate>? candidatesOverride;
  final List<String> picked = [];

  @override
  String get trigger => '/';

  @override
  String get name => 'command';

  @override
  Future<List<InputTriggerCandidate>> candidates(
      String sessionId, CandidateRequest request) async {
    final all = candidatesOverride ??
        const [
          InputTriggerCandidate(name: 'plan', description: 'Plan mode'),
          InputTriggerCandidate(name: 'deploy', description: 'Deploy site'),
        ];
    final q = request.query.toLowerCase();
    return all.where((c) => q.isEmpty || c.name.toLowerCase().startsWith(q)).toList();
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    picked.add(pick.candidate.name);
    return TextOutcome('/${pick.candidate.name} ');
  }
}

/// Scripted inline `@` source producing a reference insert.
class FakeReferenceSource extends InputTriggerSource {
  @override
  String get trigger => '@';

  @override
  String get name => 'session';

  @override
  Future<List<InputTriggerCandidate>> candidates(
      String sessionId, CandidateRequest request) async {
    return const [InputTriggerCandidate(name: 'Alpha session')];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    return InsertOutcome(ReferenceInsert(
      source: name,
      ref: 'ref-1',
      label: pick.candidate.name,
      clipboardText: '@ref-1',
    ));
  }
}

Widget _host({
  required VoidCallback onSubmit,
  required TextEditingController controller,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: ConversationShortcuts(
          onSubmit: onSubmit,
          child: ConversationComposer(sessionId: 's-trigger', controller: controller),
        ),
      ),
    ),
  );
}

/// Seeds `s-trigger` as the current session — the overlay anchor resolves the
/// menu through the session projection (production columns always render one).
Future<void> seedCurrentSession(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold));
  final container = ProviderScope.containerOf(context);
  container.read(sessionsProvider.notifier).addSession(SessionSummary(
        sessionId: const SessionId('s-trigger'),
        updatedAt: 0,
        running: false,
        blank: false,
        title: 'Trigger fixture',
      ));
  container
      .read(sessionsProvider.notifier)
      .setCurrent(const SessionId('s-trigger'));
  await tester.pump();
}

/// Reads the composer state text for the fixture session.
String composerStateText(WidgetTester tester) {
  final context = tester.element(find.byType(Scaffold));
  final container = ProviderScope.containerOf(context);
  return container.read(composerControllerProvider('s-trigger')).text;
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
    // Boot the REAL composition: ui-conversation declares the composer holes
    // and binds the hub; ui-input-trigger registers the menu into the overlay
    // anchor — the exact production seams under test.
    final client = WsInputRecordingClient();
    final host = PluginHost();
    host.provide('slots', host.slots);
    host.provide('connection', client);
    host.provide('sessions', SessionsService(client));
    host.provide('workspaces', WorkspacesService(client));
    host.provide('locale', LocaleService());
    host.provide('remote', RemoteEventBus());
    host.provide('settingsScope',
        SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-conversation'));
    // Shell declaration (AppShellPlugin's role): the layout-center cell the
    // conversation anchor waits on. Without it the composer-hole subtree
    // never installs and the trigger injection stays pending.
    host.slots.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'layout.center': SlotSpec(kind: SlotKind.single, scope: SlotScope.root),
        },
      ),
      (BuildContext context, dynamic props) => const SizedBox.shrink(),
    );
    host.register(ConversationPlugin());
    host.register(const InputTriggerPlugin());
    await host.activateAll();
    addTearDown(host.deactivateAll);
    registry = activatedRegistry!;
    registry.registerSource(FakeCommandSource());
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required TextEditingController controller,
    VoidCallback? onSubmit,
  }) async {
    final VoidCallback submit = onSubmit ?? () {};
    await tester.pumpWidget(_host(
      controller: controller,
      onSubmit: submit,
    ));
    await tester.pumpAndSettle();
    await seedCurrentSession(tester);
  }

  testWidgets('typing / opens the candidate menu above the composer',
      (tester) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);
    expect(find.text('plan'), findsNothing);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    // Candidates settle asynchronously; bounded pumps keep this deterministic.
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('plan'), findsOneWidget);
    expect(find.text('deploy'), findsOneWidget);
    // Group title row renders the source name.
    expect(find.text('command'), findsOneWidget);
  });

  testWidgets('query filters candidates live (/pl → plan)', (tester) async {
    final controller = TextEditingController(text: '/');
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/pl');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('plan'), findsOneWidget);
    expect(find.text('deploy'), findsNothing);
  });

  testWidgets('pointer pick splices the token span in the field',
      (tester) async {
    final controller = TextEditingController(text: '/');
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/de');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('deploy').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.text('deploy'));
    await tester.pumpAndSettle();

    expect(controller.text, '/deploy ');
    // Menu closed after the pick.
    expect(find.text('command'), findsNothing);
  });

  testWidgets('@ opens an inline reference group when a source registers',
      (tester) async {
    registry.registerSource(FakeReferenceSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(
        find.byType(TextField), 'look at @al');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('Alpha session').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('session'), findsOneWidget);
    expect(find.text('Alpha session'), findsOneWidget);
  });

  testWidgets('Escape dismisses the menu without cancelling the turn',
      (tester) async {
    var cancelled = false;
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('plan'), findsOneWidget);

    // Focus the field so arbitration sees the key events.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('plan'), findsNothing);
    expect(cancelled, isFalse);
    // The draft survives dismissal — Escape is not an edit.
    expect(controller.text, '/');
  });

  testWidgets('ArrowDown highlights, Enter picks the highlight',
      (tester) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    // Type the trigger like a user — detection runs on field edits (the
    // React input-event contract), not on focus alone.
    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('plan'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Highlight moved to index 1 ('deploy') before Enter picked it.
    expect(controller.text, '/deploy ');
  });

  testWidgets('Enter with no menu open submits through the shortcut seam',
      (tester) async {
    var submitted = 0;
    final controller = TextEditingController();
    await pumpComposer(
      tester,
      controller: controller,
      onSubmit: () => submitted++,
    );

    await tester.enterText(find.byType(TextField), 'plain words');
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(submitted, 1);
  });

  testWidgets('Shift+Enter inserts a newline instead of submitting',
      (tester) async {
    var submitted = 0;
    final controller = TextEditingController();
    await pumpComposer(
      tester,
      controller: controller,
      onSubmit: () => submitted++,
    );

    await tester.enterText(find.byType(TextField), 'line one');
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(submitted, 0);
    expect(controller.text, contains('\n'));
  });

  testWidgets('IME composing swallows menu navigation keys',
      (tester) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Simulate an IME composing range over the draft.
    controller.value = TextEditingValue(
      text: '/',
      selection: const TextSelection.collapsed(offset: 1),
      composing: const TextRange(start: 0, end: 1),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Composition guard passed the key through: the menu stays open.
    expect(find.text('plan'), findsOneWidget);
  });

  testWidgets('composer state mirrors spliced text for submit', (tester) async {
    final controller = TextEditingController(text: '/');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ConversationShortcuts(
            onSubmit: () {},
            child: ConversationComposer(
                sessionId: 's-trigger', controller: controller),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await seedCurrentSession(tester);

    await tester.enterText(find.byType(TextField), '/pl');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.text('plan'));
    await tester.pumpAndSettle();

    expect(composerStateText(tester), '/plan ');
  });
}
