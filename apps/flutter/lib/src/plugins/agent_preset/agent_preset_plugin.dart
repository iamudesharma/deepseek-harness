/// The `ui-agent-preset` plugin — Flutter port of
/// `packages/client/ui-agent-preset/src/client/index.ts` `apply()`.
///
/// Registered here: the `settings.agentPreset` dictionaries, the read-only
/// header label (`conversation.session.header.actions`, id `agent-preset`,
/// order -10 — React index.ts:170-177), and the new-session hero chip
/// (`conversation.hero.agentPreset` — React index.ts:165-169, rendered in
/// ConversationRoot's hero workspace row at ConversationRoot.tsx:122). Both
/// seats stay inside their owning surfaces: the label rides the 44px header
/// row, the chip only exists on the blank-session hero. The General
/// settings row and management section need the `settings.general.item` /
/// `settings.section` holes, which no Dart plugin declares yet; their
/// presentation lives in `ui/agent_preset_screen.dart` and registers when
/// those shells land. A bare register into an undeclared slot would fail
/// loud by design.
library;

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'locales.dart';
import 'ui/agent_preset_hero_seat.dart';
import 'ui/agent_preset_label.dart';

/// Header list entry id (React `id: 'agent-preset'`).
const String kAgentPresetHeaderId = 'agent-preset';

/// Plugin identity.
const String kAgentPresetPluginId = 'ui-agent-preset';

/// The `ui-agent-preset` plugin.
class AgentPresetPlugin extends DshPlugin {
  /// Creates the plugin.
  const AgentPresetPlugin();

  @override
  String get id => kAgentPresetPluginId;

  @override
  List<String> get inject => ['slots', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final LocaleService locale = ctx.require<LocaleService>('locale');

    ctx.onDispose(
      locale.register(kAgentPresetNamespace, {
        'zh': kAgentPresetZh,
        'en': kAgentPresetEn,
      }),
    );

    // Both conversation surfaces install atomically and leave with this
    // plugin: the read-only header label and the new-session hero chip
    // (React index.ts:165-177 registers the same pair in one effect).
    final stopLabel = ctx.slots.inject(
      'conversation.session.header.actions',
      () {
        return [
          ctx.slots.register(
            const RegistrationOptions(
              name: 'conversation.session.header.actions',
              id: kAgentPresetHeaderId,
              order: -10,
            ),
            (context, props) => const AgentPresetHeaderLabel(),
          ),
        ];
      },
    );
    final stopSeat = ctx.slots.inject('conversation.hero.agentPreset', () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: 'conversation.hero.agentPreset',
            registrant: kAgentPresetPluginId,
          ),
          (context, props) => const AgentPresetHeroSeat(),
        ),
      ];
    });
    ctx.onDispose(() {
      stopSeat();
      stopLabel();
    });
  }
}
