import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:dsh_flutter/src/plugins/workflow_run/locales.dart';
import 'package:dsh_flutter/src/plugins/workflow_run/ui/workflow_run_panel.dart';
import 'package:dsh_flutter/src/plugins/workflow_run/workflow_run_models.dart';
import 'package:dsh_flutter/src/plugins/workflow_run/workflow_run_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

const _run = WorkflowRunChatData(
  name: 'parallel sweep',
  status: WorkflowRunStatus.running,
  phases: [
    WorkflowRunPhaseData(
      key: 'value:6:review',
      phase: 'review',
      members: [
        WorkflowRunMemberData(
          seq: 1,
          label: 'reviewer-a',
          childId: 'sess-child-1',
          status: WorkflowRunStatus.completed,
        ),
        WorkflowRunMemberData(
          seq: 2,
          label: 'reviewer-b',
          childId: 'sess-child-2',
          status: WorkflowRunStatus.running,
        ),
      ],
    ),
    WorkflowRunPhaseData(
      key: 'missing',
      phase: null,
      members: [
        WorkflowRunMemberData(
          seq: 3,
          label: '',
          childId: 'sess-child-3',
          status: WorkflowRunStatus.failed,
        ),
      ],
    ),
  ],
);

ChatNodeData nodeFor(WorkflowRunChatData data, {String key = 'wf-1'}) =>
    ChatNodeData(key: key, lines: encodeWorkflowRunLines(data));

void main() {
  test(
    'activation registers the keyed renderer and the dictionaries',
    () async {
      final host = wsTasksHost();
      addTearDown(host.deactivateAll);

      final locale = host.service<LocaleService>('locale')!;
      host.register(const WorkflowRunPlugin());
      await host.activateAll();

      final controller = host.service<ConversationController>('conversation')!;
      expect(controller.renderers.resolve(kWorkflowRunNodeKey), isNotNull);
      expect(controller.renderers.resolve('goal'), isNull);
      expect(locale.bind(kWorkflowRunNamespace)('status.interrupted'), '已中断');
      expect(kWorkflowRunEn.keys.toSet(), kWorkflowRunZh.keys.toSet());
    },
  );

  test('phase keys preserve absent versus empty identity', () {
    expect(workflowPhaseKey(null), 'missing');
    expect(workflowPhaseKey(''), 'value:0:');
    // A length-prefixed value key cannot collide with a literal phase.
    expect(workflowPhaseKey('missing'), 'value:7:missing');
    expect(phaseFromKey('missing'), isNull);
    expect(phaseFromKey('value:0:'), '');
    expect(phaseFromKey(workflowPhaseKey('review')), 'review');
  });

  test('the line codec round-trips run data through the seam', () {
    final decoded = decodeWorkflowRun(nodeFor(_run))!;

    expect(decoded.name, 'parallel sweep');
    expect(decoded.status, WorkflowRunStatus.running);
    expect(decoded.phases.map((p) => p.phase), ['review', isNull]);
    expect(decoded.phases[0].members.map((m) => m.childId), [
      'sess-child-1',
      'sess-child-2',
    ]);
    expect(decoded.phases[1].members.single.status, WorkflowRunStatus.failed);
    expect(decoded.memberCount, 3);
  });

  testWidgets('nodes without a run payload render nothing', (tester) async {
    final host = wsTasksHost();
    addTearDown(host.deactivateAll);
    host.register(const WorkflowRunPlugin());
    await host.activateAll();
    final controller = host.service<ConversationController>('conversation')!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final renderer = controller.renderers.resolve(
                kWorkflowRunNodeKey,
              )!;
              return renderer(
                context,
                const ChatNodeData(key: 'n1', lines: ['only a name']),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(WorkflowRunPanel), findsNothing);
  });

  testWidgets(
    'the panel discloses run and phases with status-driven defaults',
    (tester) async {
      final opened = <String>[];
      final host = wsTasksHost();
      addTearDown(host.deactivateAll);
      host.register(WorkflowRunPlugin(openSession: opened.add));
      await host.activateAll();
      final controller = host.service<ConversationController>('conversation')!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final renderer = controller.renderers.resolve(
                  kWorkflowRunNodeKey,
                )!;
                return renderer(context, nodeFor(_run));
              },
            ),
          ),
        ),
      );

      // Running runs open; the collapsed tail carries member count + status.
      expect(find.text('parallel sweep'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      // Phase rows are visible under the open run header.
      expect(find.text('review'), findsOneWidget);
      expect(find.text('Unphased'), findsOneWidget);

      // Navigable: only the running member's row opens its child session.
      await tester.tap(find.text('reviewer-b'));
      await tester.pump();
      expect(opened, ['sess-child-2']);

      // Settled-clean phases stay collapsed until toggled.
      expect(find.textContaining('Completed 1 · Failed 1'), findsNothing);
    },
  );
}
