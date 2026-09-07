import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
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
    // Host `session/list(_request: SessionListRequest)` reads the reserved
    // `_request` field inside args (fixture `args._request`), so the reserved
    // empty request rides the wire instead of a bare {}.
    expect(call.body['payload'], {
      'args': {'_request': {}},
    });
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
      final lastPayload =
          host.requests.last.body['payload'] as Map<String, dynamic>;
      final lastArgs =
          lastPayload['args'] as Map<String, dynamic>? ?? lastPayload;
      final lastRequest =
          lastArgs['request'] as Map<String, dynamic>? ?? lastArgs;
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
    'respond routes through \$events/result when the events generation is live',
    () async {
      final host = _ScriptedRpcHost((_, _, _) => null);
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);
      client.eventsClientId = 'client-1';

      final receipt = await client.respond(
        rpcId: const RpcId('event-9'),
        ok: true,
        value: 'allowed-once',
      );

      final call = host.requests.single;
      expect(call.path, '/api/\$events/result');
      expect(call.body['method'], '\$events/result');
      final args =
          (call.body['payload'] as Map).cast<String, dynamic>()['args'] as Map;
      expect(args['clientId'], 'client-1');
      expect(args['eventId'], 'event-9');
      expect(args['outcome'], {'kind': 'result', 'value': 'allowed-once'});
      expect(receipt, isA<RpcReceiptAccepted>());
    },
  );

  test('respond rejects an empty correlation instead of posting', () async {
    final host = _ScriptedRpcHost((_, _, _) => null);
    final client = ConnectionClient(baseUrl: await host.start());
    addTearDown(client.dispose);
    addTearDown(host.stop);
    client.eventsClientId = 'client-1';

    await expectLater(
      client.respond(rpcId: const RpcId(''), ok: true, value: 'allowed-once'),
      throwsStateError,
    );
    expect(host.requests, isEmpty);
  });

  test(
    'sendMessage carries the caller requestId for echo correlation',
    () async {
      final host = _ScriptedRpcHost((_, _, _) => null);
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      await client.sendMessage(
        sessionId: const SessionId('s-1'),
        content: 'hi',
        requestId: 'req-echo-1',
      );

      final call = host.requests.single;
      expect(call.path, '/api/session/prompt');
      final payload =
          (call.body['payload'] as Map).cast<String, dynamic>()['args'] as Map;
      final request = (payload['request'] as Map).cast<String, dynamic>();
      expect(request['requestId'], 'req-echo-1');
      expect(request['sessionId'], 's-1');
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

  group('master wire faces the React client also uses', () {
    /// Extracts the `request` (or bare args) object a scripted call carried,
    /// mirroring how the gateway reads business payloads.
    Map<String, dynamic> requestOf(Map<String, dynamic> body) {
      final payload = (body['payload'] as Map).cast<String, dynamic>();
      final args = (payload['args'] as Map?)?.cast<String, dynamic>();
      if (args == null) return payload;
      final request = args['request'];
      if (request is Map) return request.cast<String, dynamic>();
      return args;
    }

    test('session/fork sends {sessionId, atSeq?} and unwraps the child id', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/session/fork'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'sessionId': 'fork-child'},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final child = await client.forkSession(
        sessionId: 's-src',
        atSeq: 42,
      );

      final call = host.requests.single;
      expect(call.path, '/api/session/fork');
      expect(requestOf(call.body), {'sessionId': 's-src', 'atSeq': 42});
      expect(child, 'fork-child');

      await client.forkSession(sessionId: 's-src');
      expect(requestOf(host.requests.last.body), {'sessionId': 's-src'},
          reason: 'unset atSeq stays off the wire');
    });

    test('session/rename sends {sessionId, title} under request', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/session/rename'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'title': 'renamed', 'seq': 7},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.renameSession(
        sessionId: 's-1',
        title: 'renamed',
      );

      final call = host.requests.single;
      expect(call.path, '/api/session/rename');
      expect(requestOf(call.body), {'sessionId': 's-1', 'title': 'renamed'});
      expect(value['title'], 'renamed');
      expect(value['seq'], 7);
    });

    test('settings/replace sends {ns, section, expectedRevision?}', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/settings/replace'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {
                    'ns': 'permission',
                    'value': {'defaultPreset': 'workspace-write'},
                    'revision': 4,
                  },
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final view = await client.settingsReplace(
        ns: 'permission',
        section: {'defaultPreset': 'workspace-write'},
        expectedRevision: 3,
      );

      final call = host.requests.single;
      expect(call.path, '/api/settings/replace');
      expect(requestOf(call.body), {
        'ns': 'permission',
        'section': {'defaultPreset': 'workspace-write'},
        'expectedRevision': 3,
      });
      // The complete namespace view survives — the returned revision is what
      // the caller fences the next expectedRevision against.
      expect(view['ns'], 'permission');
      expect(view['value'], {'defaultPreset': 'workspace-write'});
      expect(view['revision'], 4);

      await client.settingsReplace(ns: 'permission', section: {});
      expect(
        requestOf(host.requests.last.body).containsKey('expectedRevision'),
        isFalse,
        reason: 'unset revision stays off the wire',
      );
    });

    test('settings/openSettingsDocument is pathless and unwraps {opened}', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/settings/openSettingsDocument'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'opened': true},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.settingsOpenDocument();

      final call = host.requests.single;
      expect(call.path, '/api/settings/openSettingsDocument');
      expect(requestOf(call.body), isEmpty);
      expect(value['opened'], true);
    });

    test('session/canOpenWorkspacePath unwraps the bare boolean', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/session/canOpenWorkspacePath'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {'ok': true, 'value': true},
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final canOpen = await client.canOpenWorkspacePath();

      final call = host.requests.single;
      expect(call.path, '/api/session/canOpenWorkspacePath');
      expect(requestOf(call.body), isEmpty);
      expect(canOpen, isTrue);
    });

    test('session/openWorkspacePath sends {path} under request', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/session/openWorkspacePath'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'opened': true},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.openWorkspacePath(path: '/tmp/proj/README.md');

      final call = host.requests.single;
      expect(call.path, '/api/session/openWorkspacePath');
      expect(requestOf(call.body), {'path': '/tmp/proj/README.md'});
      expect(value['opened'], true);
    });

    test('subagents/prompt sends the continuable address and unwraps messageId',
        () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/subagents/prompt'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'messageId': 'm-1'},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final messageId = await client.subagentPrompt(
        requestId: 'req-1',
        parentSessionId: 'p-1',
        childSessionId: 'c-1',
        content: [
          {'type': 'text', 'text': 'continue'},
        ],
      );

      final call = host.requests.single;
      expect(call.path, '/api/subagents/prompt');
      expect(requestOf(call.body), {
        'requestId': 'req-1',
        'parentSessionId': 'p-1',
        'childSessionId': 'c-1',
        'mode': 'continuable',
        'content': [
          {'type': 'text', 'text': 'continue'},
        ],
      });
      expect(messageId, 'm-1');
    });

    test('subagents/interruptByParent sends the parent authority triple',
        () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/subagents/interruptByParent'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'accepted': true},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      await client.subagentInterrupt(
        childSessionId: 'c-1',
        parentSessionId: 'p-1',
      );

      final call = host.requests.single;
      expect(call.path, '/api/subagents/interruptByParent');
      expect(requestOf(call.body), {
        'childSessionId': 'c-1',
        'parentSessionId': 'p-1',
        'mode': 'continuable',
      });
    });

    test('subagents/list sends the parent id and unwraps the catalog', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/subagents/list'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {
                    'entries': [
                      {
                        'kind': 'child',
                        'id': 'c-1',
                        'activity': 'running',
                        'hasChildren': false,
                        'mode': 'continuable',
                        'label': 'explore',
                      },
                    ],
                    'parentAvailable': true,
                  },
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final catalog = await client.subagentList(parentSessionId: 'p-1');

      final call = host.requests.single;
      expect(call.path, '/api/subagents/list');
      expect(requestOf(call.body), {'parentSessionId': 'p-1'});
      final entries = catalog['entries'] as List;
      expect(entries.single['id'], 'c-1');
      expect(catalog['parentAvailable'], true);
    });

    test('workspace/archiveSession sends {sessionId} under request', () async {
      final host = _ScriptedRpcHost(
        (path, envelope, _) => path == '/api/workspace/archiveSession'
            ? {
                'type': 'server-response',
                'rpcId': envelope['rpcId'],
                'result': {
                  'ok': true,
                  'value': {'archivedSessionIds': ['s-1']},
                },
              }
            : null,
      );
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final value = await client.workspaceArchiveSession(sessionId: 's-1');

      final call = host.requests.single;
      expect(call.path, '/api/workspace/archiveSession');
      expect(requestOf(call.body), {'sessionId': 's-1'});
      expect(value['archivedSessionIds'], ['s-1']);
    });
  });

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
