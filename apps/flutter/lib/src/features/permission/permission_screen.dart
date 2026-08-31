import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'permission_provider.dart';

/// Permission presets screen — new-session default + per-session override.
///
/// Mirrors `PermissionRow` + permission-presets preset table: segmented
/// permission model (`read`/`workspace-write`/`danger-full-access`) with
/// risk confirmation for full access. ConsumerWidget, Theme + DswTokens,
/// empty/loading.
class PermissionScreen extends ConsumerWidget {
  const PermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final AsyncValue<void> loading = ref.watch(permissionLoadingProvider);
    final PermissionPreset selected = ref.watch(permissionSelectedProvider);
    final bool saving = ref.watch(permissionSavingProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Permissions',
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
      ),
      body: loading.when(
        data: (_) => ListView(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          children: [
            Container(
              padding: const EdgeInsets.all(DswTokens.spaceLg),
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
                        Icons.shield_outlined,
                        size: 18,
                        color: aliases.labelSecondary,
                      ),
                      const SizedBox(width: DswTokens.spaceSm),
                      Text(
                        'Default for new sessions',
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
                  const SizedBox(height: 4),
                  Text(
                    'Current-session changes stay on the composer /permission control.',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                  const SizedBox(height: DswTokens.spaceLg),
                  for (final preset in PermissionPreset.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
                      child: _PresetTile(
                        preset: preset,
                        selected: selected == preset,
                        aliases: aliases,
                        onSelect: saving
                            ? null
                            : (p) => _selectWithConfirm(context, ref, p),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              'Sessions running now keep the preset they started with.',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelCaption,
              ),
            ),
          ],
        ),
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
                'Loading permissions…',
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
                  'Failed to load permissions',
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
                  onPressed: () => ref.invalidate(permissionLoadingProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectWithConfirm(
    BuildContext context,
    WidgetRef ref,
    PermissionPreset preset,
  ) {
    if (preset != PermissionPreset.fullAccess) {
      _doSelect(ref, preset);
      return;
    }
    final DswAliases aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    bool acknowledged = false;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) {
          return AlertDialog(
            backgroundColor: aliases.bgLayer2,
            title: Text(
              'Enable full access?',
              style: TextStyle(color: aliases.labelPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Full access skips all permission prompts and grants the agent full host access.',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.labelSecondary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                Row(
                  children: [
                    Checkbox(
                      value: acknowledged,
                      onChanged: (bool? v) =>
                          set(() => acknowledged = v ?? false),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'I understand the risk',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          color: aliases.labelPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: aliases.stateErrorPrimary,
                ),
                onPressed: acknowledged
                    ? () {
                        Navigator.pop(ctx);
                        _doSelect(ref, preset);
                      }
                    : null,
                child: const Text('Enable'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _doSelect(WidgetRef ref, PermissionPreset preset) {
    ref.read(permissionSavingProvider.notifier).state = true;
    Future.delayed(const Duration(milliseconds: 400), () {
      ref.read(permissionSelectedProvider.notifier).state = preset;
      ref.read(permissionSavingProvider.notifier).state = false;
    });
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.aliases,
    this.onSelect,
  });
  final PermissionPreset preset;
  final bool selected;
  final DswAliases aliases;
  final ValueChanged<PermissionPreset>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? aliases.specificSidebarNavItemActive : aliases.bgLayer2,
      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      child: InkWell(
        onTap: onSelect == null ? null : () => onSelect!(preset),
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
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected
                    ? aliases.stateBusinessPrimary
                    : aliases.labelCaption,
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w500,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.id,
                      style: TextStyle(
                        fontSize: 10,
                        color: aliases.labelCaption,
                        fontFamily: 'SF Mono',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
