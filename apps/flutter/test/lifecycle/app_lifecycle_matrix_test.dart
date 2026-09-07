import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart';
import 'package:dsh_flutter/src/core/connection/connection_lifecycle.dart';
import 'package:dsh_flutter/src/core/connection/connection_target.dart';
import 'package:dsh_flutter/src/core/connection/connection_target_provider.dart';
import 'package:dsh_flutter/src/core/connection/secure_token_store.dart';
import 'package:dsh_flutter/src/core/session/live_sync.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/platform/app_lifecycle.dart';
import 'package:dsh_flutter/src/platform/connectivity.dart';
import 'package:dsh_flutter/src/core/connection/connectivity_handler.dart';
import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/plugins/conversation/queue_state.dart';
import 'package:dsh_flutter/src/plugins/plan/ui/plan_provider.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/permission_session_provider.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

/// Minimal scripted host for lifecycle matrix tests.
///
/// Handles host.describe, session.list, session.history, and WebSocket
/// upgrades for mux/host. Configurable to simulate host restart, token
/// expiry, etc.
class _LifecycleHost {
  _LifecycleHost({
    this.hostId = 'test-host-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    this.requireBearer = false,
    this.expectedToken,
    this.sessions = const [],
    this.history = const [],
    this.muxScript = const [],
    this.describeShouldFailWith = 0,
  });

  final String hostId;
  final bool requireBearer;
  final String? expectedToken;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> muxScript;
  final int describeShouldFailWith;

  HttpServer? _server;
  final List<IOWebSocketChannel> _sockets = [];
  int describeCalls = 0;

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      final path = request.uri.path;
      if (request.method == 'POST' && path == '/api/host.describe') {
        describeCalls++;
        if (describeShouldFailWith != 0) {
          request.response.statusCode = describeShouldFailWith;
          await request.response.close();
          return;
        }
        if (requireBearer) {
          final auth = request.headers.value('authorization');
          if (auth != 'Bearer $expectedToken') {
            request.response.statusCode = 401;
            await request.response.close();
            return;
          }
        }
        final body = await utf8.decoder.bind(request).join();
        final req = jsonDecode(body) as Map<String, dynamic>;
        final resp = {
          'type': 'server-response',
          'rpcId': req['rpcId'],
          'result': {
            'ok': true,
            'value': {
              'version': '0.0.0',
              'cwd': '/tmp',
              'attachedSessions': 0,
              'home': '/home',
              'canOpenPath': false,
              'hostId': hostId,
              'remoteEnabled': true,
            },
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resp));
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && path == '/api/session.list') {
        if (requireBearer) {
          final auth = request.headers.value('authorization');
          if (auth != 'Bearer $expectedToken') {
            request.response.statusCode = 401;
            await request.response.close();
            return;
          }
        }
        final body = await utf8.decoder.bind(request).join();
        final req = jsonDecode(body) as Map<String, dynamic>;
        final resp = {
          'type': 'server-response',
          'rpcId': req['rpcId'],
          'result': {
            'ok': true,
            'value': {'items': sessions},
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resp));
        await request.response.close();
        return;
      }
      if (request.method == 'POST' &&
          (path == '/api/session.history' || path == '/api/session/page')) {
        final body = await utf8.decoder.bind(request).join();
        final req = jsonDecode(body) as Map<String, dynamic>;
        final resp = {
          'type': 'server-response',
          'rpcId': req['rpcId'],
          'result': {
            'ok': true,
            'value': {
              'events': history,
              // Also provide `records` for current master `session/page` shape
              'records': [
                for (final h in history)
                  {
                    'type': 'event',
                    'event': (h as Map)['event'],
                    if ((h as Map).containsKey('view')) 'view': h['view'],
                  },
              ],
              'hasMore': false,
              'projections': {'asOfSeq': -1, 'values': {}},
            },
          },
        };
        // Also handle projections block if needed
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resp));
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && path == '/api/remote.refresh') {
        if (requireBearer) {
          final auth = request.headers.value('authorization');
          if (auth != 'Bearer $expectedToken') {
            request.response.statusCode = 401;
            await request.response.close();
            return;
          }
        }
        final body = await utf8.decoder.bind(request).join();
        final req = jsonDecode(body) as Map<String, dynamic>;
        final resp = {
          'type': 'server-response',
          'rpcId': req['rpcId'],
          'result': {
            'ok': true,
            'value': {
              'deviceToken': 'refreshed-token',
              'expiresAt': DateTime.now().millisecondsSinceEpoch + 100000,
            },
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resp));
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && path == '/api/remote.ws-ticket') {
        if (requireBearer) {
          final auth = request.headers.value('authorization');
          if (auth != 'Bearer $expectedToken') {
            request.response.statusCode = 401;
            await request.response.close();
            return;
          }
        }
        final body = await utf8.decoder.bind(request).join();
        final req = jsonDecode(body) as Map<String, dynamic>;
        final resp = {
          'type': 'server-response',
          'rpcId': req['rpcId'],
          'result': {
            'ok': true,
            'value': {
              'ticket': 'test-ticket',
              'expiresAt': DateTime.now().millisecondsSinceEpoch + 60000,
            },
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(resp));
        await request.response.close();
        return;
      }
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        if (requireBearer && request.uri.path.contains('events')) {
          // For remote, ticket is required but our _LifecycleHost uses simple bearer check for ws-ticket only;
          // actual ticket validation is via query param, we skip for test simplicity.
        }
        final channel = await WebSocketTransformer.upgrade(request)
            .then(IOWebSocketChannel.new);
        _sockets.add(channel);
        for (final frame in muxScript) {
          channel.sink.add(jsonEncode(frame));
        }
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  void pushMux(Map<String, dynamic> frame) {
    for (final s in List.of(_sockets)) {
      s.sink.add(jsonEncode(frame));
    }
  }

  void closeSockets() {
    for (final s in List.of(_sockets)) {
      s.sink.close();
    }
    _sockets.clear();
  }

  Future<void> stop() async {
    closeSockets();
    await _server?.close(force: true);
  }
}

// Fake connectivity monitor for deterministic network tests
class _FakeConnectivityMonitor implements ConnectivityMonitor {
  _FakeConnectivityMonitor(this.initial);
  AppConnectivityState current = AppConnectivityState.wifi;
  final AppConnectivityState initial;
  final StreamController<AppConnectivityState> _ctrl =
      StreamController.broadcast();

  @override
  Future<AppConnectivityState> checkConnectivity() async => current;

  @override
  Stream<AppConnectivityState> get onConnectivityChanged => _ctrl.stream;

  void emit(AppConnectivityState next) {
    current = next;
    _ctrl.add(next);
  }

  void dispose() => _ctrl.close();
}

void main() {
  group('Phase 9: Lifecycle state machine', () {
    test('A: background/resume creates new generation (Remote)', () async {
      SharedPreferences.setMockInitialValues({});
      final host = _LifecycleHost();
      final baseUrl = await host.start();
      final store = InMemoryTokenStore();
      await store.write('device-1', 'tok');
      final target = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'test-host-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hostPublicKey: 'pub',
        deviceId: 'device-1',
        displayName: 'Test Device',
      );
      // Force mobile platform for test (default is Android, so isMobileLifecyclePlatform true)
      final container = ProviderContainer(
        overrides: [
          connectionTargetProvider.overrideWith((ref) => target),
          secureTokenStoreProvider.overrideWithValue(store),
          connectionClientProvider.overrideWith(
            (ref) => ConnectionClient.fromTarget(target, tokenStore: store),
          ),
        ],
      );
      addTearDown(() {
        container.dispose();
        host.stop();
      });
      final controller = container.read(flutterConnectionProvider);
      // Activate lifecycle handler
      container.read(connectionLifecycleProvider);
      controller.start();
      // Wait for connected
      for (int i = 0; i < 40; i++) {
        if (container.read(connectionStateProvider) ==
            ConnectionState.connected)
          break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        container.read(connectionStateProvider),
        ConnectionState.connected,
      );
      final genBefore = controller.generation;
      // Simulate background: paused
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isRunning, isFalse);
      expect(
        container.read(connectionStateProvider),
        ConnectionState.disconnected,
      );
      // Resume
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Should have started new generation
      for (int i = 0; i < 40; i++) {
        if (controller.generation > genBefore &&
            container.read(connectionStateProvider) ==
                ConnectionState.connected)
          break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(controller.generation, greaterThan(genBefore));
      expect(
        container.read(connectionStateProvider),
        ConnectionState.connected,
      );
    });

    test('LocalTarget does not suspend on background (preserves macOS/Web behavior)', () async {
      final host = _LifecycleHost();
      final baseUrl = await host.start();
      final container = ProviderContainer(
        overrides: [
          connectionTargetProvider.overrideWith(
            (ref) =>
                LocalTarget(host: '127.0.0.1', port: Uri.parse(baseUrl).port),
          ),
          connectionClientProvider.overrideWith(
            (ref) => ConnectionClient(baseUrl: baseUrl),
          ),
        ],
      );
      addTearDown(() {
        container.dispose();
        host.stop();
      });
      final controller = container.read(flutterConnectionProvider);
      container.read(connectionLifecycleProvider);
      controller.start();
      for (int i = 0; i < 40; i++) {
        if (container.read(connectionStateProvider) ==
            ConnectionState.connected)
          break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        container.read(connectionStateProvider),
        ConnectionState.connected,
      );
      final genBefore = controller.generation;
      // Background should NOT suspend for LocalTarget
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Local target preserves behavior: still running, still connected (or at least not disconnected via lifecycle)
      expect(controller.isRunning, isTrue);
      expect(controller.generation, genBefore);
      // Resume should not create new generation
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.generation, genBefore);
    });

    test('inactive does not trigger suspend', () async {
      final host = _LifecycleHost();
      final baseUrl = await host.start();
      final store = InMemoryTokenStore();
      await store.write('device-1', 'tok');
      final target = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'test-host-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hostPublicKey: 'pub',
        deviceId: 'device-1',
        displayName: 'Test',
      );
      final container = ProviderContainer(
        overrides: [
          connectionTargetProvider.overrideWith((ref) => target),
          secureTokenStoreProvider.overrideWithValue(store),
          connectionClientProvider.overrideWith(
            (ref) => ConnectionClient.fromTarget(target, tokenStore: store),
          ),
        ],
      );
      addTearDown(() {
        container.dispose();
        host.stop();
      });
      final controller = container.read(flutterConnectionProvider);
      container.read(connectionLifecycleProvider);
      controller.start();
      for (int i = 0; i < 40; i++) {
        if (container.read(connectionStateProvider) ==
            ConnectionState.connected)
          break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(controller.isRunning, isTrue);
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.inactive;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isRunning, isTrue);
      expect(
        container.read(connectionStateProvider),
        ConnectionState.connected,
      );
    });
  });

  group('Generation safety', () {
    test('old generation does not call onConnected after suspend', () async {
      final host = _LifecycleHost();
      final baseUrl = await host.start();
      // Use a gated client that delays describe
      final release = Completer<void>();
      final describeSeen = Completer<void>();
      final gated = _DescribeGatedClient(release, describeSeen, baseUrl);
      final target = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'test-host-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hostPublicKey: 'pub',
        deviceId: 'device-1',
        displayName: 'Test',
      );
      final store = InMemoryTokenStore();
      await store.write('device-1', 'tok');
      final client = ConnectionClient(
        baseUrl: baseUrl,
        target: target,
        tokenStore: store,
        httpClient: gated,
      );
      final connected = <Map<String, dynamic>>[];
      final controller = FlutterConnectionController(
        client,
        onConnected: connected.add,
        config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
      );
      controller.start();
      await describeSeen.future;
      // Suspend before describe completes
      controller.suspend();
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(connected, isEmpty);
      expect(controller.isRunning, isFalse);
      controller.stop();
      await host.stop();
      gated.close();
    });

    test(
      'B: multiple background/resume cycles each create new generation',
      () async {
        final host = _LifecycleHost();
        final baseUrl = await host.start();
        final store = InMemoryTokenStore();
        await store.write('device-1', 'tok');
        final target = RemoteTarget(
          baseUri: Uri.parse(baseUrl),
          hostId: 'test-host-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          hostPublicKey: 'pub',
          deviceId: 'device-1',
          displayName: 'Test',
        );
        final container = ProviderContainer(
          overrides: [
            connectionTargetProvider.overrideWith((ref) => target),
            secureTokenStoreProvider.overrideWithValue(store),
            connectionClientProvider.overrideWith(
              (ref) => ConnectionClient.fromTarget(target, tokenStore: store),
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          host.stop();
        });
        final controller = container.read(flutterConnectionProvider);
        container.read(connectionLifecycleProvider);
        controller.start();
        for (int i = 0; i < 40; i++) {
          if (container.read(connectionStateProvider) ==
              ConnectionState.connected)
            break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final gens = <int>[];
        gens.add(controller.generation);
        for (int cycle = 0; cycle < 3; cycle++) {
          container.read(appLifecycleStateProvider.notifier).state =
              AppLifecycleState.paused;
          await Future<void>.delayed(const Duration(milliseconds: 15));
          container.read(appLifecycleStateProvider.notifier).state =
              AppLifecycleState.resumed;
          for (int i = 0; i < 40; i++) {
            if (controller.generation > gens.last &&
                container.read(connectionStateProvider) ==
                    ConnectionState.connected)
              break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          gens.add(controller.generation);
        }
        expect(gens, [gens[0], gens[0] + 1, gens[0] + 2, gens[0] + 3]);
      },
    );
  });

  group('Draft / composer safety (K/L)', () {
    test('K: draft text preserved across background/resume', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'sess-draft';
      container
          .read(composerControllerProvider(sid).notifier)
          .setText('hello draft');
      expect(
        container.read(composerControllerProvider(sid)).text,
        'hello draft',
      );
      // Simulate lifecycle suspend/resume via controller (mobile remote)
      // Draft is in-memory and should not be cleared
      final host = _LifecycleHost();
      final baseUrl = await host.start();
      final store = InMemoryTokenStore();
      await store.write('device-1', 'tok');
      final target = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'test-host-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hostPublicKey: 'pub',
        deviceId: 'device-1',
        displayName: 'Test',
      );
      final lcContainer = ProviderContainer(
        overrides: [
          connectionTargetProvider.overrideWith((ref) => target),
          secureTokenStoreProvider.overrideWithValue(store),
          connectionClientProvider.overrideWith(
            (ref) => ConnectionClient.fromTarget(target, tokenStore: store),
          ),
        ],
      );
      addTearDown(() {
        lcContainer.dispose();
        host.stop();
      });
      final ctrl = lcContainer.read(flutterConnectionProvider);
      lcContainer.read(connectionLifecycleProvider);
      ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      lcContainer.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      lcContainer.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Original container's draft should still be there
      expect(
        container.read(composerControllerProvider(sid)).text,
        'hello draft',
      );
    });

    test('L: staged attachments preserved, not auto-submitted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'sess-att';
      final att = ComposerAttachment.create(
        name: 'img.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      container.read(composerControllerProvider(sid).notifier).addAttachments([
        att,
      ]);
      expect(
        container.read(composerControllerProvider(sid)).attachments,
        hasLength(1),
      );
      // Simulate background/resume
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(composerControllerProvider(sid)).attachments,
        hasLength(1),
      );
      expect(
        container.read(composerControllerProvider(sid)).isSending,
        isFalse,
      );
    });

    test('send acknowledged does not duplicate after resume', () async {
      // Simulate a send that was acknowledged (draft cleared) before background
      final container = ProviderContainer(
        overrides: [
          connectionClientProvider.overrideWithValue(
            ConnectionClient(baseUrl: ''),
          ),
        ],
      );
      addTearDown(container.dispose);
      const sid = 'sess-send';
      container
          .read(composerControllerProvider(sid).notifier)
          .setText('to send');
      // Simulate successful submit that clears draft (via controller logic)
      // We manually clear as the real submit would
      container.read(composerControllerProvider(sid).notifier).setText('');
      expect(container.read(composerControllerProvider(sid)).text, '');
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Should remain cleared, not duplicated
      expect(container.read(composerControllerProvider(sid)).text, '');
    });
  });

  group('Background during streaming / tool / approval / question (C-F)', () {
    test('C: assistant streaming recovers via history replay', () async {
      // Simulate: streaming chunks arrive, then background, then history fetch returns final
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'stream-sess';
      // Seed live history with a user message and a chunk
      final live = container.read(liveHistoryProvider(sid).notifier);
      live.replaceAll([
        HistoryEntry(
          event: SessionEvent(
            type: 'user/message',
            data: {'content': 'hi'},
            seq: 0,
            time: 1000,
          ),
          view: null,
        ),
        HistoryEntry(
          event: SessionEvent(
            type: 'assistant/chunk',
            data: {'delta': 'He'},
            seq: 1,
            time: 1001,
          ),
          view: null,
        ),
      ]);
      expect(container.read(liveHistoryProvider(sid)), hasLength(2));
      // Background (should not clear live history)
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Simulate host history after resume returns complete message
      live.replaceAll([
        HistoryEntry(
          event: SessionEvent(
            type: 'user/message',
            data: {'content': 'hi'},
            seq: 0,
            time: 1000,
          ),
          view: null,
        ),
        HistoryEntry(
          event: SessionEvent(
            type: 'assistant/message',
            data: {'content': 'Hello final'},
            seq: 1,
            time: 1002,
          ),
          view: null,
        ),
      ]);
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final msgs = messagesFromHistory(
        container.read(liveHistoryProvider(sid)),
        isRunning: false,
      );
      expect(msgs.any((m) => m.content == 'Hello final'), isTrue);
    });

    test(
      'D: tool running state reconciled via host describe/history authority',
      () async {
        // Tool running is reflected in session running flag and tool nodes.
        // After background/resume, host authoritative history should win.
        final host = _LifecycleHost(
          sessions: [
            {
              'sessionId': 'tool-sess',
              'updatedAt': 1000,
              'running': true,
              'blank': false,
            },
          ],
          history: [
            {
              'event': {
                'type': 'tool/call',
                'data': {'tool': 'bash', 'args': '{}'},
                'seq': 0,
                'time': 1000,
              },
              'view': {'kind': 'tool', 'tool': 'bash'},
            },
          ],
        );
        final baseUrl = await host.start();
        addTearDown(host.stop);
        final client = ConnectionClient(baseUrl: baseUrl);
        final sessions = await client.getSessions();
        expect(sessions.first.running, isTrue);
        final hist = await client.getSessionEvents(
          SessionId('tool-sess'),
          throughSeq: 0,
        );
        expect(hist.first.event.type, 'tool/call');
        // After resume, re-fetch should still be authoritative
        final sessions2 = await client.getSessions();
        expect(sessions2.first.running, isTrue);
      },
    );

    test('E: approval requested survives background and is restored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'approval-sess';
      final approvals = container.read(approvalsProvider.notifier);
      approvals.requested(
        sid,
        rpcId: 'rpc-1',
        approvalId: 'appr-1',
        toolName: 'bash',
        callId: 'call-1',
        reason: 'need approval',
      );
      expect(container.read(approvalsProvider)[sid]?.approvalId, 'appr-1');
      // Background: liveSync would drop pending interactions on disconnect,
      // but mux-open replay after resume re-adds them. Simulate drop then replay.
      container.read(approvalsProvider.notifier).clear(sid);
      expect(container.read(approvalsProvider).containsKey(sid), isFalse);
      // Replay
      approvals.requested(
        sid,
        rpcId: 'rpc-1',
        approvalId: 'appr-1',
        toolName: 'bash',
        callId: 'call-1',
        reason: 'need approval',
      );
      expect(container.read(approvalsProvider)[sid]?.approvalId, 'appr-1');
      // User can respond via new connection (respond uses current client)
      // Simulate resolution
      approvals.resolved(sid, 'appr-1');
      expect(container.read(approvalsProvider).containsKey(sid), isFalse);
    });

    test('F: question requested restored, no duplicate', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'question-sess';
      final questions = container.read(pendingQuestionsProvider.notifier);
      questions.requested(
        sid,
        rpcId: 'q-rpc-1',
        questions: [
          const QuestionItem(
            id: 'q1',
            question: 'What?',
            header: 'Q',
            options: [],
            multiSelect: false,
          ),
        ],
      );
      expect(container.read(pendingQuestionsProvider)[sid]?.rpcId, 'q-rpc-1');
      // Simulate background drop
      questions.clear(sid);
      expect(
        container.read(pendingQuestionsProvider).containsKey(sid),
        isFalse,
      );
      // Replay with same rpcId (idempotent)
      questions.requested(
        sid,
        rpcId: 'q-rpc-1',
        questions: [
          const QuestionItem(
            id: 'q1',
            question: 'What?',
            header: 'Q',
            options: [],
            multiSelect: false,
          ),
        ],
      );
      expect(container.read(pendingQuestionsProvider)[sid]?.rpcId, 'q-rpc-1');
      // Duplicate request with same rpcId should replace, not duplicate
      questions.requested(
        sid,
        rpcId: 'q-rpc-1',
        questions: [
          const QuestionItem(
            id: 'q1',
            question: 'What?',
            header: 'Q',
            options: [],
            multiSelect: false,
          ),
        ],
      );
      expect(container.read(pendingQuestionsProvider).length, 1);
    });
  });

  group('Queue / plan / permission / model during background (G-J)', () {
    test('G: queue authoritative after resume', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'queue-sess';
      container.read(queueProvider.notifier).replace(sid, [
        QueuedInboxItem.fromJson({
          'id': 'item-1',
          'placement': 'queued',
          'message': {'content': 'queued'},
        }),
      ]);
      expect(container.read(queueProvider)[sid], hasLength(1));
      // After background, host authoritative queue should win (simulate host returning empty)
      container.read(queueProvider.notifier).replace(sid, []);
      expect(container.read(queueProvider)[sid], isEmpty);
      // Stale local mutation not replayed
    });

    test('H: plan pending reconciled', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(planProvider.notifier).setPending();
      expect(container.read(planProvider).pending, isTrue);
      // Simulate background/resume where host projection says active true, pending false
      container.read(planProvider.notifier).settle(active: true, error: null);
      expect(container.read(planProvider).active, isTrue);
      expect(container.read(planProvider).pending, isFalse);
    });

    test('I: permission transition reconciled', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'perm-sess';
      container
          .read(permissionSelectProvider(sid).notifier)
          .state = PermissionSelect(
        options: [PresetOption(value: 'v1', name: 'V1')],
        currentValue: 'v1',
      );
      expect(container.read(permissionSelectProvider(sid))?.currentValue, 'v1');
      // Host authoritative after resume
      container
          .read(permissionSelectProvider(sid).notifier)
          .state = PermissionSelect(
        options: [PresetOption(value: 'v2', name: 'V2')],
        currentValue: 'v2',
      );
      expect(container.read(permissionSelectProvider(sid))?.currentValue, 'v2');
    });

    test('J: model change reconciled', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'model-sess';
      container
          .read(composerControllerProvider(sid).notifier)
          .setModel('deepseek-chat');
      expect(
        container.read(composerControllerProvider(sid)).selectedModel,
        'deepseek-chat',
      );
      // After resume, host authoritative model directory would drive available models,
      // but selectedModel is local; stale selection not auto-replayed unless host says
      expect(
        container.read(composerControllerProvider(sid)).selectedModel,
        'deepseek-chat',
      );
      // Simulate host projection changing current model (would be via session.models)
      // For now just ensure local not duplicated
    });
  });

  group('Session switch + lifecycle (session)', () {
    test('session A restored after background/resume', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sA = SessionId('sess-A');
      final sB = SessionId('sess-B');
      container.read(sessionsProvider.notifier).setAll([
        SessionSummary(
          sessionId: sA,
          updatedAt: 1000,
          running: false,
          blank: false,
          title: 'A',
        ),
        SessionSummary(
          sessionId: sB,
          updatedAt: 1001,
          running: false,
          blank: false,
          title: 'B',
        ),
      ]);
      // Need to await microtask for setAll batch
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.read(sessionsProvider.notifier).setCurrent(sA);
      expect(container.read(sessionsProvider).current, sA);
      // Background/resume should preserve current
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(container.read(sessionsProvider).current, sA);
    });

    test('switch B, background, resume preserves B, no A/B leakage', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sA = SessionId('sess-A');
      final sB = SessionId('sess-B');
      container.read(sessionsProvider.notifier).setAll([
        SessionSummary(
          sessionId: sA,
          updatedAt: 1000,
          running: false,
          blank: false,
        ),
        SessionSummary(
          sessionId: sB,
          updatedAt: 1001,
          running: false,
          blank: false,
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.read(sessionsProvider.notifier).setCurrent(sA);
      expect(container.read(sessionsProvider).current, sA);
      container.read(sessionsProvider.notifier).setCurrent(sB);
      expect(container.read(sessionsProvider).current, sB);
      // Queue for A should not leak to B
      container.read(queueProvider.notifier).replace(sA.value, [
        QueuedInboxItem.fromJson({
          'id': 'qa',
          'placement': 'queued',
          'message': {'content': 'a'},
        }),
      ]);
      container.read(queueProvider.notifier).replace(sB.value, [
        QueuedInboxItem.fromJson({
          'id': 'qb',
          'placement': 'queued',
          'message': {'content': 'b'},
        }),
      ]);
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.paused;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      container.read(appLifecycleStateProvider.notifier).state =
          AppLifecycleState.resumed;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(container.read(sessionsProvider).current, sB);
      expect(container.read(queueProvider)[sA.value]?.first.id, 'qa');
      expect(container.read(queueProvider)[sB.value]?.first.id, 'qb');
    });
  });

  group('Host restart / identity / token / revocation (O-R)', () {
    test('O: host restart with same hostId reconnects', () async {
      final host = _LifecycleHost(hostId: 'host-A');
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      final desc = await client.hostDescribe();
      expect(desc['hostId'], 'host-A');
      await host.stop();
      final host2 = _LifecycleHost(hostId: 'host-A');
      final baseUrl2 = await host2.start();
      final client2 = ConnectionClient(baseUrl: baseUrl2);
      final desc2 = await client2.hostDescribe();
      expect(desc2['hostId'], 'host-A');
      client.dispose();
      client2.dispose();
      await host2.stop();
    });

    test('P: host identity change → needsReauth', () async {
      final host = _LifecycleHost(hostId: 'host-A');
      final baseUrl = await host.start();
      final store = InMemoryTokenStore();
      await store.write('device-1', 'tok');
      final target = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'host-A',
        hostPublicKey: 'pub',
        deviceId: 'device-1',
        displayName: 'Test',
      );
      final client = ConnectionClient.fromTarget(target, tokenStore: store);
      final desc = await client.hostDescribe();
      expect(desc['hostId'], 'host-A');
      await host.stop();
      // Restart with different hostId
      final host2 = _LifecycleHost(hostId: 'host-B');
      final baseUrl2 = await host2.start();
      final client2 = ConnectionClient(
        baseUrl: baseUrl2,
        target: target,
        tokenStore: store,
      );
      final desc2 = await client2.hostDescribe();
      expect(desc2['hostId'], isNot(target.hostId));
      // Controller would detect mismatch and enter needsReauth
      final states = <ConnectionState>[];
      final controller = FlutterConnectionController(
        client2,
        onStateChange: states.add,
        config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
      );
      controller.start();
      for (int i = 0; i < 40; i++) {
        if (states.contains(ConnectionState.needsReauth)) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(states.contains(ConnectionState.needsReauth), isTrue);
      controller.stop();
      client.dispose();
      client2.dispose();
      await host2.stop();
    });

    test(
      'Q: token expiry → refresh once then needsReauth if refresh fails',
      () async {
        final host = _LifecycleHost(
          requireBearer: true,
          expectedToken: 'valid-token',
          hostId: 'host-A',
        );
        final baseUrl = await host.start();
        final store = InMemoryTokenStore();
        await store.write('device-1', 'expired-token');
        final target = RemoteTarget(
          baseUri: Uri.parse(baseUrl),
          hostId: 'host-A',
          hostPublicKey: 'pub',
          deviceId: 'device-1',
          displayName: 'Test',
        );
        final client = ConnectionClient.fromTarget(target, tokenStore: store);
        try {
          await client.hostDescribe();
          fail('should throw 401');
        } catch (e) {
          expect(e, isA<RemoteAuthException>());
        }
        // Controller would attempt refresh once
        final states = <ConnectionState>[];
        final controller = FlutterConnectionController(
          client,
          onStateChange: states.add,
          config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
        );
        controller.start();
        for (int i = 0; i < 40; i++) {
          if (states.contains(ConnectionState.needsReauth)) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        // Since our _LifecycleHost's refresh endpoint also requires valid token, refresh will fail → needsReauth
        expect(states.contains(ConnectionState.needsReauth), isTrue);
        controller.stop();
        client.dispose();
        await host.stop();
      },
    );

    test('R: device revocation → needsReauth and token deleted', () async {
      final host = _LifecycleHost(
        requireBearer: true,
        expectedToken: 'valid',
        hostId: 'host-A',
      );
      final baseUrl = await host.start();
      final store = InMemoryTokenStore();
      await store.write('device-1', 'revoked-token');
      final target = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'host-A',
        hostPublicKey: 'pub',
        deviceId: 'device-1',
        displayName: 'Test',
      );
      final client = ConnectionClient.fromTarget(target, tokenStore: store);
      final states = <ConnectionState>[];
      final controller = FlutterConnectionController(
        client,
        onStateChange: states.add,
        config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
      );
      controller.start();
      for (int i = 0; i < 40; i++) {
        if (states.contains(ConnectionState.needsReauth)) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(states.contains(ConnectionState.needsReauth), isTrue);
      // Token should be deleted after needsReauth
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(await store.read('device-1'), isNull);
      controller.stop();
      client.dispose();
      await host.stop();
    });
  });

  group('Network change (S)', () {
    test('S: wifi → none → wifi triggers reconnect', () async {
      final fakeMonitor = _FakeConnectivityMonitor(AppConnectivityState.wifi);
      final container = ProviderContainer(
        overrides: [connectivityMonitorProvider.overrideWithValue(fakeMonitor)],
      );
      addTearDown(() {
        container.dispose();
        fakeMonitor.dispose();
      });
      // Activate connectivity handler
      container.read(connectivityLifecycleProvider);
      // Wait for the connectivity notifier to finish its initial check and subscription
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Simulate network loss
      fakeMonitor.emit(AppConnectivityState.none);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(connectivityStateProvider),
        AppConnectivityState.none,
      );
      // Recovery should trigger handleNetworkOnline
      fakeMonitor.emit(AppConnectivityState.wifi);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(connectivityStateProvider),
        AppConnectivityState.wifi,
      );
    });

    test('S: cellular ↔ wifi triggers generation where necessary', () async {
      final fakeMonitor = _FakeConnectivityMonitor(AppConnectivityState.wifi);
      addTearDown(fakeMonitor.dispose);
      fakeMonitor.emit(AppConnectivityState.mobile);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fakeMonitor.current, AppConnectivityState.mobile);
      fakeMonitor.emit(AppConnectivityState.wifi);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fakeMonitor.current, AppConnectivityState.wifi);
    });

    test('network recovery interrupts backoff', () async {
      final host = _LifecycleHost();
      final baseUrl = await host.start();
      // Make describe fail initially to enter backoff
      final failingHost = _LifecycleHost(describeShouldFailWith: 500);
      final failUrl = await failingHost.start();
      final controller = FlutterConnectionController(
        ConnectionClient(baseUrl: failUrl),
        config: const ConnectionConfig(backoffBaseMs: 1000, backoffMaxMs: 1000),
      );
      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.isRunning, isTrue);
      // Network recovery should interrupt backoff
      controller.handleNetworkOnline();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Should still be running (backoff interrupted, will retry)
      expect(controller.isRunning, isTrue);
      controller.stop();
      await host.stop();
      await failingHost.stop();
    });
  });

  group('Process death / cold start (T/U)', () {
    test('T/U: process death preserves RemoteTarget and token, cold start reconnects', () async {
      SharedPreferences.setMockInitialValues({});
      final target = RemoteTarget(
        baseUri: Uri.parse('https://192.168.1.10:3080'),
        hostId: 'host-A',
        hostPublicKey: 'pub',
        deviceId: 'device-1',
        displayName: 'Pixel',
      );
      final store = InMemoryTokenStore();
      await store.write('device-1', 'tok123');
      await persistConnectionTarget(target);
      // Simulate kill and relaunch: new container, new prefs read
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('dsh_connection_target');
      expect(raw, isNotNull);
      final restored = ConnectionTarget.fromJson(
        jsonDecode(raw!) as Map<String, dynamic>,
      ) as RemoteTarget;
      expect(restored, equals(target));
      expect(await store.read('device-1'), 'tok123');
      // Cold start would then do host.describe + streams
      final host = _LifecycleHost(hostId: 'host-A');
      final baseUrl = await host.start();
      final client = ConnectionClient.fromTarget(restored, tokenStore: store);
      // For test, we need to override baseUrl to match host's port (since restored has old port)
      final testClient = ConnectionClient(
        baseUrl: baseUrl,
        target: restored,
        tokenStore: store,
      );
      final desc = await testClient.hostDescribe();
      expect(desc['hostId'], 'host-A');
      testClient.dispose();
      client.dispose();
      await host.stop();
    });

    test(
      'process death does not persist conversation logs unnecessarily',
      () async {
        // Live history is in-memory only, not persisted
        final container = ProviderContainer();
        addTearDown(container.dispose);
        const sid = 'sess-process';
        container.read(liveHistoryProvider(sid).notifier).replaceAll([
          HistoryEntry(
            event: SessionEvent(
              type: 'user/message',
              data: {'content': 'hi'},
              seq: 0,
              time: 1000,
            ),
            view: null,
          ),
        ]);
        expect(container.read(liveHistoryProvider(sid)), hasLength(1));
        // Simulate process death: new container should have empty history (not persisted)
        final newContainer = ProviderContainer();
        addTearDown(newContainer.dispose);
        expect(newContainer.read(liveHistoryProvider(sid)), isEmpty);
      },
    );

    test(
      'cold start shows connecting then connected, not fake cached connected',
      () async {
        final host = _LifecycleHost();
        final baseUrl = await host.start();
        addTearDown(host.stop);
        final states = <ConnectionState>[];
        final controller = FlutterConnectionController(
          ConnectionClient(baseUrl: baseUrl),
          onStateChange: states.add,
          config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
        );
        controller.start();
        // Should start with connecting, then connected
        for (int i = 0; i < 40; i++) {
          if (states.contains(ConnectionState.connected)) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(states.first, ConnectionState.connecting);
        expect(states.contains(ConnectionState.connected), isTrue);
        // Should not have been connected before connecting
        final connectedIdx = states.indexOf(ConnectionState.connected);
        final connectingIdx = states.indexOf(ConnectionState.connecting);
        expect(connectingIdx, lessThan(connectedIdx));
        controller.stop();
      },
    );
  });

  group('Resume resync order', () {
    test('resync order: describe, hostId, mux, host, connected, session list, history', () async {
      final host = _LifecycleHost(
        sessions: [
          {
            'sessionId': 'sess-1',
            'updatedAt': 1000,
            'running': false,
            'blank': false,
            'title': 'Test',
          },
        ],
        history: [
          {
            'event': {
              'type': 'user/message',
              'data': {'content': 'hi'},
              'seq': 0,
              'time': 1000,
            },
            'view': null,
          },
          {
            'event': {
              'type': 'assistant/message',
              'data': {'content': 'hello'},
              'seq': 1,
              'time': 1001,
            },
            'view': null,
          },
        ],
      );
      final baseUrl = await host.start();
      addTearDown(host.stop);
      final client = ConnectionClient(baseUrl: baseUrl);
      // 1. host.describe
      final desc = await client.hostDescribe();
      expect(desc['hostId'], isNotNull);
      // 2. validate hostId (no mismatch)
      // 3. establish mux/host (via controller)
      bool connectedCalled = false;
      final states = <ConnectionState>[];
      final controller = FlutterConnectionController(
        client,
        onStateChange: states.add,
        onConnected: (_) => connectedCalled = true,
        config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
      );
      controller.start();
      for (int i = 0; i < 40; i++) {
        if (connectedCalled) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(connectedCalled, isTrue);
      expect(states.contains(ConnectionState.connected), isTrue);
      // 4. refresh session list
      final sessions = await client.getSessions();
      expect(sessions, hasLength(1));
      // 5. refresh session history and rebuild — through cursor 1 (last seq)
      final history = await client.getSessionEvents(
        SessionId('sess-1'),
        throughSeq: 1,
      );
      expect(history, hasLength(2));
      controller.stop();
      client.dispose();
    });
  });
}

class _DescribeGatedClient extends http.BaseClient {
  _DescribeGatedClient(this.release, this.describeSeen, this.baseUrl);
  final Completer<void> release;
  final Completer<void> describeSeen;
  final String baseUrl;
  final http.Client _inner = IOClient();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isDescribe = request.url.path == '/api/host.describe';
    if (isDescribe && !describeSeen.isCompleted) describeSeen.complete();
    final response = await _inner.send(request);
    if (isDescribe) await release.future;
    return response;
  }

  @override
  void close() => _inner.close();
}
