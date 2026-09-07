/// The `ui-plan` plugin — Flutter port of
/// `packages/client/ui-plan/src/client/index.ts` `apply()`.
///
/// React registers the chip on the `conversation.input.plan` seat
/// (ui-plan index.ts:52-53), which ui-conversation renders inside the
/// composer tool row between the access control and the left items
/// (InputBar.tsx:713). The Dart conversation hub declares that same hole,
/// so the chip mounts through [DshContext.slots.inject] and renders nothing
/// while the effective target is off — the unoccupied seat's visual
/// contract. Exit execution rides the constructor-injected command channel
/// ([PlanControl]) because no `remote.commands` service exists yet; the
/// control is provided as the `'plan'` service and bound for UI providers
/// via [bindPlanControl].
library;

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'locales.dart';
import 'plan_control.dart';
import 'ui/plan_chip_dock.dart';

/// Slot key the plan chip occupies (React `conversation.input.plan`).
const String kPlanSeatSlot = 'conversation.input.plan';

/// Seat entry id.
const String kPlanSeatId = 'plan';

/// Service name the control is published under.
const String kPlanServiceName = 'plan';

/// Plugin identity.
const String kPlanPluginId = 'ui-plan';

/// The `ui-plan` plugin.
class PlanPlugin extends DshPlugin {
  /// Creates the plugin over the `/plan off` execution channel.
  const PlanPlugin({required PlanControl planControl}) : _control = planControl;

  final PlanControl _control;

  @override
  String get id => kPlanPluginId;

  @override
  List<String> get inject => ['slots', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge.
    final LocaleService locale = ctx.require<LocaleService>('locale');

    ctx.provide(kPlanServiceName, _control);
    bindPlanControl(_control);

    ctx.onDispose(
      locale.register(kPlanNamespace, {
        'zh': {...kPlanZh, ...kPlanScreenZh},
        'en': {...kPlanEn, ...kPlanScreenEn},
      }),
    );

    // Composer tool-row seat: the chip self-hides while the effective target
    // is off. Waits for the conversation-owned declaration, installs
    // atomically, and leaves with this plugin.
    final stopSeat = ctx.slots.inject(kPlanSeatSlot, () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: kPlanSeatSlot,
            id: kPlanSeatId,
            registrant: kPlanPluginId,
          ),
          (context, props) => buildPlanSeat(),
        ),
      ];
    });
    ctx.onDispose(() {
      bindPlanControl(null);
      stopSeat();
    });
  }
}
