import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/queue_state.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/composer.dart'
    show ConversationComposer, composerQueueSteerHookProvider;
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_shortcuts.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_controller.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/ui/composer_trigger_binding.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/ui/input_trigger_shortcuts.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slash source whose pick inserts one reference chip (the occurrence path).
class _InsertSource extends InputTriggerSource {
  @override
  TriggerChar get trigger => '/';
  @override
  String get name => 'cmd';
  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async {
    return [const InputTriggerCandidate(name: 'Foo', description: 'first')];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) => const InsertOutcome(
    ReferenceInsert(
      source: 'cmd',
      ref: 'foo',
      label: 'Foo',
      appearance: 'file',
      clipboardText: '@Foo',
    ),
  );
  @override
  PickOutcome? matchSpace(String sessionId, String token) => null;
  @override
  void warm(String sessionId) {}
  @override
  List<String>? lexicon(String sessionId) => null;
}

TriggerSourceRegistry _registryWithSource() =>
    TriggerSourceRegistry()..registerSource(_InsertSource());

Future<void> _pumpShortcutField(
  WidgetTester tester, {
  required TriggerSourceRegistry registry,
  required ComposerTriggerBinding binding,
  required TextEditingController field,
  bool Function()? invocable,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InputTriggerShortcuts(
          registry: registry,
          sessionId: 's1',
          invocable: invocable,
          undo: () => binding.undo(),
          redo: () => binding.redo(),
          child: TextField(controller: field, autofocus: true),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('mounted InputTriggerShortcuts (undo/redo round-trip)', () {
    testWidgets('Cmd+Z / Cmd+Shift+Z restore the field on Apple hosts', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final registry = _registryWithSource();
      addTearDown(() => registry.disposeController('s1'));
      final controller = registry.controllerFor('s1');
      final field = TextEditingController();
      final committed = <String>[];
      final binding = ComposerTriggerBinding(field, controller, committed.add);

      await _pumpShortcutField(
        tester,
        registry: registry,
        binding: binding,
        field: field,
      );

      // Typing rides the field listener into controller.track — the typing
      // run coalesces into ONE chip transaction with an empty before-state.
      await tester.enterText(find.byType(TextField), 'h');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      expect(controller.transactions.canUndo, isTrue);
      expect(
        committed,
        isEmpty,
      ); // user typing commits via onChanged, not binding

      // Cmd+Z restores the pre-typing draft IN THE FIELD.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(field.text, '');
      expect(controller.transactions.canRedo, isTrue);
      expect(committed.single, ''); // the binding mirrored the restored draft

      // Cmd+Shift+Z re-applies the displaced draft.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(field.text, 'hi');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Ctrl+Z / Ctrl+Y drive undo/redo off Apple hosts', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final registry = _registryWithSource();
      addTearDown(() => registry.disposeController('s1'));
      final controller = registry.controllerFor('s1');
      final field = TextEditingController();
      final binding = ComposerTriggerBinding(field, controller, (_) {});

      await _pumpShortcutField(
        tester,
        registry: registry,
        binding: binding,
        field: field,
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(field.text, '');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(field.text, 'abc');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('invocable gate blocks the mutation but keeps the key', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final registry = _registryWithSource();
      addTearDown(() => registry.disposeController('s1'));
      final controller = registry.controllerFor('s1');
      controller.track('draft', 5, const TriggerGuard(TriggerGuardTier.plain));
      final field = TextEditingController(text: 'draft');
      var allowed = false;
      final binding = ComposerTriggerBinding(field, controller, (_) {});

      await _pumpShortcutField(
        tester,
        registry: registry,
        binding: binding,
        field: field,
        invocable: () => allowed,
      );

      // The machine-busy/locked port: keystroke consumed, draft untouched.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(field.text, 'draft');

      allowed = true;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(field.text, '');
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('ComposerTriggerBinding occurrences', () {
    const chip = ReferenceInsert(
      source: 'cmd',
      ref: 'foo',
      label: 'Foo',
      appearance: 'file',
      clipboardText: '@Foo',
    );

    testWidgets('insert mints one occurrence; Delete/Backspace remove it', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final registry = _registryWithSource();
      addTearDown(() => registry.disposeController('s1'));
      final controller = registry.controllerFor('s1');
      final field = TextEditingController(text: 'see now');
      final binding = ComposerTriggerBinding(field, controller, (_) {});
      addTearDown(binding.dispose);

      // Seed one chip across the '@Foo' range — the same sink path a real
      // menu pick takes (unstamped spans pass the CAS by design).
      expect(
        binding.apply(
          const InsertOutcome(chip),
          const TokenSpan(start: 4, end: 4, draftRev: 0),
        ),
        isTrue,
      );
      expect(field.text, 'see @Foonow');
      expect(binding.occurrences.single.offset, 4);
      expect(binding.occurrences.single.length, 4); // '@Foo'

      // Delete-forward at the chip start removes exactly the chip.
      expect(binding.deleteOccurrenceAt(4, backward: false), isTrue);
      expect(field.text, 'see now');
      expect(binding.occurrences, isEmpty);

      // Re-seed, then append text beyond the chip: reconciliation keeps the
      // entry anchored while plain text grows after it.
      expect(
        binding.apply(
          const InsertOutcome(chip),
          const TokenSpan(start: 4, end: 4, draftRev: 0),
        ),
        isTrue,
      );
      field.value = const TextEditingValue(
        text: 'see @Foonow XY',
        selection: TextSelection.collapsed(offset: 14),
      );
      await tester.pump();
      expect(binding.occurrences.single.offset, 4);

      // Backspace at the chip end deletes it; the next Backspace finds no
      // adjacency and reports no mutation (native deletion proceeds there).
      expect(binding.deleteOccurrenceAt(8, backward: true), isTrue);
      expect(field.text, 'see now XY');
      expect(binding.occurrences, isEmpty);
      expect(binding.deleteOccurrenceAt(4, backward: true), isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Enter repeat guard', () {
    testWidgets('held-down Enter does not machine-gun submits', (tester) async {
      var submits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () => submits++,
              child: const Focus(autofocus: true, child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submits, 1);

      // The e.repeat port: repeat events never re-enter the submit action.
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submits, 1);
    });
  });

  group('empty-draft accelerated-Enter queue steer', () {
    const queuedItem = QueuedInboxItem(
      id: 'q1',
      placement: 'queued',
      message: <String, Object?>{},
    );

    SessionSummary summary({bool running = true}) => SessionSummary(
      sessionId: const SessionId('s1'),
      updatedAt: 0,
      running: running,
      blank: false,
    );

    Future<ProviderContainer> pumpComposer(
      WidgetTester tester, {
      required SessionSummary summary,
      required List<QueuedInboxItem> queue,
    }) async {
      final container = ProviderContainer(
        overrides: [
          sessionByIdProvider.overrideWith((ref, id) => summary),
          queueProvider.overrideWith(
            (ref) => QueueController()..replace('s1', queue),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                child: ConversationComposer(sessionId: 's1'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Focus the field so dispatched keys route through the shortcut layers.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      return container;
    }

    Future<void> fireAcceleratedEnter(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets(
      'accelerated Enter over an empty draft steers the whole queue',
      (tester) async {
        final container = await pumpComposer(
          tester,
          summary: summary(),
          queue: [queuedItem],
        );

        var steers = 0;
        container
            .read(composerQueueSteerHookProvider('s1').notifier)
            .state = () =>
            steers++;

        await fireAcceleratedEnter(tester);
        expect(steers, 1);
      },
    );

    testWidgets('the steer gesture needs a running turn AND pending rows', (
      tester,
    ) async {
      // Not running: the gesture falls through to submit gating — no hook.
      var idleSteers = 0;
      final idleContainer = await pumpComposer(
        tester,
        summary: summary(running: false),
        queue: [queuedItem],
      );
      idleContainer
          .read(composerQueueSteerHookProvider('s1').notifier)
          .state = () =>
          idleSteers++;
      await fireAcceleratedEnter(tester);
      expect(idleSteers, 0);

      // Running but nothing queued: still no steer dispatch.
      var emptySteers = 0;
      final quietContainer = await pumpComposer(
        tester,
        summary: summary(),
        queue: const [],
      );
      quietContainer
          .read(composerQueueSteerHookProvider('s1').notifier)
          .state = () =>
          emptySteers++;
      await fireAcceleratedEnter(tester);
      expect(emptySteers, 0);
    });

    testWidgets('a non-empty draft never steers (submit keeps its path)', (
      tester,
    ) async {
      final container = await pumpComposer(
        tester,
        summary: summary(),
        queue: [queuedItem],
      );

      var steers = 0;
      container
          .read(composerQueueSteerHookProvider('s1').notifier)
          .state = () =>
          steers++;

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      // Draft non-empty → canSend governs; the steer hook stays cold.
      await fireAcceleratedEnter(tester);
      expect(steers, 0);
      // The submit path schedules its optimistic-clear settle timer; pump it
      // out so the test body ends quiescent.
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('mounted composer end-to-end', () {
    testWidgets('Backspace deletes the last picked chip occurrence', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final registry = _registryWithSource();
      bindActivatedRegistry(registry);
      addTearDown(() {
        bindActivatedRegistry(null);
        registry.disposeAllControllers();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                child: ConversationComposer(sessionId: 's1'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Type a prefix then the slash token; the mounted field listener feeds
      // detection, candidates settle, and the pick splices the chip through
      // the real outcome sink.
      await tester.enterText(find.byType(TextField), 'x ');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'x /Foo');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final controller = registry.controllers['s1']!;
      controller.pick('cmd', 0);
      await tester.pump();
      expect(controller.draft, 'x @Foo');
      expect(find.text('x @Foo'), findsOneWidget);

      // The caret sits after the fresh chip; Backspace removes the whole
      // occurrence instead of one glyph.
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.draft, 'x ');
      expect(find.widgetWithText(TextField, 'x '), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
