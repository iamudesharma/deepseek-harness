/// Host-born session policy — the one place that states how a Flutter client
/// brings a session into existence.
///
/// Invariant (React `SessionManager.create` +
/// `packages/client/runtime/src/client/contract/session.ts`): sessions are
/// born on the host via `session.create` — Session, Agent, and cwd come into
/// being together — so there is no local fake pre-entity. Callers adopt
/// exactly the id the host returned (`result.value.sessionId`, unwrapped by
/// `ConnectionClient.createSession`) and may address it immediately by
/// projecting a blank summary before the next list refresh confirms it.
///
/// The only sanctioned create-failure retry is the workspace-attach case:
/// the host rejected the workspace binding while the session itself is not
/// addressable, so the caller retries once without the binding rather than
/// failing the whole flow.
library;

import '../api/rpc_envelope.dart';
import 'session_models.dart';

/// Builds the `session.create` wire payload: the workspace binding travels
/// only when declared; an absent binding lets the host apply its default.
Map<String, dynamic> sessionCreatePayload({String? workspaceId, String? cwd}) {
  return {
    // ignore: use_null_aware_elements
    if (workspaceId != null) 'workspaceId': workspaceId,
    // ignore: use_null_aware_elements
    if (cwd != null) 'cwd': cwd,
  };
}

/// Whether a `session.create` failure is the workspace-binding rejection —
/// the single retryable case, retried without the workspace binding (or
/// with a `cwd` fallback for synthetic workspaces).
///
/// The host's typed codes are `workspace-not-found` (pre-create, no
/// session) and `workspace-attach-failed` (post-create with
/// `details.sessionId`). Carriers may see them as typed
/// [RemoteMethodException] or, for compat, as transport strings that embed
/// the wire literal.
bool isWorkspaceAttachFailure(Object error) {
  if (error is RemoteMethodException) {
    return error.code == RpcErrorCode.workspaceNotFound ||
        error.code == RpcErrorCode.workspaceAttachFailed;
  }
  final msg = error.toString();
  return msg.contains('workspace-not-found') ||
      msg.contains('workspace-attach-failed');
}

/// The summary projected at adoption time: a created session exists with an
/// empty log — running false, blank true (manager.ts create arm:
/// "a created session is blank by definition"). Projecting it immediately
/// keeps the id synchronously addressable in the sidebar instead of blank
/// until the next list pull lands.
SessionSummary adoptHostBornSession(SessionId sessionId, {int? now}) =>
    SessionSummary(
      sessionId: sessionId,
      updatedAt: now ?? DateTime.now().millisecondsSinceEpoch,
      running: false,
      blank: true,
    );
