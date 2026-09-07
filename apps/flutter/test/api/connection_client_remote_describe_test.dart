import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted host answering `remote/describe` for the manual-entry fetch path.
void main() {
  test(
    'remoteDescribe posts to /api/remote/describe and returns the identity',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(server.close);
      String? seenPath;
      server.listen((request) async {
        seenPath = request.uri.path;
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
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
                'tlsFingerprint': List.filled(43, 'B').join(),
              },
            },
          }),
        );
        await request.response.close();
      });

      final client = ConnectionClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      addTearDown(client.dispose);

      final identity = await client.remoteDescribe();

      expect(seenPath, '/api/remote/describe');
      expect(identity['hostId'], hasLength(43));
      expect(identity['hostPublicKey'], 'cHVibGlj');
      expect(identity['tlsFingerprint'], hasLength(43));
    },
  );

  test('remoteDescribe throws when the identity fields are missing', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(server.close);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'type': 'server-response',
          'rpcId': decoded['rpcId'],
          'result': {'ok': true, 'value': <String, dynamic>{}},
        }),
      );
      await request.response.close();
    });

    final client = ConnectionClient(baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(client.dispose);

    await expectLater(client.remoteDescribe(), throwsFormatException);
  });

  test('remoteDescribe throws on a malformed tlsFingerprint', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(server.close);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
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
              'tlsFingerprint': 'short',
            },
          },
        }),
      );
      await request.response.close();
    });

    final client = ConnectionClient(baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(client.dispose);

    await expectLater(client.remoteDescribe(), throwsFormatException);
  });
}
