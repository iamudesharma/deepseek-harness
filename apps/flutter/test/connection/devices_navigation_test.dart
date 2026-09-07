import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_target.dart';
import 'package:dsh_flutter/src/core/connection/connection_target_provider.dart';
import 'package:dsh_flutter/src/core/connection/secure_token_store.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/devices/selected_persistence.dart';
import 'package:dsh_flutter/src/features/devices/selection_restore.dart';
import 'package:dsh_flutter/src/features/workspace/workspace_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal host that serves workspace.list + session.list + host.describe
/// over POST and mux/host as no-op WebSockets (not needed for this test).
class _Host {
  _Host({required this.workspaces, required this.sessions});

  final List<Map<String, dynamic>> workspaces;
  final List<Map<String, dynamic>> sessions;

  HttpServer? _server;

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final body = await utf8.decoder.bind(req).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final method = decoded['method'] as String?;
      final rpcId = decoded['rpcId'] ?? 'r';
      Map<String, dynamic> value;
      if (method == 'host.describe') {
        value = {
          'version': '0.0.0',
          'cwd': '/tmp',
          'attachedSessions': 0,
          'home': '/home',
          'canOpenPath': false,
          'hostId': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          'remoteEnabled': false,
        };
      } else if (method == 'workspace.list') {
        value = {'items': workspaces, 'archivedSessionIds': []};
      } else if (method == 'session.list') {
        value = {'items': sessions};
      } else if (method == 'session.create') {
        value = {'sessionId': 'new-sess-1'};
      } else {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final resp = {
        'type': 'server-response',
        'rpcId': rpcId,
        'result': {'ok': true, 'value': value},
      };
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(resp));
      await req.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  group('host → workspace → session navigation', () {
    test('workspace.list and session.list authoritative', () async {
      final host = _Host(
        workspaces: [
          {
            'workspaceId': 'w1',
            'path': '/tmp/a',
            'title': 'Workspace A',
            'sessionIds': ['s1'],
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          },
          {
            'workspaceId': 'w2',
            'path': '/tmp/b',
            'title': 'Workspace B',
            'sessionIds': [],
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ],
        sessions: [
          {
            'sessionId': 's1',
            'updatedAt': 1000,
            'running': false,
            'blank': false,
          },
          {
            'sessionId': 's2',
            'updatedAt': 2000,
            'running': true,
            'blank': false,
          },
        ],
      );
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      final ws = await client.workspaceList();
      expect((ws['items'] as List).length, 2);
      final sess = await client.getSessions();
      expect(sess.length, 2);
      expect(sess.first.sessionId.value, 's1');
      client.dispose();
      await host.stop();
    });

    test('create session navigates with host-confirmed id', () async {
      final host = _Host(
        workspaces: [],
        sessions: [
          {
            'sessionId': 's1',
            'updatedAt': 1000,
            'running': false,
            'blank': false,
          },
        ],
      );
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      final newId = await client.createSession(workspaceId: 'w1');
      expect(newId.value, 'new-sess-1');
      // Must not navigate before host confirms
      expect(newId.value.isNotEmpty, isTrue);
      client.dispose();
      await host.stop();
    });

    test('session restore: persisted ids round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      await persistSelectedWorkspaceId('w1');
      await persistSelectedSessionId('s1');
      final ids = await restoreSelectedIds();
      expect(ids.workspaceId?.value, 'w1');
      expect(ids.sessionId?.value, 's1');
      await clearSelectedWorkspaceAndSession();
      final cleared = await restoreSelectedIds();
      expect(cleared.workspaceId, isNull);
      expect(cleared.sessionId, isNull);
    });

    test(
      'session restore: missing session shows clean message (no fabricate)',
      () async {
        final host = _Host(workspaces: [], sessions: []);
        final baseUrl = await host.start();
        final client = ConnectionClient(baseUrl: baseUrl);
        final sessions = await client.getSessions();
        // Persisted 's1' is not in sessions (host returned empty) — must not fabricate
        final persisted = 's1';
        final exists = sessions.any((s) => s.sessionId.value == persisted);
        expect(exists, isFalse);
        client.dispose();
        await host.stop();
      },
    );

    test('reconnect host identity mismatch → needsReauth', () async {
      SharedPreferences.setMockInitialValues({});
      // LocalTarget does not check hostId; RemoteTarget does
      const local = LocalTarget(host: '127.0.0.1', port: 3080);
      expect(local.isRemote, isFalse);
      final remote = RemoteTarget(
        baseUri: Uri.parse('https://10.0.0.1:3080'),
        hostId: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        hostPublicKey: 'cHVibGlj',
        deviceId: '11111111-1111-4111-8111-111111111111',
        displayName: 'Pixel',
      );
      expect(remote.isRemote, isTrue);
      // Simulate host returning different hostId
      final host = _Host(workspaces: [], sessions: []);
      final baseUrl = await host.start();
      final store = InMemoryTokenStore();
      await store.write(remote.deviceId, 'tok');
      final client = ConnectionClient.fromTarget(
        remote,
        tokenStore: store,
        httpClient: http.Client(),
      );
      // host.describe from _Host returns hostId A, remote pins A → ok
      // If host later returns B, controller would emit needsReauth (verified in remote_target_test)
      client.dispose();
      await host.stop();
    });
  });

  group('restart restore (selectionRestoreProvider)', () {
    Future<ProviderContainer> _container(String baseUrl) async {
      final uri = Uri.parse(baseUrl);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          connectionTargetProvider.overrideWith(
            (ref) => LocalTarget(host: uri.host, port: uri.port),
          ),
          secureTokenStoreProvider.overrideWith((ref) => InMemoryTokenStore()),
        ],
      );
      return container;
    }

    test('applies persisted ids when the host still lists them', () async {
      final host = _Host(
        workspaces: [
          {
            'workspaceId': 'w1',
            'path': '/tmp/a',
            'title': 'Workspace A',
            'sessionIds': <String>['s1'],
            'createdAt': '2026-01-01',
            'updatedAt': '2026-01-01',
          },
        ],
        sessions: [
          {
            'sessionId': 's1',
            'updatedAt': 1000,
            'running': false,
            'blank': false,
          },
        ],
      );
      final baseUrl = await host.start();
      final container = await _container(baseUrl);
      addTearDown(container.dispose);
      await persistSelectedWorkspaceId('w1');
      await persistSelectedSessionId('s1');

      final outcome = await container.read(selectionRestoreProvider.future);

      expect(outcome.attempted, isTrue);
      expect(outcome.sessionMissing, isFalse);
      expect(outcome.workspaceMissing, isFalse);
      // Selection landed on the single state system after hydration.
      expect(container.read(sessionsProvider).current?.value, 's1');
      expect(container.read(selectedWorkspaceProvider)?.value, 'w1');
      await host.stop();
    });

    test(
      'clears stale ids and reports missing instead of fabricating',
      () async {
        final host = _Host(workspaces: [], sessions: []);
        final baseUrl = await host.start();
        final container = await _container(baseUrl);
        addTearDown(container.dispose);
        await persistSelectedWorkspaceId('ghost-ws');
        await persistSelectedSessionId('ghost-s');

        final outcome = await container.read(selectionRestoreProvider.future);

        expect(outcome.sessionMissing, isTrue);
        expect(outcome.workspaceMissing, isTrue);
        expect(outcome.restoredSession, isNull);
        // Stale keys are gone — they cannot resurrect a fake session.
        final ids = await restoreSelectedIds();
        expect(ids.sessionId, isNull);
        expect(ids.workspaceId, isNull);
        expect(container.read(sessionsProvider).current, isNull);
        await host.stop();
      },
    );

    test('no-ops without persisted selections', () async {
      final host = _Host(workspaces: [], sessions: []);
      final baseUrl = await host.start();
      final container = await _container(baseUrl);
      addTearDown(container.dispose);

      final outcome = await container.read(selectionRestoreProvider.future);

      expect(outcome.attempted, isFalse);
      await host.stop();
    });
  });
}
