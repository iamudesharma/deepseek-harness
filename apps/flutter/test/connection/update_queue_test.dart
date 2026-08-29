import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';

void main() {
  test('updateQueue remove payload matches host schema', () async {
    Map<String, dynamic>? captured;
    final mock = MockClient((req) async {
      captured = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'type': 'server-response',
          'rpcId': captured!['rpcId'],
          'result': {
            'ok': true,
            'value': {'accepted': true},
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = ConnectionClient(
      baseUrl: 'http://127.0.0.1:3080',
      httpClient: mock,
    );
    await client.updateQueue(
      sessionId: SessionId('s1'),
      itemId: MessageId('m1'),
      action: const QueueActionRemove(),
    );
    expect(captured!['method'], 'session.updateQueue');
    expect((captured!['payload'] as Map)['itemId'], 'm1');
    expect(((captured!['payload'] as Map)['action'] as Map)['kind'], 'remove');
  });
  test('updateQueue edit payload', () async {
    Map<String, dynamic>? captured;
    final mock = MockClient((req) async {
      captured = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'type': 'server-response',
          'rpcId': captured!['rpcId'],
          'result': {
            'ok': true,
            'value': {'accepted': true},
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = ConnectionClient(
      baseUrl: 'http://127.0.0.1:3080',
      httpClient: mock,
    );
    await client.updateQueue(
      sessionId: SessionId('s1'),
      itemId: MessageId('m2'),
      action: QueueActionEdit([
        {'type': 'text', 'text': 'hello'},
      ]),
    );
    expect(((captured!['payload'] as Map)['action'] as Map)['kind'], 'edit');
    expect(
      ((captured!['payload'] as Map)['action'] as Map)['content'][0]['text'],
      'hello',
    );
  });
  test('updateQueue steer payload', () async {
    Map<String, dynamic>? captured;
    final mock = MockClient((req) async {
      captured = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'type': 'server-response',
          'rpcId': captured!['rpcId'],
          'result': {
            'ok': true,
            'value': {'accepted': true},
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = ConnectionClient(
      baseUrl: 'http://127.0.0.1:3080',
      httpClient: mock,
    );
    await client.updateQueue(
      sessionId: SessionId('s1'),
      itemId: MessageId('m3'),
      action: const QueueActionSteer(),
    );
    expect(((captured!['payload'] as Map)['action'] as Map)['kind'], 'steer');
  });
}
