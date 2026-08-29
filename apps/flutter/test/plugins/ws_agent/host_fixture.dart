import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart';
import 'package:flutter/widgets.dart';

class _NoopFace implements SettingsFace {
  @override
  Future<Map<String, Object?>> describe() async => const {};

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) async => const {};
}

/// Host carrying every service the four WS plugins declare (`slots`,
/// `connection`, `sessions`, `workspaces`, `locale`, `remote`,
/// `settingsScope`, plus `conversation` unless a test boots the real
/// [ConversationPlugin] to provide it), so activation runs against the real
/// DI fixpoint without booting the app shell.
PluginHost wsAgentHost({
  ConnectionClient? client,
  bool withConversation = true,
}) {
  final c = client ?? ConnectionClient(baseUrl: '');
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.provide('connection', c);
  host.provide('sessions', SessionsService(c));
  host.provide('workspaces', WorkspacesService(c));
  host.provide('locale', LocaleService());
  host.provide('remote', RemoteEventBus());
  host.provide('inputTriggers', TriggerSourceRegistry());
  final scope = SettingsScope<Object?>(
    face: _NoopFace(),
    namespace: 'ui-conversation',
  );
  host.provide('settingsScope', scope);
  if (withConversation) {
    host.provide(
      'conversation',
      ConversationController(client: c, settingsScope: scope),
    );
  }
  return host;
}

/// Declares the conversation-owned holes the WS-Agent plugins inject into
/// (header actions + the composer plan seat) without occupying them,
/// mirroring what the conversation anchor's children table does at boot. The
/// anchor entry hangs off the built-in declared `'root'` slot.
void declareHeaderActionsHole(PluginHost host) {
  host.slots.register(
    const RegistrationOptions(
      name: 'root',
      children: {
        'conversation.session.header.actions': SlotSpec(
          kind: SlotKind.list,
          scope: SlotScope.session,
        ),
        'conversation.input.plan': SlotSpec(
          kind: SlotKind.single,
          scope: SlotScope.session,
        ),
      },
    ),
    (context, props) => const SizedBox.shrink(),
  );
}
