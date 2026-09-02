/// Live Inventory tab — parity with React `PluginInventorySettingsTab`.
///
/// Replaces the stub `_InventoryTab` (5 hardcoded rows) with the
/// `pluginInventory/list` wire, searchable 2-column card grid, status dot +
/// Enabled/Disabled pill, expanding inline details, and proper empty states.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../theme/app_theme.dart';

// One inventory entry — mirrors `PluginInventorySnapshot['entries'][number]`.
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

String _shortName(String moduleName) {
  final String unscoped = moduleName.startsWith('@')
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
      return 'Waiting for dependencies';
    case 'loading':
      return 'Loading';
    case 'active':
      return 'Mounted';
    case 'failed':
      return 'Mount failed';
    case 'unloading':
      return 'Unloading';
    default:
      return 'Not mounted';
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
  String _query = '';
  String? _expandedId;
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
      final List<dynamic> raw = (snap['entries'] as List<dynamic>? ?? const []);
      final List<_Entry> entries = raw
          .whereType<Map>()
          .map((e) => _Entry.fromJson(e.cast<String, dynamic>()))
          .toList();
      setState(() {
        _status = _InvStatus.ready;
        _entries = entries;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _status = _InvStatus.error;
        _error = e.toString();
      });
    }
  }

  List<_Entry> get _filtered {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((en) => '${en.moduleName} ${en.entryId}'.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = widget.aliases;

    if (_status == _InvStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_status == _InvStatus.error) {
      return ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          Text('Plugins are temporarily unavailable.',
              style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
          const SizedBox(height: DswTokens.spaceMd),
          FilledButton(onPressed: _load, child: const Text('Retry')),
          if (_error != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Text(_error!, style: TextStyle(fontSize: 11, color: aliases.labelCaption)),
          ],
        ],
      );
    }

    // Ready
    final List<_Entry> filtered = _filtered;
    // Invalidate expanded when filtered away (mirrors React effect).
    if (_expandedId != null && !filtered.any((e) => e.entryId == _expandedId)) {
      // Schedule clear after build to avoid setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _expandedId = null);
      });
    }

    return ListView(
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
        Text('Read-only Host Loader inventory.',
            style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary)),
        const SizedBox(height: DswTokens.spaceSm),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Open configuration file — not yet wired to host FS')),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: aliases.borderL2),
            ),
            child: Text('Open configuration file', style: TextStyle(fontSize: 11, color: aliases.labelSecondary)),
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        // Search
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 16),
            hintText: 'Search plugins',
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
        // Catalog heading
        Row(
          children: [
            Text('Plugin list',
                style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary)),
            const SizedBox(width: DswTokens.spaceSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: aliases.bgOverlay,
                borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              ),
              child: Text('${filtered.length}',
                  style: TextStyle(fontSize: 11, color: aliases.labelTertiary)),
            ),
            const Spacer(),
            TextButton(onPressed: _load, child: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: DswTokens.spaceMd),
        if (_entries.isEmpty)
          _EmptyBox(aliases: aliases, label: 'No plugins are available.')
        else if (filtered.isEmpty)
          _EmptyBox(aliases: aliases, label: 'No matching plugins.')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final bool twoCol = constraints.maxWidth >= 720;
              final double gap = DswTokens.spaceSm;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final _Entry entry in filtered)
                    SizedBox(
                      width: twoCol ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth,
                      child: _InventoryCard(
                        entry: entry,
                        aliases: aliases,
                        expanded: _expandedId == entry.entryId,
                        onToggle: () => setState(() => _expandedId =
                            _expandedId == entry.entryId ? null : entry.entryId),
                      ),
                    ),
                ],
              );
            },
          ),
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
                  '${_entries.length} plugins · Host Loader inventory via pluginInventory/list (read-only).',
                  style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.entry,
    required this.aliases,
    required this.expanded,
    required this.onToggle,
  });

  final _Entry entry;
  final DswAliases aliases;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final String title = _shortName(entry.moduleName);
    final String status = _phaseLabel(entry.fiberPhase);
    final String configTag = entry.enabled ? 'Enabled' : 'Disabled';
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
                  const SizedBox(width: DswTokens.spaceSm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.enabled)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _phaseColor(entry.fiberPhase, aliases),
                            shape: BoxShape.circle,
                          ),
                        ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: entry.enabled ? aliases.stateSuccessTertiary : aliases.bgOverlay,
                          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                        ),
                        child: Text(
                          configTag,
                          style: TextStyle(
                            fontSize: 11,
                            color: entry.enabled ? aliases.stateSuccessPrimary : aliases.labelTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: DswTokens.transitionDurationFast,
                        child: Icon(Icons.keyboard_arrow_down, size: 12, color: aliases.labelTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: aliases.borderL1)),
              ),
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    entry.entryId,
                    style: TextStyle(fontSize: 11, color: aliases.labelSecondary, fontFamily: 'SF Mono'),
                  ),
                  const SizedBox(height: DswTokens.spaceMd),
                  _DetailRow(label: 'Configuration', value: configTag, aliases: aliases),
                  if (entry.enabled) ...[
                    const SizedBox(height: DswTokens.spaceSm),
                    _DetailRow(label: 'Cordis status', value: status, aliases: aliases),
                  ],
                  const SizedBox(height: DswTokens.spaceSm),
                  _DetailRow(label: 'Module', value: entry.moduleName, aliases: aliases, mono: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, required this.aliases, this.mono = false});
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
            child: Text(label, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary)),
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
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: aliases.bgLayer2,
          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
          border: Border.all(color: aliases.borderL2),
        ),
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        child: Center(
          child: Text(label, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelCaption)),
        ),
      );
}
