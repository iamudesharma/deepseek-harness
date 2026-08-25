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
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/ui/approval_card.dart';
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

    test('questionInteractionStatus narrows the binary plan-review request', () {
      final planReview = [
        QuestionItem.fromJson(_planReviewQuestion()),
      ];
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
    });

    test(
        'combinePendingStatuses ranks question ahead of approval '
        '(manager.ts: first non-approval wins)', () {
      expect(
        combinePendingStatuses(
          question: PendingQuestion(rpcId: 'm1', sessionId: 's', questions: const []),
          approval: const PendingApproval(
              rpcId: 'm2', sessionId: 's', approvalId: 'a', toolName: 'bash'),
        ),
        kPendingQuestion,
      );
      expect(
        combinePendingStatuses(
          question: null,
          approval: const PendingApproval(
              rpcId: 'm2', sessionId: 's', approvalId: 'a', toolName: 'bash'),
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

    test('requested mints keyed by session; replacement is idempotent on replay',
        () {
      controller.requested('s-100',
          rpcId: 'm7', approvalId: 'ap-1', toolName: 'write');
      expect(controller.waits['s-100']!.rpcId, 'm7');
      // Mux-open replay re-delivers still-pending requests with the same ids.
      controller.requested('s-100',
          rpcId: 'm7', approvalId: 'ap-1', toolName: 'write');
      expect(controller.waits.length, 1);
    });

    test('resolved settles only the matching approvalId; stale frames drop',
        () {
      controller.requested('s-100',
          rpcId: 'm7', approvalId: 'ap-1', toolName: 'write');
      // A resolution for a superseded id must not drop the live wait.
      controller.resolved('s-100', 'ap-stale');
      expect(controller.waits, containsPair('s-100', isNotNull));
      controller.resolved('s-100', 'ap-1');
      expect(controller.waits, isEmpty);
    });

    test('clear drops the whole session entry (removal / generation drop)',
        () {
      controller.requested('s-100',
          rpcId: 'm7', approvalId: 'ap-1', toolName: 'write');
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
      await ApprovalResponder(client: client, pending: pending)
          .answer(ApprovalAnswer.allowedOnce);
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
        ApprovalResponder(client: client, pending: pending)
            .answer(ApprovalAnswer.rejected),
        throwsStateError,
      );
    });
  });

  group('interaction-plane reconciliation through live_sync helpers', () {
    test('requested arms the amber dot; sibling question outranks approval',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final questions = container.read(pendingQuestionsProvider.notifier);
      final approvals = container.read(approvalsProvider.notifier);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.addSession(_summary('s-100'));

      approvals.requested('s-100',
          rpcId: 'm7', approvalId: 'ap-1', toolName: 'write');
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');
      expect(
        sessions.snapshot.byId[const SessionId('s-100')]!.pendingInteraction,
        kPendingApproval,
      );

      questions.requested('s-100', rpcId: 'm10', questions: [
        QuestionItem.fromJson(_planReviewQuestion()),
      ]);
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
    });

    test('dropPendingInteractionState clears waits and summary markers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final questions = container.read(pendingQuestionsProvider.notifier);
      final approvals = container.read(approvalsProvider.notifier);
      final sessions = container.read(sessionsProvider.notifier);
      sessions.addSession(_summary('s-100'));
      approvals.requested('s-100',
          rpcId: 'm7', approvalId: 'ap-1', toolName: 'write');
      questions.requested('s-101', rpcId: 'm11', questions: const []);
      reconcileSessionPendingStatus(questions, approvals, sessions, 's-100');

      dropPendingInteractionState(questions, approvals, sessions);

      expect(approvals.waits, isEmpty);
      expect(questions.waits, isEmpty);
      expect(
        sessions.snapshot.byId.values
            .every((s) => s.pendingInteraction == null),
        isTrue,
      );
    });

    test('resync listener drops state when the connection generation dies',
        () {
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
      approvals.requested('s-100',
          rpcId: 'm7', approvalId: 'ap-1', toolName: 'write');
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

    test('unknown interaction frame types discard at decode (documented default)',
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
    });
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
      approvals.requested('s-100',
          rpcId: 'm7',
          approvalId: 'ap-1',
          toolName: 'write',
          reason: 'needs write access');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ApprovalCard())),
      ));

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
            .widget<FilledButton>(find.byKey(const ValueKey('approval-allow')))
            .onPressed,
        isNull,
      );

      // Frame-driven removal: the broadcast resolution drops the wait.
      approvals.resolved('s-100', 'ap-1');
      await tester.pump();
      expect(find.byKey(const ValueKey('approval-card')), findsNothing);
    });

    testWidgets('falls back to the escalation headline without a reason',
        (tester) async {
      bindApprovalClient(WsInputRecordingClient());
      addTearDown(() => bindApprovalClient(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(approvalsProvider.notifier).requested('s-1',
          rpcId: 'r1', approvalId: 'a1', toolName: 'bash');
      container
          .read(sessionsProvider.notifier)
          .addSession(_summary('s-1'));
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s-1'));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ApprovalCard())),
      ));

      expect(find.text('Escalation: bash'), findsOneWidget);
    });
  });
}
