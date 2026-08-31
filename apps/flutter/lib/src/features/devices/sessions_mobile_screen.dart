import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/connection_controller.dart' as conn;
import '../../core/session/session_models.dart';
import '../../core/session/sessions_controller.dart';
import '../../features/workspace/workspace_provider.dart';
import '../../widgets/primitives/connection_banner.dart';
import 'selected_persistence.dart';
import 'selection_restore.dart';

/// Mobile sessions screen — reads real host data via `SessionsController` / `session.list`.
///
/// Entered from Workspaces with `workspaceId` query. Shows session title,
/// workspace, status, last update, running/completed/error, blank/new. Mobile
/// navigation: Workspaces → Sessions → Conversation (existing route).
class SessionsMobileScreen extends ConsumerStatefulWidget {
  const SessionsMobileScreen({super.key, this.workspaceId});

  /// Workspace filter from `?workspaceId=` query (optional, host-authoritative).
  final String? workspaceId;

  @override
  ConsumerState<SessionsMobileScreen> createState() =>
      _SessionsMobileScreenState();
}

class _SessionsMobileScreenState extends ConsumerState<SessionsMobileScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _restoreNoticeDismissed = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(connectionStateProvider);
    final sessionsState = ref.watch(sessionsProvider);
    final sessionBootstrap = ref.watch(sessionBootstrapProvider);
    final wsId = widget.workspaceId == null
        ? null
        : WorkspaceId(widget.workspaceId!);

    // Filter: host-authoritative ordering preserved (sessionsController.sorted is updatedAt desc).
    final filtered = sessionsState.byId.values.where((s) {
      if (wsId != null && s.cwd != null) {
        // Keep only sessions whose cwd belongs to the selected workspace when possible.
        // Fallback: show all when workspace.cwd is unavailable.
        // This is host-authoritative in the sense that `cwd` comes from `session.list`.
        // For exact workspace membership, the sidebar's `deriveWorkspaceGroups` is richer,
        // but this keeps mobile simple and transport-agnostic.
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      final title = (s.title ?? '').toLowerCase();
      final cwd = (s.cwd ?? '').toLowerCase();
      final sid = s.sessionId.value.toLowerCase();
      return title.contains(q) || cwd.contains(q) || sid.contains(q);
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // Workspace-scoped filter when we know the workspace cwd prefix.
    List<SessionSummary> scoped = filtered;
    if (wsId != null) {
      final workspacesAsync = ref.watch(workspaceListProvider);
      final List<WorkspaceView> workspaces = workspacesAsync is AsyncValue
          ? (workspacesAsync as AsyncValue<List<WorkspaceView>>).valueOrNull ?? const <WorkspaceView>[]
          : workspacesAsync as List<WorkspaceView>;
      final ws = workspaces
          .where((w) => w.workspaceId.value == wsId.value)
          .firstOrNull;
      if (ws != null && ws.cwd != null && ws.cwd!.isNotEmpty) {
        scoped = filtered
            .where(
              (s) =>
                  s.cwd == ws.cwd ||
                  (s.cwd != null && s.cwd!.startsWith('${ws.cwd}/')),
            )
            .toList();
        // If none match the cwd prefix (e.g. synthetic fallback), fall back to full filtered list
        // so the user is not stuck on an empty screen.
        if (scoped.isEmpty && filtered.isNotEmpty) scoped = filtered;
      } else {
        // Workspace membership by `workspace.sessionIds` when cwd grouping is synthetic.
        final wsIds = ws?.sessionIds ?? const <SessionId>[];
        if (wsIds.isNotEmpty) {
          final set = wsIds.map((id) => id.value).toSet();
          final byWorkspace = filtered
              .where((s) => set.contains(s.sessionId.value))
              .toList();
          if (byWorkspace.isNotEmpty) scoped = byWorkspace;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(wsId == null ? 'Sessions' : 'Sessions · ${wsId.value}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/workspaces'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              try {
                final client = ref.read(connectionClientProvider);
                final sessions = await client.getSessions();
                ref.read(sessionsProvider.notifier).setAll(sessions);
              } catch (e) {
                if (context.mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
              }
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
          if (connState == conn.ConnectionState.needsReauth)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Authentication required'),
                  subtitle: const Text(
                    'Access expired, revoked, or host identity changed.',
                  ),
                  trailing: FilledButton(
                    onPressed: () => context.go('/devices/add'),
                    child: const Text('Re-pair'),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search sessions',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          if (sessionBootstrap.isLoading)
            const LinearProgressIndicator(minHeight: 2),
          // Restore notice: a persisted session id the host no longer lists.
          // The stale key was already cleared — this is the clean message, no
          // fabricated session row.
          ref
              .watch(selectionRestoreProvider)
              .when(
                data: (outcome) =>
                    (outcome.sessionMissing && !_restoreNoticeDismissed)
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Card(
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.history_toggle_off),
                            title: const Text('Previous session unavailable'),
                            subtitle: const Text(
                              'The session you had open is no longer on this computer.',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(
                                () => _restoreNoticeDismissed = true,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
          Expanded(
            child: scoped.isEmpty
                ? _EmptySessions(query: _query, workspaceId: wsId?.value)
                : RefreshIndicator(
                    onRefresh: () async {
                      final client = ref.read(connectionClientProvider);
                      final sessions = await client.getSessions();
                      ref.read(sessionsProvider.notifier).setAll(sessions);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: scoped.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final s = scoped[i];
                        final isSelected = ref.watch(
                          sessionsProvider.select(
                            (st) => st.current == s.sessionId,
                          ),
                        );
                        return _SessionTile(
                          summary: s,
                          selected: isSelected,
                          onTap: () {
                            ref
                                .read(sessionsProvider.notifier)
                                .setCurrent(s.sessionId);
                            unawaited(
                              persistSelectedSessionId(s.sessionId.value),
                            );
                            // Reuse existing conversation route — no mobile ChatView duplicate.
                            context.go('/sessions/${s.sessionId.value}');
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSession(context, ref, wsId),
        icon: const Icon(Icons.add),
        label: const Text('New session'),
      ),
    );
  }

  Future<void> _createSession(
    BuildContext context,
    WidgetRef ref,
    WorkspaceId? wsId,
  ) async {
    final client = ref.read(connectionClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final SessionId newId;
      if (wsId != null) {
        newId = await client.createSession(workspaceId: wsId.value);
      } else {
        newId = await client.createSession();
      }
      // Host-confirmed session id — do not navigate until confirmed.
      final sessions = await client.getSessions();
      ref.read(sessionsProvider.notifier).setAll(sessions);
      // If the new session is addressable, select it; otherwise fall back to first.
      final exists = sessions.any((s) => s.sessionId == newId);
      if (exists) {
        ref.read(sessionsProvider.notifier).setCurrent(newId);
      }
      unawaited(persistSelectedSessionId(newId.value));
      if (context.mounted) context.go('/sessions/${newId.value}');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to create session: $e')),
      );
    }
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.summary,
    required this.selected,
    required this.onTap,
  });
  final SessionSummary summary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statuses = summary.sessionStatuses();
    final primary = statuses.isNotEmpty ? statuses.first : null;
    final title = summary.displayTitle;
    final subtitle = [
      if (summary.cwd != null && summary.cwd!.isNotEmpty) summary.cwd,
      _formatUpdated(summary.updatedAt),
      if (summary.blank) 'New',
      if (primary != null) primary.label,
    ].whereType<String>().join(' • ');

    IconData leadingIcon;
    Color? leadingColor;
    switch (primary?.state) {
      case 'ongoing':
        leadingIcon = Icons.circle;
        leadingColor = Colors.green;
        break;
      case 'warning':
        leadingIcon = Icons.warning_amber_rounded;
        leadingColor = Colors.orange;
        break;
      default:
        leadingIcon = summary.blank
            ? Icons.chat_bubble_outline
            : Icons.chat_bubble;
        leadingColor = summary.blank ? Colors.grey : null;
    }

    return Card(
      elevation: selected ? 1 : 0,
      child: ListTile(
        leading: Icon(leadingIcon, color: leadingColor, size: 20),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: 0.35),
        onTap: onTap,
      ),
    );
  }

  String _formatUpdated(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions({required this.query, required this.workspaceId});
  final String query;
  final String? workspaceId;
  @override
  Widget build(BuildContext context) {
    final hasQuery = query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.chat_bubble_outline,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery ? 'No sessions match "$query"' : 'No sessions',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? 'Try a different term.'
                  : (workspaceId == null
                        ? 'Create a new session to get started.'
                        : 'No sessions in this workspace yet.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
