import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/sessions_controller.dart';
import '../../core/session/session_models.dart';
import '../../features/workspace/workspace_provider.dart';
import 'selected_persistence.dart';

/// Result of validating persisted selections against live host data.
///
/// [attempted] is false when nothing was persisted. [sessionMissing] /
/// [workspaceMissing] are true only when an id was persisted but the host
/// no longer lists it — the persisted key is cleared in that case so a stale
/// id never resurrects.
class SelectionRestoreOutcome {
  /// Creates the outcome.
  const SelectionRestoreOutcome({
    required this.attempted,
    this.restoredWorkspace,
    this.restoredSession,
    this.workspaceMissing = false,
    this.sessionMissing = false,
  });

  /// Whether any persisted ids were found and validated.
  final bool attempted;

  /// Workspace restored into [selectedWorkspaceProvider], if still on host.
  final WorkspaceId? restoredWorkspace;

  /// Session restored into [sessionsProvider], if still on host.
  final SessionId? restoredSession;

  /// A workspace id was persisted but the host no longer lists it.
  final bool workspaceMissing;

  /// A session id was persisted but the host no longer lists it.
  final bool sessionMissing;
}

/// Restore persisted workspace/session selections after app restart.
///
/// Validates against direct host reads (`session.list` + `workspace.list`) —
/// deliberately not `workspaceListProvider`, whose offline fallback to
/// `kWorkspaceOptions` would validate selections against synthetic data.
/// Applies valid ids to the existing single selection state system
/// ([selectedWorkspaceProvider] + [sessionsProvider]); never fabricates a
/// missing session. Transport errors propagate as `AsyncError` with the
/// persisted keys retained — invalidate this provider after reconnect to retry.
final selectionRestoreProvider = FutureProvider<SelectionRestoreOutcome>((
  ref,
) async {
  final persisted = await restoreSelectedIds();
  final wsId = persisted.workspaceId;
  final sessId = persisted.sessionId;
  if (wsId == null && sessId == null) {
    return const SelectionRestoreOutcome(attempted: false);
  }

  final client = ref.watch(connectionClientProvider);
  // Hydration first: `setCurrent` ignores ids absent from the controller map,
  // so the restored selection must land after `sessionBootstrapProvider` has
  // populated state from `session.list`. A hydration error (host unreachable)
  // propagates with keys retained; invalidate to retry after reconnect.
  await ref.watch(sessionBootstrapProvider.future);
  final sessions = await client.getSessions();

  List<WorkspaceView> workspaces = const [];
  try {
    final value = await client.workspaceList();
    final items = value['items'] as List<dynamic>? ?? const [];
    workspaces = items.map((dynamic e) {
      final map = (e as Map).cast<String, dynamic>();
      return WorkspaceView.fromJson(map);
    }).toList();
  } catch (_) {
    // Session validation above already succeeded; workspace validation is
    // best-effort so a `workspace.list` hiccup does not block session restore.
  }

  var workspaceMissing = false;
  if (wsId != null) {
    final exists = workspaces.any((w) => w.workspaceId == wsId);
    if (exists) {
      ref.read(selectedWorkspaceProvider.notifier).state = wsId;
    } else {
      workspaceMissing = true;
      await clearSelectedWorkspaceId();
    }
  }

  var sessionMissing = false;
  SessionId? restoredSession;
  if (sessId != null) {
    final exists = sessions.any((s) => s.sessionId == sessId);
    if (exists) {
      ref.read(sessionsProvider.notifier).setCurrent(sessId);
      restoredSession = sessId;
    } else {
      sessionMissing = true;
      await clearSelectedSessionId();
    }
  }

  return SelectionRestoreOutcome(
    attempted: true,
    restoredWorkspace: workspaceMissing ? null : wsId,
    restoredSession: restoredSession,
    workspaceMissing: workspaceMissing,
    sessionMissing: sessionMissing,
  );
});
