import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/bootstrap/app_plugins.dart' show activeSlotsProvider;
import '../core/connection/connection_client.dart';
import '../core/renderer/slot_outlet.dart';
import '../core/slots/slot_registry.dart';
import '../core/session/session_models.dart';
import '../core/session/sessions_controller.dart';
import '../core/session/host_session_policy.dart'
    show adoptHostBornSession, isWorkspaceAttachFailure;
import '../features/layout/layout_controller.dart';
import '../features/settings/settings_screen.dart';
import '../features/trajectory/trajectory_screen.dart' as trajectory_feature;
import '../plugins/conversation/ui/conversation_screen.dart' as conversation_feature;
import '../plugins/conversation/ui/slots/hole_outlet.dart';
import '../features/goal/goal_screen.dart' as goal_feature;
import '../features/jobs/jobs_screen.dart' as jobs_feature;
import '../features/commands/commands_screen.dart' as commands_feature;
import '../features/input_trigger/input_trigger_screen.dart' as input_trigger_feature;
import '../features/reference/reference_screen.dart' as reference_feature;
import '../plugins/subagent/ui/subagent_screen.dart' as subagent_feature;
import '../features/workspace/workspace_provider.dart'
    show selectedWorkspaceProvider;
import '../features/workflow_run/workflow_screen.dart' as workflow_feature;
import '../theme/app_theme.dart';
import '../widgets/layout/app_frame.dart';
import '../widgets/primitives/fish_logo.dart';

/// Welcome / empty state when no current session is selected.
///
/// The plugin-shell hero phase of the conversation surface (React
/// ConversationRoot hero): fish headline (`conversation.hero.brand.mark`,
/// FishLogo fallback) + the real workspace picker seat
/// (`conversation.hero.workspace` → [WorkspacePickerChip] portal with the
/// add-workspace directory flow) + a caption. There are NO composer controls
/// here: with no session there is nothing to submit into (React renders the
/// bar inert as the picker trigger); picking a workspace creates the session
/// and navigates to its blank-session hero where the live composer mounts.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // React `selectWorkspace`: picking a hero workspace opens that
    // workspace's blank session. The chip publishes the pick through the
    // shared selection state; this screen completes it host-side.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.listenManual<WorkspaceId?>(selectedWorkspaceProvider,
          (WorkspaceId? prev, WorkspaceId? next) {
        if (next != null && next != prev) _createSessionIn(next);
      });
    });
  }

  Future<void> _createSessionIn(WorkspaceId workspaceId) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final ConnectionClient client = ref.read(connectionClientProvider);
      SessionId newId;
      try {
        newId = await client.createSession(workspaceId: workspaceId.value);
      } catch (e) {
        if (isWorkspaceAttachFailure(e)) {
          newId = await client.createSession();
        } else {
          rethrow;
        }
      }
      // Project the host-born session before the confirming list pull lands
      // (host_session_policy.dart); setAll immediately confirms it.
      final List<SessionSummary> sessions = await client.getSessions();
      ref.read(sessionsProvider.notifier).addSession(adoptHostBornSession(newId));
      ref.read(sessionsProvider.notifier).setAll(sessions);
      ref.read(sessionsProvider.notifier).setCurrent(newId);
      if (mounted && context.mounted) context.go('/sessions/${newId.value}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
            (Theme.of(context).brightness == Brightness.dark
                ? DswTokens.darkAliases
                : DswTokens.lightAliases);
    final SlotRegistry slots =
        ref.watch(activeSlotsProvider) ?? SlotRegistry();

    return Scaffold(
      backgroundColor: aliases.bgBase,
      body: Stack(
        children: [
          // Glow backdrop — figma 313:14109 ellipse blurred (HeroGlow).
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 720,
                  height: 320,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [const Color(0x146187D8), const Color(0x006187D8)],
                      center: Alignment.center,
                      radius: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Headline row: fish mark slot leading title + badge
                    // (HeroShell.tsx headline composition).
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      children: [
                        HoleOutlet(
                          registry: slots,
                          slotKey: 'conversation.hero.brand.mark',
                          fallback: const DsFishLogo(size: 34),
                        ),
                        Text('Into the Unknown',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: aliases.labelPrimary, letterSpacing: -0.3)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: aliases.stateBusinessTertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: aliases.stateBusinessPrimary.withValues(alpha: 0.18)),
                          ),
                          child: Text('Preview',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: aliases.stateBusinessPrimary, letterSpacing: 0.2)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    // Workspace row: the REAL picker seat. Its portal owns the
                    // list + add-directory flow; picking lands in
                    // selectedWorkspaceProvider and starts the session above.
                    HoleOutlet(registry: slots, slotKey: 'conversation.hero.workspace'),
                    const SizedBox(height: 20),
                    Text('Choose a workspace to start',
                        style: TextStyle(fontSize: 12, color: aliases.labelTertiary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Global router provider.
///
/// Uses `StatefulShellRoute.indexedStack` for [AppFrame] shell mounted at
/// root (no per-route AppFrame), with session scoping via `:sessionId` param
/// + [sessionByIdProvider]. Mirrors web `root → sidebar|conversation|details|shell.overlay`
/// slot graph as a GoRouter shell tree.
///
/// Routes:
/// - `/` -> redirect to `/sessions/:sid` if current exists else welcome
/// - `/sessions/:sid` (conversation)
/// - `/sessions/:sid/trajectory`
/// - `/settings`
/// Ledger handed to the router once the host activates; null before boot
/// (the sidebar hole renders its fallback).
final _nullRegistry = SlotRegistry();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell navigationShell) {
          return AppFrame(
            navigationShell: navigationShell,
            // Conversation hub renders through its own composition slot on
            // top of the shell's center occupant.
            conversationLayer: SlotOutlet(
              registry: ref.watch(activeSlotsProvider) ?? _nullRegistry,
              slotKey: 'layout.center',
            ),
            // Sidebar arrives through the composition slot (ui-sidebar plugin
            // registers `layout.sidebar`); the router holds no feature import.
            sidebar: SlotOutlet(
              registry: ref.watch(activeSlotsProvider) ?? _nullRegistry,
              slotKey: 'layout.sidebar',
              fallback: (_) => const SizedBox.shrink(),
            ),
            // Details track: no occupant exists in the Dart runtime yet, and
            // React renders the strict details entry EMPTY when there is
            // nothing to show (AppFrame.tsx:188-191) while the store boots
            // closed (`details: 0`, stores.ts:50). The frame therefore keeps
            // a zero-width collapsed track — no placeholder panel.
            details: null,
          );
        },
        branches: [
          // Branch 0: welcome + sessions (center occupant).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (BuildContext context, GoRouterState state) => const WelcomeScreen(),
                redirect: (BuildContext context, GoRouterState state) {
                  // Redirect to current session if one exists.
                  final sessions = ref.read(sessionsProvider);
                  final current = sessions.current;
                  if (current != null) {
                    return '/sessions/${current.value}';
                  }
                  return null;
                },
              ),
              GoRoute(
                path: '/sessions/:sid',
                builder: (BuildContext context, GoRouterState state) {
                  final sid = state.pathParameters['sid']!;
                  return conversation_feature.ConversationScreen(sessionId: sid);
                },
                routes: [
                  GoRoute(
                    path: 'trajectory',
                    builder: (BuildContext context, GoRouterState state) {
                      final sid = state.pathParameters['sid']!;
                      return trajectory_feature.TrajectoryScreen(sessionId: sid);
                    },
                  ),
                  GoRoute(
                    path: 'goal',
                    builder: (BuildContext context, GoRouterState state) {
                      final sid = state.pathParameters['sid']!;
                      return goal_feature.GoalScreen(sessionId: sid);
                    },
                  ),
                  GoRoute(
                    path: 'jobs',
                    builder: (BuildContext context, GoRouterState state) {
                      final sid = state.pathParameters['sid']!;
                      return jobs_feature.JobsScreen(sessionId: sid);
                    },
                  ),
                  GoRoute(
                    path: 'commands',
                    builder: (BuildContext context, GoRouterState state) => const commands_feature.CommandsScreen(),
                  ),
                  GoRoute(
                    path: 'input-trigger',
                    builder: (BuildContext context, GoRouterState state) => const input_trigger_feature.InputTriggerScreen(),
                  ),
                  GoRoute(
                    path: 'references',
                    builder: (BuildContext context, GoRouterState state) => const reference_feature.ReferenceScreen(),
                  ),
                  GoRoute(
                    path: 'subagents',
                    builder: (BuildContext context, GoRouterState state) {
                      final sid = state.pathParameters['sid']!;
                      return subagent_feature.SubagentScreen(sessionId: sid);
                    },
                  ),
                  GoRoute(
                    path: 'workflows',
                    builder: (BuildContext context, GoRouterState state) {
                      final sid = state.pathParameters['sid']!;
                      return workflow_feature.WorkflowScreen(sessionId: sid);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: settings (keeps shell mounted, switches indexed stack).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

