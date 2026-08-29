import 'dart:convert';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ConnectionClient.sendMessage with images', () {
    test('sends image blocks before text block', () async {
      Map<String, dynamic>? captured;
      final mock = MockClient((http.Request req) async {
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
      final client = ConnectionClient(baseUrl: 'http://fake', httpClient: mock);
      await client.sendMessage(
        sessionId: SessionId('s1'),
        content: 'hello',
        images: [
          {
            'type': 'image',
            'mediaType': 'image/png',
            'data': 'AQID',
            'name': 'a.png',
          },
          {
            'type': 'image',
            'mediaType': 'image/jpeg',
            'data': 'BAUG',
            'name': 'b.jpg',
          },
        ],
      );
      expect(captured, isNotNull);
      final payload = captured!['payload'] as Map<String, dynamic>;
      final content = payload['content'] as List;
      expect(content.length, 3);
      expect(content[0]['type'], 'image');
      expect(content[0]['mediaType'], 'image/png');
      expect(content[1]['type'], 'image');
      expect(content[2]['type'], 'text');
      expect(content[2]['text'], 'hello');
    });

    test('sends only images when text empty', () async {
      Map<String, dynamic>? captured;
      final mock = MockClient((http.Request req) async {
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
        );
      });
      final client = ConnectionClient(baseUrl: 'http://fake', httpClient: mock);
      await client.sendMessage(
        sessionId: SessionId('s1'),
        content: '',
        images: [
          {'type': 'image', 'mediaType': 'image/png', 'data': 'AQID'},
        ],
      );
      final content =
          (captured!['payload'] as Map<String, dynamic>)['content'] as List;
      expect(content.length, 1);
      expect(content[0]['type'], 'image');
    });

    test('sends only text when images empty (backwards compat)', () async {
      Map<String, dynamic>? captured;
      final mock = MockClient((http.Request req) async {
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
        );
      });
      final client = ConnectionClient(baseUrl: 'http://fake', httpClient: mock);
      await client.sendMessage(sessionId: SessionId('s1'), content: 'hi');
      final content =
          (captured!['payload'] as Map<String, dynamic>)['content'] as List;
      expect(content, [
        {'type': 'text', 'text': 'hi'},
      ]);
    });
  });
}
