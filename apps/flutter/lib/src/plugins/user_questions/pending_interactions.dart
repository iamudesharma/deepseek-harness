/// Pending-interaction policy shared by both wait kinds — stable wait keys,
/// wire status vocabulary, question→plan-review narrowing, and the
/// session-summary reconciliation the sidebar consumes.
///
/// Dart slice of `packages/client/runtime/src/client/sessions/pending.ts`
/// (key prefixes, `PendingInteractionStatus`) and `manager.ts`
/// (`questionInteractionStatus`, the list-snapshot precedence rule, and the
/// generation-drop clearing policy). Pure functions only: the frame routing
/// lives in live_sync.dart and the per-kind stores live next door.
library;

import '../../core/session/session_models.dart';
import 'approval_state.dart';
import 'question_models.dart';
import 'questions_state.dart';

/// Status vocabulary pushed into [SessionSummary.pendingInteraction]
/// (mirrors `PendingInteractionStatus` in pending.ts).
const String kPendingApproval = 'approval';
const String kPendingPlanReview = 'plan-review';
const String kPendingQuestion = 'question';

/// Stable approval wait identity: `<prefix>:<id>` doubles as the React key
/// and survives baseline replay verbatim (pending.ts `KEY_PREFIX.approval`).
String approvalWaitKey(String approvalId) => 'a:$approvalId';

/// Stable question wait identity keyed by the requested frame's envelope
/// rpcId (pending.ts `KEY_PREFIX.question`; manager.ts `bufferedRequestKey`).
String questionWaitKey(String rpcId) => 'q:$rpcId';

/// List-level status of one `question/requested`: `'plan-review'` when the
/// request narrows to the binary plan-review decision card, `'question'`
/// otherwise (port of `manager.ts:questionInteractionStatus`; same predicate
/// as the UI narrowing in [planReviewOf]).
String questionInteractionStatus(List<QuestionItem> questions) =>
    planReviewOf(questions) != null ? kPendingPlanReview : kPendingQuestion;

/// One displayed status per session from its live waits: a non-approval wait
/// outranks an approval (a question is a conversation the model is waiting
/// on; an approval blocks one tool call), matching the composer election rule
/// mirrored at `manager.ts` buildListSnapshot
/// (`statuses.find(candidate => candidate !== 'approval') ?? statuses[0]`).
String? combinePendingStatuses({
  required PendingQuestion? question,
  required PendingApproval? approval,
}) {
  if (question != null) return questionInteractionStatus(question.questions);
  if (approval != null) return kPendingApproval;
  return null;
}

/// Reconciles one summary's `pendingInteraction` marker against the live
/// waits. Unlike [SessionSummary.copyWith], a cleared field actually clears:
/// resolution must drop the amber dot, not preserve a stale one.
SessionSummary recomputePendingSummary(
  SessionSummary current,
  PendingQuestion? question,
  PendingApproval? approval,
) {
  final status = combinePendingStatuses(question: question, approval: approval);
  return current.withPendingInteraction(status);
}
