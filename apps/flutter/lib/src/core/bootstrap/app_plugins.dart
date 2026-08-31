/// Application bootstrap over the plugin host: core services are provided
/// under React service names, and the shell registers the one `'root'`
/// occupant. Feature screens stay exactly where they are this increment;
/// only ownership of the boot path moves to [PluginHost].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plugin/plugin_contract.dart';
import '../plugin/plugin_host.dart';
import '../../routing/app_router.dart';
import '../../theme/app_theme.dart';
import '../../theme/appearance.dart';
import '../../theme/theme_runtime.dart';
import '../../widgets/primitives/connection_banner.dart';
import '../connection/connection_client.dart' as conn;
import '../connection/connection_target_provider.dart';
import '../connection/connection_lifecycle.dart';
import '../connection/connectivity_handler.dart';
import '../renderer/slot_outlet.dart' show SlotComponentProps;
import '../session/live_sync.dart';
import '../session/sessions_controller.dart';
import '../session/session_models.dart';
import '../../features/sidebar/sidebar.dart';
import '../../features/devices/selection_restore.dart';
import '../settings/settings_scope.dart';
import '../services/runtime_services.dart' hide RemoteEventBus;
import '../slots/slot_registry.dart';
import '../../features/locale/locale_preference.dart';
import '../../plugins/conversation/conversation_plugin.dart';
import '../../plugins/subagent/subagent_link.dart';
import '../../plugins/plan/plan_control.dart';
import '../../plugins/tool/tool_plugin.dart';
import '../../plugins/trajectory/trajectory_plugin.dart';
import '../../plugins/message_feedback/message_feedback_plugin.dart';
import '../../plugins/subagent/subagent_plugin.dart';
import '../../plugins/skill/skill_plugin.dart';
import '../../plugins/agent_preset/agent_preset_plugin.dart';
import '../../plugins/plan/plan_plugin.dart';
// WS-Input: composer pipeline (trigger registry → commands/reference
// sources; question carrier).
import '../../plugins/input_trigger/input_trigger_plugin.dart';
import '../../plugins/commands/command_plugin.dart';
import '../../plugins/reference/reference_plugin.dart';
import '../../plugins/user_questions/user_questions_plugin.dart';
// WS-Surfaces: model seat, workspace, attachment, pickers, brand, settings
// children.
import '../../plugins/model_selection/model_selection_plugin.dart';
import '../../plugins/workspace/workspace_plugin.dart';
import '../../plugins/attachment/attachment_plugin.dart';
import '../../plugins/directory_picker/directory_picker_plugin.dart';
import '../../plugins/brand_official/brand_official_plugin.dart';
import '../../plugins/settings/children/general/general_settings_plugin.dart';
import '../../plugins/settings/children/models/models_settings_plugin.dart';
import '../../plugins/settings/children/plugins/plugins_settings_plugin.dart';
import '../../plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart';
// WS-Tasks: jobs / workflow runs / deliverables / goal / permission presets.
import '../../plugins/jobs/jobs_plugin.dart';
import '../../plugins/workflow_run/workflow_run_plugin.dart';
import '../../plugins/deliverables/deliverables_plugin.dart';
import '../../plugins/goal/goal_plugin.dart';
import '../../plugins/permission_presets/permission_presets_plugin.dart';

/// Ref-bound carrier handles future plugins consume instead of reaching into
/// Riverpod globals. Typed ISessions/IWorkspaces faces arrive with their P0
/// runtime rows; today this carries what the shell needs.
class ShellServices {
  /// Wraps the container's ref.
  ShellServices(this.ref);

  /// The provider scope's ref.
  final WidgetRef ref;

  /// Connection state reader.
  conn.ConnectionState get connectionState =>
      ref.read(conn.connectionStateProvider);

  /// The typed host RPC client (the `'connection'` service face).
  conn.ConnectionClient get connection =>
      ref.read(conn.connectionClientProvider);

  /// Theme mode reader.
  ThemeMode get themeMode => ref.read(themeModeProvider);
}

/// Provides `'runtime'` ([ShellServices]) — the standing service later plugins
/// inject, named like its React counterpart. The `'slots'` service is provided
/// by [buildAppHost] directly from the host's ledger.
class CoreServicesPlugin extends DshPlugin {
  /// Creates the plugin bound to the widget-tree ref.
  CoreServicesPlugin(this.services);

  /// The ref-bound handles.
  final ShellServices services;

  @override
  String get id => '@core/runtime';

  @override
  Future<void> apply(DshContext ctx) async {
    final client = ctx.require<conn.ConnectionClient>('connection');
    ctx.provide('runtime', services);
    ctx.provide('sessions', SessionsService(client));
    ctx.provide('workspaces', WorkspacesService(client));
    // One shared LocaleService: the Language row's publish path, the boot
    // adoption below, and every plugin dictionary consumer see the same
    // registry through [localeServiceProvider].
    final LocaleService locale = services.ref.read(localeServiceProvider);
    ctx.provide('locale', locale);
    ctx.provide('remote', services.ref.read(remoteBusProvider));
    // Boot adoption of the durable preference (React adopts the Host scope at
    // construction); unawaited like the other boot-time loads.
    unawaited(adoptPersistedLocale(client, locale));
  }
}

/// The ui-layout analog: owns root's single cell and renders the material app
/// shell (router, theme, connection banner). This is the only 'root' registrant.
class AppShellPlugin extends DshPlugin {
  @override
  String get id => '@app/shell';

  @override
  Future<void> apply(DshContext ctx) async {
    ctx.onDispose(
      ctx.slots.register(
        const RegistrationOptions(
          name: 'root',
          children: {
            'layout.sidebar': SlotSpec(
              kind: SlotKind.single,
              scope: SlotScope.root,
            ),
            // Conversation hub anchor: filled by ui-conversation's
            // wait-and-follow contribution once its subtree is declared.
            'layout.center': SlotSpec(
              kind: SlotKind.single,
              scope: SlotScope.root,
            ),
          },
        ),
        _buildRoot,
      ),
    );
  }
}

Widget _buildRoot(BuildContext context, SlotComponentProps props) => Consumer(
  builder: (context, ref, _) {
    // Restore the persisted connection target before the live pumps read
    // `connectionTargetProvider`, so a paired RemoteTarget reconnects on
    // app restart instead of the first handshake racing against prefs.
    ref.watch(connectionTargetBootstrapProvider);
    // Hydrate sessions from host on app start (same-origin via proxy at 8080).
    // In widget tests Uri.base is file://, bootstrap no-ops and stays empty.
    ref.watch(sessionBootstrapProvider);
    // Validate persisted workspace/session selections against host data
    // and reapply them to the single selection state system. No-op when
    // nothing was persisted (default local desktop/web).
    ref.watch(selectionRestoreProvider);
    // Live SSE pump: host.describe + mux/host streams with backoff. No-ops in
    // vm tests or when no host is configured.
    ref.watch(conn.connectionBootstrapProvider);
    // Live session/event sync: mux: session/event → messageList invalidation,
    // host: session-status / workspace → sessionsProvider.
    ref.watch(liveSyncProvider);
    // Mobile lifecycle: paused → suspend sockets, resumed → fresh generation
    // + host.describe + ticket + resync (mobile RemoteTarget only; desktop/Web no-op).
    ref.watch(connectionLifecycleProvider);
    // Network recovery: wifi/cellular after none → fresh generation where needed.
    ref.watch(connectivityLifecycleProvider);
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    // UI language: the shared LocaleService's active id mapped onto a
    // Flutter Locale, so MaterialApp rebuilds Localizations (and every
    // `Localizations.localeOf` consumer) together with the bound
    // dictionary consumers on one locale switch.
    final uiLocale = ref.watch(materialLocaleProvider);
    // Live carrier visibility: surface connecting/reconnecting/disconnected
    // so a silent stream loss is never mistaken for a quiet backend.
    final conn.ConnectionState connectionState = ref.watch(
      conn.connectionStateProvider,
    );
    return AppLifecycleObserver(
      child: MaterialApp.router(
        title: 'DeepSeek Harness',
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: themeMode,
        locale: uiLocale,
        // The shipped locale ids (React LOCALE_IDS); without them Flutter's
        // resolution falls back to en_US and Localizations.localeOf never
        // reports zh. The global delegates make Material's own strings
        // (tooltips, menus) follow the switch; product copy stays on the
        // LocaleService dictionaries.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        builder: (BuildContext context, Widget? child) {
          final bool showBanner =
              connectionState == conn.ConnectionState.connecting ||
              connectionState == conn.ConnectionState.reconnecting ||
              connectionState == conn.ConnectionState.disconnected;
          return Stack(
            children: [
              if (child != null) child,
              if (showBanner)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: DsConnectionBanner(state: connectionState),
                ),
            ],
          );
        },
      ),
    );
  },
);

/// The ui-theme analog: provides the `'theme'` service ([ThemeRuntime])
/// bridged to the appearance controller. Its settings-row contribution
/// (AppearanceRow into the General section) lands with the ui-settings
/// subtree via `slots.inject`, matching the React registration shape.
class ThemePlugin extends DshPlugin {
  @override
  String get id => 'ui-theme';

  @override
  List<String> get inject => ['runtime'];

  @override
  Future<void> apply(DshContext ctx) async {
    final runtime = ctx
        .require<ShellServices>('runtime')
        .ref
        .read(themeRuntimeProvider);
    ctx.provide('theme', runtime);
  }
}

/// The composition ledger handed to non-plugin consumers (the router's
/// `layout.sidebar` outlet). Null until [DshApp] finishes activation.
final activeSlotsProvider = StateProvider<SlotRegistry?>((ref) => null);

/// The ui-sidebar plugin: registers the sidebar column into the frame's
/// declared hole instead of being imported by the router.
class SidebarPlugin extends DshPlugin {
  @override
  String get id => 'ui-sidebar';

  @override
  List<String> get inject => ['slots', 'runtime'];

  @override
  Future<void> apply(DshContext ctx) async {
    final services = ctx.require<ShellServices>('runtime');
    ctx.onDispose(
      ctx.slots.register(
        const RegistrationOptions(
          name: 'layout.sidebar',
          children: {
            'sidebar.workspaces': SlotSpec(
              kind: SlotKind.single,
              scope: SlotScope.root,
            ),
          },
        ),
        (BuildContext context, SlotComponentProps props) => const Sidebar(),
      ),
    );
    services.ref.read(activeSlotsProvider.notifier).state = ctx.slots;
  }
}

/// The ui-settings base plugin: provides `'settingsScope'` — the per-
/// namespace settings face over `settings.describe`/`settings.mutate` — and
/// persists the theme preference into the `ui-theme` namespace exactly like
/// the React Appearance flow (namespace `ui-theme`, field `preference`).
class SettingsPlugin extends DshPlugin {
  @override
  String get id => 'ui-settings';

  @override
  List<String> get inject => ['connection', 'runtime'];

  @override
  Future<void> apply(DshContext ctx) async {
    final services = ctx.require<ShellServices>('runtime');
    final client = services.ref.read(conn.connectionClientProvider);
    final scope = SettingsScope<Object?>(
      face: SettingsRpcFace(client),
      namespace: 'ui-theme',
    );
    ctx.provide('settingsScope', scope);

    // Load the durable preference once connected; failures leave the default.
    unawaited(
      scope.refreshFromDescribe().then((_) {
        final value = scope.snapshot.value;
        if (scope.snapshot.status == SettingsScopeStatus.ready &&
            value is Map) {
          final preference = value['preference'];
          if (preference is String) {
            switch (preference) {
              case 'light':
                services.ref
                    .read(appearanceProvider.notifier)
                    .setTheme(AppThemePreference.light);
              case 'dark':
                services.ref
                    .read(appearanceProvider.notifier)
                    .setTheme(AppThemePreference.dark);
              case 'system':
                services.ref
                    .read(appearanceProvider.notifier)
                    .setTheme(AppThemePreference.system);
            }
          }
        }
      }),
    );
  }
}

/// Builds the application host with the boot-time plugin set registered but
/// not yet activated; callers run [PluginHost.activateAll] before first frame.
PluginHost buildAppHost(WidgetRef ref) {
  final host = PluginHost();
  host.provide('slots', host.slots);
  // Carrier service: provided at host level so every consumer shares one
  // client (mirrors ctx.connection from the React connection plugin).
  host.provide('connection', ref.read(conn.connectionClientProvider));
  host.register(CoreServicesPlugin(ShellServices(ref)));
  host.register(ThemePlugin());
  host.register(SettingsPlugin());
  host.register(ConversationPlugin());
  // Shell declares the holes; sidebar fills one — declaration precedes
  // contribution, mirroring the React children-authorization order.
  host.register(AppShellPlugin());
  host.register(SidebarPlugin());
  // Business-plugin workstreams (WS-Chat / WS-Agent) — chat-node renderers
  // and hub-hole contributions; activation order is service-wait resolved.
  host.register(ToolPlugin());
  host.register(TrajectoryPlugin());
  host.register(MessageFeedbackPlugin());
  host.register(
    SubagentPlugin(
      link: SubagentLink(
        selectSession: (id) =>
            ref.read(sessionsProvider.notifier).setCurrent(id),
        refreshParent: (_) async {
          final client = ref.read(conn.connectionClientProvider);
          final sessions = await client.getSessions();
          ref.read(sessionsProvider.notifier).setAll(sessions);
        },
      ),
    ),
  );
  host.register(SkillPlugin());
  host.register(AgentPresetPlugin());
  // The command channel closes over the container-scoped client resolved
  // once at boot; a per-execute `ref.read` would die with whatever widget
  // mounted the boot probe.
  final conn.ConnectionClient commandChannelClient = ref.read(
    conn.connectionClientProvider,
  );
  host.register(
    PlanPlugin(
      planControl: PlanControl(
        execute: (sessionId, line) async {
          // Canonical plan path is `remote.commands.execute` (not the
          // user-prompt `session.prompt` path). Mirrors React
          // `ctx.remote.commands.execute(sessionId, '/plan off', [])` and the
          // `plan/mode` folding contract (committed/queued/cancelled/noop).
          try {
            final value = await commandChannelClient.callMethod(
              'commands/execute',
              {
                'agentId': sessionId,
                'line': line,
                'images': [],
              },
            );
            // Host returns {commandId, result:{kind,text}} on success; a missing
            // handler would have thrown and be caught below.
            final result = value['result'];
            if (result is Map && result['kind'] == 'error') {
              return CommandOutcome(
                ok: false,
                errorCode: 'command-error',
                errorMessage: result['text'] as String? ?? 'command failed',
              );
            }
            return const CommandOutcome(ok: true, hasValue: true);
          } catch (e) {
            return CommandOutcome(
              ok: false,
              errorCode: 'command-error',
              errorMessage: e.toString(),
            );
          }
        },
      ),
    ),
  );
  // WS-Input — composer pipeline. InputTriggerPlugin provides
  // 'inputTriggers'; Commands/Reference declare it as their sequencing edge,
  // so the fixpoint orders them regardless of registration position.
  host.register(const InputTriggerPlugin());
  host.register(const CommandsPlugin());
  host.register(ReferencePlugin());
  host.register(const UserQuestionsPlugin());
  // WS-Surfaces — model seat, workspace, attachment, pickers (browse then
  // native: the native face binds last and wins on desktop), brand chrome,
  // settings children.
  host.register(const ModelSelectionPlugin());
  host.register(const WorkspacePlugin());
  host.register(const AttachmentPlugin());
  host.register(const BrowseDirectoryPickerPlugin());
  host.register(const NativeDirectoryPickerPlugin());
  host.register(const BrandOfficialPlugin());
  host
    ..register(const GeneralSettingsPlugin())
    ..register(const ModelsSettingsPlugin())
    ..register(const PluginsSettingsPlugin())
    ..register(const PluginInventoryPlugin());
  // WS-Tasks — jobs / workflow runs / deliverables / goal / permission
  // presets.
  host.register(const JobsPlugin());
  host.register(const WorkflowRunPlugin());
  host.register(const DeliverablesPlugin());
  host.register(const GoalPlugin());
  host.register(const PermissionPresetsPlugin());
  return host;
}
