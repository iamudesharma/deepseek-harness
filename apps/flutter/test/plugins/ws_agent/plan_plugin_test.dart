import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/plan/plan_control.dart';
import 'package:dsh_flutter/src/plugins/plan/plan_plugin.dart';
import 'package:dsh_flutter/src/plugins/plan/ui/plan_chip_dock.dart'
    show boundPlanControl, buildPlanSeat;
import 'package:dsh_flutter/src/plugins/plan/ui/plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

/// Records `/plan off` executions and answers with a scripted outcome.
class _ScriptedCommands {
  final executed = <({String sessionId, String line})>[];
  CommandOutcome next = const CommandOutcome(ok: true, hasValue: true);

  CommandExecutor get executor => (sessionId, line) async {
    executed.add((sessionId: sessionId, line: line));
    return next;
  };
}

void main() {
  test('exitPlanMode returns null when /plan off is admitted', () async {
    final commands = _ScriptedCommands();
    final control = PlanControl(execute: commands.executor);

    final failure = await control.exitPlanMode(const SessionId('s-1'));

    expect(failure, isNull);
    expect(commands.executed.single.line, '/plan off');
    expect(commands.executed.single.sessionId, 's-1');
  });

  test(
    'exitPlanMode maps an undefined value to the unknown-command line',
    () async {
      final commands = _ScriptedCommands()
        ..next = const CommandOutcome(ok: true);
      final control = PlanControl(execute: commands.executor);

      expect(
        await control.exitPlanMode(const SessionId('s-1')),
        'unknown command: /plan off',
      );
    },
  );

  test('exitPlanMode surfaces RPC failures as message (code)', () async {
    final commands = _ScriptedCommands()
      ..next = const CommandOutcome(
        ok: false,
        errorCode: 'E-GATE',
        errorMessage: 'gate refused',
      );
    final control = PlanControl(execute: commands.executor);

    expect(
      await control.exitPlanMode(const SessionId('s-1')),
      'gate refused (E-GATE)',
    );
  });

  test('activation provides the plan service, occupies the composer seat, and binds the control', () async {
    final host = wsAgentHost();
    addTearDown(host.deactivateAll);
    // The conversation anchor's children table (fixture stand-in) declares
    // the seat; the plugin's inject waits on it.
    declareHeaderActionsHole(host);

    final control = PlanControl(execute: _ScriptedCommands().executor);
    host.register(PlanPlugin(planControl: control));
    await host.activateAll();

    expect(host.service<PlanControl>(kPlanServiceName), same(control));
    // The chip occupies the conversation.input.plan seat once the
    // conversation hub's declaration lands.
    expect(host.slots.isDeclared(kPlanSeatSlot), isTrue);
    expect([
      for (final w in host.slots.winnersOfSlot(kPlanSeatSlot)) w.options.id,
    ], contains(kPlanSeatId));
    expect(boundPlanControl, same(control));

    // Leave a clean bridge for the next test (module-level global).
    host.deactivateAll();
    expect(boundPlanControl, isNull);
  });

  test('deactivation removes the seat and clears the bound control', () async {
    final host = wsAgentHost();
    addTearDown(host.deactivateAll);
    declareHeaderActionsHole(host);
    host.register(
      PlanPlugin(
        planControl: PlanControl(
          execute: (_, _) async => const CommandOutcome(ok: true),
        ),
      ),
    );
    await host.activateAll();
    expect(boundPlanControl, isNotNull);

    host.deactivate(kPlanPluginId);

    expect([
      for (final w in host.slots.winnersOfSlot(kPlanSeatSlot)) w.options.id,
    ], isNot(contains(kPlanSeatId)));
    expect(boundPlanControl, isNull);
  });

  testWidgets('seat chip renders only while the effective target is plan mode', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Widget seat() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (_) => buildPlanSeat())),
      ),
    );

    // Default seed: inactive before first host projection — target off.
    await tester.pumpWidget(seat());
    expect(find.text('Plan'), findsNothing);

    // Enter plan mode: active true → target on.
    container.read(planProvider.notifier).enter();
    await tester.pumpWidget(seat());
    await tester.pump();
    expect(find.text('Plan'), findsOneWidget);

    // Settle inactive: `pending=false, active=false` → target off → empty seat.
    container.read(planProvider.notifier).settle(active: false);
    await tester.pumpWidget(seat());
    await tester.pump();
    expect(find.text('Plan'), findsNothing);
  });
}
