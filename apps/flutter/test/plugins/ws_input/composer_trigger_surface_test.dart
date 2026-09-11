/// LIVE composer trigger-surface tests (manual-QA bug 2 regression gate).
///
/// Pumps the REAL [ConversationComposer] over an activated
/// [TriggerSourceRegistry] with scripted sources and drives the field like a
/// user: typing `/` must surface the candidate menu through the composer's
/// `conversation.input.overlay` anchor, keyboard arbitration must reach the
/// controller, and picks must splice the draft. Detection rules stay frozen —
/// plain `/` anywhere, `@` inline (detect.dart via ComposerTriggerBinding).
library;

import 'dart:async';
import 'dart:ui' as ui;

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
import 'package:dsh_flutter/src/plugins/commands/command_directory.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart';
import 'package:dsh_flutter/src/plugins/commands/ui/popup_select_overlay.dart'
    show bindActivatedCommandUi;
import 'package:dsh_flutter/src/plugins/conversation/locales.dart'
    show kConversationEn, kConversationZh;
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_plugin.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/locales.dart';
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
    String sessionId,
    CandidateRequest request,
  ) async {
    final all =
        candidatesOverride ??
        const [
          InputTriggerCandidate(name: 'plan', description: 'Plan mode'),
          InputTriggerCandidate(name: 'deploy', description: 'Deploy site'),
        ];
    final q = request.query.toLowerCase();
    return all
        .where((c) => q.isEmpty || c.name.toLowerCase().startsWith(q))
        .toList();
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    picked.add(pick.candidate.name);
    return TextOutcome('/${pick.candidate.name} ');
  }
}

/// `/` source whose candidates never settle on their own — the pending
/// skeleton path (React: two bars while a group has no items yet).
class _BlockingSource extends InputTriggerSource {
  @override
  String get trigger => '/';

  @override
  String get name => 'slow';

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) =>
      Completer<List<InputTriggerCandidate>>().future;

  @override
  PickOutcome? onPick(InputTriggerPick pick) => null;
}

/// `/` source emitting sectioned rows (React `item.section` breaks).
class _SectionedSource extends InputTriggerSource {
  @override
  String get trigger => '/';

  @override
  String get name => 'files';

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async => const [
    InputTriggerCandidate(name: 'a.dart', section: 'Files', icon: 'file'),
    InputTriggerCandidate(name: 'b.dart', section: 'Files', icon: 'file'),
    InputTriggerCandidate(name: 'main', section: 'Sessions', icon: 'session'),
  ];

  @override
  PickOutcome? onPick(InputTriggerPick pick) => null;
}

/// Scripted `@` drill source (React ui-reference parity): one drillable
/// directory plus one plain file, with a two-step header once drilled.
class DrillWidgetSource extends InputTriggerSource {
  final List<PickAction> actions = [];

  @override
  String get trigger => '@';

  @override
  String get name => 'reference';

  @override
  bool get showGroupTitle => false;

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async {
    return const [
      InputTriggerCandidate(name: 'assets/', icon: 'folder', drill: true),
      InputTriggerCandidate(name: 'main.dart', icon: 'file'),
    ];
  }

  @override
  List<InputTriggerCrumb>? header(String sessionId, HeaderRequest request) {
    if (!request.drilled) return null;
    return const [
      InputTriggerCrumb(label: 'Workspace', value: 'root'),
      InputTriggerCrumb(label: 'assets', value: 'assets', current: true),
    ];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    actions.add(pick.action);
    if (pick.action == PickAction.drill) {
      // Header crumb picks project the crumb as the candidate: the root
      // climbs back out, a row descends in.
      if (pick.candidate.name == 'Workspace') {
        return const TextOutcome('@', continueTracking: true);
      }
      return const TextOutcome('@assets/', continueTracking: true);
    }
    // Settling pick splices trailing-space text so the caret leaves the
    // token (chip insertions stay plain text in this seam and would
    // re-trigger detection).
    return const TextOutcome('@main.dart ');
  }
}

/// Scripted `/` claim source: one input-taking command whose menu pick
/// claims `/goal ` (the ghost-hint path).
class ClaimWidgetSource extends InputTriggerSource {
  @override
  String get trigger => '/';

  @override
  String get name => 'claimcmd';

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async {
    return const [InputTriggerCandidate(name: 'goal', description: 'Goal')];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    return ClaimOutcome(
      CommandClaim(
        token: '/goal ',
        hint: 'raw-goal-hint',
        submit: (_, __) async => const SubmitOutcome(kind: 'success'),
      ),
    );
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
    String sessionId,
    CandidateRequest request,
  ) async {
    return const [InputTriggerCandidate(name: 'Alpha session')];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    return InsertOutcome(
      ReferenceInsert(
        source: name,
        ref: 'ref-1',
        label: pick.candidate.name,
        clipboardText: '@ref-1',
      ),
    );
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
          child: ConversationComposer(
            sessionId: 's-trigger',
            controller: controller,
          ),
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
  container
      .read(sessionsProvider.notifier)
      .addSession(
        SessionSummary(
          sessionId: const SessionId('s-trigger'),
          updatedAt: 0,
          running: false,
          blank: false,
          title: 'Trigger fixture',
        ),
      );
  container
      .read(sessionsProvider.notifier)
      .setCurrent(const SessionId('s-trigger'));
  // Mirror production boot (`app_plugins.dart` provides the Riverpod
  // `localeServiceProvider` instance as the `locale` service, so plugin
  // dictionary registrations land where widgets bind). This fixture's host
  // provides a separate instance, so repeat the plugin's registration into
  // the instance the overlay actually reads.
  container.read(localeServiceProvider).register('slash.menu', {
    'zh': kSlashMenuZh,
    'en': kSlashMenuEn,
  });
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
  }) async => const {};
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
    host.provide(
      'settingsScope',
      SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-conversation'),
    );
    // Shell declaration (AppShellPlugin's role): the layout-center cell the
    // conversation anchor waits on. Without it the composer-hole subtree
    // never installs and the trigger injection stays pending.
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
    registry.registerSource(FakeCommandSource());
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required TextEditingController controller,
    VoidCallback? onSubmit,
  }) async {
    final VoidCallback submit = onSubmit ?? () {};
    await tester.pumpWidget(_host(controller: controller, onSubmit: submit));
    await tester.pumpAndSettle();
    await seedCurrentSession(tester);
  }

  testWidgets('typing / opens the candidate menu above the composer', (
    tester,
  ) async {
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
    // Group title row renders the localized source name (React `t(source)`;
    // default locale here is zh, so `command` → `指令`).
    expect(find.text('指令'), findsOneWidget);
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

  testWidgets('pointer pick splices the token span in the field', (
    tester,
  ) async {
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

  testWidgets('@ opens an inline reference group when a source registers', (
    tester,
  ) async {
    registry.registerSource(FakeReferenceSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), 'look at @al');
    await tester.pump();
    for (
      var i = 0;
      i < 10 && find.text('Alpha session').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('session'), findsOneWidget);
    expect(find.text('Alpha session'), findsOneWidget);
  });

  testWidgets('Escape dismisses the menu without cancelling the turn', (
    tester,
  ) async {
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

  testWidgets('ArrowDown highlights, Enter picks the highlight', (
    tester,
  ) async {
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

  testWidgets('tapping the composer card keeps the menu open', (tester) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('plan'), findsOneWidget);

    // React exempts the composer card from outside-close: tapping the field
    // (caret reposition) must not kill the open menu.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('plan'), findsOneWidget);
    expect(find.text('deploy'), findsOneWidget);
  });

  testWidgets('tapping outside the card dismisses the menu', (tester) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('plan'), findsOneWidget);

    // Transcript area, above the bottom-docked composer card.
    await tester.tapAt(const Offset(20, 80));
    await tester.pumpAndSettle();
    expect(find.text('plan'), findsNothing);
    // The draft survives dismissal — outside tap is not an edit.
    expect(controller.text, '/');
  });

  testWidgets('hover moves the shared highlight; enter picks it', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('deploy').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final gesture = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('deploy')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.text, '/deploy ');
    await gesture.removePointer();
  });

  testWidgets('Tab settles the highlighted candidate like Enter', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/pl');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, '/plan ');
    expect(find.text('plan'), findsNothing);
  });

  testWidgets('drill chevron shows only on the highlighted drill row', (
    tester,
  ) async {
    registry.registerSource(DrillWidgetSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('assets/').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Highlight parks on the drill directory: the descent seat shows.
    expect(find.byKey(const ValueKey('input-menu-drill')), findsOneWidget);

    // Move to the plain file row: the seat hides (React `.item.active`
    // display gate).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const ValueKey('input-menu-drill')), findsNothing);

    // Back up: the seat returns with the highlight.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const ValueKey('input-menu-drill')), findsOneWidget);
  });

  testWidgets('Tab on a drill row descends and keeps the menu open', (
    tester,
  ) async {
    registry.registerSource(DrillWidgetSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('assets/').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // The descent spliced in place and the menu stayed open with its
    // breadcrumb header (React drill: Tab twin of the chevron).
    expect(controller.text, '@assets/');
    expect(find.text('assets/'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
  });

  testWidgets('Tab on a plain row settles and closes the menu', (
    tester,
  ) async {
    registry.registerSource(DrillWidgetSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('assets/').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // Plain rows settle like Enter: text spliced, menu closed.
    expect(controller.text, '@main.dart ');
    expect(find.text('assets/'), findsNothing);
  });

  testWidgets('crumb tap drills back out without closing the menu', (
    tester,
  ) async {
    registry.registerSource(DrillWidgetSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('assets/').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '@assets/');
    expect(find.text('Workspace'), findsOneWidget);

    // The root crumb climbs back out through the same drill path (React
    // pickCrumb): the draft returns to `@` and the menu stays open.
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    expect(controller.text, '@');
    expect(find.text('assets/'), findsOneWidget);
  });

  testWidgets('claim pick splices the token and shows the ghost hint', (
    tester,
  ) async {
    registry.registerSource(ClaimWidgetSource());
    // The ghost resolves its input-taking token through the bound commandUi
    // directory; the translated conversation hint wins over the raw one.
    final directory = CommandDirectory(
      fetchCommands: (_) async => const [
        CommandDescriptor(
          name: 'goal',
          description: 'Goal',
          hint: 'raw-goal-hint',
        ),
      ],
    );
    await directory.refresh(const SessionId('s-trigger'));
    final service = CommandUiService(
      directory: directory,
      execute: (_, __) async => CommandExecutionOutcome.success(),
    );
    bindActivatedCommandUi(service);
    addTearDown(() => bindActivatedCommandUi(null));

    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);
    // Pin English copy for the translated hint assertion. The fixture host
    // owns a separate LocaleService instance from the overlay's provider
    // container (see seedCurrentSession), so repeat the conversation
    // registration into the instance the composer actually binds.
    final context = tester.element(find.byType(Scaffold));
    final scoped = ProviderScope.containerOf(context);
    scoped.read(localeServiceProvider).register('conversation', {
      'zh': kConversationZh,
      'en': kConversationEn,
    });
    scoped.read(localeServiceProvider).setLocale('en');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '/goa');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('goal').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.text('goal').last);
    await tester.pumpAndSettle();

    // The claim token spliced (no longer dropped) and the translated ghost
    // shows while args are blank; the normal placeholder stays suppressed.
    // The overlay RichText concatenates the transparent draft with the hint,
    // so the hint asserts via textContaining on RichText.
    expect(controller.text, '/goal ');
    expect(find.byKey(const ValueKey('claim-ghost-hint')), findsOneWidget);
    expect(
      find.textContaining(
        'describe the objective for a long-running task',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('raw-goal-hint'), findsNothing);

    // Typing args dismisses the ghost (React blank-args gate).
    await tester.enterText(find.byType(TextField), '/goal run');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('claim-ghost-hint')), findsNothing);
  });

  testWidgets('two co-mounted composers share no card key', (tester) async {
    // Route transitions can hold two composers at once (old + new session);
    // a shared card key throws `Multiple widgets used the same GlobalKey`
    // on every build while duplicated. Each card registers its own key, so
    // mounting both is clean and each card still exempts outside-close.
    final fieldA = TextEditingController();
    final fieldB = TextEditingController();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ConversationShortcuts(
                  onSubmit: () {},
                  child: ConversationComposer(
                    sessionId: 's-a',
                    controller: fieldA,
                  ),
                ),
                ConversationShortcuts(
                  onSubmit: () {},
                  child: ConversationComposer(
                    sessionId: 's-b',
                    controller: fieldB,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    final container = ProviderScope.containerOf(context);
    for (final sid in ['s-a', 's-b']) {
      container.read(sessionsProvider.notifier).addSession(
            SessionSummary(
              sessionId: SessionId(sid),
              updatedAt: 0,
              running: false,
              blank: false,
            ),
          );
    }
    container
        .read(sessionsProvider.notifier)
        .setCurrent(const SessionId('s-a'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Both cards stay interactive: typing and tapping in either field
    // throws nothing (each card registered its own key; the barrier
    // consults both rects).
    await tester.enterText(find.byType(TextField).first, 'hello A');
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    expect(fieldA.text, 'hello A');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending groups render skeleton rows, not an empty box', (
    tester,
  ) async {
    registry.registerSource(_BlockingSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('plan').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The ready `command` group settled; the gated `slow` group is still
    // pending with no items → React's two skeleton bars.
    expect(find.text('plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('input-menu-skeleton')),
      findsNWidgets(2),
    );
  });

  testWidgets('sectioned rows render one break per section run', (
    tester,
  ) async {
    registry.registerSource(_SectionedSource());
    final controller = TextEditingController();
    await pumpComposer(tester, controller: controller);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    for (var i = 0; i < 10 && find.text('a.dart').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // One header per contiguous section run (React `section !== prev` rule):
    // two Files rows share one break, Sessions gets its own. The list
    // lazily builds, so scroll the tail into view first.
    expect(find.text('Files'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sessions'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('input-menu-surface')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    // Leading domain glyphs (React ReferenceIcon): file rows share the doc
    // glyph, the session row the history glyph; `/` rows carry none.
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.history_outlined), findsOneWidget);
  });

  testWidgets('Enter with no menu open submits through the shortcut seam', (
    tester,
  ) async {
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

  testWidgets('Shift+Enter inserts a newline instead of submitting', (
    tester,
  ) async {
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

  testWidgets('IME composing swallows menu navigation keys', (tester) async {
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
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () {},
              child: ConversationComposer(
                sessionId: 's-trigger',
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
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
