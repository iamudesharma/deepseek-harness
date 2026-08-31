/// Conversation Plugin wiring — Flutter port of the `ui-conversation`
/// plugin boundary: dependency injection, slot-tree declarations under the
/// layout center hole (wait-and-follow), and service provision. The
/// controller/policy/registry core lives in [hub.dart]; widget surfaces in
/// `ui/`.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/slots/slot_registry.dart';
export 'hub.dart'
    show
        ConversationController,
        ChatNodeRendererRegistry,
        ChatNodeData,
        ComposerPolicy,
        BusyEnterBehavior,
        TranscriptSink,
        activatedHub,
        bindActivatedHub,
        activatedHubListenable;
import 'hub.dart';
import 'locales.dart';

/// Declares the hub slot subtree attached to the layout center anchor.
const Map<String, SlotSpec> kConversationChildSlots = {
  'conversation': SlotSpec(
    kind: SlotKind.single,
    scope: SlotScope.sessionMaybe,
  ),
  'conversation.session.header.actions': SlotSpec(
    kind: SlotKind.list,
    scope: SlotScope.session,
  ),
  'conversation.composer.dock': SlotSpec(
    kind: SlotKind.list,
    scope: SlotScope.session,
  ),
  'conversation.details': SlotSpec(
    kind: SlotKind.single,
    scope: SlotScope.session,
  ),
  // Composer-side holes for WS-Input (triggers/commands/references) and
  // model selection — declared now so contributions can slots.inject later.
  // `input.plan` mirrors the composer-bar entry's children table in React
  // ui-conversation (apply.ts declares it beside attachments/model; the plan
  // chip mounts between access and leftItems — InputBar.tsx:713).
  'conversation.input.left': SlotSpec(
    kind: SlotKind.list,
    scope: SlotScope.session,
  ),
  'conversation.input.right': SlotSpec(
    kind: SlotKind.list,
    scope: SlotScope.session,
  ),
  'conversation.input.plan': SlotSpec(
    kind: SlotKind.single,
    scope: SlotScope.session,
  ),
  'conversation.input.model': SlotSpec(
    kind: SlotKind.single,
    scope: SlotScope.session,
  ),
  'conversation.input.overlay': SlotSpec(
    kind: SlotKind.list,
    scope: SlotScope.session,
  ),
  'conversation.composer': SlotSpec(
    kind: SlotKind.chain,
    scope: SlotScope.session,
  ),
  // Hero holes for WS-Surfaces (brand mark, workspace selector, agent-preset
  // chip — React contract slots.ts:209-211 scopes all three root).
  'conversation.hero.brand.mark': SlotSpec(
    kind: SlotKind.single,
    scope: SlotScope.root,
  ),
  'conversation.hero.workspace': SlotSpec(
    kind: SlotKind.single,
    scope: SlotScope.root,
  ),
  'conversation.hero.agentPreset': SlotSpec(
    kind: SlotKind.single,
    scope: SlotScope.root,
  ),
};

Widget _centerAnchor(BuildContext context, dynamic props) =>
    const SizedBox.shrink();

/// The `ui-conversation` plugin.
class ConversationPlugin extends DshPlugin {
  @override
  String get id => 'ui-conversation';

  @override
  List<String> get inject => [
    'slots',
    'connection',
    'settingsScope',
    'sessions',
    'workspaces',
    'locale',
    'remote',
  ];

  @override
  Future<void> apply(DshContext ctx) async {
    final client = ctx.require<ConnectionClient>('connection');
    final settingsScope = ctx.require<SettingsScope<Object?>>('settingsScope');
    // Pin every declared injection edge recorded in the hub map.
    ctx.require<SessionsService>('sessions');
    ctx.require<WorkspacesService>('workspaces');
    final LocaleService locale = ctx.require<LocaleService>('locale');
    ctx.require<RemoteEventBus>('remote');

    ctx.onDispose(
      locale.register(kConversationNamespace, {
        'zh': kConversationZh,
        'en': kConversationEn,
      }),
    );

    final controller = ConversationController(
      client: client,
      settingsScope: settingsScope,
    );
    ctx.provide('conversation', controller);
    // Bridge for hub UI widgets (header/chat/docks) — they read the bound
    // hub instead of reaching into the bootstrap module.
    bindActivatedHub(ConversationHub(slots: ctx.slots, controller: controller));

    // Load durable submission preference; failures keep the default.
    unawaited(controller.policy.loadFromScope());

    // Contribution waits for the layout-owned hole, installs atomically with
    // its child-slot declarations, and leaves with this plugin.
    final stopInject = ctx.slots.inject('layout.center', () {
      final disposeAnchor = ctx.slots.register(
        const RegistrationOptions(
          name: 'layout.center',
          children: kConversationChildSlots,
        ),
        _centerAnchor,
      );
      return [disposeAnchor];
    });
    ctx.onDispose(stopInject);
  }
}
