import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models — mirrors `PluginInventoryEntry` + `PluginInventorySnapshot`
// ---------------------------------------------------------------------------

class PluginInventoryEntryView {
  const PluginInventoryEntryView({
    required this.entryId,
    required this.moduleName,
    required this.enabled,
    required this.fiberPhase,
  });

  final String entryId;
  final String moduleName;
  final bool enabled;
  final String? fiberPhase;

  factory PluginInventoryEntryView.fromJson(Map<String, dynamic> json) =>
      PluginInventoryEntryView(
        entryId: json['entryId'] as String? ?? '',
        moduleName: json['moduleName'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        fiberPhase: json['fiberPhase'] as String?,
      );
}

String _shortName(String moduleName) {
  final unscoped = moduleName.startsWith('@')
      ? moduleName.substring(moduleName.indexOf('/') + 1)
      : moduleName;
  return unscoped
      .replaceAll(RegExp(r'^cordis:'), '')
      .replaceAll(RegExp(r'^cordis-plugin-'), '')
      .replaceAll(RegExp(r'^dsh-(?:host-|client-)?'), '');
}

String _phaseLabel(String? phase) {
  switch (phase) {
    case 'pending':
      return 'Pending';
    case 'loading':
      return 'Loading';
    case 'active':
      return 'Active';
    case 'failed':
      return 'Failed';
    case 'unloading':
      return 'Unloading';
    default:
      return 'Unobserved';
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

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

enum InventoryStatus { idle, loading, ready, error }

class InventoryState {
  const InventoryState({
    this.status = InventoryStatus.idle,
    this.error,
    this.entries = const [],
    this.filter = '',
  });

  final InventoryStatus status;
  final String? error;
  final List<PluginInventoryEntryView> entries;
  final String filter;

  List<PluginInventoryEntryView> get filtered {
    final q = filter.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where((e) => '${e.moduleName} ${e.entryId}'.toLowerCase().contains(q))
        .toList();
  }

  InventoryState copyWith({
    InventoryStatus? status,
    String? error,
    List<PluginInventoryEntryView>? entries,
    String? filter,
  }) => InventoryState(
    status: status ?? this.status,
    error: error,
    entries: entries ?? this.entries,
    filter: filter ?? this.filter,
  );
}

class InventoryController extends Notifier<InventoryState> {
  @override
  InventoryState build() => const InventoryState();

  Future<void> load() async {
    state = state.copyWith(status: InventoryStatus.loading, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final snapshot = await client.pluginInventoryList();
      final entries = (snapshot['entries'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (e) => PluginInventoryEntryView.fromJson(e.cast<String, dynamic>()),
          )
          .toList();
      state = InventoryState(
        status: InventoryStatus.ready,
        entries: entries,
        filter: state.filter,
      );
    } catch (e) {
      state = state.copyWith(
        status: InventoryStatus.error,
        error: e.toString(),
      );
    }
  }

  void setFilter(String v) {
    state = state.copyWith(filter: v);
  }
}

final inventoryControllerProvider =
    NotifierProvider<InventoryController, InventoryState>(
      InventoryController.new,
    );

// ---------------------------------------------------------------------------
// Screen — mirrors `PluginInventorySettingsTab.tsx`
// ---------------------------------------------------------------------------

/// SettingsInventoryScreen — read-only Host Loader inventory table.
///
/// Mirrors `PluginInventorySettingsTab` (`ui-settings-plugin-inventory`):
/// search, catalog heading with count, DataTable with columns name, version,
/// status (phase dot + enabled tag, locale `enabledTag`/`disabledTag`),
/// expandable detail with entryId + configuration + Cordis phase, empty
/// states, retry, loading. Backend wired via `pluginInventoryList` Typert
/// (`pluginInventory/list`), no dropped typert.
///
/// Table uses [DataTable] with [DswTokens] radiusMd (8), interactiveBgHover,
/// borderL2, bgOverlay header, specificMenu dropdown semantics.
class SettingsInventoryScreen extends ConsumerStatefulWidget {
  const SettingsInventoryScreen({super.key});

  @override
  ConsumerState<SettingsInventoryScreen> createState() =>
      _SettingsInventoryScreenState();
}

class _SettingsInventoryScreenState
    extends ConsumerState<SettingsInventoryScreen> {
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(inventoryControllerProvider).status ==
          InventoryStatus.idle) {
        ref.read(inventoryControllerProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final state = ref.watch(inventoryControllerProvider);
    final controller = ref.read(inventoryControllerProvider.notifier);

    if (state.status == InventoryStatus.error) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plugins are temporarily unavailable.',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.stateErrorPrimary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceMd),
              FilledButton(
                onPressed: () => controller.load(),
                child: const Text('Retry'),
              ),
              if (state.error != null) ...[
                const SizedBox(height: DswTokens.spaceSm),
                Text(
                  state.error!,
                  style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (state.status == InventoryStatus.loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final filtered = state.filtered;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          Text(
            'Plugin list',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Read-only Host Loader inventory.',
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelTertiary,
            ),
          ),
          const SizedBox(height: DswTokens.spaceMd),
          // Search
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 16),
              hintText: 'Search plugins',
              hintStyle: TextStyle(
                color: aliases.labelCaption,
                fontSize: DswTokens.fontSizeS14,
              ),
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
                borderSide: BorderSide(
                  color: aliases.stateBusinessPrimary,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: controller.setFilter,
          ),
          const SizedBox(height: DswTokens.spaceMd),
          // Catalog heading
          Row(
            children: [
              Text(
                'Plugin list',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                ),
                child: Text(
                  '${filtered.length}',
                  style: TextStyle(fontSize: 11, color: aliases.labelTertiary),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => controller.load(),
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: DswTokens.spaceMd),
          if (state.entries.isEmpty)
            Container(
              decoration: BoxDecoration(
                color: aliases.bgLayer2,
                borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                border: Border.all(color: aliases.borderL2),
              ),
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Center(
                child: Text(
                  'No plugins are available.',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelCaption,
                  ),
                ),
              ),
            )
          else if (filtered.isEmpty)
            Container(
              decoration: BoxDecoration(
                color: aliases.bgLayer2,
                borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                border: Border.all(color: aliases.borderL2),
              ),
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Center(
                child: Text(
                  'No matching plugins.',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelCaption,
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: aliases.bgLayer2,
                borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                border: Border.all(color: aliases.borderL2),
                boxShadow: DswTokens.shadowLv1,
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(aliases.bgOverlay),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered))
                      return aliases.interactiveBgHover;
                    return aliases.bgLayer2;
                  }),
                  headingTextStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelTertiary,
                  ),
                  dataTextStyle: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.labelPrimary,
                  ),
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: aliases.borderL1,
                      width: 1,
                    ),
                  ),
                  columnSpacing: 24,
                  horizontalMargin: 16,
                  headingRowHeight: 40,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 56,
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Version')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: [
                    for (final e in filtered)
                      DataRow(
                        selected: _expandedId == e.entryId,
                        onSelectChanged: (bool? v) {
                          setState(
                            () => _expandedId = _expandedId == e.entryId
                                ? null
                                : e.entryId,
                          );
                        },
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (e.enabled)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _phaseColor(e.fiberPhase, aliases),
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: aliases.labelCaption,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _shortName(e.moduleName),
                                    style: TextStyle(
                                      fontSize: DswTokens.fontSizeS14,
                                      color: aliases.labelPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              // Version: show last segment of entryId as version-like, or dash when unavailable
                              e.entryId.split('/').last.isEmpty
                                  ? '—'
                                  : e.entryId.split('/').last,
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeXxs12,
                                color: aliases.labelSecondary,
                                fontFamily: 'SF Mono',
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: e.enabled
                                        ? aliases.stateSuccessTertiary
                                        : aliases.bgOverlay,
                                    borderRadius: BorderRadius.circular(
                                      DswTokens.radiusFull,
                                    ),
                                  ),
                                  child: Text(
                                    e.enabled ? 'Enabled' : 'Disabled',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: e.enabled
                                          ? aliases.stateSuccessPrimary
                                          : aliases.labelTertiary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _phaseColor(
                                      e.fiberPhase,
                                      aliases,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      DswTokens.radiusFull,
                                    ),
                                  ),
                                  child: Text(
                                    _phaseLabel(e.fiberPhase),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _phaseColor(e.fiberPhase, aliases),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (_expandedId != null) ...[
            const SizedBox(height: DswTokens.spaceMd),
            Container(
              decoration: BoxDecoration(
                color: aliases.bgLayer2,
                borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                border: Border.all(color: aliases.borderL2),
              ),
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Builder(
                builder: (context) {
                  final entry =
                      filtered
                          .where((e) => e.entryId == _expandedId)
                          .firstOrNull ??
                      state.entries
                          .where((e) => e.entryId == _expandedId)
                          .firstOrNull;
                  if (entry == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _shortName(entry.moduleName),
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeS14,
                                fontWeight: FontWeight.w600,
                                color: aliases.labelPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _expandedId = null),
                            color: aliases.labelTertiary,
                          ),
                        ],
                      ),
                      const SizedBox(height: DswTokens.spaceSm),
                      SelectableText(
                        entry.entryId,
                        style: TextStyle(
                          fontSize: 11,
                          color: aliases.labelSecondary,
                          fontFamily: 'SF Mono',
                        ),
                      ),
                      const SizedBox(height: DswTokens.spaceMd),
                      _DetailRow(
                        label: 'Configuration',
                        value: entry.enabled ? 'Enabled' : 'Disabled',
                        aliases: aliases,
                      ),
                      if (entry.enabled) ...[
                        const SizedBox(height: DswTokens.spaceSm),
                        _DetailRow(
                          label: 'Cordis status',
                          value: _phaseLabel(entry.fiberPhase),
                          aliases: aliases,
                        ),
                      ],
                      const SizedBox(height: DswTokens.spaceSm),
                      _DetailRow(
                        label: 'Module',
                        value: entry.moduleName,
                        aliases: aliases,
                        mono: true,
                      ),
                    ],
                  );
                },
              ),
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
                Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: aliases.labelTertiary,
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Text(
                    '${state.entries.length} plugins · Host Loader inventory via pluginInventory/list (read-only).',
                    style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.aliases,
    this.mono = false,
  });

  final String label;
  final String value;
  final DswAliases aliases;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelPrimary,
              fontFamily: mono ? 'SF Mono' : 'SF Pro',
              fontFamilyFallback: mono ? null : DswTokens.fontFamilyFallback,
            ),
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
