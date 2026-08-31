/// Subagent runtime link — the Dart slice of `ISessions`' subagent methods
/// that ui-subagent consumes in React (`openChild`, `refreshSubagents`,
/// `setSubagentCatalogOpen`). The shared sessions list is the navigation
/// target: opening a child selects its row through [selectSession], exactly
/// like `sessions.openSubagent` lands on the child session.
///
/// The link carries explicit ports instead of reaching Riverpod directly so
/// headless tests drive it against a real [SessionsController] and widget
/// code binds it to `ref.read(sessionsProvider.notifier)` without either
/// side importing the other's machinery.
library;

import '../../core/session/session_models.dart';

/// One addressed subagent: the parent whose catalog lists it plus the child
/// session the address opens.
class SubagentAddress {
  /// Creates an address.
  const SubagentAddress({
    required this.parentSessionId,
    required this.childSessionId,
  });

  /// Session whose catalog contains the child.
  final SessionId parentSessionId;

  /// Child session the address resolves to.
  final SessionId childSessionId;
}

/// Navigation + catalog-open state for one plugin instance. Provided as the
/// `'subagents'` service; widgets receive it at apply time.
class SubagentLink {
  /// Creates a link over explicit session ports.
  ///
  /// [selectSession] navigates by selecting the row in the shared sessions
  /// list (unknown ids are ignored by the controller's guard). [refreshParent]
  /// re-pulls one parent's live window — the refresh-catalog analog.
  SubagentLink({required this.selectSession, required this.refreshParent});

  /// Selects a session row in the shared sessions list.
  final void Function(SessionId sessionId) selectSession;

  /// Re-pulls one parent session's live history window.
  final Future<void> Function(SessionId parentSessionId) refreshParent;

  final Map<SessionId, bool> _catalogOpen = {};

  /// Whether the header catalog for [parentSessionId] is expanded.
  bool isCatalogOpen(SessionId parentSessionId) =>
      _catalogOpen[parentSessionId] ?? false;

  /// Mirrors `setSubagentCatalogOpen`: records expansion so reopening a
  /// header restores the state the user left behind.
  void setCatalogOpen(SessionId parentSessionId, bool open) {
    _catalogOpen[parentSessionId] = open;
  }

  /// Mirrors `openSubagent`: closes the originating catalog and navigates to
  /// the addressed child session.
  void openChild(SubagentAddress address) {
    setCatalogOpen(address.parentSessionId, false);
    selectSession(address.childSessionId);
  }

  /// Mirrors `refreshSubagents`: re-pulls [parentSessionId]'s live window so
  /// the next catalog read reflects fresh host state.
  Future<void> refresh(SessionId parentSessionId) =>
      refreshParent(parentSessionId);
}
