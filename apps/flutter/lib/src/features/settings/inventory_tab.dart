/// Live Inventory tab — parity with React `PluginInventorySettingsTab`.
///
/// Renders `pluginInventory/list` in two collapsible groups: the agent-preset
/// (session) group open by default with a preset switcher, then the global
/// plane collapsed (failures float first, preset-provided rows marked).
/// Search filters both groups and forces them open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart'
    show kInventoryNamespace;
import '../../theme/app_theme.dart';

// One global-plane entry — mirrors `PluginInventorySnapshot['entries'][number]`.
class _Entry {
  const _Entry({
    required this.entryId,
    required this.moduleName,
    required this.enabled,
    required this.fiberPhase,
  });

  final String entryId;
  final String moduleName;
  final bool enabled;
  final String? fiberPhase;

  factory _Entry.fromJson(Map<String, dynamic> j) => _Entry(
        entryId: j['entryId'] as String? ?? '',
        moduleName: j['moduleName'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        fiberPhase: j['fiberPhase'] as String?,
      );
}

// One preset composition row — mirrors `AgentPresetPluginRow`.
// `enabled` is `true`/`false`, or null when the Host reports 'conditional'.
class _PresetRow {
  const _PresetRow({
    required this.entryId,
    required this.moduleName,
    required this.enabled,
    required this.conditional,
    required this.condition,
    required this.fiberPhase,
  });

  final String? entryId;
  final String moduleName;
  final bool? enabled;
  final bool conditional;
  final String? condition;
  final String? fiberPhase;

  factory _PresetRow.fromJson(Map<String, dynamic> j) {
    final Object? raw = j['enabled'];
    final bool conditional = raw == 'conditional';
    final bool? enabled = conditional
        ? null
        : raw is bool
            ? raw
            : true;
    return _PresetRow(
      entryId: j['entryId'] as String?,
      moduleName: j['moduleName'] as String? ?? '',
      enabled: enabled,
      conditional: conditional,
      condition: j['condition'] as String?,
      fiberPhase: j['fiberPhase'] as String?,
    );
  }
}

// One agent preset group — mirrors `AgentPresetPluginGroup`.
class _PresetGroup {
  const _PresetGroup({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.broken,
    required this.rows,
  });

  final String id;
  final String? name;
  final bool isDefault;
  final String? broken;
  final List<_PresetRow> rows;

  factory _PresetGroup.fromJson(Map<String, dynamic> j) {
    final List<dynamic> raw = j['rows'] as List<dynamic>? ?? const [];
    return _PresetGroup(
      id: j['id'] as String? ?? '',
      name: j['name'] as String?,
      isDefault: j['isDefault'] as bool? ?? false,
      broken: j['broken'] as String?,
      rows: raw
          .whereType<Map>()
          .map((e) => _PresetRow.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  String get displayName => name ?? id;
}

String _shortName(String moduleName) {
  final String unscoped = moduleName.startsWith('@')
      ? moduleName.substring(moduleName.indexOf('/') + 1)
      : moduleName;
  return unscoped
      .replaceAll(RegExp(r'^cordis:'), '')
      .replaceAll(RegExp(r'^cordis-plugin-'), '')
      .replaceAll(RegExp(r'^dsh-(?:host-|client-)?'), '');
}

String _phaseLabel(String? phase, Translate t) {
  switch (phase) {
    case 'pending':
      return t('pending');
    case 'loading':
      return t('loadingPhase');
    case 'active':
      return t('active');
    case 'failed':
      return t('failed');
    case 'unloading':
      return t('unloading');
    default:
      return t('unobserved');
  }
}

Color _phaseColor(String? phase, DswAliases aliases) {
  switch (phase) {
    case 'active':
      return aliases.stateSuccessPrimary;
    case 'failed':
      return aliases.stateErrorPrimary;
    case 'loading':
    case 'pending':
      return aliases.stateWarnPrimary;
    default:
      return aliases.labelCaption;
  }
}

bool _matches(String moduleName, String? entryId, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return true;
  return '$moduleName ${entryId ?? ''}'.toLowerCase().contains(normalizedQuery);
}

_PresetGroup? _fallbackPreset(List<_PresetGroup> presets) {
  for (final p in presets) {
    if (p.isDefault) return p;
  }
  return presets.isEmpty ? null : presets.first;
}

String _presetLabel(_PresetGroup preset, Translate t) {
  final String name = preset.displayName;
  if (preset.broken != null) {
    return t('presetOptionBroken').replaceAll('{name}', name);
  }
  if (preset.isDefault) {
    return t('presetOptionDefault').replaceAll('{name}', name);
  }
  return name;
}

enum _InvStatus { loading, error, ready }

class InventoryTab extends ConsumerStatefulWidget {
  const InventoryTab({super.key, required this.aliases});
  final DswAliases aliases;

  @override
  ConsumerState<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends ConsumerState<InventoryTab> {
  _InvStatus _status = _InvStatus.loading;
  String? _error;
  List<_Entry> _entries = const [];
  List<_PresetGroup> _presets = const [];
  String _query = '';
  String? _expandedKey;
  String? _chosenPresetId;
  bool? _presetOpen;
  bool? _globalOpen;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final int gen = ++_generation;
    setState(() {
      _status = _InvStatus.loading;
      _error = null;
    });
    try {
      final Map<String, dynamic> snap =
          await ref.read(connectionClientProvider).pluginInventoryList();
      if (!mounted || gen != _generation) return;
      final List<dynamic> rawEntries =
          (snap['entries'] as List<dynamic>? ?? const []);
      final List<_Entry> entries = rawEntries
          .whereType<Map>()
          .map((e) => _Entry.fromJson(e.cast<String, dynamic>()))
          .toList();
      final List<dynamic> rawPresets =
          (snap['agentPresets'] as List<dynamic>? ?? const []);
      final List<_PresetGroup> presets = rawPresets
          .whereType<Map>()
          .map((e) => _PresetGroup.fromJson(e.cast<String, dynamic>()))
          .toList();
      setState(() {
        _status = _InvStatus.ready;
        _entries = entries;
        _presets = presets;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _status = _InvStatus.error;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = widget.aliases;
    final Translate t = ref.bindLocale(kInventoryNamespace);

    if (_status == _InvStatus.loading) {
      return Center(child: Text(t('loading')));
    }

    if (_status == _InvStatus.error) {
      return ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          Text(t('error'),
              style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
          const SizedBox(height: DswTokens.spaceMd),
          FilledButton(onPressed: _load, child: Text(t('retry'))),
          if (_error != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Text(_error!, style: TextStyle(fontSize: 11, color: aliases.labelCaption)),
          ],
        ],
      );
    }

    // Ready — derive filtered views mirroring React.
    final String q = _query.trim().toLowerCase();
    final bool searching = q.isNotEmpty;
    final _PresetGroup? selected = _presets
            .where((p) => p.id == _chosenPresetId)
            .cast<_PresetGroup?>()
            .firstWhere((p) => p != null, orElse: () => null) ??
        _fallbackPreset(_presets);

    // Presets enabling each module (for preset-provided marking).
    final Map<String, List<_PresetGroup>> enabledIn = {};
    for (final preset in _presets) {
      for (final row in preset.rows) {
        if (row.enabled != true) continue;
        final List<_PresetGroup> groups =
            enabledIn.putIfAbsent(row.moduleName, () => []);
        if (!groups.contains(preset)) groups.add(preset);
      }
    }

    final List<_Entry> failedEntries =
        _entries.where((e) => e.fiberPhase == 'failed').toList();
    final List<_Entry> regularEntries =
        _entries.where((e) => e.fiberPhase != 'failed').toList();
    final List<_Entry> filteredFailed = failedEntries
        .where((e) => _matches(e.moduleName, e.entryId, q))
        .toList();
    final List<_Entry> filteredRegular = regularEntries
        .where((e) => _matches(e.moduleName, e.entryId, q))
        .toList();
    final int globalCount = filteredFailed.length + filteredRegular.length;
    final List<_PresetRow> selectedRows = selected == null
        ? const []
        : selected.rows
            .where((r) => _matches(r.moduleName, r.entryId, q))
            .toList();
    final List<_PresetGroup> otherPresetMatches = searching
        ? _presets
            .where((p) =>
                p != selected &&
                p.rows.any((r) => _matches(r.moduleName, r.entryId, q)))
            .toList()
        : const [];
    final int otherMatchCount = otherPresetMatches.fold<int>(
        0,
        (total, p) =>
            total +
            p.rows.where((r) => _matches(r.moduleName, r.entryId, q)).length);

    final bool presetEffectiveOpen = searching || (_presetOpen ?? true);
    final bool globalEffectiveOpen =
        searching || (_globalOpen ?? _presets.isEmpty);
    final bool nothingMatches = searching &&
        globalCount == 0 &&
        selectedRows.isEmpty &&
        otherPresetMatches.isEmpty;

    // Invalidate expanded when filtered away.
    if (_expandedKey != null) {
      final bool stillVisible = selectedRows.asMap().entries.any(
              (e) => 'preset:${selected?.id}:${_selectedRowIndex(selected!, e.value)}' == _expandedKey) ||
          filteredFailed.any((e) => 'global:${e.entryId}' == _expandedKey) ||
          filteredRegular.any((e) => 'global:${e.entryId}' == _expandedKey) ||
          (selected != null &&
              selected.rows.asMap().entries.any((e) =>
                  'preset:${selected.id}:${e.key}' == _expandedKey &&
                  _matches(e.value.moduleName, e.value.entryId, q)));
      if (!stillVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _expandedKey = null);
        });
      }
    }

    return ListView(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      children: [
        Text(
          t('tab'),
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        // Search
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 16),
            hintText: t('search'),
            hintStyle: TextStyle(color: aliases.labelCaption, fontSize: DswTokens.fontSizeS14),
            filled: true,
            fillColor: aliases.specificInputMajor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceMd,
              vertical: DswTokens.spaceSm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(color: aliases.borderL2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(color: aliases.borderL2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(color: aliases.stateBusinessPrimary, width: 1.5),
            ),
          ),
          onChanged: (String v) => setState(() => _query = v),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        if (_entries.isEmpty && _presets.isEmpty)
          _EmptyBox(aliases: aliases, label: t('empty'))
        else if (nothingMatches)
          _EmptyBox(aliases: aliases, label: t('emptySearch'))
        else ...[
          if (selected != null)
            _PresetGroupSection(
              aliases: aliases,
              t: t,
              preset: selected,
              presets: _presets,
              rows: selectedRows,
              open: presetEffectiveOpen,
              onToggleOpen: () =>
                  setState(() => _presetOpen = !presetEffectiveOpen),
              onSelectPreset: (String id) => setState(() {
                _chosenPresetId = id;
                _presetOpen = true;
              }),
              expandedKey: _expandedKey,
              onToggleRow: (String key) => setState(
                  () => _expandedKey = _expandedKey == key ? null : key),
              otherPresetMatches: otherPresetMatches,
              otherMatchCount: otherMatchCount,
              query: q,
            ),
          if (_entries.isNotEmpty)
            _GlobalGroupSection(
              aliases: aliases,
              t: t,
              failed: filteredFailed,
              regular: filteredRegular,
              globalCount: globalCount,
              hasPresets: _presets.isNotEmpty,
              open: globalEffectiveOpen,
              onToggleOpen: () =>
                  setState(() => _globalOpen = !globalEffectiveOpen),
              enabledIn: enabledIn,
              expandedKey: _expandedKey,
              onToggleRow: (String key) => setState(
                  () => _expandedKey = _expandedKey == key ? null : key),
              onJumpToPreset: (String id) => setState(() {
                _chosenPresetId = id;
                _presetOpen = true;
              }),
              onRefresh: _load,
            ),
        ],
        const SizedBox(height: DswTokens.spaceLg),
        Container(
          decoration: BoxDecoration(
            color: aliases.bgLayer2,
            borderRadius: BorderRadius.circular(DswTokens.radiusLg),
            border: Border.all(color: aliases.borderL2),
          ),
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: aliases.labelTertiary),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Text(
                  '${_entries.length} ${t('countUnit')} · Host Loader inventory via pluginInventory/list (read-only).',
                  style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _selectedRowIndex(_PresetGroup preset, _PresetRow row) {
    return preset.rows.indexOf(row);
  }
}

class _PresetGroupSection extends StatelessWidget {
  const _PresetGroupSection({
    required this.aliases,
    required this.t,
    required this.preset,
    required this.presets,
    required this.rows,
    required this.open,
    required this.onToggleOpen,
    required this.onSelectPreset,
    required this.expandedKey,
    required this.onToggleRow,
    required this.otherPresetMatches,
    required this.otherMatchCount,
    required this.query,
  });

  final DswAliases aliases;
  final Translate t;
  final _PresetGroup preset;
  final List<_PresetGroup> presets;
  final List<_PresetRow> rows;
  final bool open;
  final VoidCallback onToggleOpen;
  final ValueChanged<String> onSelectPreset;
  final String? expandedKey;
  final ValueChanged<String> onToggleRow;
  final List<_PresetGroup> otherPresetMatches;
  final int otherMatchCount;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onToggleOpen,
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: DswTokens.transitionDurationFast,
                      child: Icon(Icons.chevron_right,
                          size: 14, color: aliases.labelTertiary),
                    ),
                    const SizedBox(width: 4),
                    Text(t('presetTitle'),
                        style: TextStyle(
                            fontSize: DswTokens.fontSizeS14,
                            fontWeight: FontWeight.w600,
                            color: aliases.labelPrimary)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Preset switcher pill — display-only roster selector.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: aliases.bgOverlay,
                borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: preset.id,
                  icon: Icon(Icons.keyboard_arrow_down,
                      size: 14, color: aliases.labelTertiary),
                  style: TextStyle(
                      fontSize: 12, color: aliases.labelPrimary),
                  dropdownColor: aliases.specificMenu,
                  hint: Text(t('switcherLabel')),
                  items: [
                    for (final p in presets)
                      DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(_presetLabel(p, t)),
                      ),
                  ],
                  onChanged: (String? next) {
                    if (next != null) onSelectPreset(next);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Semantics(
          label: t('switcherLabel'),
          child: Text(
            '${t('presetSubtitle')} · ${rows.length} ${t('countUnit')}',
            style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelTertiary),
          ),
        ),
        if (open) ...[
          const SizedBox(height: DswTokens.spaceMd),
          if (preset.broken != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DswTokens.spaceMd),
              decoration: BoxDecoration(
                color: aliases.bgOverlay,
                borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                border: Border.all(color: aliases.stateErrorPrimary),
              ),
              child: Text(preset.broken!,
                  style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.stateErrorPrimary)),
            ),
          if (preset.broken != null) const SizedBox(height: DswTokens.spaceSm),
          _CardsWrap(
            aliases: aliases,
            children: [
              for (int i = 0; i < preset.rows.length; i++)
                if (_matches(
                    preset.rows[i].moduleName, preset.rows[i].entryId, query))
                  _PresetRowCard(
                    preset: preset,
                    row: preset.rows[i],
                    rowKey: 'preset:${preset.id}:$i',
                    aliases: aliases,
                    t: t,
                    expanded: expandedKey == 'preset:${preset.id}:$i',
                    onToggle: () => onToggleRow('preset:${preset.id}:$i'),
                  ),
            ],
          ),
          if (query.isNotEmpty && otherMatchCount > 0) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  t('matchesInOtherPresets')
                      .replaceAll('{count}', '$otherMatchCount'),
                  style: TextStyle(
                      fontSize: 11, color: aliases.labelCaption),
                ),
                for (final p in otherPresetMatches)
                  TextButton(
                    onPressed: () => onSelectPreset(p.id),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(p.displayName,
                        style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: DswTokens.spaceLg),
      ],
    );
  }
}

class _GlobalGroupSection extends StatelessWidget {
  const _GlobalGroupSection({
    required this.aliases,
    required this.t,
    required this.failed,
    required this.regular,
    required this.globalCount,
    required this.hasPresets,
    required this.open,
    required this.onToggleOpen,
    required this.enabledIn,
    required this.expandedKey,
    required this.onToggleRow,
    required this.onJumpToPreset,
    required this.onRefresh,
  });

  final DswAliases aliases;
  final Translate t;
  final List<_Entry> failed;
  final List<_Entry> regular;
  final int globalCount;
  final bool hasPresets;
  final bool open;
  final VoidCallback onToggleOpen;
  final Map<String, List<_PresetGroup>> enabledIn;
  final String? expandedKey;
  final ValueChanged<String> onToggleRow;
  final ValueChanged<String> onJumpToPreset;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onToggleOpen,
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: DswTokens.transitionDurationFast,
                      child: Icon(Icons.chevron_right,
                          size: 14, color: aliases.labelTertiary),
                    ),
                    const SizedBox(width: 4),
                    Text(t('globalTitle'),
                        style: TextStyle(
                            fontSize: DswTokens.fontSizeS14,
                            fontWeight: FontWeight.w600,
                            color: aliases.labelPrimary)),
                  ],
                ),
              ),
            ),
            TextButton(onPressed: onRefresh, child: Text(t('retry') == 'Retry' ? 'Refresh' : t('retry'))),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${t('globalSubtitle')} · $globalCount ${t('countUnit')}${failed.isNotEmpty ? ' · ${failed.length} ${t('failedCountLabel')}' : ''}',
          style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelTertiary),
        ),
        if (open) ...[
          const SizedBox(height: DswTokens.spaceMd),
          _CardsWrap(
            aliases: aliases,
            children: [
              for (final entry in [...failed, ...regular])
                _GlobalRowCard(
                  entry: entry,
                  providers: entry.enabled
                      ? null
                      : enabledIn[entry.moduleName],
                  rowKey: 'global:${entry.entryId}',
                  aliases: aliases,
                  t: t,
                  expanded: expandedKey == 'global:${entry.entryId}',
                  onToggle: () => onToggleRow('global:${entry.entryId}'),
                  onJumpToPreset: onJumpToPreset,
                ),
            ],
          ),
        ],
        const SizedBox(height: DswTokens.spaceMd),
      ],
    );
  }
}

class _CardsWrap extends StatelessWidget {
  const _CardsWrap({required this.aliases, required this.children});
  final DswAliases aliases;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return _EmptyBox(aliases: aliases, label: '');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool twoCol = constraints.maxWidth >= 720;
        final double gap = DswTokens.spaceSm;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(
                width: twoCol
                    ? (constraints.maxWidth - gap) / 2
                    : constraints.maxWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

String _rowStateText(_PresetRow row, Translate t, bool failed) {
  if (failed) return t('failedTag');
  if (row.conditional) return t('conditionalTag');
  if (row.enabled == true) return t('enabledTag');
  return t('disabledTag');
}

String _rowStateKind(_PresetRow row, bool failed) {
  if (failed) return 'failed';
  if (row.conditional) return 'conditional';
  if (row.enabled == true) return 'enabled';
  return 'disabled';
}

class _PresetRowCard extends StatelessWidget {
  const _PresetRowCard({
    required this.preset,
    required this.row,
    required this.rowKey,
    required this.aliases,
    required this.t,
    required this.expanded,
    required this.onToggle,
  });

  final _PresetGroup preset;
  final _PresetRow row;
  final String rowKey;
  final DswAliases aliases;
  final Translate t;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final String title = _shortName(row.moduleName);
    final bool failed = row.fiberPhase == 'failed';
    final String stateText = _rowStateText(row, t, failed);
    final String kind = _rowStateKind(row, failed);
    return _CardShell(
      aliases: aliases,
      failed: failed,
      title: title,
      ariaLabel: '$title, $stateText',
      trailing: _Trailing(
        aliases: aliases,
        showDot: row.enabled == true && !failed && row.fiberPhase != null,
        phase: row.fiberPhase,
        tagKind: kind,
        tagLabel: stateText,
      ),
      expanded: expanded,
      onToggle: onToggle,
      details: [
        if (row.entryId != null)
          SelectableText(
            row.entryId!,
            style: TextStyle(
                fontSize: 11,
                color: aliases.labelSecondary,
                fontFamily: 'SF Mono'),
          ),
        if (row.entryId != null) const SizedBox(height: DswTokens.spaceMd),
        _DetailRow(
            label: t('moduleLabel'),
            value: row.moduleName,
            aliases: aliases,
            mono: true),
        const SizedBox(height: DswTokens.spaceSm),
        _DetailRow(
            label: t('fromPreset'),
            value: preset.displayName,
            aliases: aliases),
        const SizedBox(height: DswTokens.spaceSm),
        _DetailRow(
            label: t('configuration'),
            value: stateText,
            aliases: aliases),
        if (row.fiberPhase != null) ...[
          const SizedBox(height: DswTokens.spaceSm),
          _DetailRow(
              label: t('runtime'),
              value: _phaseLabel(row.fiberPhase, t),
              aliases: aliases),
        ],
        if (row.condition != null) ...[
          const SizedBox(height: DswTokens.spaceSm),
          _DetailRow(
              label: t('condition'),
              value: row.condition!,
              aliases: aliases,
              mono: true),
        ],
      ],
    );
  }
}

class _GlobalRowCard extends StatelessWidget {
  const _GlobalRowCard({
    required this.entry,
    required this.providers,
    required this.rowKey,
    required this.aliases,
    required this.t,
    required this.expanded,
    required this.onToggle,
    required this.onJumpToPreset,
  });

  final _Entry entry;
  final List<_PresetGroup>? providers;
  final String rowKey;
  final DswAliases aliases;
  final Translate t;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onJumpToPreset;

  @override
  Widget build(BuildContext context) {
    final String title = _shortName(entry.moduleName);
    final bool failed = entry.fiberPhase == 'failed';
    final String stateText = failed
        ? t('failedTag')
        : providers != null
            ? t('presetEnabledTag')
            : t(entry.enabled ? 'enabledTag' : 'disabledTag');
    final String kind = failed
        ? 'failed'
        : providers != null
            ? 'preset'
            : entry.enabled
                ? 'enabled'
                : 'disabled';
    return _CardShell(
      aliases: aliases,
      failed: failed,
      title: title,
      ariaLabel: '$title, $stateText',
      trailing: _Trailing(
        aliases: aliases,
        showDot:
            entry.enabled && !failed && entry.fiberPhase != null,
        phase: entry.fiberPhase,
        tagKind: kind,
        tagLabel: stateText,
      ),
      expanded: expanded,
      onToggle: onToggle,
      details: [
        SelectableText(
          entry.entryId,
          style: TextStyle(
              fontSize: 11,
              color: aliases.labelSecondary,
              fontFamily: 'SF Mono'),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        if (providers != null) ...[
          _DetailRow(
              label: t('configuration'),
              value: t('presetProvidedDetail'),
              aliases: aliases),
          const SizedBox(height: DswTokens.spaceSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(t('enabledIn'),
                    style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelTertiary)),
              ),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      providers!.map((p) => p.displayName).join(' · '),
                      style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelPrimary),
                    ),
                    TextButton(
                      onPressed: () => onJumpToPreset(providers!.first.id),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: Text(t('viewInPreset'),
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          _DetailRow(
              label: t('configuration'),
              value: t(entry.enabled ? 'enabledTag' : 'disabledTag'),
              aliases: aliases),
          if (entry.enabled) ...[
            const SizedBox(height: DswTokens.spaceSm),
            _DetailRow(
                label: t('runtime'),
                value: _phaseLabel(entry.fiberPhase, t),
                aliases: aliases),
          ],
          const SizedBox(height: DswTokens.spaceSm),
          _DetailRow(
              label: t('moduleLabel'),
              value: entry.moduleName,
              aliases: aliases,
              mono: true),
        ],
      ],
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.aliases,
    required this.showDot,
    required this.phase,
    required this.tagKind,
    required this.tagLabel,
  });

  final DswAliases aliases;
  final bool showDot;
  final String? phase;
  final String tagKind;
  final String tagLabel;

  @override
  Widget build(BuildContext context) {
    final bool positive =
        tagKind == 'enabled' || tagKind == 'preset' || tagKind == 'conditional';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDot)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _phaseColor(phase, aliases),
              shape: BoxShape.circle,
            ),
          ),
        if (showDot) const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: positive
                ? aliases.stateSuccessTertiary
                : aliases.bgOverlay,
            borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          ),
          child: Text(
            tagLabel,
            style: TextStyle(
              fontSize: 11,
              color: positive
                  ? aliases.stateSuccessPrimary
                  : aliases.labelTertiary,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.aliases,
    required this.failed,
    required this.title,
    required this.ariaLabel,
    required this.trailing,
    required this.expanded,
    required this.onToggle,
    required this.details,
  });

  final DswAliases aliases;
  final bool failed;
  final String title;
  final String ariaLabel;
  final Widget trailing;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
        boxShadow: DswTokens.shadowLv1,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(DswTokens.radiusLg),
            hoverColor: aliases.interactiveBgHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DswTokens.spaceLg,
                vertical: DswTokens.spaceMd,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: ariaLabel,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: DswTokens.spaceSm),
                  trailing,
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: DswTokens.transitionDurationFast,
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 12, color: aliases.labelTertiary),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: aliases.borderL1)),
              ),
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: details,
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.label,
      required this.value,
      required this.aliases,
      this.mono = false});
  final String label;
  final String value;
  final DswAliases aliases;
  final bool mono;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelTertiary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelPrimary,
                fontFamily: mono ? 'SF Mono' : null,
              ),
            ),
          ),
        ],
      );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.aliases, required this.label});
  final DswAliases aliases;
  final String label;
  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
      ),
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      child: Center(
        child: Text(label,
            style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelCaption)),
      ),
    );
  }
}
