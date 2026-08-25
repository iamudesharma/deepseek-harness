import 'package:dsh_flutter/src/core/plugin/plugin_contract.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/agent_preset/agent_preset_plugin.dart';
import 'package:dsh_flutter/src/plugins/conversation/conversation_plugin.dart';
import 'package:dsh_flutter/src/plugins/plan/plan_control.dart';
import 'package:dsh_flutter/src/plugins/plan/plan_plugin.dart';
import 'package:dsh_flutter/src/plugins/skill/skill_plugin.dart';
import 'package:dsh_flutter/src/plugins/subagent/subagent_link.dart';
import 'package:dsh_flutter/src/plugins/subagent/subagent_plugin.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

/// Declares `root`'s layout.center hole so the conversation anchor's
/// wait-and-follow contribution installs its child slots (header actions
/// among them) during activation.
class _LayoutShell extends DshPlugin {
  @override
  String get id => '@test/layout';

  @override
  Future<void> apply(DshContext ctx) async {
    ctx.onDispose(
      ctx.slots.register(
        const RegistrationOptions(
          name: 'root',
          children: {
            'layout.center': SlotSpec(kind: SlotKind.single, scope: SlotScope.root),
          },
        ),
        (context, props) => const SizedBox.shrink(),
      ),
    );
  }
}

void main() {
  test('four WS plugins cohabit with ui-conversation on one booted host', () async {
    // The real ConversationPlugin provides 'conversation' itself, so the
    // fixture must not pre-provide it.
    final host = wsAgentHost(withConversation: false);
    addTearDown(host.deactivateAll);

    host.register(_LayoutShell());
    host.register(ConversationPlugin());
    host.register(SubagentPlugin(
      link: SubagentLink(selectSession: (_) {}, refreshParent: (_) async {}),
    ));
    host.register(const SkillPlugin());
    host.register(const AgentPresetPlugin());
    host.register(PlanPlugin(
      planControl: PlanControl(
        execute: (_, _) async => const CommandOutcome(ok: true, hasValue: true),
      ),
    ));

    await host.activateAll();

    // Conversation declared its subtree once layout.center existed.
    expect(host.slots.isDeclared('conversation'), isTrue);
    expect(host.slots.isDeclared('conversation.session.header.actions'), isTrue);

    // Header band ordering: static preset label leads, catalog action trails.
    final headerWinners =
        host.slots.winnersOfSlot('conversation.session.header.actions');
    expect(
      [for (final w in headerWinners) w.options.id],
      [kAgentPresetHeaderId, kSubagentCatalogId],
    );

    // Keyed chat-node seam carries both dependents.
    final controller = host.service<ConversationController>('conversation')!;
    expect(controller.renderers.keys, containsAll(['subagent', kSkillNodeKey]));

    // Plan chip occupies the composer tool-row seat.
    expect(host.slots.isDeclared(kPlanSeatSlot), isTrue);
    expect(
      [for (final w in host.slots.winnersOfSlot(kPlanSeatSlot)) w.options.id],
      contains(kPlanSeatId),
    );
  });

  test('deactivating one plugin leaves the others installed', () async {
    final host = wsAgentHost();
    addTearDown(host.deactivateAll);

    declareHeaderActionsHole(host);
    host.register(SubagentPlugin(
      link: SubagentLink(selectSession: (_) {}, refreshParent: (_) async {}),
    ));
    host.register(const AgentPresetPlugin());
    await host.activateAll();

    host.deactivate(kSubagentPluginId);

    final ids =
        [for (final w in host.slots.winnersOfSlot('conversation.session.header.actions')) w.options.id];
    expect(ids, [kAgentPresetHeaderId]);
    expect(host.hasService('subagents'), isFalse);
    final locale = host.service<LocaleService>('locale')!;
    locale.setLocale('en');
    expect(locale.bind('settings.agentPreset')('nav'), 'Agent presets');
  });
}
