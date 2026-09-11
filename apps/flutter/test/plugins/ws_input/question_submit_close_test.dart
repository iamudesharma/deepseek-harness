/// Submit-not-closing regression: a settled question/approval answer must
/// unmount its card locally (React `answerQuestion`'s `finally remove()`),
/// because the host never emits `question/resolved` / `approval/resolved`
/// for a decided request — only cancellations synthesize one. A rejected
/// receipt keeps the surface open with the failure shown for retry.
import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/session/live_sync.dart'
    show reconcileSessionPendingStatus;
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/pending_interactions.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/ui/approval_card.dart';
import 'package:dsh_flutter/src/plugins/user_questions/ui/question_node_card.dart'
    show QuestionNodeCard, bindQuestionClient;
import 'package:dsh_flutter/src/widgets/primitives/ds_button.dart'
    show DsButton;
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

Map<String, Object?> _genericQuestion(String id, String text) => {
  'id': id,
  'question': text,
  'options': [
    {'label': 'Yes'},
    {'label': 'No'},
  ],
};

ProviderContainer _containerWithSession(String sid) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(sessionsProvider.notifier).addSession(_summary(sid));
  container
      .read(sessionsProvider.notifier)
      .setCurrent(SessionId(sid));
  return container;
}

void _requestQuestion(ProviderContainer container, String sid, String rpc) {
  container
      .read(pendingQuestionsProvider.notifier)
      .requested(
        sid,
        rpcId: rpc,
        questions: [QuestionItem.fromJson(_genericQuestion('q1', 'Proceed?'))],
      );
  reconcileSessionPendingStatus(
    container.read(pendingQuestionsProvider.notifier),
    container.read(approvalsProvider.notifier),
    container.read(sessionsProvider.notifier),
    sid,
  );
}

Future<void> _pumpQuestionCard(
  WidgetTester tester,
  ProviderContainer container,
) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: QuestionNodeCard())),
    ),
  );
}

void main() {
  group('question submit closes the card (React finally-remove parity)', () {
    testWidgets('successful submit removes the wait and unmounts', (
      tester,
    ) async {
      final client = WsInputRecordingClient();
      bindQuestionClient(client);
      addTearDown(() => bindQuestionClient(null));
      final container = _containerWithSession('s-100');
      _requestQuestion(container, 's-100', 'm10');

      await _pumpQuestionCard(tester, container);
      expect(find.byKey(const ValueKey('question-card')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('option-q1-Yes')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('question-submit')));
      await tester.pumpAndSettle();

      expect(client.responds.single.rpcId.value, 'm10');
      // The accepted receipt settles the wait locally: no host frame needed.
      expect(container.read(pendingQuestionsProvider), isEmpty);
      expect(
        container
            .read(sessionsProvider.notifier)
            .snapshot
            .byId[const SessionId('s-100')]!
            .pendingInteraction,
        isNull,
      );
      expect(find.byKey(const ValueKey('question-card')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejected receipt keeps the card with the error; retry closes', (
      tester,
    ) async {
      final client = WsInputRecordingClient()
        ..nextReceipt = const RpcReceiptRejected('not-pending');
      bindQuestionClient(client);
      addTearDown(() => bindQuestionClient(null));
      final container = _containerWithSession('s-100');
      _requestQuestion(container, 's-100', 'm10');

      await _pumpQuestionCard(tester, container);
      await tester.tap(find.byKey(const ValueKey('option-q1-Yes')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('question-submit')));
      await tester.pumpAndSettle();

      // Still open with the failure shown — never hide a refused request.
      expect(find.byKey(const ValueKey('question-card')), findsOneWidget);
      expect(
        container.read(pendingQuestionsProvider).containsKey('s-100'),
        isTrue,
      );
      expect(find.textContaining('not-pending'), findsOneWidget);
      // Buttons re-arm for retry.
      expect(
        tester
            .widget<DsButton>(find.byKey(const ValueKey('question-submit')))
            .onPressed,
        isNotNull,
      );

      client.nextReceipt = null;
      await tester.tap(find.byKey(const ValueKey('question-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('question-card')), findsNothing);
      expect(container.read(pendingQuestionsProvider), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel settles locally and unmounts', (tester) async {
      final client = WsInputRecordingClient();
      bindQuestionClient(client);
      addTearDown(() => bindQuestionClient(null));
      final container = _containerWithSession('s-100');
      _requestQuestion(container, 's-100', 'm10');

      await _pumpQuestionCard(tester, container);
      await tester.tap(find.byKey(const ValueKey('question-cancel')));
      await tester.pumpAndSettle();

      expect(client.responds.single.ok, isFalse);
      expect(container.read(pendingQuestionsProvider), isEmpty);
      expect(find.byKey(const ValueKey('question-card')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty submit shows incomplete and sends nothing', (
      tester,
    ) async {
      final client = WsInputRecordingClient();
      bindQuestionClient(client);
      addTearDown(() => bindQuestionClient(null));
      final container = _containerWithSession('s-100');
      _requestQuestion(container, 's-100', 'm10');

      await _pumpQuestionCard(tester, container);
      await tester.tap(find.byKey(const ValueKey('question-submit')));
      await tester.pumpAndSettle();

      // React parity: no wire traffic, card stays open for a real answer.
      expect(client.responds, isEmpty);
      expect(find.byKey(const ValueKey('question-card')), findsOneWidget);
      expect(
        container.read(pendingQuestionsProvider).containsKey('s-100'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a late duplicate settlement is a harmless no-op', (
      tester,
    ) async {
      final client = WsInputRecordingClient();
      bindQuestionClient(client);
      addTearDown(() => bindQuestionClient(null));
      final container = _containerWithSession('s-100');
      _requestQuestion(container, 's-100', 'm10');

      await _pumpQuestionCard(tester, container);
      await tester.tap(find.byKey(const ValueKey('option-q1-Yes')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('question-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('question-card')), findsNothing);

      // A duplicate/late frame for the settled id drops without effect.
      container
          .read(pendingQuestionsProvider.notifier)
          .resolved('s-100', 'm10', 'answered');
      await tester.pump();
      expect(find.byKey(const ValueKey('question-card')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('approval answer closes the card (React finally-remove parity)', () {
    Future<void> pumpApproval(
      WidgetTester tester,
      ProviderContainer container,
    ) {
      return tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ApprovalCard())),
        ),
      );
    }

    testWidgets('allow removes the wait and unmounts without a frame', (
      tester,
    ) async {
      final client = WsInputRecordingClient();
      bindApprovalClient(client);
      addTearDown(() => bindApprovalClient(null));
      final container = _containerWithSession('s-100');
      container
          .read(approvalsProvider.notifier)
          .requested(
            's-100',
            rpcId: 'm7',
            approvalId: 'ap-1',
            toolName: 'write',
            reason: 'needs write access',
          );

      await pumpApproval(tester, container);
      expect(find.byKey(const ValueKey('approval-card')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('approval-allow')));
      await tester.pumpAndSettle();

      expect(client.responds.single.rpcId.value, 'm7');
      expect(container.read(approvalsProvider), isEmpty);
      expect(find.byKey(const ValueKey('approval-card')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejected answer re-arms the buttons and keeps the card', (
      tester,
    ) async {
      final client = WsInputRecordingClient()
        ..nextReceipt = const RpcReceiptRejected('not-pending');
      bindApprovalClient(client);
      addTearDown(() => bindApprovalClient(null));
      final container = _containerWithSession('s-100');
      container
          .read(approvalsProvider.notifier)
          .requested(
            's-100',
            rpcId: 'm7',
            approvalId: 'ap-1',
            toolName: 'write',
          );

      await pumpApproval(tester, container);
      await tester.tap(find.byKey(const ValueKey('approval-allow')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('approval-card')), findsOneWidget);
      expect(
        container.read(approvalsProvider).containsKey('s-100'),
        isTrue,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('approval-allow')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
