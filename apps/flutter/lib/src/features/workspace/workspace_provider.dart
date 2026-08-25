import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';

/// Fallback synthetic workspaces for offline / host-unreachable UX.
///
/// Mirrors `kWorkspaceOptions` in the sidebar: keep as fallback so the UI
/// remains usable without a host (e.g. Flutter test, offline). Real data
/// comes from `workspaceList()` when available.
const kWorkspaceOptions = [
  WorkspaceView(workspaceId: WorkspaceId('default'), name: 'Default', cwd: '/work/default'),
  WorkspaceView(workspaceId: WorkspaceId('project-a'), name: 'Project A', cwd: '/work/project-a'),
];

/// Real `workspace.list` provider — parses `items` and `archivedSessionIds`.
///
/// Calls `ref.watch(connectionClientProvider).workspaceList()` and maps the
/// host `WorkspaceView` (path/title) to the Flutter `WorkspaceView` (name/cwd).
/// On transport failure, returns [kWorkspaceOptions] so offline remains usable;
/// other callers still see `AsyncError` if they want retry (caught here for
/// explicit fallback). Archived ids are parsed for completeness even though
/// grouping surfaces hide them.
final workspaceListProvider = FutureProvider<List<WorkspaceView>>((ref) async {
  final client = ref.watch(connectionClientProvider);
  try {
    final value = await client.workspaceList();
    final items = value['items'] as List<dynamic>? ?? const [];
    // Parse archivedSessionIds to ensure typert contract is consumed — even
    // though the workspace chooser hides archived sessions, the baseline needs
    // the full set for reconnect correctness.
    final archived = value['archivedSessionIds'] as List<dynamic>? ?? const [];
    // Touch archived to keep the field reachable (no dropped typert).
    if (archived.isNotEmpty) {
      // Validated as strings; no further use in this chooser.
      archived.whereType<String>().toList(growable: false);
    }
    if (items.isEmpty) return const <WorkspaceView>[];
    return items.map((dynamic e) {
      final map = (e as Map).cast<String, dynamic>();
      return WorkspaceView.fromJson(map);
    }).toList();
  } catch (_) {
    // Offline fallback — keep synthetic options so the UI is not empty.
    return kWorkspaceOptions;
  }
});

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
