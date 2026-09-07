import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_models.dart';
import 'sessions_controller.dart';

/// Provider for the currently selected session's summary.
///
/// Mirrors `useSession()` / `useSessions(selector)` standing seats from
/// `packages/client/ui-renderer` and `packages/client/runtime`. Returns `null`
/// when no session is selected or the selected id is not in [sessionsProvider].
///
/// Usage:
///
/// ```dart
/// final current = ref.watch(currentSessionProvider);
/// if (current == null) return const NoSessionView();
/// ```
final currentSessionProvider = Provider<SessionSummary?>((ref) {
  return ref.watch(sessionsProvider.select((s) => s.currentSession));
});

/// Whether a current session is selected.
final hasCurrentSessionProvider = Provider<bool>((ref) {
  return ref.watch(sessionsProvider.select((s) => s.hasCurrent));
});

/// Family provider for one session by id.
///
/// Mirrors per-session `useSession(id)` patterns and `sessionProvider` scopes.
/// Returns `null` when the id is not in the sessions map.
///
/// Usage:
///
/// ```dart
/// final summary = ref.watch(sessionByIdProvider(sessionId));
/// ```
final sessionByIdProvider = Provider.family<SessionSummary?, SessionId>((
  ref,
  id,
) {
  return ref.watch(sessionsProvider.select((s) => s.byId[id]));
});

/// All session summaries sorted by [SessionSummary.updatedAt] descending
/// (host `session.list` order).
final sortedSessionsProvider = Provider<List<SessionSummary>>((ref) {
  return ref.watch(sessionsProvider.select((s) => s.sorted));
});

/// Current session id (raw selection, may be absent from [sessionsProvider.byId]).
final currentSessionIdProvider = Provider<SessionId?>((ref) {
  return ref.watch(sessionsProvider.select((s) => s.current));
});
