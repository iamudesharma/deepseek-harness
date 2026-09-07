import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the `remote.pair` wire shape: business fields ride under
/// `args.request` like every other single-argument Typert method (flat args
/// are rejected by the gateway with `gateway/arguments-invalid`).
void main() {
  test('remotePair wraps the presentation in args.request', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(server.close);
    Map<String, dynamic>? seenPayload;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      seenPayload = (decoded['payload'] as Map).cast<String, dynamic>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'type': 'server-response',
          'rpcId': decoded['rpcId'],
          'result': {
            'ok': true,
            'value': {
              'hostId': List.filled(43, 'A').join(),
              'hostPublicKey': 'cHVibGlj',
              'deviceToken': 'tok',
              'expiresAt': 99,
            },
          },
        }),
      );
      await request.response.close();
    });

    final client = ConnectionClient(baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(client.dispose);

    await client.remotePair(
      hostId: List.filled(43, 'A').join(),
      deviceId: '11111111-1111-4111-8111-111111111111',
      displayName: 'Pixel',
      devicePublicKey: 'cHVibGlj',
      nonce: '22222222-2222-4222-8222-222222222222',
      pin: '123456',
    );

    final args = (seenPayload!['args'] as Map).cast<String, dynamic>();
    expect(args.containsKey('request'), isTrue);
    final req = (args['request'] as Map).cast<String, dynamic>();
    expect(req['nonce'], '22222222-2222-4222-8222-222222222222');
    expect(req['pin'], '123456');
    expect(req.containsKey('hostId'), isTrue);
  });

  test('remotePair omits an absent PIN', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(server.close);
    Map<String, dynamic>? seenPayload;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      seenPayload = (decoded['payload'] as Map).cast<String, dynamic>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'type': 'server-response',
          'rpcId': decoded['rpcId'],
          'result': {
            'ok': true,
            'value': {
              'hostId': List.filled(43, 'A').join(),
              'hostPublicKey': 'cHVibGlj',
              'deviceToken': 'tok',
              'expiresAt': 99,
            },
          },
        }),
      );
      await request.response.close();
    });

    final client = ConnectionClient(baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(client.dispose);

    await client.remotePair(
      hostId: List.filled(43, 'A').join(),
      deviceId: '11111111-1111-4111-8111-111111111111',
      displayName: 'Pixel',
      devicePublicKey: 'cHVibGlj',
      nonce: '22222222-2222-4222-8222-222222222222',
    );

    final args = (seenPayload!['args'] as Map).cast<String, dynamic>();
    final req = (args['request'] as Map).cast<String, dynamic>();
    expect(req.containsKey('pin'), isFalse);
  });
}
