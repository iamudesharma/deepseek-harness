import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';

/// Scriptable local host: answers `host.describe` over POST and serves the two
/// event streams over WebSocket with runtime-controllable frame injection and
/// closure, so reconnect-generation semantics run against a real carrier.
class _ScriptedHost {
  _ScriptedHost({this.muxScript = const []});

  /// Frames replayed on every new mux socket connection.
  final List<Map<String, dynamic>> muxScript;

  HttpServer? _server;
  bool streamsUp = true;
  final List<IOWebSocketChannel> _muxSockets = [];
  int describeCalls = 0;

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/api/host.describe') {
        describeCalls++;
        final body = await utf8.decoder.bind(request).join();
        final req = jsonDecode(body) as Map<String, dynamic>;
        final response = {
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
            },
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
        return;
      }
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        if (!streamsUp) {
          request.response.statusCode = 503;
          await request.response.close();
          return;
        }
        final channel = await WebSocketTransformer.upgrade(request).then(IOWebSocketChannel.new);
        _muxSockets.add(channel);
        for (final frame in muxScript) {
          channel.sink.add(jsonEncode(frame));
        }
        // Hold the socket open; tests close it explicitly.
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  void pushMux(Map<String, dynamic> frame) {
    for (final socket in List.of(_muxSockets)) {
      socket.sink.add(jsonEncode(frame));
    }
  }

  void closeMuxSockets() {
    for (final socket in List.of(_muxSockets)) {
      socket.sink.close();
    }
    _muxSockets.clear();
  }

  Future<void> stop() async {
    closeMuxSockets();
    await _server?.close(force: true);
  }
}

/// Delegates every request to an inner client, but holds `/api/host.describe`
/// responses until [release] completes — a deterministic slow handshake.
class _DescribeGatedClient extends http.BaseClient {
  _DescribeGatedClient(this.release, this.describeSeen);

  final Completer<void> release;
  final Completer<void> describeSeen;
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

void main() {
  test('generation increments on stream loss and state walks connected→reconnecting→connected', () async {
    final host = _ScriptedHost(muxScript: [
      {'type': 'session/subscribed', 'sessionId': 's1', 'lastSeq': 0},
    ]);
    final baseUrl = await host.start();
    final states = <ConnectionState>[];
    final controller = FlutterConnectionController(
      ConnectionClient(baseUrl: baseUrl),
      onStateChange: states.add,
      config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
    )..start();

    while (!states.contains(ConnectionState.connected)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.currentAttempt, 0);

    final genBefore = controller.generation;
    host.closeMuxSockets();

    while (controller.generation <= genBefore) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (!controller.isRunning) break;
    }
    expect(controller.generation, greaterThan(genBefore));
    expect(states.contains(ConnectionState.reconnecting), isTrue);

    controller.stop();
    await host.stop();
  });

  test('stream/error ends the generation and is not delivered to sinks', () async {
    final host = _ScriptedHost(muxScript: [
      {'type': 'session/subscribed', 'sessionId': 's1', 'lastSeq': 0},
    ]);
    final baseUrl = await host.start();
    final delivered = <Map<String, dynamic>>[];
    final controller = FlutterConnectionController(
      ConnectionClient(baseUrl: baseUrl),
      onMuxEnvelope: delivered.add,
      config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
    )..start();

    while (!delivered.any((f) => f['type'] == 'session/subscribed')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final genBefore = controller.generation;

    host.pushMux({
      'type': 'session/event',
      'sessionId': 's1',
      'event': {'type': 'turn/start', 'seq': 1},
    });
    host.pushMux({
      'type': 'stream/error',
      'error': {'code': 'internal', 'message': 'carriage detached', 'details': {}},
    });

    // Wait up to 200ms for the generation to turn over (30ms is tight under
    // full-suite load; poll like the first test).
    for (var i = 0; i < 20; i++) {
      if (controller.generation > genBefore) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(delivered.any((f) => f['type'] == 'session/event'), isTrue);
    expect(delivered.any((f) => f['type'] == 'stream/error'), isFalse);
    expect(controller.generation, greaterThan(genBefore));

    controller.stop();
    await host.stop();
  });

  test('stop during handshake never fires onConnected for a dead generation', () async {
    final host = _ScriptedHost();
    final baseUrl = await host.start();

    final release = Completer<void>();
    final describeSeen = Completer<void>();
    final gated = _DescribeGatedClient(release, describeSeen);

    final connectedDescriptions = <Map<String, dynamic>>[];
    final controller = FlutterConnectionController(
      ConnectionClient(baseUrl: baseUrl, httpClient: gated),
      onConnected: connectedDescriptions.add,
      config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
    )..start();

    await describeSeen.future;
    controller.stop();
    release.complete();

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(connectedDescriptions, isEmpty);
    expect(controller.isRunning, isFalse);

    await host.stop();
  });
}
