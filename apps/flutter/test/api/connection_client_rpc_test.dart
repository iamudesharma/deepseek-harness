import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted Typert host: records every request (path, envelope, headers) and
/// answers from a per-path handler, so the client's wire contract — envelope
/// shape, rpcId mint/echo discipline, result unwrapping, error
/// discrimination — is pinned against a real HTTP carrier.
class _ScriptedRpcHost {
  _ScriptedRpcHost(this.onCall);

  final Map<String, dynamic>? Function(String path, Map<String, dynamic> envelope,
      Map<String, String> headers) onCall;

  HttpServer? _server;
  final List<({String path, Map<String, dynamic> body, Map<String, String> headers})> requests = [];

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      final path = request.uri.path;
      final body = await utf8.decoder.bind(request).join();
      final headers = <String, String>{};
      request.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(','));
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      requests.add((path: path, body: decoded, headers: headers));
      final response = onCall(path, decoded, headers) ??
          {
            'type': 'server-response',
            'rpcId': decoded['rpcId'],
            'result': {'ok': true, 'value': <String, dynamic>{}},
          };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  test('unary calls POST /api/<method> with the client-request envelope and minted rpcId',
      () async {
    final host = _ScriptedRpcHost((_, _, _) => null);
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);

    await client.getSessions();

    final call = host.requests.single;
    expect(call.path, '/api/session.list');
    expect(call.body['type'], 'client-request');
    expect(call.body['method'], 'session.list');
    expect(call.body['payload'], <String, dynamic>{});
    // The initiator mints a UUID-shaped rpcId and carries it in both the
    // envelope and the x-rpc-id header.
    final rpcId = call.body['rpcId'] as String;
    expect(rpcId, matches(RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$')));
    expect(call.headers['x-rpc-id'], rpcId);
    expect(call.headers['content-type'], startsWith('application/json'));
  });

  test('the responder echoes the initiator rpcId; results unwrap through result.value',
      () async {
    final host = _ScriptedRpcHost((_, envelope, _) => {
          'type': 'server-response',
          'rpcId': envelope['rpcId'], // responder echoes verbatim
          'result': {
            'ok': true,
            'value': {
              'items': [
                {
                  'sessionId': 's-1',
                  'title': 'one',
                  'updatedAt': 5,
                  'running': false,
                  'blank': true,
                },
              ],
            },
          },
        });
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);

    final sessions = await client.getSessions();

    expect(host.requests.single.body['rpcId'], isNotNull);
    expect(sessions.single.sessionId.value, 's-1');
    expect(sessions.single.title, 'one');
  });

  test('session.create carries only set fields and unwraps result.value.sessionId', () async {
    final host = _ScriptedRpcHost((path, envelope, _) =>
        path == '/api/session.create'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'sessionId': 's-new'},
                },
              }
            : null);
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);

    final id = await client.createSession(workspaceId: 'ws-9', cwd: '/tmp/proj');

    final call = host.requests.single;
    expect(call.path, '/api/session.create');
    expect(call.body['payload'], {'workspaceId': 'ws-9', 'cwd': '/tmp/proj'});
    expect(id.value, 's-new');

    await client.createSession();
    expect(
        host.requests.last.body['payload'], <String, dynamic>{},
        reason: 'unset workspace/cwd stay off the wire');
  });

  test('a failure result discriminates as an exception carrying the error message',
      () async {
    final host = _ScriptedRpcHost((_, envelope, _) => {
          'type': 'server-response',
          'rpcId': envelope['rpcId'],
          'result': {
            'ok': false,
            'error': {
              'code': 'workspace-not-found',
              'message': 'no such workspace',
              'details': {},
            },
          },
        });
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);

    await expectLater(
      client.callMethod('session.selectModel', {'sessionId': 's', 'provider': 'p', 'model': 'm'}),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('no such workspace'),
      )),
    );
  });

  test('respond posts the client-response carrier echoing the requested rpcId', () async {
    final host = _ScriptedRpcHost((_, _, _) => {'accepted': true});
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);

    final receipt = await client.respond(
      rpcId: const RpcId('req-7'),
      ok: true,
      value: {'answer': 42},
    );

    final call = host.requests.single;
    expect(call.path, '/api/respond');
    expect(call.body['type'], 'client-response');
    expect(call.body['rpcId'], 'req-7'); // responder echoes the requested frame's id
    expect(call.headers['x-rpc-id'], 'req-7');
    expect(call.body['result'], {
      'ok': true,
      'value': {'answer': 42},
    });
    expect(receipt, isA<RpcReceiptAccepted>());
  });

  test('non-2xx carrier status surfaces as a ClientException, not a silent empty', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(server.close);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 503;
      await request.response.close();
    });
    final client = ConnectionClient(baseUrl: 'http://127.0.0.1:${server.port}');
    addTearDown(client.dispose);

    await expectLater(client.getSessions(), throwsA(isA<Exception>()));
  });
}
