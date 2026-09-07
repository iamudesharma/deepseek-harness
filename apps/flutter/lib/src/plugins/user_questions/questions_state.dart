/// Frame-fed pending-question state — the queue_state.dart pattern applied to
/// the interaction frames: `question/requested` carries the authoritative
/// whole question set (its envelope rpcId is the question's stable logical
/// id, echoed by answers), and `question/resolved` announces settlement keyed
/// by that same rpcId.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'question_models.dart';

/// One pending question request for a session (at most one at a time — the
/// host serializes ask() per session).
@immutable
class PendingQuestion {
  /// Creates a pending request.
  const PendingQuestion({
    required this.rpcId,
    required this.sessionId,
    required this.questions,
  });

  /// The requested frame's stable envelope id; answers echo it verbatim.
  final String rpcId;

  /// Owning session.
  final String sessionId;

  /// The decoded `AskUserQuestionItem[]`.
  final List<QuestionItem> questions;
}

/// Per-session pending-question store. [requested] replaces a session's
/// entry (replay re-delivers the same rpcId, so replacement is idempotent);
/// [resolved] clears only when the settling rpcId matches the stored one.
class QuestionsController extends StateNotifier<Map<String, PendingQuestion>> {
  QuestionsController() : super(const {});

  /// Public read face for reconciliation helpers ([state] stays protected).
  Map<String, PendingQuestion> get waits => state;

  /// Applies one `question/requested` frame.
  void requested(
    String sessionId, {
    required String rpcId,
    required List<QuestionItem> questions,
  }) {
    state = {
      ...state,
      sessionId: PendingQuestion(
        rpcId: rpcId,
        sessionId: sessionId,
        questions: questions,
      ),
    };
  }

  /// Applies one `question/resolved` frame (`outcome`: answered | cancelled).
  void resolved(String sessionId, String questionRpcId, String outcome) {
    final current = state[sessionId];
    if (current == null || current.rpcId != questionRpcId) return;
    final next = {...state}..remove(sessionId);
    state = next;
  }

  /// Drops a session's entry entirely (session removed).
  void clear(String sessionId) {
    if (!state.containsKey(sessionId)) return;
    state = {...state}..remove(sessionId);
  }
}

/// Pending question requests per session id.
final pendingQuestionsProvider =
    StateNotifierProvider<QuestionsController, Map<String, PendingQuestion>>(
      (ref) => QuestionsController(),
    );
