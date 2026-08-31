/// Trajectory Plugin — Flutter port of the `ui-trajectory` package boundary
/// (`packages/client/ui-trajectory/src/client/index.ts`): one entry in the
/// conversation view slot, no service of its own.
///
/// React injects `conversationEvents`/`conversationViews` (the runtime object
/// layer feeding the timeline fold); no Dart services carry those yet, so the
/// entry renders the provider-backed screen and the ledger contribution stays
/// queued until a shell declares `conversation.view` — the same
/// wait-and-follow posture the hub uses for `layout.center`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plugin/plugin_contract.dart';
import '../../core/renderer/slot_outlet.dart' show SlotComponentProps;
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import '../../core/session/session_provider.dart';
import 'ui/trajectory_screen.dart';

/// The `ui-trajectory` plugin.
class TrajectoryPlugin extends DshPlugin {
  @override
  String get id => 'ui-trajectory';

  @override
  List<String> get inject => ['slots', 'sessions'];

  @override
  Future<void> apply(DshContext ctx) async {
    ctx.require<SessionsService>('sessions');

    // Contribution waits for the conversation-owned view hole, installs
    // atomically, and leaves with this plugin (slot effect contract).
    final stopInject = ctx.slots.inject('conversation.view', () {
      final dispose = ctx.slots.register(
        const RegistrationOptions(
          name: 'conversation.view',
          id: 'trajectory',
          order: 10,
        ),
        _trajectoryViewEntry,
      );
      return [dispose];
    });
    ctx.onDispose(stopInject);
  }
}

Widget _trajectoryViewEntry(BuildContext context, SlotComponentProps props) =>
    const _TrajectoryViewEntry();

/// Session-scoped entry: the outlet's props carry no session share, so the
/// view reads the selected session until the outlet passes one explicitly.
class _TrajectoryViewEntry extends ConsumerWidget {
  const _TrajectoryViewEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = ref.watch(currentSessionIdProvider);
    if (sessionId == null) return const SizedBox.shrink();
    return TrajectoryScreen(sessionId: sessionId);
  }
}
