import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models — mirrors `PluginInventoryEntry` + `SettingsNamespaceView` + tab-store
// ---------------------------------------------------------------------------

/// One configurable plugin entry shown as a card — mirrors
/// `ConfigurablePluginsTab` dispatch keyed by namespace plus
/// `PluginCard` shell contract.
class PluginCardView {
  const PluginCardView({
    required this.id,
    required this.name,
    required this.description,
    required this.settingsNs,
    required this.settingsPath,
    required this.enabled,
    required this.phase,
    required this.available,
    required this.writable,
  });

  final String id;
  final String name;
  final String description;
  final String settingsNs;
  final List<String> settingsPath;
  final bool enabled;
  final String phase;
  final bool available;
  final bool writable;
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

/// Known plugin descriptions — mirrors `locales.ts` plugin card copy
/// (bashTitle/description, agentLoopTitle etc) plus shell/fs fallbacks.
String _descriptionFor(String ns, String moduleName) {
  switch (ns) {
    case 'shell':
      return 'Limits every command the agent runs.';
    case 'agent-loop':
      return 'How the agent dispatches tool calls.';
    case 'web-search-deepseek':
      return 'The DeepSeek search provider.';
    case 'locale':
      return 'Interface language preference.';
    case 'ui-theme':
      return 'Appearance preference (light / dark / system).';
    case 'agent-presets':
      return 'Per-session agent composition.';
    default:
      if (moduleName.contains('fs'))
        return 'Filesystem capability + policy enforcement.';
      if (moduleName.contains('lsp'))
        return 'Language Server capability for code intelligence.';
      if (moduleName.contains('skill')) return 'Skill registry + local loader.';
      if (moduleName.contains('e2b'))
        return 'Sandbox + FS/subprocess adapters (POC).';
      if (moduleName.contains('compaction'))
        return 'Context compaction capability.';
      return 'Plugin settings namespace `$ns`.';
  }
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

enum PluginsSettingsStatus { idle, loading, ready, error }

class PluginsSettingsState {
  const PluginsSettingsState({
    this.status = PluginsSettingsStatus.idle,
    this.error,
    this.writable = false,
    this.cards = const [],
  });

  final PluginsSettingsStatus status;
  final String? error;
  final bool writable;
  final List<PluginCardView> cards;

  PluginsSettingsState copyWith({
    PluginsSettingsStatus? status,
    String? error,
    bool? writable,
    List<PluginCardView>? cards,
  }) => PluginsSettingsState(
    status: status ?? this.status,
    error: error,
    writable: writable ?? this.writable,
    cards: cards ?? this.cards,
  );
}

class PluginsSettingsController extends Notifier<PluginsSettingsState> {
  @override
  PluginsSettingsState build() => const PluginsSettingsState();

  Future<void> load() async {
    state = state.copyWith(status: PluginsSettingsStatus.loading, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final results = await Future.wait([
        client.settingsDescribe(),
        client.pluginInventoryList(),
      ]);
      // ignore: unnecessary_cast
      final describe = results[0] as Map<String, dynamic>;
      // ignore: unnecessary_cast
      final inventory = results[1] as Map<String, dynamic>;

      final writable = describe['writable'] as bool? ?? false;
      final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final entries = (inventory['entries'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

      final nsSet = <String>{
        for (final n in namespaces) n['ns'] as String? ?? '',
      };

      // Build cards from inventory entries; mark available if its ns is served.
      // For entries without a direct ns match, fall back to moduleName-derived id.
      final cards = <PluginCardView>[];
      for (final e in entries) {
        final entryId = e['entryId'] as String? ?? '';
        final moduleName = e['moduleName'] as String? ?? entryId;
        final short = _shortName(moduleName);
        // Heuristic: map module short to settings ns (e.g. 'shell' -> 'shell', 'agent-loop' -> 'agent-loop')
        // If no entry matches nsSet, still show but as unavailable (renders nothing in React — here we show disabled placeholder)
        String matchedNs = '';
        for (final ns in nsSet) {
          final normNs = ns.replaceAll('-', '').toLowerCase();
          final normShort = short.replaceAll('-', '').toLowerCase();
          if (normNs == normShort ||
              short.toLowerCase() == ns.toLowerCase() ||
              moduleName.toLowerCase().contains(ns.toLowerCase())) {
            matchedNs = ns;
            break;
          }
        }
        // Fallback: use entryId as ns for host-plane cards that expose no settings
        final displayNs = matchedNs.isEmpty ? entryId : matchedNs;
        final enabled = e['enabled'] as bool? ?? true;
        final phase = e['fiberPhase'] as String?;
        cards.add(
          PluginCardView(
            id: entryId.isEmpty ? short : entryId,
            name: short.isEmpty ? entryId : short,
            description: _descriptionFor(displayNs, moduleName),
            settingsNs: displayNs,
            settingsPath: displayNs.isEmpty ? const [] : [displayNs],
            enabled: enabled,
            phase: _phaseLabel(phase),
            available: matchedNs.isNotEmpty || nsSet.contains(displayNs),
            writable: writable,
          ),
        );
      }

      // Also include namespaces that have no inventory entry (pure settings plugins)
      for (final ns in namespaces) {
        final nsStr = ns['ns'] as String? ?? '';
        if (nsStr.isEmpty) continue;
        if (cards.any((c) => c.settingsNs == nsStr)) continue;
        cards.add(
          PluginCardView(
            id: nsStr,
            name: nsStr,
            description: _descriptionFor(nsStr, nsStr),
            settingsNs: nsStr,
            settingsPath: [nsStr],
            enabled: true,
            phase: 'Active',
            available: true,
            writable: writable,
          ),
        );
      }

      state = PluginsSettingsState(
        status: PluginsSettingsStatus.ready,
        writable: writable,
        cards: cards,
      );
    } catch (e) {
      state = state.copyWith(
        status: PluginsSettingsStatus.error,
        error: e.toString(),
      );
    }
  }
}

final pluginsSettingsControllerProvider =
    NotifierProvider<PluginsSettingsController, PluginsSettingsState>(
      PluginsSettingsController.new,
    );

// ---------------------------------------------------------------------------
// Widget — mirrors `ConfigurablePluginsTab.tsx` + `PluginCard.tsx`
// ---------------------------------------------------------------------------

/// SettingsPluginsScreen — port of `ConfigurablePluginsTab` + `PluginCard`.
///
/// Enumerates settings namespaces via `settings.describe` but never
/// interprets one — a card arrives keyed by the namespace it edits, so a
/// plugin that ships a browser half owns its own card and this tab only
/// decides which keys to dispatch. Mirrors tab-store filtering: served
/// namespaces intersect registered `settings.plugin.item` entries; here the
/// inventory loader provides the entry ledger.
///
/// Each card header follows `PluginCard.module.css`: flex row with name over
/// description, pending badge when dirty, chevron, enable toggle Switch,
/// settingsPath code, and phase tag. Typert wired via
/// [ConnectionClient.settingsDescribe] + [ConnectionClient.pluginInventoryList]
/// + [ConnectionClient.settingsMutate] (future toggle writes).
class SettingsPluginsScreen extends ConsumerStatefulWidget {
  const SettingsPluginsScreen({super.key});

  @override
  ConsumerState<SettingsPluginsScreen> createState() =>
      _SettingsPluginsScreenState();
}

class _SettingsPluginsScreenState extends ConsumerState<SettingsPluginsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(pluginsSettingsControllerProvider).status ==
          PluginsSettingsStatus.idle) {
        ref.read(pluginsSettingsControllerProvider.notifier).load();
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
    final state = ref.watch(pluginsSettingsControllerProvider);
    final controller = ref.read(pluginsSettingsControllerProvider.notifier);

    if (state.status == PluginsSettingsStatus.error) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Loading plugin configuration failed: ${state.error}',
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
            ],
          ),
        ),
      );
    }

    if (state.status == PluginsSettingsStatus.loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Ready — card list or empty line (mirrors `loaded ? <p empty> : null`)
    if (state.cards.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: Text(
            'This deployment exposes no plugin settings.',
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelTertiary,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          Text(
            'Plugins',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure and inspect the plugins installed in this deployment.',
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelTertiary,
            ),
          ),
          const SizedBox(height: DswTokens.spaceMd),
          for (final card in state.cards)
            Padding(
              padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
              child: _PluginCard(card: card, aliases: aliases),
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
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: aliases.labelTertiary,
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Text(
                    '${state.cards.length} plugin cards · Enable toggles reflect Host Loader enabled; '
                    'settingsPath shows the settings namespace each card edits.',
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

/// One plugin's card: header naming the plugin and what its settings govern,
/// disclosing controls in place, with enable Switch.
///
/// The header is its own button rather than a shared disclosure row because a
/// card stacks its name over its description, while that row lays the two
/// side by side — the layout, not the behavior, is what differs. Disclosure
/// is card-local state. Mirrors `PluginCard.tsx` CSS variables:
/// `radiusLg` 12, `borderL2`, `bgLayer2`, `interactiveBgHover`, chevron 14.
class _PluginCard extends StatefulWidget {
  const _PluginCard({required this.card, required this.aliases});

  final PluginCardView card;
  final DswAliases aliases;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  bool _open = false;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.card.enabled;
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final aliases = widget.aliases;
    // Unavailable cards render nothing in React; here we dim rather than hide so inventory stays visible.
    final double opacity = card.available ? 1 : 0.6;

    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: aliases.bgLayer2,
          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
          border: Border.all(color: aliases.borderL2),
          boxShadow: DswTokens.shadowLv1,
        ),
        child: Column(
          children: [
            // Header button
            InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(DswTokens.radiusLg),
              hoverColor: aliases.interactiveBgHover,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DswTokens.spaceLg,
                  vertical: DswTokens.spaceMd,
                ),
                child: Row(
                  children: [
                    Icon(
                      _enabled ? Icons.extension : Icons.extension_outlined,
                      size: 18,
                      color: _enabled
                          ? aliases.stateBusinessPrimary
                          : aliases.labelCaption,
                    ),
                    const SizedBox(width: DswTokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.name,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              fontWeight: FontWeight.w600,
                              color: aliases.labelPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card.description,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: aliases.bgOverlay,
                                  borderRadius: BorderRadius.circular(
                                    DswTokens.radiusFull,
                                  ),
                                ),
                                child: Text(
                                  'ns: ${card.settingsNs}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: aliases.labelCaption,
                                    fontFamily: 'SF Mono',
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
                                  color: card.writable
                                      ? aliases.stateSuccessTertiary
                                      : aliases.bgOverlay,
                                  borderRadius: BorderRadius.circular(
                                    DswTokens.radiusFull,
                                  ),
                                ),
                                child: Text(
                                  card.writable ? 'Writable' : 'Read-only',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: card.writable
                                        ? aliases.stateSuccessPrimary
                                        : aliases.labelCaption,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DswTokens.spaceSm),
                    Switch(
                      value: _enabled,
                      activeThumbColor: aliases.stateBusinessPrimary,
                      onChanged: card.available
                          ? (bool v) {
                              setState(() => _enabled = v);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    v
                                        ? '${card.name} enabled (local)'
                                        : '${card.name} disabled (local)',
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          : null,
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: DswTokens.transitionDurationFast,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: aliases.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: aliases.borderL1)),
                ),
                padding: const EdgeInsets.all(DswTokens.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!card.writable)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: DswTokens.spaceMd,
                        ),
                        child: Text(
                          'This deployment stores settings read-only.',
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: aliases.stateWarnLabel,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Settings path',
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelTertiary,
                            ),
                          ),
                        ),
                        Text(
                          card.settingsPath.join(' › '),
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: aliases.labelPrimary,
                            fontFamily: 'SF Mono',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DswTokens.spaceSm),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cordis phase',
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelTertiary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: card.phase == 'Active'
                                ? aliases.stateSuccessTertiary
                                : aliases.bgOverlay,
                            borderRadius: BorderRadius.circular(
                              DswTokens.radiusFull,
                            ),
                          ),
                          child: Text(
                            card.phase,
                            style: TextStyle(
                              fontSize: 11,
                              color: card.phase == 'Active'
                                  ? aliases.stateSuccessPrimary
                                  : aliases.labelTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DswTokens.spaceMd),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Plugin cards are contributed via settings.plugin.item slot; enable state comes from Loader inventory.',
                        style: TextStyle(
                          fontSize: 11,
                          color: aliases.labelCaption,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
