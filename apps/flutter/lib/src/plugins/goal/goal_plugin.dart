/// The `ui-goal` plugin — Flutter port of
/// `packages/client/ui-goal/src/client/index.ts` `apply()`.
///
/// Registrations, in React order: the `goal` locale dictionaries, the keyed
/// `command-input` chat-node renderer (the `/goal` input bubble), and the
/// goal strip dock entry (id `goal`, the `conversation.input.dock` analog)
/// carrying the four mutation verbs. Goal creation stays on the `/goal`
/// host command; this plugin only mutates.
///
/// Seam notes: the live goal value arrives through the bound
/// [GoalProjectionSource] (`useProjection('goal')` stand-in — no Dart
/// projection store exists yet, so unwired boots render nothing), and the
/// verbs carry exact wire methods over [ConnectionClient.callMethod] because
/// no typed `remote.goals` face exists yet.
library;

import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../conversation/hub.dart' show ConversationController;
import 'goal_control.dart';
import 'goal_projection.dart';
import 'locales.dart';
import 'ui/goal_command_input_view.dart';
import 'ui/goal_dock.dart';

/// Plugin identity.
const String kGoalPluginId = 'ui-goal';

/// Composer dock id the goal strip occupies.
const String kGoalDockId = 'goal';

/// Chat-node key this package claims (the human `/goal` command input).
const String kGoalCommandInputNodeKey = 'command-input';

/// Service name the mutation-verb control is published under.
const String kGoalServiceName = 'goal';

/// The `ui-goal` plugin.
class GoalPlugin extends DshPlugin {
  /// Creates the plugin over the projection source that stands in for the
  /// `useProjection('goal')` seat; null keeps every verb on the
  /// `no-current-goal` short-circuit until a store lands.
  const GoalPlugin({this.projectionSource});

  /// The projection read bound at activation.
  final GoalProjectionSource? projectionSource;

  @override
  String get id => kGoalPluginId;

  @override
  List<String> get inject => ['slots', 'connection', 'locale', 'conversation'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge. React also declares 'sessions'
    // (its projection face rides the session binding); the Dart projection
    // read arrives through the constructor-bound source instead, so the edge
    // is pinned type-only until that face exists.
    ctx.require<SessionsService>('sessions');
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    final LocaleService locale = ctx.require<LocaleService>('locale');
    final ConversationController controller = ctx
        .require<ConversationController>('conversation');

    final control = GoalControl(
      client: client,
      projectionSource: projectionSource,
    );
    ctx.provide(kGoalServiceName, control);
    bindGoalControl(control);
    if (projectionSource != null) {
      bindGoalProjectionSource(projectionSource);
    }

    ctx.onDispose(
      locale.register(kGoalNamespace, {'zh': kGoalZh, 'en': kGoalEn}),
    );

    // Keyed chat-node renderer for the `/goal` command input. The registry
    // exposes registration only — no removal — so this contribution lives
    // until host teardown.
    controller.renderers.register(
      kGoalCommandInputNodeKey,
      renderGoalCommandInput,
    );

    // Goal strip in the composer dock band; leaves with this plugin.
    final removeDock = controller.registerDock(kGoalDockId, buildGoalDock);
    ctx.onDispose(() {
      removeDock();
      bindGoalControl(null);
      if (identical(boundGoalProjectionSource, projectionSource)) {
        bindGoalProjectionSource(null);
      }
    });
  }
}
