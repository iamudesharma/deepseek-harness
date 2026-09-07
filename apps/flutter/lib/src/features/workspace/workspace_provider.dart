import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/remote_mux_client.dart';
import '../../core/session/live_sync.dart';
import '../../core/session/session_models.dart';
import '../../core/session/sessions_controller.dart';
import '../../utils/workspace_labels.dart' show workspaceLabel;

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

/// Diagnostic state for Phase 0 instrumentation — tracks whether the live pump
/// has received a baseline and whether the current [workspaceListProvider]
/// value is still the synthetic fallback. Mirrors the screenshot symptom
/// (`Default`/`Project A` + `Ungrouped 53`) when `isFallback` stays true.
class WorkspaceSyncDiagnostics {
  const WorkspaceSyncDiagnostics({
    required this.isFallback,
    required this.liveCount,
    required this.hasBaseline,
    required this.lastBaselineAt,
    required this.lastError,
  });
  final bool isFallback;
  final int liveCount;
  final bool hasBaseline;
  final DateTime? lastBaselineAt;
  final String? lastError;
}

final _workspaceHasBaselineProvider = StateProvider<bool>((ref) => false);
final _workspaceLastBaselineAtProvider = StateProvider<DateTime?>((ref) => null);
final _workspaceLastErrorProvider = StateProvider<String?>((ref) => null);

/// Public diagnostics for overlay/logging — Phase 0 instrument.
final workspaceDiagnosticsProvider = Provider<WorkspaceSyncDiagnostics>((ref) {
  final live = ref.watch(_workspaceLiveListProvider);
  final hasBaseline = ref.watch(_workspaceHasBaselineProvider);
  final lastAt = ref.watch(_workspaceLastBaselineAtProvider);
  final lastError = ref.watch(_workspaceLastErrorProvider);
  // Fallback detection: strict identity against kWorkspaceOptions length+names
  final isFallback = !hasBaseline &&
      live.length == kWorkspaceOptions.length &&
      live.every((w) => kWorkspaceOptions.any((k) => k.workspaceId == w.workspaceId));
  return WorkspaceSyncDiagnostics(
    isFallback: isFallback,
    liveCount: live.length,
    hasBaseline: hasBaseline,
    lastBaselineAt: lastAt,
    lastError: lastError,
  );
});

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
  if (mux == null) {
    // Phase 0: surface mux-not-ready so fallback symptom is explainable.
    // ignore: avoid_print
    print('[workspace] pump skipped: remoteMux == null (still fallback ${kWorkspaceOptions.map((w) => w.name).join(",")})');
    return;
  }
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
    // Phase 0: surface stream open.
    // ignore: avoid_print
    print('[workspace] pump start: open workspace/follow');
    _sub = mux.openWorkspaceFollow().listen(
      (raw) {
        final type = raw['type'] as String?;
        if (type == 'baseline') {
          final value = (raw['value'] as Map?) ?? raw;
          final itemsRaw = (value['items'] as List? ?? const []);
          List<WorkspaceView> parsed;
          try {
            parsed = itemsRaw
                .whereType<Map>()
                .map((m) => WorkspaceView.fromJson(m.cast<String, dynamic>()))
                .toList();
            _items = parsed;
          } catch (e, st) {
            // ignore: avoid_print
            print('[workspace] baseline parse failed: $e $st raw=$raw');
            ref.read(_workspaceLastErrorProvider.notifier).state = 'parse:$e';
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
          // ignore: avoid_print
          print('[workspace] baseline items=${_items.length} names=${_items.map((w)=>w.name).join(",")} order=${_order.join(",")} archived=${(value['archivedSessionIds'] as List?)?.length ?? 0} rawKeys=${value.keys.join(",")}');
          ref.read(_workspaceHasBaselineProvider.notifier).state = true;
          ref.read(_workspaceLastBaselineAtProvider.notifier).state = DateTime.now();
          ref.read(_workspaceLastErrorProvider.notifier).state = null;
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
            // ignore: avoid_print
            print('[workspace] upsert ${view.workspaceId.value} -> count=${_items.length}');
          } catch (e, st) {
            // ignore: avoid_print
            print('[workspace] upsert parse failed: $e $st raw=$raw');
            ref.read(_workspaceLastErrorProvider.notifier).state = 'upsert:$e';
          }
        } else if (type == 'remove') {
          final idRaw = raw['workspaceId'] as String?;
          if (idRaw == null) return;
          _items = _items.where((w) => w.workspaceId.value != idRaw).toList();
          ref.read(_workspaceLiveListProvider.notifier).state = _items;
          // ignore: avoid_print
          print('[workspace] remove $idRaw -> count=${_items.length}');
        } else if (type == 'order') {
          final ids = (raw['workspaceIds'] as List? ?? const []).whereType<String>().toList();
          _order = ids;
          final byId = {for (final w in _items) w.workspaceId.value: w};
          _items = [
            for (final id in _order) if (byId.containsKey(id)) byId[id]!,
            for (final w in _items) if (!_order.contains(w.workspaceId.value)) w,
          ];
          ref.read(_workspaceLiveListProvider.notifier).state = _items;
          // ignore: avoid_print
          print('[workspace] order ${ids.join(",")}');
        } else if (type == 'archived') {
          final idsRaw = (raw['archivedSessionIds'] as List? ?? const [])
              .whereType<String>()
              .map(SessionId.new)
              .toSet();
          ref.read(_workspaceArchivedIdsProvider.notifier).state = idsRaw;
          // ignore: avoid_print
          print('[workspace] archived ${idsRaw.length}');
        } else {
          // ignore: avoid_print
          print('[workspace] unknown type=$type raw=$raw');
        }
      },
      onError: (e, st) {
        // Keep last known; fallback already synthetic
        // ignore: avoid_print
        print('[workspace] stream error: $e $st');
        ref.read(_workspaceLastErrorProvider.notifier).state = 'stream:$e';
      },
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// Synthesized workspaces from session cwds — offline/catch-up fallback.
///
/// When the host `workspace/follow` baseline has not yet arrived and the only
/// live value is the synthetic [kWorkspaceOptions], derive one workspace per
/// distinct `cwd` from the current sessions. This matches the visual expectation
/// of `hhh` / `untitled folder` groups (React parity) even when the mux is
/// not yet connected, while remaining compatible with `tree.ts:groupByWorkspace`
/// membership via `sessionIds`.
///
/// Host remains authoritative: once a real baseline lands (`hasBaseline==true`),
/// synthesis is bypassed even if the host list is empty.
List<WorkspaceView> _synthesizedFromSessions(
  Map<SessionId, SessionSummary> byId,
  Set<SessionId> archived,
) {
  final byCwd = <String, List<SessionSummary>>{};
  for (final s in byId.values) {
    if (s.origin == 'subagent') continue;
    if (archived.contains(s.sessionId)) continue;
    final cwd = s.cwd;
    if (cwd == null || cwd.isEmpty) continue;
    byCwd.putIfAbsent(cwd, () => []).add(s);
  }
  if (byCwd.isEmpty) return const [];
  final out = <WorkspaceView>[];
  for (final entry in byCwd.entries) {
    final cwd = entry.key;
    final list = entry.value..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final base = workspaceLabel(cwd);
    // Stable synthetic id: prefer cwd hash + base hash, prefixed so it never
    // collides with host `workspaceId`s (host ids are UUID-like).
    final id = 'synth-${cwd.hashCode.abs()}-${base.hashCode.abs()}';
    // Earliest updatedAt as createdAt proxy; newest as updatedAtMillis.
    final createdAt = list.map((s) => s.updatedAt).reduce((a, b) => a < b ? a : b);
    final updatedAt = list.first.updatedAt;
    out.add(WorkspaceView(
      workspaceId: WorkspaceId(id),
      name: base,
      cwd: cwd,
      sessionIds: list.map((s) => s.sessionId).toList(),
      createdAt: createdAt,
      updatedAtMillis: updatedAt,
    ));
  }
  // Deterministic: sort by name like host `order` baseline would.
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// Real `workspace.list` provider — now live via `workspace/follow`.
///
/// Watches the live pump so UI updates on baseline + increments. Falls back
/// to synthetic `kWorkspaceOptions` offline or before first baseline, but now
/// with a Phase 0/1 improvement: when a baseline has not yet arrived and
/// sessions are present, synthesize workspaces per `cwd` so the UI shows
/// `hhh` / `untitled folder` instead of dummy `Default`/`Project A` (payload
/// repro). The old `workspace.list` unary was removed in master
/// (`WorkspaceController` only `follow`), so no `client.workspaceList()` call —
/// avoids `404`.
final workspaceListProvider = Provider<AsyncValue<List<WorkspaceView>>>((ref) {
  // Ensure pump is running (idempotent)
  ref.watch(workspaceFollowPumpProvider);
  final live = ref.watch(_workspaceLiveListProvider);
  final hasBaseline = ref.watch(_workspaceHasBaselineProvider);
  final archived = ref.watch(_workspaceArchivedIdsProvider);
  final sessions = ref.watch(sessionsProvider);
  final isFallback = !hasBaseline &&
      live.length == kWorkspaceOptions.length &&
      live.every((w) => kWorkspaceOptions.any((k) => k.workspaceId == w.workspaceId));
  if (isFallback && sessions.byId.isNotEmpty) {
    final synth = _synthesizedFromSessions(sessions.byId, archived);
    if (synth.isNotEmpty) {
      // ignore: avoid_print
      print('[workspace] synthesized ${synth.length} workspaces from ${sessions.byId.length} sessions: ${synth.map((w) => w.name).join(",")}');
      return AsyncValue.data(synth);
    }
  }
  // Host is authoritative once baseline lands, even if empty.
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
