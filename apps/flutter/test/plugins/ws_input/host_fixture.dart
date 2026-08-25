import 'dart:async';
import 'dart:convert';

import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' show fail;

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

/// One recorded `respond` call (the answerable-frame carrier).
class RecordedRespond {
  RecordedRespond(this.rpcId, this.ok, this.value, this.error);

  final RpcId rpcId;
  final bool ok;
  final Object? value;
  final Map<String, Object?>? error;

  Map<String, Object?> get decodedValue {
    if (value is! Map) return const {};
    return value as Map<String, Object?>;
  }
}

/// ConnectionClient double that records carrier calls — the recorder pattern
/// from the other workstreams' fixtures.
class WsInputRecordingClient extends ConnectionClient {
  WsInputRecordingClient() : super(baseUrl: '');

  /// Recorded generic carrier calls (`command.list`, `session.prompt`, …).
  final List<(String, Map<String, dynamic>)> calls = [];

  /// Recorded respond calls in order.
  final List<RecordedRespond> responds = [];

  /// Next reply for any recorded call; thrown when [failNext] is set,
  /// returned otherwise.
  Object? nextValue;

  /// When non-null, the next call throws this error message string.
  String? failNext;

  /// Next receipt returned by [respond]; defaults to accepted. Set a
  /// rejected receipt here to exercise the rejected-receipt paths.
  RpcReceipt? nextReceipt;

  @override
  Future<Map<String, dynamic>> callMethod(
      String method, Map<String, dynamic> payload) async {
    calls.add((method, payload));
    final failure = failNext;
    if (failure != null) throw Exception('$method: $failure');
    final value = nextValue;
    if (value is Map<String, dynamic>) return value;
    return const {};
  }

  @override
  Future<RpcReceipt> respond({
    required RpcId rpcId,
    required bool ok,
    Object? value,
    Map<String, Object?>? error,
  }) async {
    responds.add(RecordedRespond(rpcId, ok, value, error));
    final receipt = nextReceipt;
    if (receipt != null) return receipt;
    return const RpcReceiptAccepted();
  }

  void clear() {
    calls.clear();
    responds.clear();
  }
}

/// Raw question/requested frame body (the narrow payload the transports
/// yield, with the envelope rpcId stamped per the transport contract).
Map<String, dynamic> questionRequestedFrame({
  required String sessionId,
  required String rpcId,
  required List<Map<String, Object?>> questions,
}) =>
    {'type': 'question/requested', 'rpcId': rpcId, 'sessionId': sessionId, 'questions': questions};

Map<String, dynamic> questionResolvedFrame({
  required String sessionId,
  required String rpcId,
  required String outcome,
}) =>
    {
      'type': 'question/resolved',
      'sessionId': sessionId,
      'questionRpcId': rpcId,
      'outcome': outcome,
    };

/// One AskUserQuestionItem wire row.
Map<String, Object?> askItem({
  required String id,
  required String question,
  String? detail,
  List<Map<String, Object?>> options = const [],
  bool multiSelect = false,
}) =>
    {
      'id': id,
      'question': question,
      if (detail != null) 'detail': detail,
      if (options.isNotEmpty)
        'options': [
          for (final o in options) o,
        ],
      if (multiSelect) 'multiSelect': true,
    };

/// Decodes a candidate's opaque payload for assertions.
Map<String, dynamic>? decodeCandidateValue(String? raw) {
  if (raw == null) return null;
  final decoded = jsonDecode(raw);
  return decoded is Map ? decoded.cast<String, dynamic>() : null;
}

/// Host carrying every service the WS-Input plugins declare. Declares the
/// conversation composer holes (`conversation.input.left`/`right`) exactly
/// like the conversation anchor's children table does at boot.
PluginHost wsInputHost({WsInputRecordingClient? client}) {
  final c = client ?? WsInputRecordingClient();
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.provide('connection', c);
  host.provide('sessions', SessionsService(c));
  host.provide('locale', LocaleService());
  host.provide('remote', RemoteEventBus());
  final scope = SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-conversation');
  host.provide('conversation', ConversationController(client: c, settingsScope: scope));
  declareComposerHoles(host);
  return host;
}

/// Declares the two composer-side holes on the built-in `'root'` entry
/// without occupying them (mirrors what ConversationPlugin's anchor declares).
void declareComposerHoles(PluginHost host) {
  host.slots.register(
    const RegistrationOptions(
      name: 'root',
      children: {
        'conversation.input.left':
            SlotSpec(kind: SlotKind.list, scope: SlotScope.session),
        'conversation.input.right':
            SlotSpec(kind: SlotKind.list, scope: SlotScope.session),
      },
    ),
    (context, props) => const SizedBox.shrink(),
  );
}

Future<void> pumpUntil(bool Function() test, {Duration limit = const Duration(seconds: 2)}) async {
  final end = DateTime.now().add(limit);
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      fail('condition not met within $limit');
    }
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
