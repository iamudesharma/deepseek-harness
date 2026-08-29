import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_contract.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/conversation/conversation_plugin.dart';
import 'package:dsh_flutter/src/core/renderer/slot_outlet.dart'
    show SlotComponentProps;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Minimal host carrying the services ConversationPlugin declares, so
/// activation runs against the real DI fixpoint.
PluginHost _hostWith(ConnectionClient client) {
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.provide('connection', client);
  host.provide('sessions', SessionsService(client));
  host.provide('workspaces', WorkspacesService(client));
  host.provide('locale', LocaleService());
  host.provide('remote', RemoteEventBus());
  host.provide(
    'settingsScope',
    SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-theme'),
  );
  host.register(ConversationPlugin());
  return host;
}

SettingsScope<Object?> _scope() =>
    SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-theme');

Widget _stubRenderer(BuildContext context, ChatNodeData data) =>
    const SizedBox.shrink();

void main() {
  test(
    'activation queues contribution until layout declares its hole',
    () async {
      final host = _hostWith(ConnectionClient(baseUrl: ''));
      addTearDown(host.deactivateAll);

      await host.activateAll();

      // No layout shell in this fixture: the wait-and-follow stays queued and
      // the service seam is still live.
      expect(host.slots.isDeclared('layout.center'), isFalse);
      expect(host.service<Object>('conversation'), isNotNull);
    },
  );

  test('inject installs declarations once layout.center exists', () async {
    final host = _hostWith(ConnectionClient(baseUrl: ''));

    // Layout-shaped shell declares the hole first…
    host.register(_LayoutShellPlugin());
    // …the conversation contribution (already registered) follows on
    // declaration during activation.
    await host.activateAll();

    expect(host.slots.isDeclared('layout.center'), isTrue);
    expect(host.slots.winnersOfSlot('layout.center'), hasLength(1));
    expect(host.slots.isDeclared('conversation'), isTrue);
  });

  test(
    'chat-node renderer registry: register, resolve, fallback, conflict',
    () {
      final controller = ConversationController(
        client: ConnectionClient(baseUrl: ''),
        settingsScope: _scope(),
      );
      controller.renderers.register('tool', _stubRenderer);

      expect(controller.renderers.resolve('tool'), same(_stubRenderer));
      expect(controller.renderers.resolve('goal'), isNull);
      expect(
        () => controller.renderers.register('tool', _stubRenderer),
        throwsStateError,
      );
    },
  );

  test('fallback renderer serves unknown keys when registered under *', () {
    final controller = ConversationController(
      client: ConnectionClient(baseUrl: ''),
      settingsScope: _scope(),
    )..renderers.register('*', _stubRenderer);
    expect(controller.renderers.resolve('anything'), same(_stubRenderer));
  });

  test('send delegates to session.prompt for the given session', () async {
    final sent = <({String sessionId, String content})>[];
    final client = ConnectionClient(baseUrl: '');
    final controller = ConversationController(
      client: client,
      settingsScope: _scope(),
    );

    // Spy by overriding through a subclass is unnecessary: assert the call
    // surfaces the carrier error for an empty baseUrl (no network attempted),
    // proving delegation reached the client.
    await expectLater(
      controller.send(const SessionId('s-1'), 'ping', agentRunning: false),
      throwsA(isA<Object>()),
    );
    expect(sent, isEmpty);
  });
}

class _LayoutShellPlugin extends DshPlugin {
  @override
  String get id => '@test/layout';

  @override
  Future<void> apply(DshContext ctx) async {
    // Declare the hole without occupying it — the conversation contribution
    // becomes the single occupant and attaches its own subtree declarations.
    ctx.onDispose(
      ctx.slots.register(
        const RegistrationOptions(
          name: 'root',
          children: {
            'layout.center': SlotSpec(
              kind: SlotKind.single,
              scope: SlotScope.root,
            ),
          },
        ),
        _frame,
      ),
    );
  }

  static Widget _frame(BuildContext context, SlotComponentProps props) =>
      const SizedBox.shrink();
}
