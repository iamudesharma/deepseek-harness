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

  final Map<String, dynamic>? Function(
    String path,
    Map<String, dynamic> envelope,
    Map<String, String> headers,
  )
  onCall;

  HttpServer? _server;
  final List<
    ({String path, Map<String, dynamic> body, Map<String, String> headers})
  >
  requests = [];

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      final path = request.uri.path;
      final body = await utf8.decoder.bind(request).join();
      final headers = <String, String>{};
      request.headers.forEach(
        (name, values) => headers[name.toLowerCase()] = values.join(','),
      );
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      requests.add((path: path, body: decoded, headers: headers));
      final response =
          onCall(path, decoded, headers) ??
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
  test('unary calls POST /api/<method> with the client-request envelope and minted rpcId', () async {
    final host = _ScriptedRpcHost((_, _, _) => null);
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);

    await client.getSessions();

    final call = host.requests.single;
    expect(call.path, '/api/session/list');
    expect(call.body['type'], 'client-request');
    expect(call.body['method'], 'session/list');
    expect(call.body['payload'], <String, dynamic>{});
    // The initiator mints a UUID-shaped rpcId and carries it in both the
    // envelope and the x-rpc-id header.
    final rpcId = call.body['rpcId'] as String;
    expect(
      rpcId,
      matches(RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$')),
    );
    expect(call.headers['x-rpc-id'], rpcId);
    expect(call.headers['content-type'], startsWith('application/json'));
  });

  test('the responder echoes the initiator rpcId; results unwrap through result.value', () async {
    final host = _ScriptedRpcHost(
      (_, envelope, _) => {
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
      },
    );
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);

    final sessions = await client.getSessions();

    expect(host.requests.single.body['rpcId'], isNotNull);
    expect(sessions.single.sessionId.value, 's-1');
    expect(sessions.single.title, 'one');
  });

  test(
    'session.create carries only set fields and unwraps result.value.sessionId',
    () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/session/create'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'sessionId': 's-new'},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final id = await client.createSession(
        workspaceId: 'ws-9',
        cwd: '/tmp/proj',
      );

      final call = host.requests.single;
      expect(call.path, '/api/session/create');
      // Typert gateway wraps as {args: {request: {...}}}; the business
      // payload is inside args.request.
      final payload = call.body['payload'] as Map<String, dynamic>;
      final args = payload['args'] as Map<String, dynamic>? ?? payload;
      final request = args['request'] as Map<String, dynamic>? ?? args;
      expect(request, {'workspaceId': 'ws-9', 'cwd': '/tmp/proj'});
      expect(id.value, 's-new');

      await client.createSession();
      final lastPayload = host.requests.last.body['payload'] as Map<String, dynamic>;
      final lastArgs = lastPayload['args'] as Map<String, dynamic>? ?? lastPayload;
      final lastRequest = lastArgs['request'] as Map<String, dynamic>? ?? lastArgs;
      expect(
        lastRequest,
        <String, dynamic>{},
        reason: 'unset workspace/cwd stay off the wire',
      );
    },
  );

  test(
    'a failure result discriminates as an exception carrying the error message',
    () async {
      final host = _ScriptedRpcHost(
        (_, envelope, _) => {
          'type': 'server-response',
          'rpcId': envelope['rpcId'],
          'result': {
            'ok': false,
            'error': {
              'code': 'workspace/not-found',
              'message': 'no such workspace',
              'details': {},
            },
          },
        },
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      await expectLater(
        client.callMethod('session.selectModel', {
          'sessionId': 's',
          'provider': 'p',
          'model': 'm',
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no such workspace'),
          ),
        ),
      );
    },
  );

  test(
    'respond posts the client-response carrier echoing the requested rpcId',
    () async {
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
      expect(
        call.body['rpcId'],
        'req-7',
      ); // responder echoes the requested frame's id
      expect(call.headers['x-rpc-id'], 'req-7');
      expect(call.body['result'], {
        'ok': true,
        'value': {'answer': 42},
      });
      expect(receipt, isA<RpcReceiptAccepted>());
    },
  );

  test(
    'non-2xx carrier status surfaces as a ClientException, not a silent empty',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = 503;
        await request.response.close();
      });
      final client = ConnectionClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      addTearDown(client.dispose);

      await expectLater(client.getSessions(), throwsA(isA<Exception>()));
    },
  );

  group('console terminal wire faces (ctx.remote.terminal)', () {
    /// Extracts the `request` object a scripted terminal call carried.
    Map<String, dynamic> terminalRequestOf(Map<String, dynamic> body) {
      final payload = (body['payload'] as Map).cast<String, dynamic>();
      final args = (payload['args'] as Map?)?.cast<String, dynamic>();
      if (args == null) return payload;
      final request = args['request'];
      if (request is Map) return request.cast<String, dynamic>();
      return args;
    }

    test('terminal/list posts bare payload and unwraps the session pool', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/terminal/list'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {
                    'sessions': [
                      {
                        'sessionId': 'pty-1',
                        'name': 'panel',
                        'type': 'shell',
                        'pid': 42,
                        'status': {'kind': 'running'},
                      },
                    ],
                  },
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.terminalList();

      final call = host.requests.single;
      expect(call.path, '/api/terminal/list');
      final sessions = value['sessions'] as List;
      expect(sessions.single['sessionId'], 'pty-1');
      expect(sessions.single['status'], {'kind': 'running'});
    });

    test('terminal/open carries only set fields and unwraps snapshot plus motd', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/terminal/open'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {
                    'sessionId': 'pty-2',
                    'type': 'shell',
                    'status': {'kind': 'running'},
                    'motd': 'ready',
                  },
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.terminalOpen(name: 'panel');

      final call = host.requests.single;
      expect(call.path, '/api/terminal/open');
      expect(terminalRequestOf(call.body), {'name': 'panel'});
      expect(value['sessionId'], 'pty-2');
      expect(value['motd'], 'ready');
    });

    test('terminal/send carries the line and unwraps the settled viewport', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/terminal/send'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {
                    'viewport': 'ran:echo hi',
                    'waitReason': 'stdin_read',
                    'sessionStatus': {'kind': 'running'},
                    'truncated': false,
                  },
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.terminalSend(
        sessionId: 'pty-1',
        text: 'echo hi',
        submit: true,
      );

      final call = host.requests.single;
      expect(call.path, '/api/terminal/send');
      expect(terminalRequestOf(call.body), {
        'sessionId': 'pty-1',
        'text': 'echo hi',
        'submit': true,
      });
      expect(value['viewport'], 'ran:echo hi');
      expect(value['waitReason'], 'stdin_read');
    });

    test('terminal/read carries the page window and unwraps pagination', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/terminal/read'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {
                    'text': 'out',
                    'totalLines': 3,
                    'lineBegin': 0,
                    'lineEnd': 1,
                    'truncated': false,
                  },
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.terminalRead(sessionId: 'pty-1', count: 20);

      final call = host.requests.single;
      expect(call.path, '/api/terminal/read');
      expect(terminalRequestOf(call.body), {'sessionId': 'pty-1', 'count': 20});
      expect(value['text'], 'out');
      expect(value['totalLines'], 3);
    });

    test('terminal/signal carries the signal and unwraps the delivery receipt', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/terminal/signal'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'delivered': true, 'targetPgid': 7},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.terminalSignal(
        sessionId: 'pty-1',
        signal: 'SIGINT',
      );

      final call = host.requests.single;
      expect(call.path, '/api/terminal/signal');
      expect(terminalRequestOf(call.body), {
        'sessionId': 'pty-1',
        'signal': 'SIGINT',
      });
      expect(value['delivered'], true);
      expect(value['targetPgid'], 7);
    });

    test('terminal/close carries the id and unwraps the receipt', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/terminal/close'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'closed': true},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.terminalClose(sessionId: 'pty-1');

      final call = host.requests.single;
      expect(call.path, '/api/terminal/close');
      expect(terminalRequestOf(call.body), {'sessionId': 'pty-1'});
      expect(value['closed'], true);
    });
  });
}