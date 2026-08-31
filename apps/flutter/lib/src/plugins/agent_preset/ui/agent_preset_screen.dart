import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart' show kAgentPresetNamespace;
import 'agent_preset_provider.dart';

/// Agent preset screen — Section/Row/Seat list + PresetMenu.
///
/// Mirrors `AgentPresetSection` + `AgentPresetRow` + `AgentPresetSeat` + `PresetMenu`:
/// system vs user groups, card with badge/broken/in-use, viewer modal, copy
/// dialog, and single-select menu row.
/// Real `agentPresetList()` via [agentPresetListProvider]
/// (`ref.watch(connectionClientProvider).agentPresetList()`) and
/// `agentPresetSelect(sessionId: currentSessionId, agentPreset: id)` via
/// [_select] then invalidates provider. Shows real `presets` from host
/// (id, displayName, isDefault). ConsumerWidget, Theme + DswTokens,
/// loading/error with Retry via `AsyncValue.when`.
class AgentPresetScreen extends ConsumerWidget {
  const AgentPresetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final AsyncValue<AgentPresetRoster> async = ref.watch(
      agentPresetListProvider,
    );
    final String current = ref.watch(agentPresetCurrentProvider);
    final bool saving = ref.watch(agentPresetSavingProvider);
    // bindLocale watches localeRevisionProvider, so a Language-row switch
    // re-renders every label on this screen.
    final Translate t = ref.bindLocale(kAgentPresetNamespace);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          t('nav'),
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
            tooltip: t('refresh'),
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => ref.invalidate(agentPresetListProvider),
          ),
          const SizedBox(width: DswTokens.spaceSm),
        ],
      ),
      body: async.when(
        data: (AgentPresetRoster roster) {
          final List<AgentPresetOption> options = roster.presets;
          // Derive current display: prefer explicit current, else isDefault, else first.
          final String effectiveCurrent = options.any((o) => o.id == current)
              ? current
              : options.where((o) => o.isDefault).firstOrNull?.id ??
                    options.firstOrNull?.id ??
                    current;
          return ListView(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            children: [
              AgentPresetRow(
                options: options,
                selectedId: effectiveCurrent,
                saving: saving,
                aliases: aliases,
                onSelect: (String id) => _select(context, ref, id),
              ),
              const SizedBox(height: DswTokens.spaceLg),
              AgentPresetSection(
                options: options,
                current: effectiveCurrent,
                authorable: roster.authorable,
                hasDocument: roster.hasDocument,
                aliases: aliases,
                onMakeDefault: (String id) => _select(context, ref, id),
                onView: (String id) => _viewComposition(context, ref, id),
                onCopy: (String fromId, String presetId, String name) =>
                    _copy(context, ref, fromId, presetId, name),
                onDelete: (String id) => _delete(context, ref, id),
              ),
              const SizedBox(height: DswTokens.spaceLg),
              AgentPresetSeat(
                options: options,
                current: effectiveCurrent,
                aliases: aliases,
                onSelect: (String id) => _select(context, ref, id),
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
                t('loading'),
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
                  t('error'),
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
                  onPressed: () => ref.invalidate(agentPresetListProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(t('retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the read-only viewer over one preset's shipped composition
  /// (`agentPreset.read`); failures surface as a snackbar, never a fake body.
  Future<void> _viewComposition(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final Translate t = ref.bindLocale(kAgentPresetNamespace);
    try {
      final String content = await readPresetComposition(
        ref.read(connectionClientProvider),
        id,
      );
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (BuildContext ctx) {
          final DswAliases viewerAliases = aliasesOf(ctx);
          return AlertDialog(
            backgroundColor: viewerAliases.bgLayer2,
            title: Text(
              '${t('view')} · $id',
              style: TextStyle(color: viewerAliases.labelPrimary),
            ),
            content: SingleChildScrollView(
              child: SelectableText(
                content,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  fontFamily: 'SF Mono',
                  color: viewerAliases.labelSecondary,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('close')),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _toast(context, 'Failed to read "$id": $e');
    }
  }

  /// Creates a copy through `agentPreset.copy` and refreshes the roster.
  Future<void> _copy(
    BuildContext context,
    WidgetRef ref,
    String fromId,
    String presetId,
    String name,
  ) async {
    try {
      final String created = await copyPreset(
        ref.read(connectionClientProvider),
        from: fromId,
        presetId: presetId,
        name: name,
      );
      ref.invalidate(agentPresetListProvider);
      if (context.mounted) _toast(context, 'Created preset "$created"');
    } catch (e) {
      if (context.mounted) _toast(context, 'Failed to create "$presetId": $e');
    }
  }

  /// Deletes a user preset through `agentPreset.remove`; running sessions
  /// keep the composition they were mounted with.
  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    try {
      await removePreset(ref.read(connectionClientProvider), id);
      ref.invalidate(agentPresetListProvider);
      if (context.mounted) _toast(context, 'Deleted "$id"');
    } catch (e) {
      if (context.mounted) _toast(context, 'Failed to delete "$id": $e');
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  DswAliases aliasesOf(BuildContext context) =>
      Theme.of(context).extension<DswThemeExtension>()?.aliases ??
      DswTokens.lightAliases;

  Future<void> _select(BuildContext context, WidgetRef ref, String id) async {
    final String? sessionId = ref.read(currentSessionIdProvider)?.value;
    ref.read(agentPresetSavingProvider.notifier).state = true;
    try {
      final client = ref.read(connectionClientProvider);
      if (sessionId != null && sessionId.isNotEmpty) {
        await client.agentPresetSelect(sessionId: sessionId, agentPreset: id);
      } else {
        // No session selected — still validate preset exists via host by listing?
        // For offline/testing, just update local state without host call.
        if (sessionId == null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No session selected — set default to $id locally'),
            ),
          );
        }
      }
      ref.read(agentPresetCurrentProvider.notifier).state = id;
      ref.invalidate(agentPresetListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Preset "$id" selected')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to select preset: $e')));
      }
    } finally {
      ref.read(agentPresetSavingProvider.notifier).state = false;
    }
  }
}

/// AgentPresetRow — preference row with PresetMenu.
class AgentPresetRow extends ConsumerWidget {
  const AgentPresetRow({
    super.key,
    required this.options,
    required this.selectedId,
    required this.saving,
    required this.aliases,
    required this.onSelect,
  });
  final List<AgentPresetOption> options;
  final String selectedId;
  final bool saving;
  final DswAliases aliases;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kAgentPresetNamespace);
    final AgentPresetOption? chosen = options
        .where((o) => o.id == selectedId)
        .firstOrNull;
    final String label = chosen?.displayName ?? chosen?.name ?? selectedId;
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('title'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w500,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t('description'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DswTokens.spaceMd),
          PresetMenu(
            options: options,
            selectedId: selectedId,
            label: label,
            aliases: aliases,
            saving: saving,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

/// AgentPresetSeat — hero chip on new-session surface.
class AgentPresetSeat extends ConsumerWidget {
  const AgentPresetSeat({
    super.key,
    required this.options,
    required this.current,
    required this.aliases,
    required this.onSelect,
  });
  final List<AgentPresetOption> options;
  final String current;
  final DswAliases aliases;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kAgentPresetNamespace);
    final AgentPresetOption? chosen = options
        .where((o) => o.id == current)
        .firstOrNull;
    final String label = chosen?.displayName ?? chosen?.name ?? current;
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
            t('seatHint'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          PresetMenu(
            options: options,
            selectedId: current,
            label: label,
            aliases: aliases,
            saving: false,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

/// PresetMenu — shared picker (button + Menu overlay).
class PresetMenu extends ConsumerWidget {
  const PresetMenu({
    super.key,
    required this.options,
    required this.selectedId,
    required this.label,
    required this.aliases,
    required this.saving,
    required this.onSelect,
  });
  final List<AgentPresetOption> options;
  final String selectedId;
  final String label;
  final DswAliases aliases;
  final bool saving;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kAgentPresetNamespace);
    return PopupMenuButton<String>(
      enabled: !saving && options.isNotEmpty,
      onSelected: onSelect,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      ),
      color: aliases.specificMenu,
      itemBuilder: (BuildContext ctx) => [
        for (final o in options)
          PopupMenuItem<String>(
            value: o.id,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    o.trust == PresetTrust.user
                        ? '${o.displayName ?? o.name} · ${t('userTrust')}'
                        : o.displayName ?? o.name,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      color: aliases.labelPrimary,
                    ),
                  ),
                ),
                if (o.id == selectedId)
                  Icon(
                    Icons.check,
                    size: 14,
                    color: aliases.stateBusinessPrimary,
                  ),
                if (o.isDefault) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: aliases.stateSuccessTertiary,
                      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                    ),
                    child: Text(
                      t('defaultBadge'),
                      style: TextStyle(
                        fontSize: 10,
                        color: aliases.stateSuccessPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: aliases.specificSelector,
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          border: Border.all(color: aliases.borderL2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (saving) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: aliases.labelTertiary,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: aliases.labelTertiary),
          ],
        ),
      ),
    );
  }
}

/// AgentPresetSection — card roster grouped by trust.
///
/// Copy/delete ride the host wire (`agentPreset.copy`/`.remove`) and are
/// gated on `authorable` exactly like React's section store; a broken preset
/// can neither compose nor copy. The location action lands with the native
/// opener face and stays out.
class AgentPresetSection extends ConsumerWidget {
  const AgentPresetSection({
    super.key,
    required this.options,
    required this.current,
    this.authorable = false,
    this.hasDocument = false,
    required this.aliases,
    required this.onMakeDefault,
    required this.onView,
    required this.onCopy,
    required this.onDelete,
  });
  final List<AgentPresetOption> options;
  final String current;
  final bool authorable;
  final bool hasDocument;
  final DswAliases aliases;
  final ValueChanged<String> onMakeDefault;
  final ValueChanged<String> onView;
  final void Function(String fromId, String presetId, String name) onCopy;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kAgentPresetNamespace);
    final List<AgentPresetOption> system = options
        .where((o) => o.trust == PresetTrust.system)
        .toList();
    final List<AgentPresetOption> user = options
        .where((o) => o.trust == PresetTrust.user)
        .toList();
    Widget group(String title, List<AgentPresetOption> rows) {
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              fontWeight: FontWeight.w600,
              color: aliases.labelCaption,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          for (final o in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
              child: _PresetCard(
                option: o,
                isDefault: o.id == current,
                authorable: authorable,
                hasDocument: hasDocument,
                aliases: aliases,
                onMakeDefault: onMakeDefault,
                onView: onView,
                onCopy: onCopy,
                onDelete: onDelete,
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('allPresets'),
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        const SizedBox(height: DswTokens.spaceSm),
        group(t('builtInGroup'), system),
        const SizedBox(height: DswTokens.spaceSm),
        group(t('customGroup'), user),
      ],
    );
  }
}

class _PresetCard extends ConsumerWidget {
  const _PresetCard({
    required this.option,
    required this.isDefault,
    required this.authorable,
    required this.hasDocument,
    required this.aliases,
    required this.onMakeDefault,
    required this.onView,
    required this.onCopy,
    required this.onDelete,
  });
  final AgentPresetOption option;
  final bool isDefault;
  final bool authorable;
  final bool hasDocument;
  final DswAliases aliases;
  final ValueChanged<String> onMakeDefault;
  final ValueChanged<String> onView;
  final void Function(String fromId, String presetId, String name) onCopy;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kAgentPresetNamespace);
    final bool broken = option.broken != null;
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: isDefault
            ? aliases.specificSidebarNavItemActive
            : aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(
          color: broken
              ? aliases.stateErrorPrimary.withValues(alpha: 0.4)
              : isDefault
              ? aliases.buttonGhostActiveBorder
              : aliases.borderL2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  option.displayName ?? option.name,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                ),
                child: Text(
                  option.trust == PresetTrust.user
                      ? t('userTrust')
                      : t('builtInGroup'),
                  style: TextStyle(fontSize: 10, color: aliases.labelCaption),
                ),
              ),
              if (isDefault || option.isDefault) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: aliases.stateSuccessTertiary,
                    borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                  ),
                  child: Text(
                    isDefault ? t('inUse') : t('defaultBadge'),
                    style: TextStyle(
                      fontSize: 10,
                      color: aliases.stateSuccessPrimary,
                    ),
                  ),
                ),
              ],
              if (broken) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: aliases.stateErrorPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                  ),
                  child: Text(
                    t('brokenBadge'),
                    style: TextStyle(
                      fontSize: 10,
                      color: aliases.stateErrorPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            option.description ?? t('noDescription'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            option.id,
            style: TextStyle(
              fontSize: 10,
              color: aliases.labelCaption,
              fontFamily: 'SF Mono',
            ),
          ),
          if (broken) ...[
            const SizedBox(height: 4),
            Text(
              option.broken!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.stateErrorPrimary,
              ),
            ),
          ],
          const SizedBox(height: DswTokens.spaceSm),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: isDefault || broken
                    ? null
                    : () => onMakeDefault(option.id),
                icon: const Icon(Icons.check_circle_outline, size: 14),
                label: Text(
                  isDefault ? t('inUse') : t('setDefault'),
                  style: const TextStyle(fontSize: DswTokens.fontSizeXxs12),
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              // Shipped presets open read-only to be READ; a broken one has no
              // readable composition, so its viewer is withheld (React rule).
              if (option.trust == PresetTrust.system)
                IconButton(
                  tooltip: t('view'),
                  icon: Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                  onPressed: broken ? null : () => onView(option.id),
                ),
              IconButton(
                tooltip: authorable
                    ? t('duplicate')
                    : t('duplicateUnavailable'),
                icon: Icon(Icons.copy, size: 16, color: aliases.labelTertiary),
                onPressed: !authorable || broken
                    ? null
                    : () => _copyDialog(context, option, t),
              ),
              if (option.trust == PresetTrust.user)
                IconButton(
                  tooltip: authorable ? t('delete') : t('deleteUnavailable'),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: aliases.stateErrorPrimary,
                  ),
                  onPressed: !authorable
                      ? null
                      : () => _confirmDelete(context, option, t),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyDialog(
    BuildContext context,
    AgentPresetOption option,
    Translate t,
  ) {
    final TextEditingController idCtrl = TextEditingController(
      text: '${option.id}-copy',
    );
    final TextEditingController nameCtrl = TextEditingController(
      text: '${option.displayName ?? option.name} copy',
    );
    final DswAliases a = aliases;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: a.bgLayer2,
        title: Text(
          '${t('copyTitle')} · ${option.displayName ?? option.name}',
          style: TextStyle(color: a.labelPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              decoration: InputDecoration(labelText: t('presetId')),
            ),
            const SizedBox(height: DswTokens.spaceSm),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: t('displayName')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onCopy(option.id, idCtrl.text.trim(), nameCtrl.text.trim());
            },
            child: Text(t('create')),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    AgentPresetOption option,
    Translate t,
  ) {
    final DswAliases a = aliases;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: a.bgLayer2,
        title: Text(t('deleteTitle')),
        content: Text(
          t('deleteDescription'),
          style: TextStyle(color: a.labelSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: a.stateErrorPrimary),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(option.id);
            },
            child: Text(t('deleteConfirm')),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    for (final E e in this) {
      return e;
    }
    return null;
  }
}
