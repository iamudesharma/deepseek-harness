import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_contract.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/renderer/slot_outlet.dart' show SlotComponentProps;
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/trajectory/trajectory_plugin.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host carrying the services TrajectoryPlugin declares.
PluginHost _host() {
  final host = PluginHost();
  host.provide('slots', host.slots);
  // An unconnected client is enough: activation only pins the service edge,
  // no calls are made.
  host.provide('sessions', SessionsService(ConnectionClient(baseUrl: '')));
  return host;
}

class _ViewShellPlugin extends DshPlugin {
  @override
  String get id => '@test/conversation-view-shell';

  @override
  Future<void> apply(DshContext ctx) async {
    ctx.onDispose(ctx.slots.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'conversation.view':
              SlotSpec(kind: SlotKind.list, scope: SlotScope.session),
        },
      ),
      (_, _) => const SizedBox.shrink(),
    ));
  }
}

void main() {
  test('contribution queues until conversation.view is declared', () async {
    final host = _host();
    addTearDown(host.deactivateAll);
    host.register(TrajectoryPlugin());

    await host.activateAll();

    // No view shell in this fixture: the wait-and-follow stays queued.
    expect(host.slots.isDeclared('conversation.view'), isFalse);
    expect(host.slots.winnersOfSlot('conversation.view'), isEmpty);
  });

  test('inject installs the trajectory tab once conversation.view exists', () async {
    final host = _host();
    addTearDown(host.deactivateAll);
    host.register(_ViewShellPlugin());
    host.register(TrajectoryPlugin());

    await host.activateAll();

    final winners = host.slots.winnersOfSlot('conversation.view');
    expect(winners, hasLength(1));
    expect(winners.first.options.id, 'trajectory');
    expect(winners.first.options.order, 10);
    // The contributed component is a widget builder over slot props.
    expect(winners.first.component, isA<Widget Function(BuildContext, SlotComponentProps)>());
  });

  test('deactivation removes the tab', () async {
    final host = _host();
    host.register(_ViewShellPlugin());
    host.register(TrajectoryPlugin());
    await host.activateAll();

    host.deactivate('ui-trajectory');

    expect(host.slots.winnersOfSlot('conversation.view'), isEmpty);
  });
}
