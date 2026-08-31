/// Approval answering — the Dart slice of `ui-conversation`'s
/// `PendingApproval` domain face (contract/slots.ts): the decision payload
/// encoding lives HERE, and it rides one carrier — `ConnectionClient.respond`
/// posting a client-response that echoes the requested frame's rpcId with
/// `{ sessionId, approvalId, outcome }` as the result value.
library;

import '../../core/api/rpc_envelope.dart';
import '../../core/connection/connection_client.dart';
import 'approval_state.dart';

/// The outcomes a client may answer with. `cancelled` / `unavailable` are
/// host-side outcomes and never travel on a client-response
/// (`packages/host/apiproxy/src/api/approvals.ts:ApprovalResponsePayload`).
enum ApprovalAnswer {
  /// Grant once for this action.
  allowedOnce('allowed-once'),

  /// Refuse the action.
  rejected('rejected');

  const ApprovalAnswer(this.wire);

  /// Exact wire literal.
  final String wire;
}

/// The approval protocol face over one pending request. Components mint one
/// per pending request (stable identity rides [PendingApproval.rpcId]).
class ApprovalResponder {
  /// Creates the responder over one pending request.
  const ApprovalResponder({
    required ConnectionClient client,
    required PendingApproval pending,
  }) : _client = client,
       _pending = pending;

  final ConnectionClient _client;
  final PendingApproval _pending;

  /// Deliver the user's decision; a rejected carrier receipt throws (the
  /// React face turns a rejected receipt into a thrown error too). Panel
  /// removal stays frame-driven — the broadcast `approval/resolved` settles
  /// the wait and drops it from the store.
  ///
  /// Current master: `approval/request` waterfall expects `ApprovalOutcome`
  /// string via `$events/result` `outcome:{kind:result,value:Outcome}`.
  /// Legacy `POST /api/respond` used `{sessionId,approvalId,outcome}` wrapper.
  /// When `eventsClientId` is set (new transport) send bare outcome; otherwise
  /// keep legacy wrapper for compat.
  Future<void> answer(ApprovalAnswer outcome) async {
    final bool useNew = _client.eventsClientId != null;
    final receipt = await _client.respond(
      rpcId: RpcId(_pending.rpcId),
      ok: true,
      value: useNew
          ? outcome.wire
          : {
              'sessionId': _pending.sessionId,
              'approvalId': _pending.approvalId,
              'outcome': outcome.wire,
            },
    );
    if (receipt is RpcReceiptRejected) {
      throw StateError('approval response rejected: ${receipt.reason}');
    }
  }
}
