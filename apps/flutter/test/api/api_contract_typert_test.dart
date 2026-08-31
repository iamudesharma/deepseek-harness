/// Wire-contract pin for the two open bug fixes against the current master:
///
/// 1. `commands/list` and `commands/execute` send exactly the wire fields the
///    host descriptor expects — no extra outer `args` wrapper. Before the fix
///    Flutter emitted `{args: {args: {agentId: ...}}}` and the host rejected
///    with `args fields do not match the descriptor: missing 'agentId';
///    unexpected 'args'` (see `packages/api/gateway/src/index.ts:1119-1145`).
///
/// 2. Directory-picker verbs (`directoryPicker/pick`, `directoryPicker/list`,
///    `directoryPicker/createDirectory`) carry the correct wire args. The
///    picker kind is detected at runtime via the typed
///    `directory-picker-unavailable` failure (`details.capability`), not by a
///    hidden client branch — the harness has no `host.describe` advertisement
///    for the picker.
///
/// Each test scripts the host at the HTTP carrier, captures the exact wire
/// request body, and asserts the request shape. The session/prompt path is
/// also re-pinned to confirm the generic `_postTypert` envelope builder did
/// not regress when the commands/* caller-side double-wrap was removed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/session_workspace_services.dart';
import 'package:dsh_flutter/src/core/connection/connection_target.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart' show SessionId;
import 'package:flutter_test/flutter_test.dart';

class _ScriptedHost {
  _ScriptedHost(this.onCall);
  final Map<String, dynamic>? Function(
    String path,
    Map<String, dynamic> envelope,
    Map<String, String> headers,
  )
  onCall;
  HttpServer? _server;
  final List<
      ({String path, Map<String, dynamic> body, Map<String, String> headers})>
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

Map<String, dynamic> _ok(Object? value, String rpcId) => {
      'type': 'server-response',
      'rpcId': rpcId,
      'result': {'ok': true, 'value': value},
    };

Map<String, dynamic> _fail(String code, String message, Object details, String rpcId) =>
    {
      'type': 'server-response',
      'rpcId': rpcId,
      'result': {
        'ok': false,
        'error': {
          'code': code,
          'message': message,
          'details': details,
        },
      },
    };

void main() {
  group('commands/* wire contract', () {
    test(
      'commands/list sends exactly {args:{agentId}} — no outer args wrap',
      () async {
        final host = _ScriptedHost((_, envelope, _) {
          return _ok(<Map<String, Object?>>[], envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        await client.callMethod('commands/list', {
          'agentId': 'session-1c256b7d-7e7b-4f01-aaaa-bbbbbbbbbbbb',
        });

        final call = host.requests.single;
        expect(call.path, '/api/commands/list');
        expect(call.body['method'], 'commands/list');
        // The carrier wraps the caller's wire fields once. The caller must
        // never pre-wrap with `args` — the host descriptor is `list(agent)`
        // with `agent` lookup → wire `agentId`. An outer `args` key produces
        // the host validation failure `args fields do not match the
        // descriptor: missing 'agentId'; unexpected 'args'`.
        expect(call.body['payload'], {
          'args': {
            'agentId': 'session-1c256b7d-7e7b-4f01-aaaa-bbbbbbbbbbbb',
          },
        });
      },
    );

    test(
      'commands/list does NOT send {args:{args:{...}}} double-wrap',
      () async {
        final host = _ScriptedHost((_, envelope, _) {
          return _ok(<Map<String, Object?>>[], envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        // Mirror the call-site payload that was passing before the fix.
        await client.callMethod('commands/list', {
          'agentId': 's-1',
        });

        final call = host.requests.single;
        final args = (call.body['payload'] as Map)['args'];
        expect(args, isA<Map<String, dynamic>>());
        // Defensive: assert the descriptor-expected key sits at the top of
        // the args dict (not nested under another `args`).
        expect(args.containsKey('agentId'), isTrue);
        expect(args.containsKey('args'), isFalse);
      },
    );

    test(
      'commands/execute sends {args:{agentId,line,images}} — no outer args',
      () async {
        final host = _ScriptedHost((_, envelope, _) {
          return _ok(
            {'commandId': 'cmd-1', 'result': {'kind': 'ok', 'text': ''}},
            envelope['rpcId'] as String,
          );
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        await client.callMethod('commands/execute', {
          'agentId': 'session-x',
          'line': '/permission full',
          'images': [],
        });

        final call = host.requests.single;
        expect(call.path, '/api/commands/execute');
        expect(call.body['method'], 'commands/execute');
        // Host descriptor: `execute(agent, line, images, signal)`. `signal`
        // is the cancellation slot — never on the wire.
        expect(call.body['payload'], {
          'args': {
            'agentId': 'session-x',
            'line': '/permission full',
            'images': [],
          },
        });
        final args = (call.body['payload'] as Map)['args'];
        expect(args.containsKey('signal'), isFalse);
        expect(args.containsKey('args'), isFalse);
      },
    );
  });

  group('session/prompt wire contract (regression pin)', () {
    test('session/prompt still sends the descriptor-shaped request', () async {
      final host = _ScriptedHost((_, envelope, _) {
        return _ok({'accepted': true}, envelope['rpcId'] as String);
      });
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      await client.sendMessage(
        sessionId: const SessionId('s-1'),
        content: 'hello',
      );

      final call = host.requests.single;
      expect(call.path, '/api/session/prompt');
      expect(call.body['method'], 'session/prompt');
      // session/prompt descriptor is single-param → wrapped as
      // {args: {request: {…}}}. The non-args carrier form must not regress
      // when commands/* callers change shape.
      final payload = call.body['payload'] as Map;
      expect(payload.containsKey('args'), isTrue);
      final args = payload['args'] as Map;
      expect(args.containsKey('request'), isTrue);
      final req = (args['request'] as Map);
      expect(req['sessionId'], 's-1');
      expect(req['mode'], 'queue');
      expect(req['content'], [
        {'type': 'text', 'text': 'hello'},
      ]);
    });
  });

  group('directoryPicker/* wire contract', () {
    test('directoryPicker/pick sends exactly {args:{}} (native capability)',
        () async {
      final host = _ScriptedHost((_, envelope, _) {
        return _ok({'path': '/Users/me/Projects'}, envelope['rpcId'] as String);
      });
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      await client.callMethod('directoryPicker/pick', const {});

      final call = host.requests.single;
      expect(call.path, '/api/directoryPicker/pick');
      expect(call.body['method'], 'directoryPicker/pick');
      // Native descriptor: `pick(signal)`. `signal` is cancellation — never
      // on the wire. The args dict is empty.
      expect(call.body['payload'], {'args': <String, dynamic>{}});
    });

    test('directoryPicker/list sends {args:{path?:string}} (browse capability)',
        () async {
      final host = _ScriptedHost((_, envelope, _) {
        return _ok(
          {
            'path': '/Users/me',
            'home': '/Users/me',
            'crumbs': [],
            'entries': <Map<String, Object?>>[],
            'truncated': false,
          },
          envelope['rpcId'] as String,
        );
      });
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      await client.callMethod('directoryPicker/list', {'path': '/Users/me'});

      final call = host.requests.single;
      expect(call.path, '/api/directoryPicker/list');
      expect(call.body['method'], 'directoryPicker/list');
      expect(call.body['payload'], {
        'args': {
          'path': '/Users/me',
        },
      });
    });

    test(
      'directoryPicker/createDirectory sends {args:{path,name}} (browse capability)',
      () async {
        final host = _ScriptedHost((_, envelope, _) {
          return _ok(
            {'path': '/Users/me/Projects/new'},
            envelope['rpcId'] as String,
          );
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        await client.callMethod('directoryPicker/createDirectory', {
          'path': '/Users/me/Projects',
          'name': 'new',
        });

        final call = host.requests.single;
        expect(call.path, '/api/directoryPicker/createDirectory');
        expect(call.body['method'], 'directoryPicker/createDirectory');
        expect(call.body['payload'], {
          'args': {
            'path': '/Users/me/Projects',
            'name': 'new',
          },
        });
      },
    );
  });

  group('directoryPicker capability detection', () {
    test(
      'probeDirectoryPickerKind returns native when pick succeeds',
      () async {
        final host = _ScriptedHost((_, envelope, _) {
          return _ok({'path': null}, envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        final svc = WorkspacesService(client);
        final kind = await svc.probeDirectoryPickerKind();

        expect(kind, DirectoryPickerKind.native);
        expect(svc.directoryPickerKind, DirectoryPickerKind.native);
      },
    );

    test(
      'probeDirectoryPickerKind returns browse when host rejects pick '
      'with directory-picker-unavailable {capability:browse}',
      () async {
        final host = _ScriptedHost((path, envelope, _) {
          if (path == '/api/directoryPicker/pick') {
            return _fail(
              'directory-picker-unavailable',
              'directoryPicker.pick needs the native capability; '
                  'the composed picker serves "browse"',
              {'capability': 'browse'},
              envelope['rpcId'] as String,
            );
          }
          return _ok(<String, dynamic>{}, envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        final svc = WorkspacesService(client);
        final kind = await svc.probeDirectoryPickerKind();

        expect(kind, DirectoryPickerKind.browse);
        expect(svc.directoryPickerKind, DirectoryPickerKind.browse);
      },
    );

    test(
      'probeDirectoryPickerKind returns native when host rejects list '
      'with directory-picker-unavailable {capability:native}',
      () async {
        // Both `pick` and `list` reject with the same `native` capability
        // hint; the first call determines the cached kind, the second call
        // is short-circuited.
        final host = _ScriptedHost((path, envelope, _) {
          return _fail(
            'directory-picker-unavailable',
            'directoryPicker.$path needs the browse capability; '
                'the composed picker serves "native"',
            {'capability': 'native'},
            envelope['rpcId'] as String,
          );
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        final svc = WorkspacesService(client);
        final kind = await svc.probeDirectoryPickerKind();
        expect(kind, DirectoryPickerKind.native);
        expect(svc.directoryPickerKind, DirectoryPickerKind.native);
      },
    );

    test(
      'listDirectory surfaces RemoteMethodException for cross-kind host',
      () async {
        final host = _ScriptedHost((path, envelope, _) {
          if (path == '/api/directoryPicker/pick') {
            return _ok({'path': null}, envelope['rpcId'] as String);
          }
          if (path == '/api/directoryPicker/list') {
            return _fail(
              'directory-picker-unavailable',
              'directoryPicker.list needs the browse capability; '
                  'the composed picker serves "native"',
              {'capability': 'native'},
              envelope['rpcId'] as String,
            );
          }
          return _ok(<String, dynamic>{}, envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        final svc = WorkspacesService(client);
        Object? thrown;
        try {
          await svc.listDirectory();
        } on Object catch (e) {
          thrown = e;
        }

        expect(thrown, isA<RemoteMethodException>());
        final err = thrown! as RemoteMethodException;
        expect(err.code, RpcErrorCode.directoryPickerUnavailable);
        expect(err.details['capability'], 'native');
        expect(svc.directoryPickerKind, DirectoryPickerKind.native);
      },
    );

    test(
      'createDirectory surfaces RemoteMethodException for cross-kind host',
      () async {
        final host = _ScriptedHost((path, envelope, _) {
          if (path == '/api/directoryPicker/pick') {
            return _ok({'path': null}, envelope['rpcId'] as String);
          }
          if (path == '/api/directoryPicker/createDirectory') {
            return _fail(
              'directory-picker-unavailable',
              'directoryPicker.createDirectory needs the browse capability; '
                  'the composed picker serves "native"',
              {'capability': 'native'},
              envelope['rpcId'] as String,
            );
          }
          return _ok(<String, dynamic>{}, envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        final svc = WorkspacesService(client);
        Object? thrown;
        try {
          await svc.createDirectory(path: '/Users/me', name: 'new');
        } on Object catch (e) {
          thrown = e;
        }

        expect(thrown, isA<RemoteMethodException>());
        final err = thrown! as RemoteMethodException;
        expect(err.code, RpcErrorCode.directoryPickerUnavailable);
        expect(err.details['capability'], 'native');
      },
    );

    test(
      'probe is cached — second call does not re-issue pick',
      () async {
        var pickCalls = 0;
        final host = _ScriptedHost((path, envelope, _) {
          if (path == '/api/directoryPicker/pick') {
            pickCalls++;
            return _ok({'path': null}, envelope['rpcId'] as String);
          }
          return _ok(<String, dynamic>{}, envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        final svc = WorkspacesService(client);
        await svc.probeDirectoryPickerKind();
        await svc.probeDirectoryPickerKind();
        await svc.probeDirectoryPickerKind();

        expect(pickCalls, 1);
      },
    );

    test(
      'invalidateDirectoryPickerKind forces a re-probe',
      () async {
        var pickCalls = 0;
        final host = _ScriptedHost((path, envelope, _) {
          if (path == '/api/directoryPicker/pick') {
            pickCalls++;
            return _ok({'path': null}, envelope['rpcId'] as String);
          }
          return _ok(<String, dynamic>{}, envelope['rpcId'] as String);
        });
        final client = ConnectionClient(baseUrl: await host.start());
        addTearDown(client.dispose);
        addTearDown(host.stop);

        final svc = WorkspacesService(client);
        await svc.probeDirectoryPickerKind();
        svc.invalidateDirectoryPickerKind();
        await svc.probeDirectoryPickerKind();

        expect(pickCalls, 2);
      },
    );

    test('RemoteTarget probe returns browse without network call (remote-capable)', () async {
      var pickCalls = 0;
      final host = _ScriptedHost((path, envelope, _) {
        if (path == '/api/directoryPicker/pick') pickCalls++;
        return _ok({'path': null}, envelope['rpcId'] as String);
      });
      final baseUrl = await host.start();
      final remoteTarget = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'test-host-id-12345678',
        hostPublicKey: 'test-pub-key',
        deviceId: 'device-1',
        displayName: 'Test Device',
      );
      final client = ConnectionClient.fromTarget(remoteTarget);
      // Override baseUrl for test host binding
      final clientForTest = ConnectionClient(
        baseUrl: baseUrl,
        target: remoteTarget,
      );
      addTearDown(client.dispose);
      addTearDown(clientForTest.dispose);
      addTearDown(host.stop);

      final svc = WorkspacesService(clientForTest);
      final kind = await svc.probeDirectoryPickerKind();

      expect(kind, DirectoryPickerKind.browse);
      expect(svc.directoryPickerKind, DirectoryPickerKind.browse);
      // No network call should have been made for remote
      expect(pickCalls, 0);
    });

    test('LocalTarget probe uses native capability when host returns pick success', () async {
      final host = _ScriptedHost((path, envelope, _) {
        return _ok({'path': '/Users/me'}, envelope['rpcId'] as String);
      });
      final client = ConnectionClient(baseUrl: await host.start());
      addTearDown(client.dispose);
      addTearDown(host.stop);

      final svc = WorkspacesService(client);
      // isRemote should be false for local
      expect(client.isRemote, isFalse);
      final kind = await svc.probeDirectoryPickerKind();
      expect(kind, DirectoryPickerKind.native);
    });
  });
}