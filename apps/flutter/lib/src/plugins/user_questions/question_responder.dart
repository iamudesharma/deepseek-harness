/// Question answering — the Dart slice of `ui-user-questions`'s
/// `PendingQuestion` domain face: the answer batch and the cancelled-error
/// encoding live HERE, and both ride one carrier — `ConnectionClient.respond`
/// posting a client-response that echoes the requested frame's rpcId.
library;

import '../../core/api/rpc_envelope.dart';
import '../../core/connection/connection_client.dart';
import 'question_models.dart';
import 'questions_state.dart';

/// The question protocol face over one pending request. Components mint one
/// per pending request (stable identity rides [PendingQuestion.rpcId]).
class QuestionResponder {
  /// Creates the responder over one pending request.
  const QuestionResponder({
    required ConnectionClient client,
    required PendingQuestion pending,
  }) : _client = client,
       _pending = pending;

  final ConnectionClient _client;
  final PendingQuestion _pending;

  /// Deliver the whole answer batch; a rejected carrier receipt throws (the
  /// React face turns a rejected receipt into a thrown error too).
  ///
  /// Current master: `user-questions/request` waterfall expects
  /// `AskUserQuestionAnswer {answers:[{id,selected,custom?}]}` via
  /// `$events/result` `outcome:{kind:result,value:Answer}`.
  Future<void> answer(QuestionAnswerBatch batch) async {
    final bool useNew = _client.eventsClientId != null;
    final receipt = await _client.respond(
      rpcId: RpcId(_pending.rpcId),
      ok: true,
      value: useNew ? batch.toJson() : {'sessionId': _pending.sessionId, 'answer': batch.toJson()},
    );
    if (receipt is RpcReceiptRejected) {
      throw StateError('question response rejected: ${receipt.reason}');
    }
  }

  /// Reject the whole wait (the host resolves the tool call as cancelled);
  /// a rejected receipt throws.
  Future<void> cancel() async {
    final receipt = await _client.respond(
      rpcId: RpcId(_pending.rpcId),
      ok: false,
      error: const {
        'code': 'cancelled',
        'message': 'the user closed this question request',
        'details': {},
      },
    );
    if (receipt is RpcReceiptRejected) {
      throw StateError('question cancellation rejected: ${receipt.reason}');
    }
  }
}
