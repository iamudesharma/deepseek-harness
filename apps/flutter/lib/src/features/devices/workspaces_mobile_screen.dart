import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/connection_target.dart';
import '../../core/connection/connection_target_provider.dart';
import '../../core/session/session_models.dart';
import '../../core/session/sessions_controller.dart';
import '../../features/workspace/workspace_provider.dart';
import '../../widgets/primitives/connection_banner.dart';
import '../../core/connection/connection_controller.dart' as conn;
import 'selected_persistence.dart';

/// Mobile workspaces screen — reads real host data via `workspace.list`.
///
/// Entered from Devices after a host is selected/connected. Reads the existing
/// `workspaceListProvider` and host `hostDescribeProvider` — no local folder
/// creation on the phone. Mobile navigation: Devices → Workspaces → Sessions.
class WorkspacesMobileScreen extends ConsumerWidget {
  const WorkspacesMobileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(connectionTargetProvider);
    final connState = ref.watch(connectionStateProvider);
    final hostDescAsync = ref.watch(hostDescribeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspaces'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/devices'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(workspaceListProvider);
              ref.invalidate(hostDescribeProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (connState != conn.ConnectionState.connected &&
              connState != conn.ConnectionState.idle)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: DsConnectionBanner(state: connState),
            ),
          hostDescAsync.when(
            data: (desc) {
              final cwd = (desc['cwd'] as String?) ?? '';
              if (cwd.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.computer_outlined, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cwd,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          if (target is RemoteTarget)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.phone_android_outlined),
                  title: Text(target.displayName),
                  subtitle: Text(
                    '${target.baseUri.host} • ${target.hostId.substring(0, 8)}…',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  trailing: Icon(
                    connState == conn.ConnectionState.connected
                        ? Icons.check_circle
                        : Icons.cloud_outlined,
                    size: 16,
                    color: connState == conn.ConnectionState.connected
                        ? Colors.green
                        : null,
                  ),
                ),
              ),
            ),
          if (connState == conn.ConnectionState.needsReauth)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Authentication required'),
                  subtitle: const Text(
                    'Access expired, revoked, or host identity changed. Re-pair to continue.',
                  ),
                  trailing: FilledButton(
                    onPressed: () => context.go('/devices/add'),
                    child: const Text('Re-pair'),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final workspacesAsync = ref.watch(workspaceListProvider);
                return workspacesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => _ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(workspaceListProvider),
                  ),
                  data: (workspaces) {
                    if (workspaces.isEmpty) {
                      return const _EmptyWorkspaces();
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(workspaceListProvider);
                        try {
                          final client = ref.read(connectionClientProvider);
                          final sessions = await client.getSessions();
                          ref.read(sessionsProvider.notifier).setAll(sessions);
                        } catch (_) {}
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: workspaces.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final ws = workspaces[i];
                          final selectedId = ref.watch(selectedWorkspaceProvider);
                          final isSelected = selectedId != null &&
                              selectedId.value == ws.workspaceId.value;
                          return Card(
                            elevation: isSelected ? 1 : 0,
                            child: ListTile(
                              leading: Icon(
                                isSelected ? Icons.folder_open : Icons.folder_outlined,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(ws.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ws.cwd != null && ws.cwd!.isNotEmpty)
                                    Text(
                                      ws.cwd!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  Text(
                                    '${ws.sessionIds.length} session(s)',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              selected: isSelected,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.35),
                              onTap: () {
                                ref.read(selectedWorkspaceProvider.notifier).state =
                                    ws.workspaceId;
                                unawaited(
                                  persistSelectedWorkspaceId(ws.workspaceId.value),
                                );
                                context.go(
                                  '/sessions?workspaceId=${Uri.encodeComponent(ws.workspaceId.value)}',
                                );
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyWorkspaces extends StatelessWidget {
  const _EmptyWorkspaces();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No workspaces',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'This host has no workspaces yet. Create one from Host → Sessions, or ask the host to add a workspace.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
