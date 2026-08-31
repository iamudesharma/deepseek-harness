/// Frame-fed pending-approval state — the approval half of the pending-wait
/// store (`packages/client/runtime/src/client/sessions/session.ts` mint/settle
/// over `approval/requested` / `approval/resolved`). The requested frame is an
/// answerable server-request whose envelope rpcId backs the client-response;
/// `approvalId` governs resolution matching, exactly as `PendingWait`
/// settlement matches `payload.approvalId`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One pending host-owned approval for a session (at most one live at a
/// time — a tool awaits its decision inline before the turn continues).
class PendingApproval {
  /// Creates a pending approval.
  const PendingApproval({
    required this.rpcId,
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    this.callId,
    this.reason,
  });

  /// The requested frame's stable envelope id; answers echo it verbatim.
  final String rpcId;

  /// Owning session.
  final String sessionId;

  /// Core audit correlation id; the resolved frame names it to settle.
  final String approvalId;

  /// Tool awaiting approval (headline fallback in the card).
  final String toolName;

  /// Paired tool-call identity when the ask names one.
  final String? callId;

  /// Asker's human-readable why (card headline when present).
  final String? reason;
}

/// Per-session pending-approval store. [requested] replaces a session's
/// entry (mux-open replay re-delivers still-pending requests with the same
/// rpcId, so replacement is idempotent); [resolved] clears only when the
/// settling frame names the stored [PendingApproval.approvalId], so a stale
/// resolved frame cannot drop a superseding live wait.
class ApprovalsController extends StateNotifier<Map<String, PendingApproval>> {
  ApprovalsController() : super(const {});

  /// Public read face for reconciliation helpers ([state] stays protected).
  Map<String, PendingApproval> get waits => state;

  /// Applies one `approval/requested` frame.
  void requested(
    String sessionId, {
    required String rpcId,
    required String approvalId,
    required String toolName,
    String? callId,
    String? reason,
  }) {
    state = {
      ...state,
      sessionId: PendingApproval(
        rpcId: rpcId,
        sessionId: sessionId,
        approvalId: approvalId,
        toolName: toolName,
        callId: callId,
        reason: reason,
      ),
    };
  }

  /// Applies one `approval/resolved` frame (`outcome`: allowed-once |
  /// rejected | cancelled | unavailable — all four settle the wait).
  void resolved(String sessionId, String approvalId) {
    final current = state[sessionId];
    if (current == null || current.approvalId != approvalId) return;
    state = {...state}..remove(sessionId);
  }

  /// Drops a session's entry entirely (session removed / generation dropped).
  void clear(String sessionId) {
    if (!state.containsKey(sessionId)) return;
    state = {...state}..remove(sessionId);
  }
}

/// Pending approvals per session id.
final approvalsProvider =
    StateNotifierProvider<ApprovalsController, Map<String, PendingApproval>>(
      (ref) => ApprovalsController(),
    );
