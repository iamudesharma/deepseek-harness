import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';
import '../../theme/app_theme.dart';
import 'workspace_provider.dart';

/// Workspace selector/creation screen — augments sidebar workspace.
///
/// Mirrors `WorkspacePicker` / `WorkspacePickFlow` + `WorkspaceBrowser`:
/// menu listing, `Add workspace` via directory pick (real `workspace.create`),
/// error dialog, selected check, empty/loading.
/// Also augments the existing sidebar workspace selector (shared providers).
/// Uses real `workspaceList()` via [workspaceListProvider] (parses `items` and
/// `archivedSessionIds` via `ref.watch(connectionClientProvider).workspaceList()`)
/// and shows `hostDescribe` cwd. Keeps `kWorkspaceOptions` as offline fallback
/// and provides a `TextField` for new workspace path with `workspaceCreate` on
/// submit.
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final AsyncValue<List<WorkspaceView>> async = ref.watch(
      workspaceListProvider,
    );
    final AsyncValue<Map<String, dynamic>> hostAsync = ref.watch(
      hostDescribeProvider,
    );
    final WorkspaceId? selected = ref.watch(selectedWorkspaceProvider);
    final bool saving = ref.watch(workspaceSavingProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Workspaces',
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => ref.invalidate(workspaceListProvider),
          ),
          IconButton(
            tooltip: 'Refresh host',
            icon: const Icon(Icons.sync, size: 18),
            onPressed: () => ref.invalidate(hostDescribeProvider),
          ),
          const SizedBox(width: DswTokens.spaceSm),
        ],
      ),
      body: async.when(
        data: (List<WorkspaceView> workspaces) {
          if (workspaces.isEmpty)
            return _EmptyWorkspace(
              aliases: aliases,
              onAdd: () => _addWorkspace(context, ref),
            );
          return ListView(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            children: [
              // Host cwd banner from hostDescribe — reachable typert, DswTokens styled.
              hostAsync.when(
                data: (Map<String, dynamic> host) {
                  final String cwd = host['cwd'] as String? ?? '';
                  final String home = host['home'] as String? ?? '';
                  return Container(
                    padding: const EdgeInsets.all(DswTokens.spaceMd),
                    decoration: BoxDecoration(
                      color: aliases.bgLayer2,
                      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                      border: Border.all(color: aliases.borderL2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.computer_outlined,
                              size: 14,
                              color: aliases.labelTertiary,
                            ),
                            const SizedBox(width: DswTokens.spaceSm),
                            Text(
                              'Host',
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeXxs12,
                                fontWeight: FontWeight.w600,
                                color: aliases.labelCaption,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Retry host describe',
                              icon: Icon(
                                Icons.refresh,
                                size: 14,
                                color: aliases.labelTertiary,
                              ),
                              onPressed: () =>
                                  ref.invalidate(hostDescribeProvider),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'cwd: $cwd',
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeS14,
                            color: aliases.labelPrimary,
                          ),
                        ),
                        if (home.isNotEmpty)
                          Text(
                            'home: $home',
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelSecondary,
                            ),
                          ),
                      ],
                    ),
                  );
                },
                loading: () => Container(
                  padding: const EdgeInsets.all(DswTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: aliases.bgLayer2,
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    border: Border.all(color: aliases.borderL2),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: aliases.labelTertiary,
                        ),
                      ),
                      const SizedBox(width: DswTokens.spaceSm),
                      Text(
                        'Loading host…',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          color: aliases.labelSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                error: (Object err, StackTrace st) => Container(
                  padding: const EdgeInsets.all(DswTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: aliases.bgLayer2,
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    border: Border.all(
                      color: aliases.stateErrorPrimary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: aliases.stateErrorPrimary,
                      ),
                      const SizedBox(width: DswTokens.spaceSm),
                      Expanded(
                        child: Text(
                          'Host unavailable: $err',
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: aliases.labelSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: DswTokens.spaceSm),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(hostDescribeProvider),
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('Retry'),
                        style: FilledButton.styleFrom(
                          backgroundColor: aliases.buttonPrimaryFill,
                          foregroundColor: aliases.labelPrimaryForeground,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DswTokens.spaceLg),
              WorkspaceSelector(
                workspaces: workspaces,
                selected: selected,
                saving: saving,
                aliases: aliases,
                onSelect: (WorkspaceId id) =>
                    ref.read(selectedWorkspaceProvider.notifier).state = id,
                onAdd: () => _addWorkspace(context, ref),
              ),
              const SizedBox(height: DswTokens.spaceLg),
              Text(
                'All workspaces',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceSm),
              for (final w in workspaces)
                Padding(
                  padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
                  child: _WorkspaceTile(
                    workspace: w,
                    selected: selected == w.workspaceId,
                    aliases: aliases,
                    onTap: () =>
                        ref.read(selectedWorkspaceProvider.notifier).state =
                            w.workspaceId,
                  ),
                ),
              const SizedBox(height: DswTokens.spaceMd),
              // New workspace path TextField inline — also available via dialog.
              _InlineCreateField(
                aliases: aliases,
                saving: saving,
                onCreate: (String path) => _createWorkspace(context, ref, path),
              ),
            ],
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: aliases.labelTertiary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceMd),
              Text(
                'Loading workspaces…',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  color: aliases.labelSecondary,
                ),
              ),
            ],
          ),
        ),
        error: (Object err, StackTrace st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 28,
                  color: aliases.stateErrorPrimary,
                ),
                const SizedBox(height: DswTokens.spaceSm),
                Text(
                  'Failed to load workspaces',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  err.toString(),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelSecondary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(workspaceListProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                // Offline fallback notice — kWorkspaceOptions remains usable.
                Container(
                  padding: const EdgeInsets.all(DswTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: aliases.bgLayer2,
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    border: Border.all(color: aliases.borderL2),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Offline fallback available',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelCaption,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final w in kWorkspaceOptions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 14,
                                color: aliases.labelTertiary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                w.name,
                                style: TextStyle(
                                  fontSize: DswTokens.fontSizeXxs12,
                                  color: aliases.labelSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: aliases.buttonPrimaryFill,
        foregroundColor: aliases.labelPrimaryForeground,
        onPressed: saving ? null : () => _addWorkspace(context, ref),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add workspace'),
      ),
    );
  }

  Future<void> _createWorkspace(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) return;
    ref.read(workspaceSavingProvider.notifier).state = true;
    try {
      final client = ref.read(connectionClientProvider);
      final result = await client.workspaceCreate(path: trimmed);
      // Invalidate to re-fetch real list including new workspace.
      ref.invalidate(workspaceListProvider);
      ref.invalidate(hostDescribeProvider);
      if (!context.mounted) return;
      final workspace = result['workspace'] as Map<String, dynamic>?;
      final title = workspace?['title'] as String? ?? trimmed;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Workspace "$title" created')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create workspace: $e'),
          backgroundColor: Theme.of(context)
              .extension<DswThemeExtension>()
              ?.aliases
              .stateErrorPrimary,
        ),
      );
    } finally {
      ref.read(workspaceSavingProvider.notifier).state = false;
    }
  }

  void _addWorkspace(BuildContext context, WidgetRef ref) {
    final TextEditingController ctrl = TextEditingController(
      text: '/work/new-project',
    );
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: aliases.bgLayer2,
        title: Text(
          'Add workspace',
          style: TextStyle(
            color: aliases.labelPrimary,
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Host directory path',
                hintText: '/work/...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                ),
              ),
              onSubmitted: (String v) {
                final String path = v.trim();
                if (path.isEmpty) return;
                Navigator.pop(ctx);
                _createWorkspace(context, ref, path);
              },
            ),
            const SizedBox(height: DswTokens.spaceSm),
            // Show host cwd hint from hostDescribe
            Consumer(
              builder: (BuildContext context, WidgetRef ref2, _) {
                final AsyncValue<Map<String, dynamic>> hostAsync = ref2.watch(
                  hostDescribeProvider,
                );
                return hostAsync.when(
                  data: (m) => Text(
                    'Host cwd: ${m['cwd'] ?? ''}',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                  loading: () => Text(
                    'Loading host cwd…',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                  error: (e, _) => Text(
                    'Host unavailable',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.stateErrorPrimary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final String path = ctrl.text.trim();
              if (path.isEmpty) return;
              Navigator.pop(ctx);
              _createWorkspace(context, ref, path);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Inline TextField for quick workspace creation — also tests workspaceCreate reachability.
class _InlineCreateField extends StatefulWidget {
  const _InlineCreateField({
    required this.aliases,
    required this.saving,
    required this.onCreate,
  });
  final DswAliases aliases;
  final bool saving;
  final ValueChanged<String> onCreate;

  @override
  State<_InlineCreateField> createState() => _InlineCreateFieldState();
}

class _InlineCreateFieldState extends State<_InlineCreateField> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = widget.aliases;
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create workspace',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: !widget.saving,
                  decoration: InputDecoration(
                    hintText: '/work/new-project',
                    labelText: 'Host directory path',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: DswTokens.spaceMd,
                      vertical: DswTokens.spaceSm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    ),
                  ),
                  onSubmitted: widget.saving
                      ? null
                      : (String v) => widget.onCreate(v),
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              FilledButton.icon(
                onPressed: widget.saving || _ctrl.text.trim().isEmpty
                    ? null
                    : () => widget.onCreate(_ctrl.text),
                icon: widget.saving
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: aliases.labelPrimaryForeground,
                        ),
                      )
                    : const Icon(Icons.add, size: 16),
                label: const Text('Create'),
                style: FilledButton.styleFrom(
                  backgroundColor: aliases.buttonPrimaryFill,
                  foregroundColor: aliases.labelPrimaryForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable WorkspaceSelector dropdown — augments sidebar's selector.
class WorkspaceSelector extends StatelessWidget {
  const WorkspaceSelector({
    super.key,
    required this.workspaces,
    required this.selected,
    required this.saving,
    required this.aliases,
    required this.onSelect,
    required this.onAdd,
  });
  final List<WorkspaceView> workspaces;
  final WorkspaceId? selected;
  final bool saving;
  final DswAliases aliases;
  final ValueChanged<WorkspaceId> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspaces_outlined,
                size: 16,
                color: aliases.labelTertiary,
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Text(
                'Workspace',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              const Spacer(),
              if (saving)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: aliases.labelTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: DswTokens.spaceSm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: aliases.specificSelector,
              borderRadius: BorderRadius.circular(DswTokens.radiusSm),
              border: Border.all(color: aliases.borderL2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<WorkspaceId?>(
                value: selected,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: DswTokens.spaceSm,
                ),
                dropdownColor: aliases.specificMenu,
                hint: Text(
                  'All workspaces',
                  style: TextStyle(color: aliases.labelPrimary),
                ),
                items: [
                  const DropdownMenuItem<WorkspaceId?>(
                    value: null,
                    child: Text('All workspaces'),
                  ),
                  for (final w in workspaces)
                    DropdownMenuItem<WorkspaceId?>(
                      value: w.workspaceId,
                      child: Text(w.name),
                    ),
                  const DropdownMenuItem<WorkspaceId?>(
                    enabled: false,
                    value: WorkspaceId('__add__'),
                    child: Text('+ Add workspace…'),
                  ),
                ],
                onChanged: (WorkspaceId? next) {
                  if (next == null) {
                    onSelect(const WorkspaceId('all'));
                    return;
                  }
                  if (next.value == '__add__') {
                    onAdd();
                    return;
                  }
                  onSelect(next);
                },
              ),
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add workspace'),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.selected,
    required this.aliases,
    required this.onTap,
  });
  final WorkspaceView workspace;
  final bool selected;
  final DswAliases aliases;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? aliases.specificSidebarNavItemActive : aliases.bgLayer2,
      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DswTokens.spaceMd,
            vertical: DswTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            border: Border.all(
              color: selected
                  ? aliases.buttonGhostActiveBorder
                  : aliases.borderL1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: selected
                    ? aliases.stateBusinessPrimary
                    : aliases.labelTertiary,
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w500,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    if (workspace.cwd != null)
                      Text(
                        workspace.cwd!,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  size: 16,
                  color: aliases.stateBusinessPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({required this.aliases, required this.onAdd});
  final DswAliases aliases;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspaces_outlined,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              'No workspaces',
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a host directory to create your first workspace.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: DswTokens.spaceLg),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add workspace'),
            ),
          ],
        ),
      ),
    );
  }
}
