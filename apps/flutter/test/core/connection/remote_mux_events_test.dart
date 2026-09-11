import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart';
import 'package:dsh_flutter/src/core/connection/remote_mux_client.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_responder.dart';
import 'package:dsh_flutter/src/plugins/user_questions/approval_state.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_models.dart';
import 'package:dsh_flutter/src/plugins/user_questions/question_responder.dart';
import 'package:dsh_flutter/src/plugins/user_questions/questions_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// Scripted `remote.mux` host with `$events/result` capture: serves the
/// multiplex plus the unary result RPC so waterfall round-trips run against
/// the current contract (ready/clientId/eventId/agentId/result/next).
class _EventsHost {
  _EventsHost({this.autoReady = true});

  bool autoReady;

  HttpServer? _server;
  final List<IOWebSocketChannel> sockets = [];

  /// `$events` stream ids opened per socket.
  final Map<IOWebSocketChannel, List<String>> eventsStreams = {};

  /// Every logical-stream open seen, in arrival order.
  final List<_MuxOpen> allOpens = [];

  /// `cancel` stream ids received, in arrival order.
  final List<String> cancels = [];

  /// `$events/result` request bodies received, in arrival order.
  final List<Map<String, dynamic>> results = [];

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
      return _json(request, {
        'type': 'server-response',
        'rpcId': 'r1',
        'result': {
          'ok': true,
          'value': {'version': '0.0.0', 'home': '/home', 'cwd': '/tmp'},
        },
      });
    }
    if (request.method == 'POST' && path == r'/api/$events/result') {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      results.add(decoded);
      return _json(request, {
        'type': 'server-response',
        'rpcId': 'r1',
        'result': {
          'ok': true,
          'value': {'received': true},
        },
      });
    }
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final channel = await WebSocketTransformer.upgrade(
        request,
      ).then(IOWebSocketChannel.new);
      sockets.add(channel);
      eventsStreams[channel] = [];
      channel.stream.listen(
        (data) {
          final text = data is String ? data : utf8.decode(data as List<int>);
          final map = jsonDecode(text) as Map<String, dynamic>;
          if (map['type'] == 'cancel') {
            cancels.add(map['streamId'] as String);
            return;
          }
          if (map['type'] != 'open') return;
          if (map['type'] == 'open') {
            final endpoint = map['endpoint'] as String? ?? '';
            final openId = map['streamId'] as String? ?? '';
            allOpens.add(_MuxOpen(endpoint, openId));
          }
          if (map['endpoint'] == r'$events') {
            final streamId = map['streamId'] as String;
            eventsStreams[channel]!.add(streamId);
            if (autoReady) _sendReady(channel, streamId);
          }
        },
        onDone: () {},
      );
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  }

  void _sendReady(IOWebSocketChannel channel, String streamId) {
    channel.sink.add(jsonEncode({
      'type': 'item',
      'streamId': streamId,
      'value': {
        'type': 'ready',
        'clientId': 'c-test',
        'host': {'home': '/home'},
      },
    }));
  }

  Future<void> _json(HttpRequest request, Map<String, dynamic> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  void pushDownlink(
    String streamId,
    Map<String, dynamic>? value, {
    bool isError = false,
  }) {
    for (final s in List.of(sockets)) {
      s.sink.add(jsonEncode(isError
          ? {
              'type': 'error',
              'streamId': streamId,
              'error': {'code': 'internal', 'message': 'detached', 'details': {}},
            }
          : {
              'type': 'item',
              'streamId': streamId,
              'value': value,
            }));
    }
  }

  String eventsStreamOf(int socketIndex) =>
      eventsStreams[sockets[socketIndex]]!.last;
  Future<void> stop() async {
    for (final s in sockets) {
      try {
        await s.sink.close();
      } catch (_) {}
    }
    await _server?.close(force: true);
  }
}

/// One logical-stream open observed by the scripted host.
class _MuxOpen {
  const _MuxOpen(this.endpoint, this.streamId);

  /// `<namespace>/<method>` or `$events`.
  final String endpoint;

  /// Client-minted stream correlation id.
  final String streamId;
}

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
  group('remote.mux + \$events contract', () {
    test('stream cancel unwinds and the Host sees the cancel frame', () async {
      final host = _EventsHost(autoReady: false);
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      final mux = client.createRemoteMuxClient()..start();

      final sub = mux.open(r'$events', {'args': {}}).listen((_) {});
      await _pollUntil(
        () => host.eventsStreams.values.any((l) => l.isNotEmpty),
      );
      final streamId = host.eventsStreams.values
          .expand((l) => l)
          .first;
      // Cancelling must complete (async* + broadcast await-for never
      // unwinds) and release the logical stream server-side.
      await sub.cancel().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('stream cancel hung'),
      );
      await _pollUntil(() => host.cancels.contains(streamId));
      expect(host.cancels, contains(streamId));
      await mux.close();
      client.dispose();
      await host.stop();
    });

    test('first frame must be ready; empty ids rejected', () async {
      final host = _EventsHost(autoReady: false);
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      final mux = client.createRemoteMuxClient()..start();

      // Unknown stream ids are tolerated (no crash); the stream stays open.
      final bad = mux.open(r'$events', {'args': {}});
      await _pollUntil(() => host.sockets.isNotEmpty);
      final sub = bad.listen(null, onError: (_) {});
      host.pushDownlink('no-such-stream', {'type': 'emit'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      // Non-ready first value on $events fails the stream (React: the
      // stream did not begin with ready).
      final errors = <Object>[];
      final opensBefore = host.eventsStreams.values
          .expand((l) => l)
          .length;
      final sub0 = mux.openEvents().listen(null, onError: errors.add);
      await _pollUntil(
        () =>
            host.eventsStreams.values.expand((l) => l).length >
            opensBefore,
      );
      var streamId = host.eventsStreams.values
          .expand((l) => l)
          .last;
      // The server may record the open before the client attaches its
      // fan-in listener; retry the push until the enforcement fires.
      final stopwatch = Stopwatch()..start();
      while (errors.isEmpty && stopwatch.elapsed < const Duration(seconds: 3)) {
        host.pushDownlink(streamId, {
          'type': 'emit',
          'event': 'x',
          'args': [],
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(errors, isNotEmpty);
      await sub0.cancel();

      // Malformed waterfall (empty eventId) yields no frame; the valid one
      // after it still arrives with real correlation fields.
      final frames = <RemoteEventDownlinkFrame>[];
      final seenBefore = host.eventsStreams.values
          .expand((l) => l)
          .toList();
      final sub2 = mux.openEvents().listen(frames.add, onError: (_) {});
      await _pollUntil(
        () => host.eventsStreams.values.expand((l) => l).length > seenBefore.length,
      );
      streamId = host.eventsStreams.values
          .expand((l) => l)
          .firstWhere((id) => !seenBefore.contains(id));
      // Ready first (required), then an empty-id waterfall (dropped
      // silently, stream stays alive), then the valid delivery.
      host.pushDownlink(streamId, {
        'type': 'ready',
        'clientId': 'c-test',
        'host': {'home': '/home'},
      });
      host.pushDownlink(streamId, {
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': '',
        'agentId': 'a1',
        'request': {'toolName': 'bash'},
      });
      host.pushDownlink(streamId, {
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': 'e1',
        'agentId': 'a1',
        'request': {'toolName': 'bash', 'reason': 'run tests'},
      });
      await _pollUntil(() => frames.whereType<RemoteEventWaterfallFrame>().isNotEmpty);
      final waterfalls = frames.whereType<RemoteEventWaterfallFrame>().toList();
      expect(waterfalls, hasLength(1));
      expect(waterfalls.single.eventId, 'e1');
      expect(waterfalls.single.agentId, 'a1');
      expect(waterfalls.single.request['toolName'], 'bash');
      await sub2.cancel();
      await mux.close();
      client.dispose();
      await host.stop();
    });

    test('stream error ends the logical stream, never delivered as value',
        () async {
      final host = _EventsHost(autoReady: false);
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      final mux = client.createRemoteMuxClient()..start();

      final values = <Map<String, dynamic>>[];
      final errors = <Object>[];
      final sub = mux
          .open('session/follow', {'args': {}}).listen(
            values.add,
            onError: errors.add,
          );
      await _pollUntil(() => host.allOpens.isNotEmpty);
      final streamId = host.allOpens
          .firstWhere((o) => o.endpoint == 'session/follow')
          .streamId;
      host.pushDownlink(streamId, null, isError: true);
      await _pollUntil(() => errors.isNotEmpty);
      expect(values, isEmpty);
      expect(errors.single, isA<RemoteStreamError>());
      await sub.cancel();
      await mux.close();
      client.dispose();
      await host.stop();
    });

    test('malformed server messages fail the carrier, unknown streams pass',
        () async {
      final host = _EventsHost(autoReady: false);
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      final mux = client.createRemoteMuxClient()..start();

      final errors = <Object>[];
      final sub = mux.open(r'$events', {'args': {}}).listen(
            (_) {},
            onError: errors.add,
          );
      await _pollUntil(() => host.sockets.isNotEmpty);
      // Not JSON at all: carrier failure surfaces on open streams.
      host.sockets.first.sink.add('this is not json{{{');
      await _pollUntil(() => errors.isNotEmpty);
      expect(errors, isNotEmpty);
      await sub.cancel();
      await mux.close();
      client.dispose();
      await host.stop();
    });
  });

  group('approval/question waterfall round-trips', () {
    test('approval allow posts result with real correlation', () async {
      final host = _EventsHost();
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      client.eventsClientId = 'c-test';

      const pending = PendingApproval(
        rpcId: 'e-approval-1',
        sessionId: 's1',
        approvalId: 'e-approval-1',
        toolName: 'bash',
        reason: 'run tests',
      );
      await ApprovalResponder(client: client, pending: pending)
          .answer(ApprovalAnswer.allowedOnce);

      expect(host.results, hasLength(1));
      final body =
          (host.results.single['payload'] as Map)['args'] as Map;
      expect(body['clientId'], 'c-test');
      expect(body['eventId'], 'e-approval-1');
      expect(body['outcome'], {
        'kind': 'result',
        'value': 'allowed-once',
      });
      client.dispose();
      await host.stop();
    });

    test('approval deny posts result rejected outcome value', () async {
      final host = _EventsHost();
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      client.eventsClientId = 'c-test';

      const pending = PendingApproval(
        rpcId: 'e-approval-2',
        sessionId: 's1',
        approvalId: 'e-approval-2',
        toolName: 'bash',
      );
      await ApprovalResponder(client: client, pending: pending)
          .answer(ApprovalAnswer.rejected);

      // Denial is an `ApprovalOutcome` result value (fail-closed vocabulary),
      // not a transport rejection: the Host waterfall resolves normally.
      expect(host.results, hasLength(1));
      final body =
          (host.results.single['payload'] as Map)['args'] as Map;
      expect(body['eventId'], 'e-approval-2');
      expect(body['outcome'], {
        'kind': 'result',
        'value': 'rejected',
      });
      client.dispose();
      await host.stop();
    });

    test('question answer posts the answers batch', () async {
      final host = _EventsHost();
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      client.eventsClientId = 'c-test';

      final pending = PendingQuestion(
        rpcId: 'e-question-1',
        sessionId: 's1',
        questions: [
          QuestionItem(
            id: 'q1',
            question: 'Proceed?',
            options: const [],
          ),
        ],
      );
      await QuestionResponder(client: client, pending: pending).answer(
        const QuestionAnswerBatch(
          answers: [
            QuestionAnswerItem(id: 'q1', selected: ['Yes']),
          ],
        ),
      );

      expect(host.results, hasLength(1));
      final body =
          (host.results.single['payload'] as Map)['args'] as Map;
      expect(body['eventId'], 'e-question-1');
      final value = (body['outcome'] as Map)['value'] as Map;
      expect((value['answers'] as List).single['id'], 'q1');
      client.dispose();
      await host.stop();
    });

    test('question cancel posts transport rejected outcome', () async {
      final host = _EventsHost();
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      client.eventsClientId = 'c-test';

      final pending = PendingQuestion(
        rpcId: 'e-question-2',
        sessionId: 's1',
        questions: const [],
      );
      await QuestionResponder(client: client, pending: pending).cancel();

      expect(host.results, hasLength(1));
      final body =
          (host.results.single['payload'] as Map)['args'] as Map;
      final outcome = body['outcome'] as Map;
      expect(outcome['kind'], 'rejected');
      expect((outcome['error'] as Map)['name'], isNotEmpty);
      expect((outcome['error'] as Map)['message'], isNotEmpty);
      client.dispose();
      await host.stop();
    });

    test('cancelled waterfall: late answer is dropped locally', () async {
      final host = _EventsHost();
      final baseUrl = await host.start();
      final client = ConnectionClient(baseUrl: baseUrl);
      client.eventsClientId = 'c-test';
      client.noteWaterfallCancelled('e-cancelled-1');

      const pending = PendingApproval(
        rpcId: 'e-cancelled-1',
        sessionId: 's1',
        approvalId: 'e-cancelled-1',
        toolName: 'bash',
      );
      await expectLater(
        ApprovalResponder(client: client, pending: pending)
            .answer(ApprovalAnswer.allowedOnce),
        throwsStateError,
      );
      // Nothing traveled: the Host already settled the waterfall.
      expect(host.results, isEmpty);
      client.dispose();
      await host.stop();
    });

    test('controller: cancel settles the card, unknown event sends next',
        () async {
      final host = _EventsHost();
      final baseUrl = await host.start();
      final muxFrames = <Map<String, dynamic>>[];
      final controller = FlutterConnectionController(
        ConnectionClient(baseUrl: baseUrl),
        onMuxEnvelope: muxFrames.add,
        config: const ConnectionConfig(backoffBaseMs: 5, backoffMaxMs: 10),
      )..start();

      await _pollUntil(() => host.sockets.isNotEmpty);
      await _pollUntil(
        () => host.eventsStreams.values.any((l) => l.isNotEmpty),
      );
      final streamId = host.eventsStreams.values.expand((l) => l).isEmpty
          ? null
          : host.eventsStreams.values.expand((l) => l).first;
      expect(streamId, isNotNull);

      // Unknown waterfall: dispatched to the bus AND delegated with next
      // (no Host hang).
      host.pushDownlink(streamId!, {
        'type': 'waterfall',
        'event': 'future/extension-event',
        'eventId': 'e-unknown-1',
        'agentId': 'a1',
        'request': {'note': 'hello'},
      });
      await _pollUntil(
        () => host.results.any(
          (r) =>
              ((r['payload'] as Map)['args'] as Map)['eventId'] ==
              'e-unknown-1',
        ),
      );
      final nextBody =
          (host.results.last['payload'] as Map)['args'] as Map;
      expect(nextBody['outcome'], {'kind': 'next'});

      // Approval waterfall then cancel: the card settles by event id.
      host.pushDownlink(streamId, {
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': 'e-approval-9',
        'agentId': 'a1',
        'request': {'toolName': 'bash'},
      });
      await _pollUntil(
        () => muxFrames.any(
          (f) =>
              f['type'] == 'approval/requested' &&
              f['rpcId'] == 'e-approval-9',
        ),
      );
      final requested = muxFrames.firstWhere(
        (f) => f['rpcId'] == 'e-approval-9',
      );
      expect(requested['approvalId'], 'e-approval-9');
      expect(requested['toolName'], 'bash');

      host.pushDownlink(streamId, {
        'type': 'cancel',
        'eventId': 'e-approval-9',
      });
      await _pollUntil(
        () => muxFrames.any(
          (f) =>
              f['type'] == 'approval/resolved' &&
              f['approvalId'] == 'e-approval-9',
        ),
      );

      controller.stop();
      await host.stop();
    });
  });
}
