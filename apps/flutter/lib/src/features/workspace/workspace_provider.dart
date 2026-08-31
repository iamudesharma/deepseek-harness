import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/remote_mux_client.dart';
import '../../core/session/live_sync.dart';
import '../../core/session/session_models.dart';

/// Fallback synthetic workspaces for offline / host-unreachable UX.
///
/// Mirrors `kWorkspaceOptions` in the sidebar: keep as fallback so the UI
/// remains usable without a host (e.g. Flutter test, offline). Real data
/// comes from `workspaceList()` when available.
const kWorkspaceOptions = [
  WorkspaceView(
    workspaceId: WorkspaceId('default'),
    name: 'Default',
    cwd: '/work/default',
  ),
  WorkspaceView(
    workspaceId: WorkspaceId('project-a'),
    name: 'Project A',
    cwd: '/work/project-a',
  ),
];

/// Live workspaces from `workspace/follow` baseline + increments.
///
/// Mirrors `packages/client/ui-workspace/src/client/transport.ts` + `tree.ts`.
/// `WorkspaceController` has no `list` — only `workspace/follow` stream
/// (`baseline {items, archivedSessionIds}` then `upsert|remove|order|archived`).
/// `kWorkspaceOptions` remains offline fallback. The mux is shared via
/// `remoteMuxProvider` (same physical `WSS /api/remote.mux` as `session/follow`).
final _workspaceLiveListProvider =
    StateProvider<List<WorkspaceView>>((ref) => kWorkspaceOptions);

/// Live archived session ids from `workspace/follow` baseline + `archived` increments.
/// Mirrors `useWorkspaces(state => state.archivedSessionIds)` in React.
final _workspaceArchivedIdsProvider =
    StateProvider<Set<SessionId>>((ref) => <SessionId>{});

/// Public provider for archived ids (used by sidebar grouping to hide archived rows).
final workspaceArchivedIdsProvider = Provider<Set<SessionId>>((ref) {
  ref.watch(workspaceFollowPumpProvider);
  return ref.watch(_workspaceArchivedIdsProvider);
});

/// Pump `workspace/follow` into `_workspaceLiveListProvider`.
///
/// Idempotent: only one pump per mux generation. Handles `baseline` + `upsert`/
/// `remove`/`order`/`archived` (archived ignored for grouping, order re-sorts).
final workspaceFollowPumpProvider = Provider<void>((ref) {
  final mux = ref.watch(remoteMuxProvider);
  if (mux == null) return;
  // Keep one subscription per mux instance.
  ref.onDispose(() {});
  // Use a key to avoid duplicate pumps on unrelated rebuilds.
  final sub = _WorkspaceFollowPump(mux, ref);
  sub.start();
  ref.onDispose(() => sub.dispose());
});

class _WorkspaceFollowPump {
  _WorkspaceFollowPump(this.mux, this.ref);
  final RemoteMuxClient mux;
  final Ref ref;
  StreamSubscription<Map<String, dynamic>>? _sub;
  List<WorkspaceView> _items = const [];
  List<String> _order = const [];

  void start() {
    _sub?.cancel();
    _sub = mux.openWorkspaceFollow().listen(
      (raw) {
        final type = raw['type'] as String?;
        if (type == 'baseline') {
          final value = (raw['value'] as Map?) ?? raw;
          final itemsRaw = (value['items'] as List? ?? const []);
          try {
            _items = itemsRaw
                .whereType<Map>()
                .map((m) => WorkspaceView.fromJson(m.cast<String, dynamic>()))
                .toList();
          } catch (_) {
            _items = const [];
          }
          final orderRaw = (value['workspaceIds'] as List?) ??
              (value['order'] as List?) ??
              const [];
          _order = orderRaw.whereType<String>().toList();
          // Apply order if provided
          if (_order.isNotEmpty) {
            final byId = {for (final w in _items) w.workspaceId.value: w};
            _items = [
              for (final id in _order) if (byId.containsKey(id)) byId[id]!,
              for (final w in _items) if (!_order.contains(w.workspaceId.value)) w,
            ];
          }
          // Host is authoritative: even empty list wins over synthetic fallback.
          // Synthetic kWorkspaceOptions is only for pre-baseline / offline.
          ref.read(_workspaceLiveListProvider.notifier).state = _items;
          // Capture archived ids from baseline.
          final archivedRaw = (value['archivedSessionIds'] as List? ?? const []);
          final archived = archivedRaw
              .whereType<String>()
              .map(SessionId.new)
              .toSet();
          ref.read(_workspaceArchivedIdsProvider.notifier).state = archived;
        } else if (type == 'upsert') {
          final wRaw = raw['workspace'] as Map?;
          if (wRaw == null) return;
          try {
            final view = WorkspaceView.fromJson(wRaw.cast<String, dynamic>());
            final idx = _items.indexWhere((w) => w.workspaceId == view.workspaceId);
            if (idx >= 0) {
              _items = [..._items]..[idx] = view;
            } else {
              _items = [..._items, view];
            }
            ref.read(_workspaceLiveListProvider.notifier).state = _items;
          } catch (_) {}
        } else if (type == 'remove') {
          final idRaw = raw['workspaceId'] as String?;
          if (idRaw == null) return;
          _items = _items.where((w) => w.workspaceId.value != idRaw).toList();
          ref.read(_workspaceLiveListProvider.notifier).state = _items;
        } else if (type == 'order') {
          final ids = (raw['workspaceIds'] as List? ?? const []).whereType<String>().toList();
          _order = ids;
          final byId = {for (final w in _items) w.workspaceId.value: w};
          _items = [
            for (final id in _order) if (byId.containsKey(id)) byId[id]!,
            for (final w in _items) if (!_order.contains(w.workspaceId.value)) w,
          ];
          ref.read(_workspaceLiveListProvider.notifier).state = _items;
        } else if (type == 'archived') {
          final idsRaw = (raw['archivedSessionIds'] as List? ?? const [])
              .whereType<String>()
              .map(SessionId.new)
              .toSet();
          ref.read(_workspaceArchivedIdsProvider.notifier).state = idsRaw;
        }
      },
      onError: (_) {
        // Keep last known; fallback already synthetic
      },
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// Real `workspace.list` provider — now live via `workspace/follow`.
///
/// Watches the live pump so UI updates on baseline + increments. Falls back
/// to synthetic `kWorkspaceOptions` offline or before first baseline. The old
/// `workspace.list` unary was removed in master (`WorkspaceController` only
/// `follow`), so no `client.workspaceList()` call — avoids `404`.
final workspaceListProvider = Provider<AsyncValue<List<WorkspaceView>>>((ref) {
  // Ensure pump is running (idempotent)
  ref.watch(workspaceFollowPumpProvider);
  final live = ref.watch(_workspaceLiveListProvider);
  // `AsyncValue.data` so existing `when(loading/error/data)` and `valueOrNull`
  // call sites keep working (they previously watched FutureProvider).
  return AsyncValue.data(live);
});

// Backward-compat alias for `ref.watch(workspaceListProvider)` that previously
// returned `FutureProvider`'s `AsyncValue`; `Provider<AsyncValue<...>>` already
// matches. Keep `FutureProvider` name for grep, but now stream-backed.

/// Host cwd provider for the workspace screen header.
///
/// Mirrors `host.describe` — shows `cwd` so the user sees where a new
/// workspace will be created. Separate provider so `workspaceList` and host
/// describe can load/error independently with their own Retry.
final hostDescribeProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(connectionClientProvider);
  return client.hostDescribe();
});

final selectedWorkspaceProvider = StateProvider<WorkspaceId?>((ref) => null);
final workspaceSavingProvider = StateProvider<bool>((ref) => false);
