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
  HttpServer? _server;
  bool streamsUp = true;
  final List<IOWebSocketChannel> _muxSockets = [];
  int describeCalls = 0;

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      if (request.method == 'POST' &&
          request.uri.path == '/api/host.describe') {
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
        final channel = await WebSocketTransformer.upgrade(request)
            .then(IOWebSocketChannel.new);
        _muxSockets.add(channel);
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
  // NOTE: the retired-transport generation tests lived here. They drove
  // `host.describe` + raw `session/subscribed` sockets, which the remote.mux
  // transport replaced: without a `$events` ready frame no generation can
  // establish, so they failed at HEAD and poisoned neighboring tests with
  // hot-looping leaked controllers. Their behaviors now live in
  // `connection_recovery_test.dart` (turnover, resubscription) and
  // `remote_mux_events_test.dart` (stream/error delivery).

  test(
    'stop during handshake never fires onConnected for a dead generation',
    () async {
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
    },
  );
}
