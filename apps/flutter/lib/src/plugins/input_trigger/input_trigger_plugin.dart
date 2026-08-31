/// The `ui-input-trigger` plugin — Flutter port of
/// `packages/client/ui-input-trigger/src/client/index.ts` `apply()`.
///
/// Mounts the [TriggerSourceRegistry] as the `'inputTriggers'` service and
/// registers the candidate menu into `conversation.input.overlay` (id
/// `slash-menu`, order 0 — under ui-commands' popupSelect at 20), exactly
/// like React: MenuView rides the composer's overlay anchor, which floats
/// entries above the composer card. The declared-but-unoccupied
/// `conversation.input.left` / `right` tool-row seats stay empty here too.
library;

import 'package:flutter/widgets.dart';

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'input_trigger_service.dart';
import 'ui/input_menu_anchor.dart';

/// Plugin identity.
const String kInputTriggerPluginId = 'ui-input-trigger';

/// Service name the registry is published under (React `ctx.inputTriggers`).
const String kInputTriggersServiceName = 'inputTriggers';

/// List entry id of the overlay menu anchor (React registration id
/// `slash-menu`).
const String kInputMenuOverlayId = 'slash-menu';

/// The `ui-input-trigger` plugin.
class InputTriggerPlugin extends DshPlugin {
  /// Creates the plugin.
  const InputTriggerPlugin();

  @override
  String get id => kInputTriggerPluginId;

  @override
  List<String> get inject => ['slots', 'sessions'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge: the roster reads session identity,
    // and the seats render under the conversation hub's slot tree.
    ctx.require<SessionsService>('sessions');

    final registry = TriggerSourceRegistry();
    ctx.provide(kInputTriggersServiceName, registry);
    bindActivatedRegistry(registry);
    ctx.onDispose(() {
      bindActivatedRegistry(null);
      registry.disposeAllControllers();
    });

    // The candidate menu waits for the conversation-owned overlay hole,
    // installs atomically, and leaves with this plugin (the ui-commands
    // popupSelect entry shares the anchor; list order refines by `order`).
    final stopOverlay = ctx.slots.inject('conversation.input.overlay', () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: 'conversation.input.overlay',
            id: kInputMenuOverlayId,
            order: 0,
            registrant: kInputTriggerPluginId,
          ),
          (context, props) => const _Seat(),
        ),
      ];
    });
    ctx.onDispose(stopOverlay);
  }
}

class _Seat extends StatelessWidget {
  const _Seat();

  @override
  Widget build(BuildContext context) {
    if (activatedRegistry == null) return const SizedBox.shrink();
    return const InputMenuAnchor();
  }
}
