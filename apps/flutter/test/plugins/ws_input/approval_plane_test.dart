import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart';
import 'package:dsh_flutter/src/core/session/live_sync.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_responder.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/pending_interactions.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_responder.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/ui/approval_card.dart';
import 'package:dsh_flutter/src/plugins/user_questions/ui/question_composer_entry.dart'
    show questionComposerSelect;
import 'package:dsh_flutter/src/plugins/user_questions/ui/question_node_card.dart'
    show QuestionNodeCard, bindQuestionClient;
import 'package:dsh_flutter/src/plugins/user_questions/user_questions_plugin.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

SessionSummary _summary(String id) => SessionSummary(
  sessionId: SessionId(id),
  updatedAt: 0,
  running: false,
  blank: false,
);

Map<String, Object?> _planReviewQuestion() => {
  'id': 'q1',
  'question': 'Proceed with this plan?',
  'detail': '1. do it',
  'intent': {'kind': 'plan-review', 'approve': 'Approve'},
  'options': [
    {'label': 'Approve'},
    {'label': 'Decline'},
  ],
};

void main() {
  group('pending_interactions policy (pending.ts / manager.ts ports)', () {
    test('stable wait keys use the a:/q: prefixes', () {
      expect(approvalWaitKey('ap-1'), 'a:ap-1');
      expect(questionWaitKey('m10'), 'q:m10');
    });

    test(
      'questionInteractionStatus narrows the binary plan-review request',
      () {
        final planReview = [QuestionItem.fromJson(_planReviewQuestion())];
        expect(questionInteractionStatus(planReview), kPendingPlanReview);
        final generic = [
          QuestionItem.fromJson(const {
            'id': 'q2',
            'question': 'Which database?',
            'options': [
              {'label': 'Postgres'},
              {'label': 'SQLite'},
              {'label': 'DuckDB'},
            ],
          }),
        ];
        expect(questionInteractionStatus(generic), kPendingQuestion);
      },
    );

    test('combinePendingStatuses ranks question ahead of approval '
        '(manager.ts: first non-approval wins)', () {
      expect(
        combinePendingStatuses(
          question: PendingQuestion(
            rpcId: 'm1',
            sessionId: 's',
            questions: const [],
          ),
          approval: const PendingApproval(
            rpcId: 'm2',
            sessionId: 's',
            approvalId: 'a',
            toolName: 'bash',
          ),
        ),
        kPendingQuestion,
      );
      expect(
        combinePendingStatuses(
          question: null,
          approval: const PendingApproval(
            rpcId: 'm2',
            sessionId: 's',
            approvalId: 'a',
            toolName: 'bash',
          ),
        ),
        kPendingApproval,
      );
      expect(combinePendingStatuses(question: null, approval: null), isNull);
    });

    test('recomputePendingSummary clears the marker once waits settle', () {
      final base = _summary('s-100').copyWith(pendingInteraction: 'approval');
      final cleared = recomputePendingSummary(base, null, null);
      expect(cleared.pendingInteraction, isNull);
    });
  });

  group('ApprovalsController (session.ts mint/settle port)', () {
    late ApprovalsController controller;
    setUp(() => controller = ApprovalsController());

    test(
      'requested mints keyed by session; replacement is idempotent on replay',
      () {
        controller.requested(
          's-100',
          rpcId: 'm7',
          approvalId: 'ap-1',
          toolName: 'write',
        );
        expect(controller.waits['s-100']!.rpcId, 'm7');
        // Mux-open replay re-delivers still-pending requests with the same ids.
        controller.requested(
          's-100',
          rpcId: 'm7',
          approvalId: 'ap-1',
          toolName: 'write',
        );
        expect(controller.waits.length, 1);
      },
    );

    test(
      'resolved settles only the matching approvalId; stale frames drop',
      () {
        controller.requested(
          's-100',
          rpcId: 'm7',
          approvalId: 'ap-1',
          toolName: 'write',
        );
        // A resolution for a superseded id must not drop the live wait.
        controller.resolved('s-100', 'ap-stale');
        expect(controller.waits, containsPair('s-100', isNotNull));
        controller.resolved('s-100', 'ap-1');
        expect(controller.waits, isEmpty);
      },
    );

    test('clear drops the whole session entry (removal / generation drop)', () {
      controller.requested(
        's-100',
        rpcId: 'm7',
        approvalId: 'ap-1',
        toolName: 'write',
      );
      controller.clear('s-100');
      expect(controller.waits, isEmpty);
    });
  });

  group('ApprovalResponder wire face', () {
    test('answer echoes the requested rpcId with the payload triple', () async {
      final client = WsInputRecordingClient();
      const pending = PendingApproval(
        rpcId: 'm7',
        sessionId: 's-100',
        approvalId: 'ap-1',
        toolName: 'write',
        reason: 'needs write access',
      );
      await ApprovalResponder(
        client: client,
        pending: pending,
      ).answer(ApprovalAnswer.allowedOnce);
      expect(client.responds.single.rpcId.value, 'm7');
      expect(client.responds.single.ok, isTrue);
      expect(client.responds.single.decodedValue, {
        'sessionId': 's-100',
        'approvalId': 'ap-1',
        'outcome': 'allowed-once',
      });
    });

    test('rejected receipt throws so the card re-arms for retry', () async {
      final client = WsInputRecordingClient();
      client.nextReceipt = const RpcReceiptRejected('not-pending');
      const pending = PendingApproval(
        rpcId: 'late',
        sessionId: 's-100',
        approvalId: 'ap-1',
        toolName: 'write',
      );
      await expectLater(
        ApprovalResponder(
          client: client,
          pending: pending,
        ).answer(ApprovalAnswer.rejected),
        throwsStateError,
      );
    });
  });

  group('interaction-plane reconciliation through live_sync helpers', () {
    test(
      'requested arms the amber dot; sibling question outranks approval',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final questions = container.read(pendingQuestionsProvider.notifier);
        final approvals = container.read(approvalsProvider.notifier);
        final sessions = container.read(sessionsProvider.notifier);
        sessions.addSession(_summary('s-100'));

        approvals.requested(
          's-100',
          rpcId: 'm7',
          approvalId: 'ap-1',
          toolName: 'write',
        );
        reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
        expect(
          sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
          kPendingApproval,
        );

        questions.requested(
          's-100',
          rpcId: 'm10',
          questions: [QuestionItem.fromJson(_planReviewQuestion())],
        );
        reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
        expect(
          sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
          kPendingPlanReview,
        );

        // Settling one wait keeps the dot with the surviving kind.
        approvals.resolved('s-100', 'ap-1');
        reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
        expect(
          sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
          kPendingPlanReview,
        );

        questions.resolved('s-100', 'm10', 'answered');
        reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
        expect(
          sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
          isNull,
        );
      },
    );

    test('dropPendingInteractionState clears waits and summary markers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final questions = container.read(pendingQuestionsProvider.notifier);
      final approvals = container.read(approvalsProvider.notifier);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.addSession(_summary('s-100'));
      approvals.requested(
        's-100',
        rpcId: 'm7',
        approvalId: 'ap-1',
        toolName: 'write',
      );
      questions.requested('s-101', rpcId: 'm11', questions: const []);
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');

      dropPendingInteractionState(questions, approvals, sessions);

      expect(approvals.waits, isEmpty);
      expect(questions.waits, isEmpty);
      expect(
        sessions.snapshot.byId.values.every(
          (s) => s.pendingInteraction == null,
        ),
        isTrue,
      );
    });

    test('resync listener drops state when the connection generation dies', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Probe provider installs the listener inside build (ref.listen rule).
      final probe = Provider<void>((ref) {
        installPendingInteractionResync(
          ref,
          questions: ref.read(pendingQuestionsProvider.notifier),
          approvals: ref.read(approvalsProvider.notifier),
          sessions: ref.read(sessionsProvider.notifier),
        );
      });
      container.read(probe);

      final questions = container.read(pendingQuestionsProvider.notifier);
      final approvals = container.read(approvalsProvider.notifier);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.addSession(_summary('s-100'));
      approvals.requested(
        's-100',
        rpcId: 'm7',
        approvalId: 'ap-1',
        toolName: 'write',
      );
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
      expect(
        sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
        kPendingApproval,
      );

      container.read(connectionStateProvider.notifier).markReconnecting();

      expect(approvals.waits, isEmpty);
      expect(
        sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
        isNull,
      );
    });

    test(
      'unknown interaction frame types discard at decode (documented default)',
      () {
        // live_sync's handler decodes every envelope inside try/catch; an
        // unknown discriminant throws and the catch drops it silently.
        expect(
          () => MuxFrame.fromJson(const {
            'type': 'plan-review/requested',
            'sessionId': 's-100',
          }),
          throwsArgumentError,
        );
      },
    );
  });

  group('ApprovalCard plane surface', () {
    testWidgets(
      'renders the pending approval, answers allow-once, leaves on resolved frame',
      (tester) async {
        final client = WsInputRecordingClient();
        bindApprovalClient(client);
        addTearDown(() => bindApprovalClient(null));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final approvals = container.read(approvalsProvider.notifier);
        final sessions = container.read(sessionsProvider.notifier);
        sessions.addSession(_summary('s-100'));
        sessions.setCurrent(const SessionId('s-100'));
        approvals.requested(
          's-100',
          rpcId: 'm7',
          approvalId: 'ap-1',
          toolName: 'write',
          reason: 'needs write access',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: ApprovalCard())),
          ),
        );

        expect(find.byKey(const ValueKey('approval-card')), findsOneWidget);
        // The asker's reason is the headline; the toolName fallback only shows
        // when no reason rode the frame.
        expect(find.text('needs write access'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('approval-allow')));
        await tester.pump();
        expect(client.responds.single.rpcId.value, 'm7');
        expect(client.responds.single.decodedValue['outcome'], 'allowed-once');
        // One-shot latch: buttons stay disabled until the resolved frame lands.
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('approval-allow')),
              )
              .onPressed,
          isNull,
        );

        // Frame-driven removal: the broadcast resolution drops the wait.
        approvals.resolved('s-100', 'ap-1');
        await tester.pump();
        expect(find.byKey(const ValueKey('approval-card')), findsNothing);
      },
    );

    testWidgets('falls back to the escalation headline without a reason', (
      tester,
    ) async {
      bindApprovalClient(WsInputRecordingClient());
      addTearDown(() => bindApprovalClient(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(approvalsProvider.notifier)
          .requested('s-1', rpcId: 'r1', approvalId: 'a1', toolName: 'bash');
      container.read(sessionsProvider.notifier).addSession(_summary('s-1'));
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s-1'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ApprovalCard())),
        ),
      );

      expect(find.text('Escalation: bash'), findsOneWidget);
    });
  });

  group('QuestionsController (question/requested+resolved port)', () {
    late QuestionsController controller;
    setUp(() => controller = QuestionsController());

    test('requested mints keyed by session; replay is idempotent', () {
      controller.requested(
        's-100',
        rpcId: 'm10',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );
      expect(controller.waits['s-100']!.rpcId, 'm10');
      // Mux-open replay re-delivers still-pending requests with the same ids.
      controller.requested(
        's-100',
        rpcId: 'm10',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );
      expect(controller.waits, hasLength(1));
    });

    test('superseding replay re-arms with the live rpcId', () {
      controller.requested(
        's-100',
        rpcId: 'm10',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );
      // Generation death drops state; mux-open replay re-adds the live wait
      // with its fresh envelope id — replacement, not accumulation.
      controller.requested(
        's-100',
        rpcId: 'm11',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );
      expect(controller.waits, hasLength(1));
      expect(controller.waits['s-100']!.rpcId, 'm11');
    });

    test('resolved settles only the matching rpcId; stale frames drop', () {
      controller.requested(
        's-100',
        rpcId: 'm10',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );
      // A resolution for a superseded id must not drop the live wait.
      controller.resolved('s-100', 'm-stale', 'answered');
      expect(controller.waits, containsPair('s-100', isNotNull));
      controller.resolved('s-100', 'm10', 'answered');
      expect(controller.waits, isEmpty);
    });

    test('resolved on an unknown session is a no-op', () {
      controller.resolved('s-unknown', 'm10', 'answered');
      expect(controller.waits, isEmpty);
    });

    test('clear drops the whole session entry (removal / generation drop)',
        () {
      controller.requested(
        's-100',
        rpcId: 'm10',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );
      controller.clear('s-100');
      expect(controller.waits, isEmpty);
    });
  });

  group('QuestionResponder wire face', () {
    PendingQuestion planReviewPending(String rpcId) => PendingQuestion(
          rpcId: rpcId,
          sessionId: 's-100',
          questions: [QuestionItem.fromJson(_planReviewQuestion())],
        );

    test('answer echoes the requested rpcId with the legacy wrapper', () async {
      final client = WsInputRecordingClient();
      final batch = QuestionAnswerBatch(
        answers: const [
          QuestionAnswerItem(id: 'q1', selected: ['Approve']),
        ],
      );
      await QuestionResponder(
        client: client,
        pending: planReviewPending('m10'),
      ).answer(batch);
      expect(client.responds.single.rpcId.value, 'm10');
      expect(client.responds.single.ok, isTrue);
      expect(client.responds.single.decodedValue, {
        'sessionId': 's-100',
        'answer': {
          'answers': [
            {'id': 'q1', 'selected': ['Approve']},
          ],
        },
      });
    });

    test('answer sends the bare batch when the events channel is live',
        () async {
      final client = WsInputRecordingClient()..eventsClientId = 'c1';
      final batch = QuestionAnswerBatch(
        answers: const [
          QuestionAnswerItem(id: 'q1', selected: ['Approve']),
          QuestionAnswerItem(id: 'q2', selected: [], custom: 'other way'),
        ],
      );
      await QuestionResponder(
        client: client,
        pending: planReviewPending('m10'),
      ).answer(batch);
      expect(client.responds.single.rpcId.value, 'm10');
      expect(client.responds.single.decodedValue, {
        'answers': [
          {'id': 'q1', 'selected': ['Approve']},
          {
            'id': 'q2',
            'selected': [],
            'custom': 'other way',
          },
        ],
      });
    });

    test('cancel echoes the rpcId with the cancelled error', () async {
      final client = WsInputRecordingClient();
      await QuestionResponder(
        client: client,
        pending: planReviewPending('m10'),
      ).cancel();
      expect(client.responds.single.rpcId.value, 'm10');
      expect(client.responds.single.ok, isFalse);
      expect(
        client.responds.single.error!['code'],
        'cancelled',
      );
    });

    test('rejected receipt throws so the caller can re-arm', () async {
      final client = WsInputRecordingClient()
        ..nextReceipt = const RpcReceiptRejected('not-pending');
      await expectLater(
        QuestionResponder(
          client: client,
          pending: planReviewPending('late'),
        ).answer(
          const QuestionAnswerBatch(
            answers: [QuestionAnswerItem(id: 'q1', selected: ['Approve'])],
          ),
        ),
        throwsStateError,
      );
    });

    test('QuestionAnswerBatch omits empty custom (React answer shape)', () {
      const batch = QuestionAnswerBatch(
        answers: [
          QuestionAnswerItem(id: 'q1', selected: ['a'], custom: ''),
          QuestionAnswerItem(id: 'q2', selected: [], custom: 'free'),
        ],
      );
      expect(batch.toJson(), {
        'answers': [
          {'id': 'q1', 'selected': ['a']},
          {
            'id': 'q2',
            'selected': [],
            'custom': 'free',
          },
        ],
      });
    });
  });

  group('ApprovalResponder new transport', () {
    test('answer sends the bare outcome when the events channel is live',
        () async {
      final client = WsInputRecordingClient()..eventsClientId = 'c1';
      const pending = PendingApproval(
        rpcId: 'm7',
        sessionId: 's-100',
        approvalId: 'ap-1',
        toolName: 'write',
      );
      await ApprovalResponder(client: client, pending: pending)
          .answer(ApprovalAnswer.allowedOnce);
      expect(client.responds.single.rpcId.value, 'm7');
      expect(client.responds.single.ok, isTrue);
      expect(client.responds.single.value, 'allowed-once');
    });
  });

  group('planReviewOf narrowing (slots.ts planReviewOf port)', () {
    test('narrows the binary plan-review request', () {
      final review =
          planReviewOf([QuestionItem.fromJson(_planReviewQuestion())]);
      expect(review, isNotNull);
      expect(review!.id, 'q1');
      expect(review.approve.label, 'Approve');
      expect(review.decline!.label, 'Decline');
      expect(review.plan, '1. do it');
    });

    test('narrows approve-only to a null decline', () {
      final review = planReviewOf([
        QuestionItem.fromJson(const {
          'id': 'q1',
          'question': 'Proceed?',
          'detail': 'plan body',
          'intent': {'kind': 'plan-review', 'approve': 'Approve'},
          'options': [
            {'label': 'Approve'},
          ],
        }),
      ]);
      expect(review, isNotNull);
      expect(review!.decline, isNull);
    });

    test('rejects every shape the generic flow owns', () {
      Map<String, Object?> item({
        Object? intent = const {'kind': 'plan-review', 'approve': 'Approve'},
        Object? detail = 'plan body',
        Object? options = const [
          {'label': 'Approve'},
          {'label': 'Decline'},
        ],
        Object? multiSelect,
      }) =>
          {
            'id': 'q1',
            'question': 'Proceed?',
            if (detail != null) 'detail': detail,
            if (intent != null) 'intent': intent,
            if (options != null) 'options': options,
            if (multiSelect != null) 'multiSelect': multiSelect,
          };
      // Multi-question batches stay generic.
      expect(
        planReviewOf([
          QuestionItem.fromJson(item()),
          QuestionItem.fromJson(const {'id': 'q2', 'question': 'Other?'}),
        ]),
        isNull,
      );
      // Multi-select has answers two buttons cannot express.
      expect(
        planReviewOf([QuestionItem.fromJson(item(multiSelect: true))]),
        isNull,
      );
      // A third option has answers two buttons cannot express.
      expect(
        planReviewOf([
          QuestionItem.fromJson(
            item(
              options: const [
                {'label': 'Approve'},
                {'label': 'Decline'},
                {'label': 'Maybe'},
              ],
            ),
          ),
        ]),
        isNull,
      );
      // Missing approve label, missing detail, unknown intent, empty approve.
      expect(
        planReviewOf([
          QuestionItem.fromJson(
            item(
              options: const [
                {'label': 'Yes'},
                {'label': 'No'},
              ],
            ),
          ),
        ]),
        isNull,
      );
      expect(planReviewOf([QuestionItem.fromJson(item(detail: null))]), isNull);
      expect(
        planReviewOf([
          QuestionItem.fromJson(item(intent: const {'kind': 'other'})),
        ]),
        isNull,
      );
      expect(
        planReviewOf([
          QuestionItem.fromJson(
            item(intent: const {'kind': 'plan-review', 'approve': ''}),
          ),
        ]),
        isNull,
      );
    });
  });

  group('composer chain contract (question 0 beats approval 1)', () {
    test('selectors are disjoint across the two carriers', () {
      const question = PendingQuestion(
        rpcId: 'r1',
        sessionId: 's',
        questions: [],
      );
      const approval = PendingApproval(
        rpcId: 'r2',
        sessionId: 's',
        approvalId: 'ap',
        toolName: 'bash',
      );
      expect(questionComposerSelect(question), same(question));
      expect(questionComposerSelect(approval), isNull);
      expect(questionComposerSelect(null), isNull);
      expect(approvalComposerSelect(approval), same(approval));
      expect(approvalComposerSelect(question), isNull);
      expect(approvalComposerSelect(null), isNull);
    });

    test('plugin registers question at 0 and approval at 1, sorted first',
        () async {
      final client = WsInputRecordingClient();
      final host = wsInputHost(client: client);
      // Declare the conversation-owned chain the plugin injects into.
      host.slots.register(
        const RegistrationOptions(
          name: 'root',
          priority: 1,
          children: {
            'conversation.composer': SlotSpec(
              kind: SlotKind.chain,
              scope: SlotScope.session,
            ),
          },
        ),
        (context, props) => const SizedBox.shrink(),
      );
      host.register(const UserQuestionsPlugin());
      await host.activateAll();
      addTearDown(host.deactivateAll);

      final entries = host.slots.entries('conversation.composer');
      expect(entries, hasLength(2));
      expect(entries[0].priority, 0);
      expect(entries[0].options.id, 'ui-user-questions-composer');
      expect(entries[1].priority, 1);
      expect(entries[1].options.id, 'ui-user-questions-approval-composer');

      // Election in priority order: each currency elects its own entry.
      Object? elect(Object currency) {
        final sorted = List.of(entries)
          ..sort((a, b) => a.priority.compareTo(b.priority));
        for (final entry in sorted) {
          if (entry.options.select!(currency) != null) {
            return entry.options.id;
          }
        }
        return null;
      }
      const question = PendingQuestion(
        rpcId: 'r1',
        sessionId: 's',
        questions: [],
      );
      const approval = PendingApproval(
        rpcId: 'r2',
        sessionId: 's',
        approvalId: 'ap',
        toolName: 'bash',
      );
      expect(elect(question), 'ui-user-questions-composer');
      expect(elect(approval), 'ui-user-questions-approval-composer');
    });

    test('approval re-elects after the sibling question settles', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final questions = container.read(pendingQuestionsProvider.notifier);
      final approvals = container.read(approvalsProvider.notifier);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.addSession(_summary('s-100'));

      approvals.requested(
        's-100',
        rpcId: 'm7',
        approvalId: 'ap-1',
        toolName: 'write',
      );
      questions.requested(
        's-100',
        rpcId: 'm10',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );
      // Both wait: the question outranks the approval.
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
      expect(
        sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
        kPendingPlanReview,
      );
      expect(
        combinePendingStatuses(
          question: questions.waits['s-100'],
          approval: approvals.waits['s-100'],
        ),
        kPendingPlanReview,
      );

      // The question settles first: the surviving approval re-elects.
      questions.resolved('s-100', 'm10', 'answered');
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
      expect(
        sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
        kPendingApproval,
      );

      approvals.resolved('s-100', 'ap-1');
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
      expect(
        sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
        isNull,
      );
    });

    test('generic question outranks approval the same way plan-review does',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final questions = container.read(pendingQuestionsProvider.notifier);
      final approvals = container.read(approvalsProvider.notifier);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.addSession(_summary('s-100'));
      approvals.requested(
        's-100',
        rpcId: 'm7',
        approvalId: 'ap-1',
        toolName: 'write',
      );
      questions.requested(
        's-100',
        rpcId: 'm10',
        questions: [
          QuestionItem.fromJson(const {
            'id': 'q2',
            'question': 'Which database?',
            'options': [
              {'label': 'Postgres'},
              {'label': 'SQLite'},
              {'label': 'DuckDB'},
            ],
          }),
        ],
      );
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
      expect(
        sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
        kPendingQuestion,
      );
    });
  });

  group('unknown MuxFrame discriminant discards without side effects', () {
    test('every unknown type throws at decode and leaves waits empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final questions = container.read(pendingQuestionsProvider.notifier);
      final approvals = container.read(approvalsProvider.notifier);
      const unknownTypes = [
        'plan-review/requested',
        'question/updated',
        'approval/updated',
        'session/unknown',
      ];
      for (final type in unknownTypes) {
        // live_sync decodes inside try/catch: the throw is the discard.
        try {
          MuxFrame.fromJson({'type': type, 'sessionId': 's-100'});
          fail('expected $type to throw');
        } on ArgumentError {
          // Discarded, exactly as live_sync's catch does.
        }
      }
      expect(questions.waits, isEmpty);
      expect(approvals.waits, isEmpty);
    });
  });

  group('QuestionNodeCard batch surface', () {
    testWidgets('generic flow submits the whole answer batch', (tester) async {
      final client = WsInputRecordingClient();
      bindQuestionClient(client);
      addTearDown(() => bindQuestionClient(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(sessionsProvider.notifier).addSession(_summary('s-100'));
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s-100'));
      container.read(pendingQuestionsProvider.notifier).requested(
        's-100',
        rpcId: 'm10',
        questions: [
          QuestionItem.fromJson(const {
            'id': 'q1',
            'question': 'Which database?',
            'options': [
              {'label': 'Postgres'},
              {'label': 'SQLite'},
            ],
          }),
          QuestionItem.fromJson(const {
            'id': 'q2',
            'question': 'Which cache?',
            'options': [
              {'label': 'Redis'},
              {'label': 'Memcached'},
            ],
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: QuestionNodeCard())),
        ),
      );

      expect(find.byKey(const ValueKey('question-card')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('option-q1-Postgres')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('option-q2-Redis')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('question-submit')));
      await tester.pumpAndSettle();

      expect(client.responds.single.rpcId.value, 'm10');
      expect(client.responds.single.ok, isTrue);
      expect(client.responds.single.decodedValue, {
        'sessionId': 's-100',
        'answer': {
          'answers': [
            {
              'id': 'q1',
              'selected': ['Postgres'],
            },
            {
              'id': 'q2',
              'selected': ['Redis'],
            },
          ],
        },
      });
    });

    testWidgets('plan-review decide answers with the chosen label',
        (tester) async {
      final client = WsInputRecordingClient();
      bindQuestionClient(client);
      addTearDown(() => bindQuestionClient(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(sessionsProvider.notifier).addSession(_summary('s-100'));
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s-100'));
      container.read(pendingQuestionsProvider.notifier).requested(
        's-100',
        rpcId: 'm10',
        questions: [QuestionItem.fromJson(_planReviewQuestion())],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: QuestionNodeCard())),
        ),
      );

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(client.responds.single.rpcId.value, 'm10');
      expect(client.responds.single.decodedValue, {
        'sessionId': 's-100',
        'answer': {
          'answers': [
            {'id': 'q1', 'selected': ['Approve']},
          ],
        },
      });
    });

    testWidgets('renders nothing without a pending request', (tester) async {
      bindQuestionClient(WsInputRecordingClient());
      addTearDown(() => bindQuestionClient(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(sessionsProvider.notifier).addSession(_summary('s-100'));
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s-100'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: QuestionNodeCard())),
        ),
      );

      expect(find.byKey(const ValueKey('question-card')), findsNothing);
    });
  });
}
