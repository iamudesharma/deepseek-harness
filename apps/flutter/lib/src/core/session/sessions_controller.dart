import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/connection_client.dart';
import 'session_models.dart';

/// Immutable sessions state: normalized map plus current selection.
///
/// Mirrors the list snapshot managed by `SessionManager` in
/// `packages/client/runtime/src/client/sessions/manager.ts` but trimmed to
/// UI-required fields. Map keys are [SessionId] raw strings for cheap equality.
///
/// Factory is invocable via `ProviderContainer` for tests — no static singleton.
class SessionsState {
  /// Sessions indexed by [SessionId.value].
  final Map<SessionId, SessionSummary> byId;

  /// Currently selected session id, or `null` when no session is selected.
  final SessionId? current;

  /// Creates sessions state.
  const SessionsState({this.byId = const {}, this.current});

  /// Whether a current session is selected and present in [byId].
  bool get hasCurrent => current != null && byId.containsKey(current);

  /// Currently selected session summary, or `null` when none selected / absent.
  SessionSummary? get currentSession {
    final id = current;
    if (id == null) return null;
    return byId[id];
  }

  /// All summaries sorted by [SessionSummary.updatedAt] descending (like host
  /// `session.list` order).
  List<SessionSummary> get sorted {
    final list = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(list);
  }

  /// Creates a copy with selected fields replaced.
  SessionsState copyWith({
    Map<SessionId, SessionSummary>? byId,
    SessionId? current,
    bool clearCurrent = false,
  }) {
    return SessionsState(
      byId: byId ?? this.byId,
      current: clearCurrent ? null : (current ?? this.current),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionsState &&
          runtimeType == other.runtimeType &&
          current == other.current &&
          _mapEquals(byId, other.byId);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      byId.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    current,
  );

  @override
  String toString() => 'SessionsState(byId: ${byId.length}, current: $current)';
}

bool _mapEquals(
  Map<SessionId, SessionSummary> a,
  Map<SessionId, SessionSummary> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other != entry.value) return false;
  }
  return true;
}

/// Riverpod controller for [SessionsState].
///
/// No static singleton — share via `ProviderScope` overrides to mirror
/// `createXXXStore` factory tests (`ProviderContainer().read(sessionsProvider.notifier)`).
///
/// Microtask batching: bulk list refreshes use [Future.microtask] to coalesce
/// rapid `session/added` + `session/status` bursts into one notification,
/// mirroring `Notifier.markDirty`. Single writes notify immediately (visible).
class SessionsController extends Notifier<SessionsState> {
  bool _batchScheduled = false;
  SessionsState? _batched;

  @override
  SessionsState build() => const SessionsState();

  /// Public read face for reconciliation helpers ([state] stays protected).
  SessionsState get snapshot => state;

  /// Select the current session. Pass `null` to clear.
  ///
  /// If [id] is non-null but absent from [SessionsState.byId], the selection
  /// is ignored (mirrors manager's `select` unknown-session guard without
  /// throwing in the UI layer).
  void setCurrent(SessionId? id) {
    if (id == null) {
      if (state.current == null) return;
      state = state.copyWith(clearCurrent: true);
      return;
    }
    if (!state.byId.containsKey(id)) return;
    if (state.current == id) return;
    state = state.copyWith(current: id);
  }

  /// Insert or replace one session summary.
  ///
  /// If the session is new, it is inserted; existing ids are replaced.
  void addSession(SessionSummary summary) {
    final next = Map<SessionId, SessionSummary>.from(state.byId);
    next[summary.sessionId] = summary;
    state = state.copyWith(byId: Map.unmodifiable(next));
  }

  /// Bulk replace from a fresh `session.list` pull.
  ///
  /// Batches via microtask so a burst of `session.list` + projection frames
  /// surfaces as one frame.
  void setAll(List<SessionSummary> summaries) {
    final next = <SessionId, SessionSummary>{
      for (final s in summaries) s.sessionId: s,
    };
    _scheduleBatched(
      SessionsState(
        byId: Map.unmodifiable(next),
        current: _resolveCurrent(next, state.current),
      ),
    );
  }

  /// Apply a partial update to one session if present.
  ///
  /// Returns `true` when the session existed and was updated.
  bool updateSession(
    SessionId id,
    SessionSummary Function(SessionSummary current) update,
  ) {
    final existing = state.byId[id];
    if (existing == null) return false;
    final next = update(existing);
    if (next == existing) return false;
    final map = Map<SessionId, SessionSummary>.from(state.byId);
    map[id] = next;
    state = state.copyWith(byId: Map.unmodifiable(map));
    return true;
  }

  /// Remove a session by id. Clears current selection if it pointed there.
  void removeSession(SessionId id) {
    if (!state.byId.containsKey(id)) return;
    final next = Map<SessionId, SessionSummary>.from(state.byId)..remove(id);
    final nextCurrent = state.current == id ? null : state.current;
    state = SessionsState(byId: Map.unmodifiable(next), current: nextCurrent);
  }

  /// Clear all sessions (e.g. on reconnect teardown).
  void clear() {
    if (state.byId.isEmpty && state.current == null) return;
    state = const SessionsState();
  }

  SessionId? _resolveCurrent(
    Map<SessionId, SessionSummary> nextById,
    SessionId? current,
  ) {
    if (current == null) return null;
    return nextById.containsKey(current) ? current : null;
  }

  void _scheduleBatched(SessionsState next) {
    _batched = next;
    if (_batchScheduled) return;
    _batchScheduled = true;
    Future.microtask(() {
      _batchScheduled = false;
      final batched = _batched;
      _batched = null;
      if (batched != null) {
        state = batched;
      }
    });
  }
}

/// Global sessions provider.
///
/// Seeded like `PLATFORM_MODULES` standing seats: override in `ProviderScope`
/// for scoped tests.
final sessionsProvider = NotifierProvider<SessionsController, SessionsState>(
  SessionsController.new,
);

/// Bootstrap future that hydrates [sessionsProvider] from the host `session.list`.
///
/// Watched once at app shell mount (e.g. in `DshApp`). In `flutter test` (vm,
/// file:// base) this no-ops so widget tests stay isolated with empty state.
final sessionBootstrapProvider = FutureProvider<void>((ref) async {
  final client = ref.watch(connectionClientProvider);
  if (client.baseUrl.isEmpty) return;
  try {
    final sessions = await client.getSessions();
    ref.read(sessionsProvider.notifier).setAll(sessions);
  } catch (e) {
    // Keep bootstrap as failed future so UI can show retry; don't throw to root.
    // ignore: avoid_print
    print('[sessionBootstrap] getSessions failed: $e');
    rethrow;
  }
});
