import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:flutter/widgets.dart';

class _NoopFace implements SettingsFace {
  @override
  Future<Map<String, Object?>> describe() async => const {};

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) async =>
      const {};
}

/// ConnectionClient double that records every generic carrier call — the
/// recorder pattern for asserting exact wire method strings.
class RecordingClient extends ConnectionClient {
  /// Creates the recorder (no network: every call is overridden).
  RecordingClient() : super(baseUrl: '');

  /// One recorded `callMethod`.
  final List<RecordedCall> calls = [];

  /// Next reply thrown as an RPC failure when non-null.
  Object? failNextWith;

  @override
  Future<Map<String, dynamic>> callMethod(
      String method, Map<String, dynamic> payload) async {
    calls.add(RecordedCall(method: method, payload: payload));
    final failure = failNextWith;
    if (failure != null) throw failure;
    return const {};
  }

  void clear() => calls.clear();
}

/// One recorded carrier call, field-asserted instead of string-matched.
class RecordedCall {
  /// Creates a record.
  const RecordedCall({required this.method, required this.payload});

  /// Wire method name (`goal.edit`, …).
  final String method;

  /// Request payload.
  final Map<String, dynamic> payload;
}

/// Host carrying every service the WS-Tasks plugins declare (`slots`,
/// `connection`, `sessions`, `locale`, plus `conversation` unless a test
/// boots the real [ConversationPlugin] to provide it), so activation runs
/// against the real DI fixpoint without booting the app shell.
PluginHost wsTasksHost({ConnectionClient? client, bool withConversation = true}) {
  final c = client ?? RecordingClient();
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.provide('connection', c);
  host.provide('sessions', SessionsService(c));
  host.provide('locale', LocaleService());
  if (withConversation) {
    final scope = SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-conversation');
    host.provide('conversation', ConversationController(client: c, settingsScope: scope));
  }
  return host;
}

/// Declares the conversation-owned header-actions hole without occupying it,
/// mirroring what the conversation anchor's children table does at boot. The
/// anchor entry hangs off the built-in declared `'root'` slot.
void declareHeaderActionsHole(PluginHost host) {
  host.slots.register(
    const RegistrationOptions(
      name: 'root',
      children: {
        'conversation.session.header.actions':
            SlotSpec(kind: SlotKind.list, scope: SlotScope.session),
      },
    ),
    (context, props) => const SizedBox.shrink(),
  );
}
