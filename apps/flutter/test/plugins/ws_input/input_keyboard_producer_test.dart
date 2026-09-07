import 'dart:async';

import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_controller.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/ui/input_keyboard_producer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Source that settles two candidates once the fetch is pumped.
class _FakeSource extends InputTriggerSource {
  @override
  TriggerChar get trigger => '/';
  @override
  String get name => 'cmd';
  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async {
    return [
      const InputTriggerCandidate(name: 'run', description: 'run a script'),
      const InputTriggerCandidate(name: 'build', description: 'build all'),
    ];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) => null;
  @override
  PickOutcome? matchSpace(String sessionId, String token) => null;
  @override
  void warm(String sessionId) {}
  @override
  List<String>? lexicon(String sessionId) => null;
}

/// Source whose candidates never settle, so the menu stays `loading` with no
/// highlight — exercises the `pass`/no-highlight Enter path.
class _NeverSettlingSource extends InputTriggerSource {
  final Completer<List<InputTriggerCandidate>> gate = Completer();

  @override
  TriggerChar get trigger => '/';
  @override
  String get name => 'cmd';
  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) => gate.future;
  @override
  PickOutcome? onPick(InputTriggerPick pick) => null;
  @override
  PickOutcome? matchSpace(String sessionId, String token) => null;
  @override
  void warm(String sessionId) {}
  @override
  List<String>? lexicon(String sessionId) => null;
}

Future<void> pumpProducer(
  WidgetTester tester,
  InputTriggerController controller, {
  bool composing = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InputKeyboardProducer(
          controller: controller,
          composing: composing,
          child: const TextField(),
        ),
      ),
    ),
  );
  // Focus the field so keys route through the producer.
  await tester.tap(find.byType(TextField));
  await tester.pump();
}

void main() {
  late TriggerSourceRegistry registry;
  late InputTriggerController controller;

  setUp(() {
    registry = TriggerSourceRegistry()..registerSource(_FakeSource());
    controller = registry.controllerFor('s1');
    // Open the trigger menu: draft "/run" with the caret past the slash.
    controller.track('/run', 3, const TriggerGuard(TriggerGuardTier.plain));
  });

  tearDown(() => registry.disposeController('s1'));

  testWidgets('ArrowDown/ArrowUp move the highlight and are consumed', (
    tester,
  ) async {
    await pumpProducer(tester, controller);
    expect(controller.menu.value.open, isTrue);
    // Candidates settle → the first item is auto-highlighted.
    expect(controller.menu.value.highlight, isNotNull);
    expect(controller.menu.value.highlight!.index, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.menu.value.highlight!.index, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(controller.menu.value.highlight!.index, 0);
  });

  testWidgets('Enter picks the highlighted candidate and is consumed', (
    tester,
  ) async {
    await pumpProducer(tester, controller);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final pickedBefore = controller.menu.value.open;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Enter on a highlight consumes and closes (pick path returns pickHighlighted).
    expect(controller.menu.value.open, isFalse);
    expect(pickedBefore, isTrue);
  });

  testWidgets('Escape closes the menu and is consumed (no cancelTurn)', (
    tester,
  ) async {
    await pumpProducer(tester, controller);
    expect(controller.menu.value.open, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.menu.value.open, isFalse);
  });

  testWidgets('Enter with no highlight passes through', (tester) async {
    // A never-settling source leaves the menu open with no highlight.
    final noHighlightRegistry = TriggerSourceRegistry()
      ..registerSource(_NeverSettlingSource());
    final noHit = noHighlightRegistry.controllerFor('n1');
    noHit.track('/run', 3, const TriggerGuard(TriggerGuardTier.plain));
    await pumpProducer(tester, noHit);
    expect(noHit.menu.value.open, isTrue);
    expect(noHit.menu.value.highlight, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Pass branch: menu stays open; nothing picked.
    expect(noHit.menu.value.open, isTrue);
    noHighlightRegistry.disposeController('n1');
  });

  testWidgets('keys pass through when the menu is closed or composing', (
    tester,
  ) async {
    // Closed menu: plain draft opens nothing, Escape passes harmlessly.
    final closed = registry.controllerFor('s2');
    closed.track('hello', 5, const TriggerGuard(TriggerGuardTier.plain));
    await pumpProducer(tester, closed);
    expect(closed.menu.value.open, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed.menu.value.open, isFalse);
    registry.disposeController('s2');

    // Composing: every key passes even with an open menu — highlight stays
    // at the auto-selected first item (pass never moves it).
    final composingCtrl = registry.controllerFor('s3');
    composingCtrl.track('/run', 3, const TriggerGuard(TriggerGuardTier.plain));
    await pumpProducer(tester, composingCtrl, composing: true);
    expect(composingCtrl.menu.value.open, isTrue);
    expect(composingCtrl.menu.value.highlight!.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // composing=true forces pass → highlight unchanged at 0.
    expect(composingCtrl.menu.value.highlight!.index, 0);
    registry.disposeController('s3');
  });

  testWidgets('null controller passes everything through', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputKeyboardProducer(
            controller: null,
            composing: false,
            child: const TextField(),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
