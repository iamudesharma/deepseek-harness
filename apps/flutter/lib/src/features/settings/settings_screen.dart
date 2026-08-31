import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../core/session/sessions_controller.dart';
import '../../platform/adaptive_directory_picker.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primitives/ds_select.dart';
import '../model_selection/model_directory.dart';
import '../settings_general/widgets/appearance_row.dart';
import '../settings_general/widgets/language_row.dart';
import '../settings_models/settings_models_screen.dart';
import '../../plugins/settings/children/general/general_settings_plugin.dart'
    show kSettingsNamespace;
import '../../plugins/settings/children/models/models_settings_plugin.dart'
    show kModelsNamespace;
import '../../plugins/settings/children/plugins/plugins_settings_plugin.dart'
    show kPluginsNamespace;
import '../../plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart'
    show kInventoryNamespace;
import '../../plugins/conversation/locales.dart' show kConversationNamespace;

/// Settings language preference (stub, mirrors web `Appearance` language row).
enum AppLanguage { system, english, chinese }

/// Provider for app language (stub persistence).
final appLanguageProvider = StateProvider<AppLanguage>(
  (ref) => AppLanguage.system,
);

/// Provider for notifications toggle (stub).
final notificationsEnabledProvider = StateProvider<bool>((ref) => true);

/// Provider for selected model in settings.
final settingsSelectedModelProvider = StateProvider<String?>((ref) => null);

/// Provider for the workspace directory path picked via [AdaptiveDirectoryPicker].
///
/// Persisted via `SharedPreferences` in a real integration; here kept as
/// in-memory state with provider override support for tests.
final workspaceDirectoryProvider = StateProvider<String?>((ref) => null);

/// Busy-state Enter behavior — mirrors `BusyEnterBehavior` in
/// `packages/client/ui-conversation/src/client/contract/composer-submission.ts`
/// (`queue` = queue the message, `steer` = steer the running turn).
enum BusyEnterBehavior { queue, steer }

/// State for the busy Enter preference row.
class BusyEnterState {
  const BusyEnterState({
    this.behavior = BusyEnterBehavior.queue,
    this.loading = false,
    this.error,
    this.revision = -1,
  });
  final BusyEnterBehavior behavior;
  final bool loading;
  final String? error;
  final int revision;
  BusyEnterState copyWith({
    BusyEnterBehavior? behavior,
    bool? loading,
    String? error,
    int? revision,
  }) => BusyEnterState(
    behavior: behavior ?? this.behavior,
    loading: loading ?? this.loading,
    error: error,
    revision: revision ?? this.revision,
  );
}

/// Controller for busy Enter — mirrors `EnterBehaviorRowInjected` store.
///
/// Loads via `settings.describe` ns `conversation` and mutates via
/// `settings.mutate` with revision guard, matching React's
/// `createLanguageRowStore` / `ConversationSettings` pattern.
class BusyEnterController extends Notifier<BusyEnterState> {
  @override
  BusyEnterState build() => const BusyEnterState();

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final describe = await client.settingsDescribe();
      final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? convNs;
      for (final ns in namespaces) {
        if (ns['ns'] == 'conversation') {
          convNs = ns;
          break;
        }
      }
      final value = convNs?['value'] as Map<String, dynamic>?;
      final raw = value?['busyEnter'] as String?;
      final behavior = raw == 'steer'
          ? BusyEnterBehavior.steer
          : BusyEnterBehavior.queue;
      final revision = convNs?['revision'] as int? ?? 0;
      if (revision <= state.revision) {
        state = state.copyWith(loading: false);
        return;
      }
      state = BusyEnterState(
        behavior: behavior,
        revision: revision,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<String?> setBusyEnter(BusyEnterBehavior next) async {
    final prev = state;
    state = state.copyWith(behavior: next, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final describe = await client.settingsDescribe();
      final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? convNs;
      for (final ns in namespaces) {
        if (ns['ns'] == 'conversation') {
          convNs = ns;
          break;
        }
      }
      final expectedRevision = convNs?['revision'] as int?;
      await client.settingsMutate(
        ns: 'conversation',
        ops: [
          {
            'op': 'set',
            'path': ['busyEnter'],
            'value': next.name,
          },
        ],
        expectedRevision: expectedRevision,
      );
      await load();
      return null;
    } catch (e) {
      state = prev.copyWith(error: e.toString());
      return e.toString();
    }
  }
}

final busyEnterProvider = NotifierProvider<BusyEnterController, BusyEnterState>(
  BusyEnterController.new,
);

/// Settings screen — four tabs: General, Models, Plugins, Inventory.
///
/// Uses [TabBar] + [TabBarView] with [DefaultTabController] (length 4).
/// General tab wires to [appearanceProvider] for theme, [appLanguageProvider]
/// for language row, and a notification toggle. Models tab shows model
/// selection form. Plugins and Inventory are placeholder lists.
///
/// Handles empty/loading states via local stub data; uses [Theme] and
/// [DswTokens] throughout. [ConsumerWidget] for Riverpod integration.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    // Each tab label resolves in the namespace owned by the settings child
    // plugin that registers it (React: every section owns its copy).
    final Translate ts = ref.bindLocale(kSettingsNamespace);
    final Translate tm = ref.bindLocale(kModelsNamespace);
    final Translate tp = ref.bindLocale(kPluginsNamespace);
    final Translate ti = ref.bindLocale(kInventoryNamespace);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            ts('title'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeL20,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: aliases.labelPrimary,
                unselectedLabelColor: aliases.labelTertiary,
                indicatorColor: aliases.stateBusinessPrimary,
                indicatorWeight: 2,
                labelStyle: const TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w400,
                ),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.tune, size: 16),
                    text: ts('general.nav'),
                  ),
                  Tab(
                    icon: const Icon(Icons.memory, size: 16),
                    text: tm('nav'),
                  ),
                  Tab(
                    icon: const Icon(Icons.extension_outlined, size: 16),
                    text: tp('nav'),
                  ),
                  Tab(
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                    text: ti('nav'),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _GeneralTab(aliases: aliases),
            const SettingsModelsScreen(),
            _PluginsTab(aliases: aliases),
            _InventoryTab(aliases: aliases),
          ],
        ),
      ),
    );
  }
}

/// General tab — language + appearance wired to Host settings document.
///
/// Language uses [LanguageRow] (Dropdown via DsSelect, options from locale,
/// calls `settings.mutate` ns `locale`). Appearance uses [AppearanceRow]
/// (cube SegmentedButton-style via `appearanceRowProvider` + global
/// `appearanceProvider` + [DswTokens] radiusMd / interactiveBgHover), both
/// with revision-guarded stores mirroring `createLanguageRowStore` /
/// `createAppearanceRowStore` slot inject contract (`--dsw-` tokens).
class _GeneralTab extends ConsumerWidget {
  const _GeneralTab({required this.aliases});

  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool notifications = ref.watch(notificationsEnabledProvider);
    final Translate ts = ref.bindLocale(kSettingsNamespace);

    return ListView(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      children: [
        _SectionHeader(title: ts('general.nav'), aliases: aliases),
        const SizedBox(height: 4),
        Text(
          ts('general.title'),
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelTertiary,
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(
          aliases: aliases,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [LanguageRow(), AppearanceRow()],
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(aliases: aliases, child: _EnterBehaviorRow()),
        // Note: EnterBehaviorRow could also live inside the same card as Language/Appearance
        // to match React's single GeneralSection column, but keeping separate card
        // preserves the existing Flutter card visual hierarchy and avoids const constraints.
        const SizedBox(height: DswTokens.spaceLg),
        _SectionHeader(title: ts('section.notifications'), aliases: aliases),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(
          aliases: aliases,
          child: _SettingsRow(
            icon: Icons.notifications_outlined,
            title: ts('notifications.enable'),
            subtitle: ts('notifications.enableDesc'),
            aliases: aliases,
            trailing: Switch(
              value: notifications,
              activeThumbColor: aliases.stateBusinessPrimary,
              onChanged: (bool v) =>
                  ref.read(notificationsEnabledProvider.notifier).state = v,
            ),
          ),
        ),
        const SizedBox(height: DswTokens.spaceLg),
        _SectionHeader(title: ts('section.workspace'), aliases: aliases),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(
          aliases: aliases,
          child: AdaptiveDirectoryPicker(
            label: ts('workspace.directory'),
            value: ref.watch(workspaceDirectoryProvider),
            dialogTitle: ts('workspace.selectFolder'),
            onPicked: (String? path) {
              ref.read(workspaceDirectoryProvider.notifier).state = path;
            },
          ),
        ),
        const SizedBox(height: DswTokens.spaceLg),
        _SectionHeader(title: ts('section.about'), aliases: aliases),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(
          aliases: aliases,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DeepSeek Harness',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: aliases.bgOverlay,
                      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                    ),
                    child: Text(
                      'v1.0.0',
                      style: TextStyle(
                        fontSize: 11,
                        color: aliases.labelCaption,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ts('about.tagline'),
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Theme · Language · Notifications are wired to Riverpod providers and persist via overrides for tests.',
                style: TextStyle(fontSize: 11, color: aliases.labelCaption),
              ),
            ],
          ),
        ),
        const SizedBox(height: DswTokens.spaceXl),
      ],
    );
  }
}

/// Enter-behavior row — mirrors `EnterBehaviorRow.tsx` (queue vs steer).
///
/// Uses `DsSelect` (MenuAnchor) with `BusyEnterBehavior` options, wired to
/// `busyEnterProvider` → `settings.mutate` ns `conversation`. Loaded via
/// `busyEnterProvider.notifier.load()` on first build, matching React's
/// `useBusyEnter` hook + `setBusyEnter` injection.
class _EnterBehaviorRow extends ConsumerStatefulWidget {
  const _EnterBehaviorRow();

  @override
  ConsumerState<_EnterBehaviorRow> createState() => _EnterBehaviorRowState();
}

class _EnterBehaviorRowState extends ConsumerState<_EnterBehaviorRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(busyEnterProvider);
      if (s.revision == -1 && !s.loading)
        ref.read(busyEnterProvider.notifier).load();
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
    final BusyEnterState st = ref.watch(busyEnterProvider);
    final BusyEnterController ctrl = ref.read(busyEnterProvider.notifier);
    final Translate tc = ref.bindLocale(kConversationNamespace);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: aliases.borderL1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tc('settings.enter.title'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w500,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tc('settings.enter.description'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelTertiary,
                  ),
                ),
                if (st.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    st.error!,
                    style: TextStyle(
                      fontSize: 11,
                      color: aliases.stateErrorPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Flexible + maxWidth mirrors the React selector pill: DsSelect's
          // root Column stretches, so it needs bounded width — a bare Row
          // child gets unbounded width and crashes at layout.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: DsSelect(
                value: st.behavior.name,
                placeholder: st.loading ? tc('loading') : tc('select'),
                options: [
                  for (final b in BusyEnterBehavior.values)
                    DsSelectOption(
                      value: b.name,
                      label: b == BusyEnterBehavior.queue
                          ? tc('settings.enter.queue')
                          : tc('settings.enter.steer'),
                    ),
                ],
                onChanged: (String next) async {
                  final beh = BusyEnterBehavior.values.firstWhere(
                    (e) => e.name == next,
                    orElse: () => BusyEnterBehavior.queue,
                  );
                  final err = await ctrl.setBusyEnter(beh);
                  if (!mounted) return;
                  if (err != null) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(err),
                        backgroundColor: aliases.stateErrorPrimary,
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Models tab — live model selection via per-session ModelDirectory.
///
/// Mirrors web's model directory wire: watches [modelDirectoryProvider]
/// keyed by first session id (or "settings" placeholder) and derives
/// `availableModels` + `currentModel`. Dropdown and list select via
/// `dir.select(ModelSelection(provider, model))` with provider lookup
/// `groups.firstWhere((g) => g.models.any((m) => m.id == v)).id`.
/// Handles loading/error via [ModelDirectoryState.status].
// ignore: unused_element
class _ModelsTab extends ConsumerWidget {
  const _ModelsTab({required this.aliases});

  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionsState sessionsState = ref.watch(sessionsProvider);
    final sorted = sessionsState.sorted;
    final String sessionId = sorted.isNotEmpty
        ? sorted.first.sessionId.value
        : 'settings';
    final ModelDirectoryState dirState = ref.watch(
      modelDirectoryProvider(sessionId),
    );
    final ModelDirectory dir = ref.read(
      modelDirectoryProvider(sessionId).notifier,
    );

    final List<String> availableModels = dirState.groups
        .expand((g) => g.models.map((m) => m.id))
        .toList();
    final String? currentModel = dirState.current?.model;

    String findProviderForModel(String modelId) {
      for (final ModelProviderGroup g in dirState.groups) {
        if (g.models.any((m) => m.id == modelId)) return g.id;
      }
      return dirState.groups.isNotEmpty
          ? dirState.groups.first.id
          : 'deepseek-official';
    }

    final bool deepSeekConnected = dirState.groups.any(
      (g) => g.id == 'deepseek-official' || g.id == 'deepseek',
    );
    final bool localConnected = dirState.groups.any(
      (g) => g.id == 'local' || g.id.toLowerCase().contains('local'),
    );

    final bool noSessions = sorted.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      children: [
        _SectionHeader(title: 'Model selection', aliases: aliases),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(
          aliases: aliases,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default model',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Used for new sessions when no preset overrides it.',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelSecondary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceMd),
              DropdownButtonFormField<String>(
                initialValue: currentModel,
                hint: Text(
                  'Select a model',
                  style: TextStyle(color: aliases.labelCaption),
                ),
                decoration: InputDecoration(
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
                ),
                dropdownColor: aliases.specificMenu,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  color: aliases.labelPrimary,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('System default'),
                  ),
                  for (final String m in availableModels)
                    DropdownMenuItem<String>(
                      value: m,
                      child: Row(
                        children: [
                          Icon(
                            Icons.memory,
                            size: 14,
                            color: aliases.labelTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(m),
                        ],
                      ),
                    ),
                ],
                onChanged: (String? next) async {
                  if (next == null) return;
                  final String provider = findProviderForModel(next);
                  try {
                    await ref
                        .read(modelDirectoryProvider(sessionId).notifier)
                        .select(
                          ModelSelection(provider: provider, model: next),
                        );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Model select failed: $e')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: DswTokens.spaceSm),
              Text(
                currentModel == null
                    ? 'Using system default model.'
                    : 'Selected: $currentModel',
                style: TextStyle(fontSize: 11, color: aliases.labelCaption),
              ),
            ],
          ),
        ),
        const SizedBox(height: DswTokens.spaceLg),
        _SectionHeader(title: 'Available models', aliases: aliases),
        const SizedBox(height: DswTokens.spaceMd),
        if (noSessions)
          _EmptyListHint(
            label: 'No sessions — no models available',
            aliases: aliases,
          )
        else if (dirState.status == 'loading')
          Padding(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            child: Center(
              child: CircularProgressIndicator(
                color: aliases.stateBusinessPrimary,
              ),
            ),
          )
        else if (dirState.status == 'error')
          _CardShell(
            aliases: aliases,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dirState.error ?? 'Failed to load models',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.stateErrorPrimary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                TextButton(
                  onPressed: () => dir.load(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else ...[
          for (final ModelInfo m in dirState.groups.expand((g) => g.models))
            Padding(
              padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
              child: _CardShell(
                aliases: aliases,
                child: _SettingsRow(
                  icon: Icons.smart_toy_outlined,
                  title: m.id,
                  subtitle:
                      m.description ??
                      (m.id == 'deepseek-chat'
                          ? 'General chat — balanced latency and quality.'
                          : 'Reasoning — extended chain-of-thought.'),
                  aliases: aliases,
                  trailing: currentModel == m.id
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: aliases.stateSuccessTertiary,
                            borderRadius: BorderRadius.circular(
                              DswTokens.radiusFull,
                            ),
                          ),
                          child: Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: aliases.stateSuccessPrimary,
                            ),
                          ),
                        )
                      : TextButton(
                          onPressed: () async {
                            final String provider = findProviderForModel(m.id);
                            try {
                              await ref
                                  .read(
                                    modelDirectoryProvider(sessionId).notifier,
                                  )
                                  .select(
                                    ModelSelection(
                                      provider: provider,
                                      model: m.id,
                                    ),
                                  );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Model select failed: $e'),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Select'),
                        ),
                ),
              ),
            ),
          if (dirState.groups.expand((g) => g.models).isEmpty)
            _EmptyListHint(label: 'No models configured', aliases: aliases),
        ],
        const SizedBox(height: DswTokens.spaceLg),
        _SectionHeader(title: 'Provider status', aliases: aliases),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(
          aliases: aliases,
          child: Column(
            children: [
              _ProviderStatusRow(
                name: 'DeepSeek API',
                status: deepSeekConnected ? 'Connected' : 'Not configured',
                healthy: deepSeekConnected,
                aliases: aliases,
              ),
              Divider(height: DswTokens.spaceLg, color: aliases.borderL1),
              _ProviderStatusRow(
                name: 'Local provider',
                status: localConnected ? 'Connected' : 'Not configured',
                healthy: localConnected,
                aliases: aliases,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Plugins tab — plugin list with enable / disable toggles.
class _PluginsTab extends ConsumerWidget {
  const _PluginsTab({required this.aliases});

  final DswAliases aliases;

  static const List<_PluginInfo> _plugins = [
    _PluginInfo(
      id: 'shell',
      name: 'Shell',
      description: 'Bash capability + local/pwsh providers.',
      enabled: true,
    ),
    _PluginInfo(
      id: 'fs',
      name: 'Filesystem',
      description: 'FS capability + policy enforcement.',
      enabled: true,
    ),
    _PluginInfo(
      id: 'lsp',
      name: 'Language Server',
      description: 'LSP capability for code intelligence.',
      enabled: true,
    ),
    _PluginInfo(
      id: 'web',
      name: 'Web',
      description: 'Web search + fetch providers.',
      enabled: true,
    ),
    _PluginInfo(
      id: 'skill',
      name: 'Skill',
      description: 'Skill registry + local loader.',
      enabled: false,
    ),
    _PluginInfo(
      id: 'e2b',
      name: 'E2B Sandbox',
      description: 'Sandbox + FS/subprocess adapters (POC).',
      enabled: false,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      children: [
        _SectionHeader(title: 'Plugins', aliases: aliases),
        const SizedBox(height: 4),
        Text(
          '${_plugins.where((p) => p.enabled).length} of ${_plugins.length} enabled — toggles are local stubs.',
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelCaption,
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        for (final plugin in _plugins)
          Padding(
            padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
            child: _PluginCard(plugin: plugin, aliases: aliases),
          ),
        const SizedBox(height: DswTokens.spaceLg),
        _CardShell(
          aliases: aliases,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: aliases.labelTertiary),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Text(
                  'Plugins are contributed via ctx.effect / cordis.yml. Toggle states here are UI-only and do not mutate the runtime.',
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

/// Inventory tab — skill / tool inventory placeholder table.
class _InventoryTab extends ConsumerWidget {
  const _InventoryTab({required this.aliases});

  final DswAliases aliases;

  static const List<_InventoryItem> _items = [
    _InventoryItem(
      name: 'ReadFile',
      kind: 'Tool',
      provider: 'fs/local',
      status: 'Available',
    ),
    _InventoryItem(
      name: 'Bash',
      kind: 'Tool',
      provider: 'shell/local',
      status: 'Available',
    ),
    _InventoryItem(
      name: 'WebFetch',
      kind: 'Tool',
      provider: 'web/fetch',
      status: 'Available',
    ),
    _InventoryItem(
      name: 'Plan',
      kind: 'Skill',
      provider: 'skill/local',
      status: 'Installed',
    ),
    _InventoryItem(
      name: 'Trajectory',
      kind: 'Capability',
      provider: 'compaction/basic',
      status: 'Available',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      children: [
        _SectionHeader(title: 'Inventory', aliases: aliases),
        const SizedBox(height: DswTokens.spaceMd),
        _CardShell(
          aliases: aliases,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Table header.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DswTokens.spaceSm,
                  vertical: DswTokens.spaceSm,
                ),
                decoration: BoxDecoration(
                  color: aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Name',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Kind',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Provider',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        'Status',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DswTokens.spaceSm),
              for (final item in _items) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DswTokens.spaceSm,
                    vertical: DswTokens.spaceSm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Icon(
                              _iconForKind(item.kind),
                              size: 14,
                              color: aliases.labelTertiary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: DswTokens.fontSizeS14,
                                  color: aliases.labelPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.kind,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: aliases.labelSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.provider,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: aliases.labelSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: item.status == 'Available'
                                  ? aliases.stateSuccessTertiary
                                  : aliases.bgOverlay,
                              borderRadius: BorderRadius.circular(
                                DswTokens.radiusFull,
                              ),
                            ),
                            child: Text(
                              item.status,
                              style: TextStyle(
                                fontSize: 11,
                                color: item.status == 'Available'
                                    ? aliases.stateSuccessPrimary
                                    : aliases.labelTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (item != _items.last)
                  Divider(height: 1, color: aliases.borderL1),
              ],
              if (_items.isEmpty)
                _EmptyListHint(label: 'Inventory empty', aliases: aliases),
            ],
          ),
        ),
        const SizedBox(height: DswTokens.spaceLg),
        _CardShell(
          aliases: aliases,
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
                  '${_items.length} items · Tools, skills, and capabilities contributed by installed plugins.',
                  style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconForKind(String kind) => switch (kind) {
    'Tool' => Icons.build_outlined,
    'Skill' => Icons.auto_awesome_outlined,
    'Capability' => Icons.extension_outlined,
    _ => Icons.category_outlined,
  };
}

// Shared primitives.

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.aliases});

  final String title;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: DswTokens.fontSizeS14,
        fontWeight: FontWeight.w600,
        color: aliases.labelPrimary,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.aliases, required this.child});

  final DswAliases aliases;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
        boxShadow: DswTokens.shadowLv1,
      ),
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      child: child,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.aliases,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DswAliases aliases;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: aliases.bgOverlay,
            borderRadius: BorderRadius.circular(DswTokens.radiusSm),
          ),
          child: Icon(icon, size: 16, color: aliases.labelSecondary),
        ),
        const SizedBox(width: DswTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w500,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: DswTokens.spaceMd),
        trailing,
      ],
    );
  }
}

class _ProviderStatusRow extends StatelessWidget {
  const _ProviderStatusRow({
    required this.name,
    required this.status,
    required this.healthy,
    required this.aliases,
  });

  final String name;
  final String status;
  final bool healthy;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: healthy ? aliases.stateSuccessPrimary : aliases.labelCaption,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: DswTokens.spaceSm),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              color: aliases.labelPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: healthy ? aliases.stateSuccessTertiary : aliases.bgOverlay,
            borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: healthy
                  ? aliases.stateSuccessPrimary
                  : aliases.labelTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PluginCard extends StatefulWidget {
  const _PluginCard({required this.plugin, required this.aliases});

  final _PluginInfo plugin;
  final DswAliases aliases;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.plugin.enabled;
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      aliases: widget.aliases,
      child: Row(
        children: [
          Icon(
            _enabled ? Icons.extension : Icons.extension_outlined,
            size: 18,
            color: _enabled
                ? widget.aliases.stateBusinessPrimary
                : widget.aliases.labelCaption,
          ),
          const SizedBox(width: DswTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.plugin.name,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: widget.aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.plugin.description,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: widget.aliases.labelSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'id: ${widget.plugin.id}',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.aliases.labelCaption,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            activeThumbColor: widget.aliases.stateBusinessPrimary,
            onChanged: (bool v) => setState(() => _enabled = v),
          ),
        ],
      ),
    );
  }
}

class _EmptyListHint extends StatelessWidget {
  const _EmptyListHint({required this.label, required this.aliases});

  final String label;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelCaption,
          ),
        ),
      ),
    );
  }
}

class _PluginInfo {
  const _PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
  });

  final String id;
  final String name;
  final String description;
  final bool enabled;
}

class _InventoryItem {
  const _InventoryItem({
    required this.name,
    required this.kind,
    required this.provider,
    required this.status,
  });

  final String name;
  final String kind;
  final String provider;
  final String status;
}
