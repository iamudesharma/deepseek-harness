import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/trajectory/trajectory_provider.dart';
import 'package:dsh_flutter/src/plugins/tool/tool_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sentinel probe regression suite — verifies the `1<<30` cursor-discovery
/// path is gone and the authoritative `session/follow → LiveHistory` flow
/// is the sole initial history source.

class _CaptureHost {
  _CaptureHost(this.onCall);

  final Map<String, dynamic>? Function(
    String path,
    Map<String, dynamic> envelope,
  )
  onCall;

  HttpServer? _server;
  final List<Map<String, dynamic>> requests = [];

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((req) async {
      final path = req.uri.path;
      final body = await utf8.decoder.bind(req).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      requests.add(decoded);
      final resp =
          onCall(path, decoded) ??
          {
            'type': 'server-response',
            'rpcId': decoded['rpcId'],
            'result': {'ok': true, 'value': <String, dynamic>{}},
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
  group('A. Sentinel removal', () {
    test('getSessionHistory requires throughSeq — omitting throws', () async {
      final client = ConnectionClient(baseUrl: 'http://dummy');
      addTearDown(client.dispose);
      expect(
        () => client.getSessionHistory(SessionId('s-1')),
        throwsA(isA<ArgumentError>()),
      );
      // Also via acceptedSeq alias missing
      expect(
        () => client.getSessionHistory(SessionId('s-1'), beforeSeq: 10),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getSessionHistory does not send 1<<30 probe', () async {
      final host = _CaptureHost((path, envelope) {
        final method = envelope['method'] as String?;
        if (method == 'session/page') {
          final payload = (envelope['payload'] as Map)['args'] as Map;
          final req = payload['request'] as Map;
          final throughSeq = req['throughSeq'] as int?;
          // Probe would be 1<<30
          expect(throughSeq, isNot(1073741824));
          expect(throughSeq, isNot(1 << 30));
          expect(throughSeq, isNot(2147483647));
          return {
            'type': 'server-response',
            'rpcId': envelope['rpcId'],
            'result': {
              'ok': true,
              'value': {
                'records': [],
                'hasMore': false,
              },
            },
          };
        }
        return null;
      });
      final baseUrl = await host.start();
      addTearDown(host.stop);
      final client = ConnectionClient(baseUrl: baseUrl);
      addTearDown(client.dispose);

      // Valid call with explicit cursor -1 (empty) should succeed without probe
      final res = await client.getSessionHistory(
        SessionId('s-empty'),
        throughSeq: -1,
      );
      expect(res.entries, isEmpty);
      expect(
        host.requests.where((r) => r['method'] == 'session/page'),
        hasLength(1),
      );
      final req = ((host.requests.first['payload'] as Map)['args'] as Map)['request'] as Map;
      expect(req['throughSeq'], -1);
    });

    test('getSessionEvents requires throughSeq', () async {
      final client = ConnectionClient(baseUrl: 'http://dummy');
      addTearDown(client.dispose);
      expect(
        () => client.getSessionEvents(SessionId('s-1'), throughSeq: -1),
        returnsNormally,
      );
      // Missing throughSeq is a compile-time error; runtime probe removed
    });

    test('no RegExp past cursor in connection_client', () {
      final file = File(
        'lib/src/core/connection/connection_client.dart',
      ).readAsStringSync();
      expect(file.contains('RegExp'), isFalse, reason: 'no RegExp past cursor probe');
      expect(file.contains('past cursor'), isFalse, reason: 'no past cursor string');
      expect(file.contains('1 << 30'), isFalse, reason: 'no 1<<30 probe in connection client');
      expect(file.contains('1073741824'), isFalse);
    });
  });

  group('B. Initial conversation uses session/follow', () {
    test('messageListProvider does not call session/page when live empty', () async {
      final client = _CaptureHost((_, e) => null);
      final base = await client.start();
      addTearDown(client.stop);
      final container = ProviderContainer(
        overrides: [
          connectionClientProvider.overrideWithValue(
            ConnectionClient(baseUrl: base),
          ),
        ],
      );
      addTearDown(container.dispose);

      // liveHistory is empty initially
      expect(container.read(liveHistoryProvider('sess-b')), isEmpty);

      // messageListProvider should return empty without HTTP
      final msgs = await container.read(messageListProvider('sess-b').future);
      expect(msgs, isEmpty);
      expect(client.requests.where((r) => r['method'] == 'session/page'), isEmpty,
          reason: 'initial load must not call session/page');
    });

    test('liveHistory populated via snapshot, not page', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'sess-snap';
      final notifier = container.read(liveHistoryProvider(sid).notifier);
      // Simulate snapshot replaceAllWithCursorAndHasMore
      final entries = [
        HistoryEntry(
          event: SessionEvent(type: 'user/message', data: {'content': 'hi'}, seq: 0, time: 1000),
        ),
        HistoryEntry(
          event: SessionEvent(type: 'assistant/message', data: {'content': 'hello'}, seq: 1, time: 1001),
        ),
      ];
      notifier.replaceAllWithCursorAndHasMore(entries, 1, false);
      expect(container.read(liveHistoryProvider(sid)), hasLength(2));
      expect(container.read(liveHistoryProvider(sid).notifier).acceptedSeq, 1);
      final msgs = await container.read(messageListProvider(sid).future);
      expect(msgs, hasLength(2));
    });
  });

  group('C. Follow cursor adoption', () {
    test('LiveHistory acceptedSeq tracks snapshot cursor 1268', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'sess-1268';
      final notifier = container.read(liveHistoryProvider(sid).notifier);
      expect(notifier.acceptedSeq, -1);
      // Simulate follow snapshot with cursor 1268
      final entries = List.generate(
        2,
        (i) => HistoryEntry(
          event: SessionEvent(type: 'user/message', data: {}, seq: i, time: i),
        ),
      );
      // Manually set cursor 1268 with empty entries to represent tail gap case
      notifier.replaceAllWithCursorAndHasMore(entries, 1268, true);
      expect(notifier.acceptedSeq, 1268);
      expect(container.read(liveHasMoreProvider(sid)), isTrue);
    });

    test('appendLive respects acceptedSeq fence', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'sess-fence';
      final n = container.read(liveHistoryProvider(sid).notifier);
      n.replaceAllWithCursor([HistoryEntry(event: SessionEvent(type: 'user/message', data: {}, seq: 5, time: 0))], 5);
      expect(n.acceptedSeq, 5);
      // Duplicate seq <= acceptedSeq dropped
      n.appendLive(HistoryEntry(event: SessionEvent(type: 'tool/call', data: {}, seq: 5, time: 1)));
      expect(container.read(liveHistoryProvider(sid)), hasLength(1));
      // Next seq accepted
      n.appendLive(HistoryEntry(event: SessionEvent(type: 'assistant/message', data: {}, seq: 6, time: 2)));
      expect(container.read(liveHistoryProvider(sid)), hasLength(2));
    });
  });

  group('D. Older history uses authoritative cursor', () {
    test('loadOlder sends throughSeq=cursor and beforeSeq=firstSeq', () async {
      final host = _CaptureHost((path, envelope) {
        if (envelope['method'] == 'session/page') {
          final req = ((envelope['payload'] as Map)['args'] as Map)['request'] as Map;
          expect(req['throughSeq'], 1268);
          expect(req['beforeSeq'], 10);
          expect(req['maxMessages'], 50);
          return {
            'type': 'server-response',
            'rpcId': envelope['rpcId'],
            'result': {
              'ok': true,
              'value': {
                'records': [
                  {'type': 'event', 'event': {'type': 'user/message', 'seq': 5, 'time': 0, 'data': {}}},
                ],
                'hasMore': true,
              },
            },
          };
        }
        return null;
      });
      final baseUrl = await host.start();
      addTearDown(host.stop);
      final container = ProviderContainer(
        overrides: [
          connectionClientProvider.overrideWithValue(ConnectionClient(baseUrl: baseUrl)),
        ],
      );
      addTearDown(container.dispose);
      const sid = 'sess-older';
      final n = container.read(liveHistoryProvider(sid).notifier);
      // Seed with snapshot cursor 1268 and window 10..20
      final window = List.generate(2, (i) => HistoryEntry(event: SessionEvent(type: 'user/message', data: {}, seq: 10 + i, time: 0)));
      n.replaceAllWithCursorAndHasMore(window, 1268, true);
      expect(n.acceptedSeq, 1268);
      await n.loadOlder();
      expect(host.requests.where((r) => r['method'] == 'session/page'), hasLength(1));
      // After loadOlder, window should be prepended
      expect(container.read(liveHistoryProvider(sid)).first.event.seq, 5);
    });

    test('loadOlder without cursor does not call page', () async {
      final host = _CaptureHost((_, e) => null);
      final baseUrl = await host.start();
      addTearDown(host.stop);
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(ConnectionClient(baseUrl: baseUrl))],
      );
      addTearDown(container.dispose);
      const sid = 'sess-nocursor';
      final n = container.read(liveHistoryProvider(sid).notifier);
      // No snapshot yet, acceptedSeq -1, hasMore false initially
      expect(n.acceptedSeq, -1);
      // Enable hasMore artificially but cursor still -1 -> should not call
      container.read(liveHasMoreProvider(sid).notifier).state = true;
      await n.loadOlder();
      expect(host.requests.where((r) => r['method'] == 'session/page'), isEmpty);
    });
  });

  group('G-I. Trajectory/Tool/Subagent via liveHistory', () {
    test('trajectoryProvider uses liveHistory, not page', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'traj-sess';
      // Initially empty
      var traj = await container.read(trajectoryProvider(sid).future);
      expect(traj.turns, isEmpty);
      // Seed live history with a turn
      final n = container.read(liveHistoryProvider(sid).notifier);
      n.replaceAll([
        HistoryEntry(event: SessionEvent(type: 'user/message', data: {'content': 'hi'}, seq: 0, time: 0)),
        HistoryEntry(event: SessionEvent(type: 'assistant/message', data: {'content': 'hello'}, seq: 1, time: 1)),
      ]);
      traj = await container.read(trajectoryProvider(sid).future);
      expect(traj.turns, isNotEmpty);
    });

    test('toolCallsProvider uses liveHistory', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'tool-sess';
      var tools = await container.read(toolCallsProvider(sid).future);
      expect(tools, isEmpty);
      final n = container.read(liveHistoryProvider(sid).notifier);
      n.replaceAll([
        HistoryEntry(event: SessionEvent(type: 'tool/call', data: {'callId': 'c1', 'name': 'bash'}, seq: 0, time: 0)),
      ]);
      tools = await container.read(toolCallsProvider(sid).future);
      expect(tools, hasLength(1));
      expect(tools.first.toolName, 'bash');
    });
  });

  group('N. Empty session cursor -1', () {
    test('empty session stays at -1 without page', () async {
      final host = _CaptureHost((_, e) => null);
      final base = await host.start();
      addTearDown(host.stop);
      final container = ProviderContainer(
        overrides: [connectionClientProvider.overrideWithValue(ConnectionClient(baseUrl: base))],
      );
      addTearDown(container.dispose);
      const sid = 'empty-sess';
      final n = container.read(liveHistoryProvider(sid).notifier);
      expect(n.acceptedSeq, -1);
      expect(container.read(liveHistoryProvider(sid)), isEmpty);
      final msgs = await container.read(messageListProvider(sid).future);
      expect(msgs, isEmpty);
      expect(host.requests.where((r) => r['method'] == 'session/page'), isEmpty);
      // Explicit -1 page request is allowed but not used for initial load
      final client = ConnectionClient(baseUrl: base);
      addTearDown(client.dispose);
      // Direct call with throughSeq -1 should not probe, should return empty
      // We mock host to return empty for -1
      final res = await client.getSessionHistory(SessionId(sid), throughSeq: -1);
      expect(res.entries, isEmpty);
    });
  });

  group('F. No regex cursor discovery', () {
    test('connection_client has no past-cursor parsing', () {
      final src = File('lib/src/core/connection/connection_client.dart').readAsStringSync();
      expect(src.contains('past cursor'), isFalse);
      expect(src.contains('RegExp'), isFalse);
    });
  });
}
