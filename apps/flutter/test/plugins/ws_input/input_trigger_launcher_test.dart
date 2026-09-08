/// `+` launcher toggle tests — the programmatic `command`-source menu
/// (React `toggleSource`) over the shared slash pipeline.
library;

import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_controller.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted `/` source with canned candidates.
class LauncherFakeSource extends InputTriggerSource {
  LauncherFakeSource({this.sourceName = 'command'});

  final String sourceName;
  final List<String> picked = [];

  @override
  TriggerChar get trigger => '/';

  @override
  String get name => sourceName;

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

void main() {
  InputTriggerController controllerFor(
    TriggerSourceRegistry registry,
    List<(PickOutcome, TokenSpan)> records,
  ) {
    return registry.controllerFor(
      's1',
      sink: (outcome, span) {
        records.add((outcome, span));
        return true;
      },
    );
  }

  test('toggle opens the single-source menu with the full catalog', () async {
    final registry = TriggerSourceRegistry();
    registry.registerSource(LauncherFakeSource());
    final records = <(PickOutcome, TokenSpan)>[];
    final controller = controllerFor(registry, records);

    controller.toggleLauncherSource(
      source: 'command',
      trigger: '/',
      caretOffset: 0,
    );
    // Candidates arrive async under the generation guard.
    for (var i = 0; i < 50; i++) {
      final groups = controller.menu.value.groups;
      if (controller.menu.value.open &&
          groups.isNotEmpty &&
          groups.single.status == 'ready') {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final state = controller.menu.value;
    expect(state.open, isTrue);
    expect(controller.launcher.value, 'command');
    expect(state.groups.map((g) => g.source), ['command']);
    expect(
      state.groups.single.items.map((c) => c.name),
      ['compact', 'model'],
    );
    expect(state.hit?.query, '');
    expect(state.hit?.position, TriggerPosition.leading);
  });

  test('toggle twice closes; unknown source closes without throwing', () async {
    final registry = TriggerSourceRegistry();
    registry.registerSource(LauncherFakeSource());
    final records = <(PickOutcome, TokenSpan)>[];
    final controller = controllerFor(registry, records);

    controller.toggleLauncherSource(
      source: 'command',
      trigger: '/',
      caretOffset: 0,
    );
    for (var i = 0; i < 20 && !controller.menu.value.open; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.menu.value.open, isTrue);

    controller.toggleLauncherSource(
      source: 'command',
      trigger: '/',
      caretOffset: 0,
    );
    expect(controller.menu.value.open, isFalse);
    expect(controller.launcher.value, isNull);

    controller.toggleLauncherSource(
      source: 'nope',
      trigger: '/',
      caretOffset: 0,
    );
    expect(controller.menu.value.open, isFalse);
  });

  test('pick after launch routes through the source and sink', () async {
    final registry = TriggerSourceRegistry();
    final source = LauncherFakeSource();
    registry.registerSource(source);
    final records = <(PickOutcome, TokenSpan)>[];
    final controller = controllerFor(registry, records);

    controller.toggleLauncherSource(
      source: 'command',
      trigger: '/',
      caretOffset: 3,
    );
    for (var i = 0; i < 50 && controller.menu.value.groups.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Wait until the group settles ready.
    for (var i = 0; i < 50; i++) {
      final groups = controller.menu.value.groups;
      if (groups.isNotEmpty && groups.single.status == 'ready') break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    controller.pick('command', 0);
    expect(source.picked, ['compact']);
    expect(records, hasLength(1));
    expect(controller.menu.value.open, isFalse);
  });

  test('typing after launch falls back to draft detection', () async {
    final registry = TriggerSourceRegistry();
    registry.registerSource(LauncherFakeSource());
    final records = <(PickOutcome, TokenSpan)>[];
    final controller = controllerFor(registry, records);

    controller.toggleLauncherSource(
      source: 'command',
      trigger: '/',
      caretOffset: 0,
    );
    for (var i = 0; i < 20 && !controller.menu.value.open; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.menu.value.open, isTrue);

    // Plain text with no trigger closes the launched menu and clears the
    // launcher, exactly like React's track-after-launch.
    controller.track('hello', 5, const TriggerGuard(TriggerGuardTier.plain));
    expect(controller.menu.value.open, isFalse);
    expect(controller.launcher.value, isNull);

    // A typed slash reopens through ordinary detection.
    controller.track('/c', 2, const TriggerGuard(TriggerGuardTier.plain));
    for (var i = 0; i < 20 && !controller.menu.value.open; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.menu.value.open, isTrue);
    expect(controller.launcher.value, isNull);
  });
}
