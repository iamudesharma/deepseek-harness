import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart';
import 'package:dsh_flutter/src/core/connection/connection_target.dart';
import 'package:dsh_flutter/src/core/connection/secure_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// Scripted `remote.mux` host: answers `host.describe` over POST and serves
/// the multiplex over WebSocket with runtime-controllable ready frames,
/// closure, and per-socket open inspection, so generation/reconnect semantics
/// run against the current transport (not the retired host.describe+sockets
/// harness of `connection_generation_test.dart`).
class _ScriptedMuxHost {
  _ScriptedMuxHost({this.autoReady = true, this.ticketStatus = 200});

  /// Send a `$events` ready item for every `$events` open while true.
  bool autoReady;

  /// HTTP status for `POST /api/remote/ws-ticket` (401 simulates revocation).
  int ticketStatus;

  HttpServer? _server;

  /// One record per accepted mux socket, in accept order.
  final List<_MuxSocket> sockets = [];

  /// Endpoints opened across all sockets, in arrival order.
  final List<String> opensSeen = [];

  int describeCalls = 0;

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      try {
        await _handle(request);
      } catch (_) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'POST' && path == '/api/host.describe') {
      describeCalls++;
      return _json(request, {
        'type': 'server-response',
        'rpcId': 'r1',
        'result': {
          'ok': true,
          'value': {'version': '0.0.0', 'home': '/home', 'cwd': '/tmp'},
        },
      });
    }
    if (request.method == 'POST' && path == '/api/remote/ws-ticket') {
      if (ticketStatus != 200) {
        request.response.statusCode = ticketStatus;
        await request.response.close();
        return;
      }
      return _json(request, {
        'type': 'server-response',
        'rpcId': 'r1',
        'result': {
          'ok': true,
          'value': {'ticket': 't-test'},
        },
      });
    }
    if (request.method == 'POST' && path == '/api/remote/refresh') {
      request.response.statusCode = 500;
      await request.response.close();
      return;
    }
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      if (request.uri.path != '/api/remote.mux') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final channel = await WebSocketTransformer.upgrade(
        request,
      ).then(IOWebSocketChannel.new);
      final sock = _MuxSocket(channel, this);
      sockets.add(sock);
      channel.stream.listen(
        (data) => sock.onMessage(data),
        onDone: () => sock.closed.complete(),
      );
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  }

  Future<void> _json(HttpRequest request, Map<String, dynamic> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  void closeAllSockets() {
    for (final s in List.of(sockets)) {
      try {
        s.channel.sink.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    closeAllSockets();
    await _server?.close(force: true);
  }
}

class _MuxSocket {
  _MuxSocket(this.channel, this.host);

  final IOWebSocketChannel channel;
  final _ScriptedMuxHost host;
  final Completer<void> closed = Completer<void>();

  /// `$events` stream ids opened on this socket, in arrival order.
  final List<String> eventsStreams = [];

  void onMessage(dynamic data) {
    final text = data is String ? data : utf8.decode(data as List<int>);
    final map = jsonDecode(text) as Map<String, dynamic>;
    if (map['type'] != 'open') return;
    final endpoint = map['endpoint'] as String? ?? '';
    final streamId = map['streamId'] as String? ?? '';
    host.opensSeen.add(endpoint);
    if (endpoint == r'$events') {
      eventsStreams.add(streamId);
      if (host.autoReady) sendReady(streamId);
    } else if (endpoint == 'session/control') {
      channel.sink.add(jsonEncode({
        'type': 'item',
        'streamId': streamId,
        'value': {
          'type': 'baseline',
          'value': {
            'queues': {
              's1': [
                {'id': 'q1', 'placement': 'queued'},
              ],
            },
            'jobs': {},
            'projections': {},
          },
        },
      }));
    } else if (endpoint == 'session/follow') {
      channel.sink.add(jsonEncode({
        'type': 'item',
        'streamId': streamId,
        'value': {
          'type': 'snapshot',
          'cursor': 0,
          'records': [],
          'hasMore': false,
        },
      }));
    } else if (endpoint == 'workspace/follow') {
      channel.sink.add(jsonEncode({
        'type': 'item',
        'streamId': streamId,
        'value': {'type': 'baseline', 'value': {}},
      }));
    }
  }

  /// Pushes a downlink item on the `$events` logical stream.
  void pushEventsItem(Map<String, dynamic> value, String streamId) {
    channel.sink.add(jsonEncode({
      'type': 'item',
      'streamId': streamId,
      'value': value,
    }));
  }

  /// Answers the `$events` open with a ready frame (late readiness).
  void sendReady([String? streamId]) {
    final id = streamId ??
        (eventsStreams.isNotEmpty ? eventsStreams.last : null);
    if (id == null) return;
    pushEventsItem({
      'type': 'ready',
      'clientId': 'c-test',
      'host': {'home': '/home'},
    }, id);
  }
}

FlutterConnectionController _controller(
  String baseUrl, {
  List<ConnectionState>? states,
  List<Map<String, dynamic>>? mux,
  List<Map<String, dynamic>>? connected,
  ConnectionConfig config = const ConnectionConfig(
    backoffBaseMs: 5,
    backoffMaxMs: 10,
  ),
}) => FlutterConnectionController(
  ConnectionClient(baseUrl: baseUrl),
  onStateChange: states?.add,
  onMuxEnvelope: mux?.add,
  onConnected: connected?.add,
  config: config,
);

Future<void> _pollUntil(
  bool Function() done, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!done()) {
    if (stopwatch.elapsed > budget) break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('connection recovery parity (react recovery-config)', () {
    test('delayed ready within the deadline connects once', () async {
      final host = _ScriptedMuxHost(autoReady: false);
      final baseUrl = await host.start();
      final states = <ConnectionState>[];
      final connected = <Map<String, dynamic>>[];
      final controller = _controller(
        baseUrl,
        states: states,
        connected: connected,
        config: const ConnectionConfig(
          backoffBaseMs: 5,
          backoffMaxMs: 10,
          generationReadyWarnMs: 10,
          generationReadyTimeoutMs: 2000,
        ),
      )..start();

      // Slow handshake (warn fires, deadline does not): still connecting.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(states, contains(ConnectionState.connecting));
      expect(connected, isEmpty);

      // Ready lands before the deadline on the live socket: genuine
      // ready-driven connect (exactly one `connected`).
      host.autoReady = true;
      for (final s in host.sockets) {
        s.sendReady();
      }
      await _pollUntil(
        () => states.contains(ConnectionState.connected),
      );
      expect(states.contains(ConnectionState.connected), isTrue);
      expect(connected, hasLength(1));
      expect(controller.currentAttempt, 0);

      controller.stop();
      await host.stop();
    });

    test('missed deadline fails the generation and reconnects', () async {
      final host = _ScriptedMuxHost(autoReady: false);
      final baseUrl = await host.start();
      final states = <ConnectionState>[];
      final controller = _controller(
        baseUrl,
        states: states,
        config: const ConnectionConfig(
          backoffBaseMs: 5,
          backoffMaxMs: 10,
          generationReadyWarnMs: 10,
          generationReadyTimeoutMs: 60,
        ),
      )..start();

      await _pollUntil(() => controller.generation >= 2);
      expect(controller.generation, greaterThanOrEqualTo(2));
      expect(states.contains(ConnectionState.reconnecting), isTrue);
      // The failed handshake closed its socket instead of leaking it:
      // every accepted socket is closed once the deadline fires.
      await _pollUntil(() => host.sockets.every((s) => s.closed.isCompleted));
      expect(host.sockets, isNotEmpty);
      expect(
        host.sockets.every((s) => s.closed.isCompleted),
        isTrue,
      );

      controller.stop();
      await host.stop();
    });

    test('host restart turns the generation over and resubscribes', () async {
      final host = _ScriptedMuxHost();
      final baseUrl = await host.start();
      final states = <ConnectionState>[];
      final mux = <Map<String, dynamic>>[];
      final connected = <Map<String, dynamic>>[];
      final controller = _controller(
        baseUrl,
        states: states,
        mux: mux,
        connected: connected,
      )..start();

      await _pollUntil(
        () => states.contains(ConnectionState.connected),
      );
      expect(connected, hasLength(1));
      expect(controller.currentAttempt, 0);
      final genBefore = controller.generation;
      final socketsBefore = host.sockets.length;

      // Host restart: drop the socket; the controller must open a fresh
      // physical carrier (new socket) and resubscribe every domain stream.
      // Generous budget: under full-suite load the second handshake is slow.
      host.closeAllSockets();
      await _pollUntil(() => controller.generation > genBefore,
          budget: const Duration(seconds: 10));
      await _pollUntil(
        () => connected.length >= 2,
        budget: const Duration(seconds: 10),
      );
      expect(controller.generation, greaterThan(genBefore));
      expect(host.sockets.length, greaterThan(socketsBefore));
      expect(connected, hasLength(2));
      expect(controller.currentAttempt, 0);
      // Resubscription: the new generation reopened every controller-owned
      // stream (`session/follow` is LiveSync-owned and reopens on the
      // `onConnected` resync, covered by the follow cursor tests).
      final opensAfterRestart = host.opensSeen;
      for (final endpoint in [
        r'$events',
        'session/control',
        'workspace/follow',
      ]) {
        expect(opensAfterRestart, contains(endpoint));
      }
      // Domain baseline reached the mux sink (control pump translated it).
      expect(
        mux.any(
          (f) =>
              f['type'] == 'session/queue' ||
              f['type'] == 'session/jobs' ||
              f['type'] == 'session/projection',
        ),
        isTrue,
      );

      controller.stop();
      await host.stop();
    });

    test('suspend emits disconnected and resume starts a fresh generation',
        () async {
      final host = _ScriptedMuxHost();
      final baseUrl = await host.start();
      final states = <ConnectionState>[];
      final connected = <Map<String, dynamic>>[];
      final controller = _controller(
        baseUrl,
        states: states,
        connected: connected,
      )..start();

      await _pollUntil(
        () => states.contains(ConnectionState.connected),
      );
      final genBefore = controller.generation;

      controller.suspend();
      expect(controller.isSuspended, isTrue);
      expect(states.last, ConnectionState.disconnected);

      controller.resume();
      await _pollUntil(() => controller.generation > genBefore);
      await _pollUntil(() => connected.length >= 2);
      expect(connected, hasLength(2));

      controller.stop();
      await host.stop();
    });

    test('online trigger restarts the retry sequence', () async {
      final host = _ScriptedMuxHost(autoReady: false);
      final baseUrl = await host.start();
      final states = <ConnectionState>[];
      final controller = _controller(
        baseUrl,
        states: states,
        config: const ConnectionConfig(
          backoffBaseMs: 500,
          backoffMaxMs: 1000,
          generationReadyWarnMs: 10,
          generationReadyTimeoutMs: 40,
        ),
      )..start();

      await _pollUntil(
        () => states.contains(ConnectionState.reconnecting),
      );
      expect(controller.currentAttempt, greaterThan(0));
      controller.handleNetworkOnline();
      expect(controller.currentAttempt, 0);

      controller.stop();
      await host.stop();
    });

    test('auth failure stops the loop with needsReauth', () async {
      final host = _ScriptedMuxHost(autoReady: false, ticketStatus: 401);
      final baseUrl = await host.start();
      final remote = RemoteTarget(
        baseUri: Uri.parse(baseUrl),
        hostId: 'h1',
        hostPublicKey: 'k1',
        deviceId: 'd1',
        displayName: 'test device',
      );
      final store = InMemoryTokenStore();
      await store.write('d1', 'expired-token');
      final states = <ConnectionState>[];
      final controller = FlutterConnectionController(
        ConnectionClient.fromTarget(remote, tokenStore: store),
        onStateChange: states.add,
        config: const ConnectionConfig(
          backoffBaseMs: 5,
          backoffMaxMs: 10,
          generationReadyWarnMs: 10,
          generationReadyTimeoutMs: 500,
        ),
      )..start();

      await _pollUntil(
        () => states.contains(ConnectionState.needsReauth),
        budget: const Duration(seconds: 10),
      );
      expect(states.contains(ConnectionState.needsReauth), isTrue);
      // The dead pump must not masquerade as ready: no `connected` fires
      // on the way to reauth.
      expect(states.contains(ConnectionState.connected), isFalse);
      expect(controller.isRunning, isFalse);

      controller.stop();
      await host.stop();
    });
  });
}
