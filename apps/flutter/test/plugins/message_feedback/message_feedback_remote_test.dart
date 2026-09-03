import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/message_feedback_controller.dart';
import 'package:dsh_flutter/src/plugins/message_feedback/message_feedback_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingClient extends ConnectionClient {
  _RecordingClient() : super(baseUrl: '');
  final List<String> methods = [];
  final List<Map<String, dynamic>> payloads = [];
  Map<String, dynamic> answer = {};
  Object? error;

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    methods.add(method);
    payloads.add(payload);
    if (error != null) throw error!;
    return answer;
  }
}

RemoteMethodException _wireError(String wire, {Map<String, Object?> details = const {}}) =>
    RemoteMethodException(
      code: RpcErrorCode.tryParse(wire) ?? RpcErrorCode.internal,
      message: wire,
      details: details,
    );

void main() {
  group('MessageFeedback live remote — messageFeedback/* slash parity', () {
    test('list uses messageFeedback/list with sessionId', () async {
      final client = _RecordingClient()
        ..answer = {
          'items': [
            {'messageId': 'm1', 'rating': 'positive', 'version': 2},
          ],
        };
      final remote = ConnectionClientMessageFeedbackRemote(client);
      final reply = await remote.list(sessionId: 'sess-1');
      expect(client.methods.single, 'messageFeedback/list');
      expect(client.payloads.single['sessionId'], 'sess-1');
      expect(reply, isA<ReplyOk<List<MessageFeedbackItem>>>());
      final items = (reply as ReplyOk<List<MessageFeedbackItem>>).value;
      expect(items.single.messageId, 'm1');
      expect(items.single.rating, FeedbackRatingValue.positive);
      expect(items.single.version, 2);
    });

    test('put uses messageFeedback/put with sessionId/messageId/rating/ifVersion', () async {
      final client = _RecordingClient()
        ..answer = {
          'messageId': 'm1',
          'rating': 'negative',
          'note': 'off topic',
          'version': 3,
        };
      final remote = ConnectionClientMessageFeedbackRemote(client);
      final reply = await remote.put(
        sessionId: 'sess-1',
        messageId: 'm1',
        rating: FeedbackRatingValue.negative,
        note: 'off topic',
        ifVersion: 2,
      );
      expect(client.methods.single, 'messageFeedback/put');
      expect(client.payloads.single['sessionId'], 'sess-1');
      expect(client.payloads.single['messageId'], 'm1');
      expect(client.payloads.single['rating'], 'negative');
      expect(client.payloads.single['note'], 'off topic');
      expect(client.payloads.single['ifVersion'], 2);
      final item = (reply as ReplyOk<MessageFeedbackItem?>).value!;
      expect(item.version, 3);
      expect(item.rating, FeedbackRatingValue.negative);
    });

    test('put omits note when null (Host note? optional)', () async {
      final client = _RecordingClient()
        ..answer = {'messageId': 'm1', 'rating': 'positive', 'version': 1};
      final remote = ConnectionClientMessageFeedbackRemote(client);
      await remote.put(
        sessionId: 's',
        messageId: 'm1',
        rating: FeedbackRatingValue.positive,
        ifVersion: null,
      );
      expect(client.payloads.single.containsKey('note'), isFalse);
      expect(client.payloads.single['ifVersion'], isNull);
    });

    test('delete uses messageFeedback/delete and maps absent:true to null', () async {
      final client = _RecordingClient()..answer = {'absent': true};
      final remote = ConnectionClientMessageFeedbackRemote(client);
      final reply = await remote.delete(
        sessionId: 's',
        messageId: 'm1',
        ifVersion: 4,
      );
      expect(client.methods.single, 'messageFeedback/delete');
      expect(client.payloads.single['ifVersion'], 4);
      expect((reply as ReplyOk<MessageFeedbackItem?>).value, isNull);
    });

    test('version-conflict carries authoritative current row', () async {
      final client = _RecordingClient()
        ..error = _wireError('version-conflict', details: {
          'current': {'messageId': 'm1', 'rating': 'positive', 'version': 5},
        });
      final remote = ConnectionClientMessageFeedbackRemote(client);
      final reply = await remote.put(
        sessionId: 's',
        messageId: 'm1',
        rating: FeedbackRatingValue.negative,
        ifVersion: 2,
      );
      final err = reply as ReplyError<MessageFeedbackItem?>;
      expect(err.code, 'version-conflict');
      expect(err.current?.version, 5);
      expect(err.current?.rating, FeedbackRatingValue.positive);
    });

    test('target-not-found maps to business code, never throws', () async {
      final client = _RecordingClient()..error = _wireError('target-not-found');
      final remote = ConnectionClientMessageFeedbackRemote(client);
      final reply = await remote.list(sessionId: 'missing');
      expect(reply, isA<ReplyError<List<MessageFeedbackItem>>>());
      expect(
        (reply as ReplyError<List<MessageFeedbackItem>>).code,
        'target-not-found',
      );
    });

    test('never uses dot-form wires', () async {
      final client = _RecordingClient()..answer = {'items': []};
      final remote = ConnectionClientMessageFeedbackRemote(client);
      await remote.list(sessionId: 's');
      expect(client.methods, isNot(contains('messageFeedback.list')));
      expect(client.methods, isNot(contains('message-feedback/list')));
    });
  });
}
