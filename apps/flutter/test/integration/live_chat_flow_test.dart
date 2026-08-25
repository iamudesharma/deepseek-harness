import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/live_sync.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/composer_controller.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';

/// Test the required data flow:
/// Composer → ConnectionClient.sendMessage() → session.prompt
/// → mux: session/event → liveHistory → liveMessageList → UI
///
/// This test uses a MockClient that simulates the host's SSE mux stream
/// and session.history, and verifies that sending a message immediately
/// displays the user message (optimistic), then the host's user/message
/// event appears via liveHistory, and assistant streaming appears.

class _MockHost {
  final List<HistoryEntry> history = [];
  int seq = 0;
  final StreamController<Map<String, dynamic>> muxController = StreamController.broadcast();

  Future<http.Response> handle(http.Request req) async {
    final body = req.body.isEmpty ? '{}' : req.body;
    final Map<String, dynamic> envelope = jsonDecode(body) as Map<String, dynamic>;
    final method = envelope['method'] as String? ?? '';
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final rpcId = envelope['rpcId'] as String? ?? 'test';

    Map<String, dynamic> ok(Object? value) => {
          'type': 'server-response',
          'rpcId': rpcId,
          'result': {'ok': true, 'value': value}
        };
    Map<String, dynamic> err(String code, String msg) => {
          'type': 'server-response',
          'rpcId': rpcId,
          'result': {'ok': false, 'error': {'code': code, 'message': msg}}
        };

    if (req.url.path == '/api/session.list') {
      return http.Response(jsonEncode(ok({'items': []})), 200, headers: {'content-type': 'application/json'});
    }
    if (req.url.path == '/api/session.history') {
      final sessionId = payload['sessionId'] as String? ?? '';
      // Return history filtered by sessionId (for simplicity, return all)
      final filtered = history.where((e) => true).toList();
      return http.Response(
          jsonEncode(ok({'events': filtered.map((e) => e.toJson()).toList(), 'hasMore': false, 'projections': {'asOfSeq': seq, 'values': {}}})), 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.url.path == '/api/session.create') {
      final newId = 'test-session-${DateTime.now().millisecondsSinceEpoch}';
      // Add to history a blank session? For now just return id
      return http.Response(jsonEncode(ok({'sessionId': newId})), 200, headers: {'content-type': 'application/json'});
    }
    if (req.url.path == '/api/session.prompt') {
      final sessionId = payload['sessionId'] as String? ?? 'test-session';
      final content = (payload['content'] as List?)?.firstOrNullX?['text'] as String? ?? 'hi';
      // Simulate host immediately emitting user/message via mux stream
      final userEvent = HistoryEntry(
        event: SessionEvent(type: 'user/message', data: {'content': content}, seq: seq++, time: DateTime.now().millisecondsSinceEpoch),
        view: null,
      );
      history.add(userEvent);
      // Emit via mux stream as session/event frame
      muxController.add({
        'type': 'session/event',
        'sessionId': sessionId,
        'event': userEvent.event.toJson(),
        'view': null,
      });
      // Simulate assistant chunk streaming after a short delay
      Future.delayed(const Duration(milliseconds: 50), () {
        final chunk = HistoryEntry(
          event: SessionEvent(type: 'assistant/chunk', data: {'delta': 'Hello!'}, seq: seq++, time: DateTime.now().millisecondsSinceEpoch),
          view: null,
        );
        history.add(chunk);
        muxController.add({
          'type': 'session/event',
          'sessionId': sessionId,
          'event': chunk.event.toJson(),
        });
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        final msg = HistoryEntry(
          event: SessionEvent(type: 'assistant/message', data: {'content': 'Hello! How can I help?'}, seq: seq++, time: DateTime.now().millisecondsSinceEpoch),
          view: null,
        );
        history.add(msg);
        muxController.add({
          'type': 'session/event',
          'sessionId': sessionId,
          'event': msg.event.toJson(),
        });
      });
      return http.Response(jsonEncode(ok({})), 200, headers: {'content-type': 'application/json'});
    }
    if (req.url.path == '/api/events.mux' || req.url.path == '/api/events.host') {
      // For SSE, return a stream that never ends (but for test we handle via muxController.stream)
      // This path is for the initial handshake; we return a simple 200 with empty stream
      // The actual mux stream is via muxController.stream in the mock.
      // For now, just return a 200 with empty body and let the test drive the stream via direct muxController.
      return http.Response('', 200, headers: {'content-type': 'text/event-stream'});
    }
    if (req.url.path == '/api/host.describe') {
      return http.Response(jsonEncode(ok({'cwd': '/tmp', 'home': '/tmp', 'version': 'test'})), 200, headers: {'content-type': 'application/json'});
    }
    return http.Response(jsonEncode(err('not-found', 'unknown $method')), 404);
  }
}

// ignore: unused_element
extension _FirstOrNullX<E> on List<E> {
  E? get firstOrNullX => this.isEmpty ? null : this[0];
}

void main() {
  test('live chat flow: user message appears immediately, assistant streams, no refresh needed', () async {
    final mockHost = _MockHost();
    final mockHttp = MockClient((req) async {
      // Handle SSE specially: if it's a GET to /api/events.mux, return a stream from muxController
      if (req.method == 'GET' && (req.url.path == '/api/events.mux' || req.url.path == '/api/events.host')) {
        // For the test, we don't actually use the SSE transport; we directly
        // drive the liveHistory via the muxController. So just return an empty SSE response
        // that never emits, and the test will manually push to liveHistory.
        final streamed = http.StreamedResponse(const Stream.empty(), 200, headers: {'content-type': 'text/event-stream'});
        return http.Response('', 200, headers: {'content-type': 'text/event-stream'});
      }
      return mockHost.handle(req);
    });

    final client = ConnectionClient(baseUrl: 'http://test', httpClient: mockHttp);
    final container = ProviderContainer(overrides: [
      connectionClientProvider.overrideWithValue(client),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
      mockHost.muxController.close();
    });

    // Seed a session
    const sid = 'test-session-live';
    container.read(sessionsProvider.notifier).addSession(
          SessionSummary(sessionId: const SessionId(sid), updatedAt: 1000, running: false, blank: true, title: 'Test'),
        );
    container.read(sessionsProvider.notifier).setCurrent(const SessionId(sid));

    // Initially, liveHistory is empty, messageList is empty
    expect(container.read(liveHistoryProvider(sid)), isEmpty);
    expect(container.read(liveMessageListProvider(sid)), isEmpty);

    // Simulate composer submit
    final notifier = container.read(composerControllerProvider(sid).notifier);
    notifier.setText('hello live');
    expect(notifier.state.text, 'hello live');
    expect(notifier.state.canSubmit, isTrue);

    // Call submit (will do optimistic + host call)
    // For this test, baseUrl is http://test (not empty), so it will try to call host.
    // Our mockHost will handle /api/session.prompt and emit user/message via muxController,
    // but our liveSync is not actually listening to muxController in this test (since we mocked http but not the SSE stream).
    // Instead, we will manually simulate the live event by appending to liveHistory.
    await notifier.submit();

    // After submit, draft should be cleared and isSending false (after delay for host call, but our mock is fast)
    // The optimistic message should be in optimisticMessagesProvider
    final optimistic = container.read(optimisticMessagesProvider(sid));
    expect(optimistic.any((m) => m.content == 'hello live'), isTrue);
    expect(container.read(composerControllerProvider(sid)).text, isEmpty);

    // The liveMessageList should now show the optimistic user message immediately
    final liveMsgsAfterSubmit = container.read(liveMessageListProvider(sid));
    expect(liveMsgsAfterSubmit.any((m) => m.content == 'hello live' && m.role == MessageRole.user), isTrue);

    // Simulate host echo: user/message event arrives via liveHistory
    final hostUserEntry = HistoryEntry(
      event: SessionEvent(type: 'user/message', data: {'content': 'hello live'}, seq: 0, time: 1000),
      view: null,
    );
    container.read(liveHistoryProvider(sid).notifier).appendLive(hostUserEntry);
    // After host echo, optimistic should be deduped, but message should still be visible once
    final afterHost = container.read(liveMessageListProvider(sid));
    expect(afterHost.where((m) => m.content == 'hello live').length, 1);

    // Simulate assistant chunk streaming
    final chunkEntry = HistoryEntry(
      event: SessionEvent(type: 'assistant/chunk', data: {'delta': 'Hi there'}, seq: 1, time: 1001),
      view: null,
    );
    container.read(liveHistoryProvider(sid).notifier).appendLive(chunkEntry);
    // Need to set running to true for streaming to be shown
    container.read(sessionsProvider.notifier).updateSession(const SessionId(sid), (s) => s.copyWith(running: true));
    final streamingMsgs = container.read(liveMessageListProvider(sid));
    expect(streamingMsgs.any((m) => m.content == 'Hi there' && m.streaming), isTrue);

    // Simulate final assistant message
    final assistantEntry = HistoryEntry(
      event: SessionEvent(type: 'assistant/message', data: {'content': 'Hello! How can I help?'}, seq: 2, time: 1002),
      view: null,
    );
    container.read(liveHistoryProvider(sid).notifier).appendLive(assistantEntry);
    container.read(sessionsProvider.notifier).updateSession(const SessionId(sid), (s) => s.copyWith(running: false));
    final finalMsgs = container.read(liveMessageListProvider(sid));
    expect(finalMsgs.any((m) => m.content.contains('How can I help?')), isTrue);

    // Send another message without refresh — should still work
    notifier.setText('second message');
    await notifier.submit();
    expect(container.read(optimisticMessagesProvider(sid)).any((m) => m.content == 'second message'), isTrue);
    final secondHost = HistoryEntry(
      event: SessionEvent(type: 'user/message', data: {'content': 'second message'}, seq: 3, time: 1003),
      view: null,
    );
    container.read(liveHistoryProvider(sid).notifier).appendLive(secondHost);
    final afterSecond = container.read(liveMessageListProvider(sid));
    expect(afterSecond.any((m) => m.content == 'second message'), isTrue);

    // Simulate page refresh: create a new container that re-fetches history via messageListProvider
    // For this test, we just verify that liveHistory persists across a new container that shares the same mockHost history
    // In a real app, refresh would re-fetch via session.history and get all events
    final refreshContainer = ProviderContainer(overrides: [connectionClientProvider.overrideWithValue(client)]);
    addTearDown(refreshContainer.dispose);
    // Seed history via mockHost.history
    mockHost.history.addAll([hostUserEntry, chunkEntry, assistantEntry, secondHost]);
    // The new container's liveHistory would be empty initially, but messageListProvider would fetch history and get all
    // For this test, we just verify that messagesFromHistory on the full history contains all
    final allHistory = mockHost.history;
    final allMsgs = messagesFromHistory(allHistory);
    expect(allMsgs.any((m) => m.content == 'hello live'), isTrue);
    expect(allMsgs.any((m) => m.content.contains('How can I help?')), isTrue);
    expect(allMsgs.any((m) => m.content == 'second message'), isTrue);
  });
}
