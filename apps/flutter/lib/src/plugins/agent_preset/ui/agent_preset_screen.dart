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
      body: const AgentPresetRosterBody(),
    );
  }
}

/// Roster body shared by [AgentPresetScreen] and the Settings `Agent presets`
/// tab: picker row + management section + seat. The Settings tab passes
/// `showPickers: false` — React's settings section is intro plus cards only,
/// while the standalone screen keeps the per-session pickers.
class AgentPresetRosterBody extends ConsumerWidget {
  const AgentPresetRosterBody({super.key, this.showPickers = true});

  final bool showPickers;

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
    final Translate t = ref.bindLocale(kAgentPresetNamespace);

    return async.when(
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
              if (showPickers)
                AgentPresetRow(
                  options: options,
                  selectedId: effectiveCurrent,
                  saving: saving,
                  aliases: aliases,
                  onSelect: (String id) => selectPreset(context, ref, id),
                ),
              if (showPickers) const SizedBox(height: DswTokens.spaceLg),
              AgentPresetSection(
                options: options,
                current: effectiveCurrent,
                authorable: roster.authorable,
                hasDocument: roster.hasDocument,
                aliases: aliases,
                onMakeDefault: (String id) =>
                    makeDefaultPresetSelection(context, ref, id),
                onView: (String id) => viewPresetComposition(context, ref, id),
                onCopy: (String fromId, String presetId, String name) =>
                    copyPresetAs(context, ref, fromId, presetId, name),
                onDelete: (String id) => deletePreset(context, ref, id),
                onCreatorDraft: () => selectPreset(context, ref, 'cordis'),
              ),
              if (showPickers) ...[
                const SizedBox(height: DswTokens.spaceLg),
                AgentPresetSeat(
                  options: options,
                  current: effectiveCurrent,
                  aliases: aliases,
                  onSelect: (String id) => selectPreset(context, ref, id),
                ),
              ],
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
      );
  }
}

/// Opens the read-only viewer over one preset's shipped composition
/// (`agentPreset.read`); failures surface as a snackbar, never a fake body.
Future<void> viewPresetComposition(
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
          final DswAliases viewerAliases = presetAliasesOf(ctx);
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
      showPresetToast(context, 'Failed to read "$id": $e');
    }
  }

  /// Creates a copy through `agentPreset.copy` and refreshes the roster, then
  /// takes the user to the new preset's files like React `confirmCopy`: the
  /// directory opens where the host has a desktop, and its path appears on
  /// the new row where it does not. A location failure never fails the copy.
  Future<void> copyPresetAs(
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
      try {
        final PresetLocation loc = await openPresetLocation(
          ref.read(connectionClientProvider),
          created,
        );
        if (!loc.opened && loc.path != null) {
          ref.read(agentPresetRevealedPathsProvider.notifier).update((m) => {
            ...m,
            created: loc.path!,
          });
        }
      } catch (_) {
        // The copy landed; getting to its files is a follow-up, not the write.
      }
      if (context.mounted) showPresetToast(context, 'Created preset "$created"');
    } catch (e) {
      if (context.mounted) showPresetToast(context, 'Failed to create "$presetId": $e');
    }
  }

  /// Deletes a user preset through `agentPreset.remove`; running sessions
  /// keep the composition they were mounted with.
  Future<void> deletePreset(BuildContext context, WidgetRef ref, String id) async {
    try {
      await removePreset(ref.read(connectionClientProvider), id);
      ref.invalidate(agentPresetListProvider);
      if (context.mounted) showPresetToast(context, 'Deleted "$id"');
    } catch (e) {
      if (context.mounted) showPresetToast(context, 'Failed to delete "$id": $e');
    }
  }

void showPresetToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  DswAliases presetAliasesOf(BuildContext context) =>
      Theme.of(context).extension<DswThemeExtension>()?.aliases ??
      DswTokens.lightAliases;

  Future<void> selectPreset(BuildContext context, WidgetRef ref, String id) async {
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

/// Persists one preset as the deployment default for sessions created later
/// (React `makeDefault` → `writeDefaultPreset` over
/// `settings.update('agent-presets', {default})`), then re-reads the roster.
///
/// This is what makes a management-card pick reflect throughout the app:
/// the hero seat falls back to the roster's `isDefault` row and the host
/// resolves the default at session creation. Running sessions keep the
/// composition they began with. Failures surface as a snackbar and leave
/// the roster untouched.
Future<void> makeDefaultPresetSelection(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  ref.read(agentPresetSavingProvider.notifier).state = true;
  try {
    final String? failure = await makeDefaultPreset(
      ref.read(connectionClientProvider),
      id,
    );
    if (failure != null) {
      if (context.mounted) showPresetToast(context, 'Failed to set default: $failure');
      return;
    }
    ref.read(agentPresetCurrentProvider.notifier).state = id;
    ref.invalidate(agentPresetListProvider);
    if (context.mounted) {
      showPresetToast(context, 'Preset "$id" is now the default for new sessions');
    }
  } finally {
    ref.read(agentPresetSavingProvider.notifier).state = false;
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
/// can neither compose nor copy. The location action rides the host wire too
/// (`settings/openAgentPresetDirectory`): the directory opens on the host
/// desktop where it can, otherwise its path appears on the row.
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
    this.onCreatorDraft,
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

  /// Guided alternative to copying: stage the self-referential preset for the
  /// next session. Mirrors React's `startCreatorDraft` entry point, which is
  /// offered only where the `cordis` preset is on the roster.
  final VoidCallback? onCreatorDraft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kAgentPresetNamespace);
    final List<AgentPresetOption> system = options
        .where((o) => o.trust == PresetTrust.system)
        .toList();
    final List<AgentPresetOption> user = options
        .where((o) => o.trust == PresetTrust.user)
        .toList();
    Widget cards(List<AgentPresetOption> rows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
              child: _PresetCard(
                option: o,
                options: options,
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

    Widget groupHead(String title) {
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
        ],
      );
    }

    // The custom group stays on screen even while empty: it is where a preset
    // of one's own will appear (React section rule).
    final bool showCreator =
        onCreatorDraft != null && options.any((o) => o.id == 'cordis');

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
        const SizedBox(height: 4),
        Text(
          t('sectionIntro'),
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelSecondary,
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        if (system.isNotEmpty) ...[
          groupHead(t('builtInGroup')),
          cards(system),
          const SizedBox(height: DswTokens.spaceSm),
        ],
        groupHead(t('customGroup')),
        cards(user),
        if (showCreator) ...[
          const SizedBox(height: DswTokens.spaceSm),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: authorable ? '' : t('duplicateUnavailable'),
              child: OutlinedButton.icon(
                onPressed: authorable ? onCreatorDraft : null,
                icon: const Icon(Icons.add, size: 14),
                label: Text(t('creatorDraft')),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: aliases.borderL2),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(DswTokens.radiusMd),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PresetCard extends ConsumerWidget {
  const _PresetCard({
    required this.option,
    required this.options,
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
  final List<AgentPresetOption> options;
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
    final String? revealed = ref.watch(
      agentPresetRevealedPathsProvider,
    )[option.id];
    // The card body IS the control (React rule): picking a preset is the
    // common act. A broken preset cannot compose a session so its body
    // refuses the pick; the default one is already picked.
    final bool pickable = !broken && !isDefault;
    final String cardLabel = broken
        ? '${t('brokenBadge')}: ${option.displayName ?? option.name}'
        : isDefault
            ? '${t('inUse')}: ${option.displayName ?? option.name}'
            : '${t('setDefault')}: ${option.displayName ?? option.name}';
    return Semantics(
      button: pickable,
      label: cardLabel,
      child: InkWell(
        onTap: pickable ? () => onMakeDefault(option.id) : null,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        hoverColor: aliases.interactiveBgHover,
        child: Container(
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
              // A custom preset is edited in its own files instead, which the
              // location action leads to — kept even for a broken one, since
              // the files are where it gets fixed (React cardFoot rule).
              if (option.trust == PresetTrust.system)
                IconButton(
                  tooltip: t('view'),
                  icon: Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                  onPressed: broken ? null : () => onView(option.id),
                )
              else
                IconButton(
                  tooltip: hasDocument
                      ? t('openLocation')
                      : t('showLocation'),
                  icon: Icon(
                    Icons.folder_open_outlined,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                  onPressed: () => _openLocation(context, ref, option.id),
                ),
              IconButton(
                tooltip: broken
                    ? t('brokenNoCopy')
                    : authorable
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
          // The host answered with a path instead of opening: show it on the
          // row (React `revealedPaths` paragraph). Plain widgets so the
          // label and the path stay exact-match findable in widget tests.
          if (revealed != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Text(
              t('revealedPathLabel'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              revealed,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                fontFamily: 'SF Mono',
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }

  /// Opens one preset's directory on the host desktop, or reveals its path
  /// on the row where the deployment has no opener. Failures surface as a
  /// snackbar, never a fake path.
  Future<void> _openLocation(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    try {
      final PresetLocation loc = await openPresetLocation(
        ref.read(connectionClientProvider),
        id,
      );
      if (loc.opened || loc.path == null) return;
      ref.read(agentPresetRevealedPathsProvider.notifier).update((m) => {
        ...m,
        id: loc.path!,
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open "$id": $e')));
      }
    }
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
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          // Client-side only: the host re-checks the id and its answer is
          // what the dialog reports on failure (React draftBlocker rule).
          final String? blocker = presetCopyBlocker(idCtrl.text, options);
          final String? message = blocker == null ? null : t(blocker);
          return AlertDialog(
            backgroundColor: a.bgLayer2,
            title: Text(
              '${t('copyTitle')} · ${option.displayName ?? option.name}',
              style: TextStyle(color: a.labelPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('copyIntro'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: a.labelSecondary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceSm),
                TextField(
                  controller: idCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: t('presetId')),
                ),
                const SizedBox(height: DswTokens.spaceSm),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: t('displayName')),
                ),
                if (message != null) ...[
                  const SizedBox(height: DswTokens.spaceSm),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: a.stateErrorPrimary,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('cancel')),
              ),
              FilledButton(
                onPressed: blocker != null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        onCopy(
                          option.id,
                          idCtrl.text.trim(),
                          nameCtrl.text.trim(),
                        );
                      },
                child: Text(t('create')),
              ),
            ],
          );
        },
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
