import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:dsh_flutter/src/plugins/goal/goal_control.dart';
import 'package:dsh_flutter/src/plugins/goal/goal_models.dart';
import 'package:dsh_flutter/src/plugins/goal/goal_plugin.dart';
import 'package:dsh_flutter/src/plugins/goal/goal_projection.dart';
import 'package:dsh_flutter/src/plugins/goal/locales.dart';
import 'package:dsh_flutter/src/plugins/goal/ui/goal_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

class _Source implements GoalProjectionSource {
  _Source(this.snapshots);
  final Map<String, GoalSnapshot> snapshots;

  @override
  GoalSnapshot? snapshotOf(String sessionId) => snapshots[sessionId];
}

const _activeGoal = GoalSnapshot(
  id: 'goal-1',
  objective: 'Ship the migration',
  phase: GoalPhase.active,
  revision: 3,
);

void main() {
  test('activation provides the goal mutation service and leaves cleanly', () async {
    final client = RecordingClient();
    final host = wsTasksHost(client: client);
    addTearDown(host.deactivateAll);

    final source = _Source({'s1': _activeGoal});
    host.register(GoalPlugin(projectionSource: source));
    await host.activateAll();

    final control = host.service<GoalControl>('goal');
    expect(control, isNotNull);
    expect(control!.refOf('s1'), const GoalRef(id: 'goal-1', revision: 3));
    expect(boundGoalControl, same(control));
    expect(boundGoalProjectionSource, same(source));
    expect(host.service<ConversationController>('conversation')!.dockIds,
        contains(kGoalDockId));

    host.deactivate(kGoalPluginId);
    expect(host.hasService('goal'), isFalse);
    expect(boundGoalControl, isNull);
    expect(boundGoalProjectionSource, isNull);
    expect(host.service<ConversationController>('conversation')!.dockIds,
        isNot(contains(kGoalDockId)));
  });

  test('mutation verbs carry exact wire methods and CAS refs from the projection',
      () async {
    final client = RecordingClient();
    final control = GoalControl(client: client, projectionSource: _Source({
      's1': _activeGoal,
      'paused': const GoalSnapshot(
          id: 'goal-2', objective: 'x', phase: GoalPhase.paused, revision: 7),
    }));

    await control.edit('s1', 'rewritten');
    await control.pause('s1');
    await control.resume('paused');
    await control.clear('s1');

    expect(
      [for (final c in client.calls) c.method],
      ['goal.edit', 'goal.pause', 'goal.resume', 'goal.clear'],
    );
    expect(client.calls[0].payload['sessionId'], 's1');
    expect(client.calls[0].payload['objective'], 'rewritten');
    expect(client.calls[0].payload['ref'], {'id': 'goal-1', 'revision': 3});
    expect(client.calls[2].payload['sessionId'], 'paused');
    expect(client.calls[2].payload.containsKey('objective'), isFalse);
    expect(client.calls[2].payload['ref'], {'id': 'goal-2', 'revision': 7});
    expect(client.calls[3].payload['ref'], {'id': 'goal-1', 'revision': 3});
  });

  test('without a projection the verbs fail no-current-goal and never hit the wire',
      () async {
    final client = RecordingClient();
    final control = GoalControl(client: client);

    for (final action in [
      () => control.edit('s1', 'x'),
      () => control.pause('s1'),
      () => control.resume('s1'),
      () => control.clear('s1'),
    ]) {
      final result = await action();
      expect(result.ok, isFalse);
      expect(result.code, 'no-current-goal');
    }
    expect(client.calls, isEmpty);
  });

  test('an RPC failure settles as an ok:false result carrying the message', () async {
    final client = RecordingClient()..failNextWith = Exception('goal.edit: agent-busy');
    final control = GoalControl(
        client: client,
        projectionSource: _Source({'s1': _activeGoal}));

    final result = await control.edit('s1', 'nope');

    expect(result.ok, isFalse);
    expect(result.message, contains('agent-busy'));
  });

  test('dictionaries register under the goal namespace and leave with the plugin',
      () async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);

    final locale = host.service<LocaleService>('locale')!;
    host.register(const GoalPlugin());
    await host.activateAll();

    expect(locale.bind(kGoalNamespace)('phase.active'), '进行中的目标');
    locale.setLocale('en');
    expect(locale.bind(kGoalNamespace)('phase.active'), 'Ongoing Goal');
    // zh is the key-set source of truth; en mirrors every key.
    expect(kGoalEn.keys.toSet(), kGoalZh.keys.toSet());

    host.deactivate(kGoalPluginId);
    expect(locale.bind(kGoalNamespace)('phase.active'), 'phase.active');
  });

  testWidgets('the command-input renderer renders the /goal line right-aligned',
      (tester) async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);
    host.register(const GoalPlugin());
    await host.activateAll();
    final controller = host.service<ConversationController>('conversation')!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          final renderer = controller.renderers.resolve(kGoalCommandInputNodeKey)!;
          return renderer(
            context,
            const ChatNodeData(key: 'n1', lines: ['/goal ship it']),
          );
        }),
      ),
    ));

    expect(find.text('/goal ship it'), findsOneWidget);
    // Right-aligned bubble: the Align sits at the row's right edge.
    final align = tester.widget<Align>(
        find.ancestor(of: find.text('/goal ship it'), matching: find.byType(Align)).first);
    expect(align.alignment, Alignment.centerRight);
  });

  testWidgets('the dock renders the projected goal and mutates through taps',
      (tester) async {
    final client = RecordingClient();
    final host = wsTasksHost(client: client);
    addTearDown(host.deactivateAll);

    host.register(GoalPlugin(
        projectionSource: _Source({'s1': _activeGoal})));
    await host.activateAll();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentSessionIdProvider.overrideWithValue(const SessionId('s1')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Builder(builder: (context) => buildGoalDock(context)),
          ]),
        ),
      ),
    ));

    // The strip shows the projected objective; pause routes to the wire.
    expect(find.text('Ship the migration'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    // Fixed pumps: the ongoing-goal dot pulses forever by design, so
    // pumpAndSettle would never settle.
    await tester.pump();
    await tester.pump();
    expect(client.calls.single.method, 'goal.pause');
    expect(client.calls.single.payload['ref'], {'id': 'goal-1', 'revision': 3});

    // A failed edit surfaces `message (code)` inline.
    client.failNextWith = Exception('goal.edit: rejected');
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    expect(client.calls.last.method, 'goal.edit');
    expect(find.textContaining('rejected'), findsOneWidget);
  });

  testWidgets('complete goals render no strip at all', (tester) async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);
    host.register(GoalPlugin(projectionSource: _Source({
      's1': const GoalSnapshot(
          id: 'goal-9', objective: 'done deal', phase: GoalPhase.complete),
    })));
    await host.activateAll();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentSessionIdProvider.overrideWithValue(const SessionId('s1')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => buildGoalDock(context)),
        ),
      ),
    ));

    expect(find.text('done deal'), findsNothing);
  });
}
