import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/conversation_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEvent _ev(String type, Map<String, dynamic> data, {int seq = 0, int time = 1000}) =>
    SessionEvent(type: type, data: data, seq: seq, time: time);

HistoryEntry _h(String type, Map<String, dynamic> data, {int seq = 0, int time = 1000, Map<String, dynamic>? view}) =>
    HistoryEntry(event: _ev(type, data, seq: seq, time: time), view: view);

void main() {
  group('ConversationReducer', () {
    test('1. normal text response renders correctly', () {
      final r = reduceConversation([
        _h('user/message', {'content': 'hello'}, seq: 0),
        _h('assistant/message', {'content': 'Hi there'}, seq: 1),
      ]);
      expect(r.messages.any((m) => m.content == 'Hi there'), isTrue);
      expect(r.turnFailed, isFalse);
      expect(r.errorMessage, isNull);
    });

    test('2. streaming response: one assistant message updates incrementally', () {
      final r = reduceConversation([
        _h('user/message', {'content': 'hi'}, seq: 0),
        _h('assistant/chunk', {'delta': 'Hello'}, seq: 1),
        _h('assistant/chunk', {'delta': ' world'}, seq: 2),
      ], isRunning: true);
      // streaming buffer emitted as one message
      final assistants = r.messages.where((m) => m.role.toString().contains('assistant')).toList();
      expect(assistants, hasLength(1));
      expect(assistants.first.streaming, isTrue);
      expect(assistants.first.content, 'Hello world');
    });

    test('3. thinking/reasoning rendered as collapsible thinking section', () {
      final r = reduceConversation([
        _h('user/message', {'content': 'q'}, seq: 0),
        _h('assistant/chunk', {'delta': {'type': 'reasoning', 'text': 'let me think'}}, seq: 1),
        _h('assistant/chunk', {'delta': {'type': 'text', 'text': 'answer'}}, seq: 2),
      ], isRunning: true);
      // Reducer keeps reasoning separate: expect a reasoning block on the assistant message
      final assistant = r.messages.firstWhere((m) => m.role.toString().contains('assistant'));
      expect(assistant.blocks, isNotNull);
      expect(assistant.blocks!.any((b) => b.kind == 'reasoning'), isTrue);
      // reasoning text not merged into main content
      expect(assistant.content, 'answer');
    });

    test('4. tool call + tool result: tool card pending/running -> completed', () {
      final r = reduceConversation([
        _h('user/message', {'content': 'do it'}, seq: 0),
        _h('assistant/message', {
          'content': [
            {'type': 'tool-call', 'callId': 'c1', 'name': 'read', 'arguments': '{"path":"a.txt"}'}
          ]
        }, seq: 1),
        _h('tool/call', {'callId': 'c1', 'name': 'read', 'args': {'path': 'a.txt'}}, seq: 2),
        _h('tool/result', {'callId': 'c1', 'result': 'file content', 'isError': false}, seq: 3),
      ]);
      expect(r.tools, hasLength(1));
      expect(r.tools.first.status.toString(), contains('success'));
    });

    test('5. tool execution failure -> failed state', () {
      final r = reduceConversation([
        _h('tool/call', {'callId': 'c1', 'name': 'bash', 'args': {'command': 'ls'}}, seq: 0),
        _h('tool/result', {'callId': 'c1', 'isError': true, 'result': 'permission denied'}, seq: 1),
      ]);
      expect(r.tools.first.status.toString(), contains('error'));
    });

    test('6. model failure before tool execution: no orphaned running tools', () {
      final r = reduceConversation([
        _h('user/message', {'content': 'go'}, seq: 0),
        _h('tool/call', {'callId': 'c1', 'name': 'skill', 'args': {}}, seq: 1),
        _h('tool/call', {'callId': 'c2', 'name': 'bash', 'args': {}}, seq: 2),
        _h('tool/call', {'callId': 'c3', 'name': 'read', 'args': {}}, seq: 3),
        _h('turn/end', {'reason': {'kind': 'error', 'error': {'type': 'ModelError', 'message': '401 ModelError: Free promotion has ended for DeepSeek V4 Flash Free'}}}, seq: 4),
      ]);
      expect(r.tools.where((t) => t.status.toString() == 'ToolCallStatus.running'), isEmpty);
      expect(r.tools, hasLength(3));
      // unresolved tools become cancelled / not-executed
      expect(r.tools.every((t) => t.status.toString().contains('cancel')), isTrue);
      // One concise error, not per-tool running cards.
      expect(r.errorMessage, isNotNull);
      // React displayFailureMessage: non-AUTH failures project the provider
      // message verbatim ('This turn failed\n' + message) — no legacy mapping.
      expect(r.errorMessage, contains('This turn failed'));
      expect(r.errorMessage, contains('promotion has ended'));
      expect(r.errorMessage, contains('ModelError'));
    });

    test('7. model failure after some tools complete: completed stay, unresolved cancelled', () {
      final r = reduceConversation([
        _h('tool/call', {'callId': 'c1', 'name': 'read', 'args': {'path': 'a'}}, seq: 0),
        _h('tool/result', {'callId': 'c1', 'result': 'ok'}, seq: 1),
        _h('tool/call', {'callId': 'c2', 'name': 'bash', 'args': {}}, seq: 2),
        _h('tool/call', {'callId': 'c3', 'name': 'skill', 'args': {}}, seq: 3),
        _h('turn/end', {'reason': {'kind': 'error', 'error': {'message': '401 ModelError: Free promotion has ended for DeepSeek V4 Flash Free'}}}, seq: 4),
      ]);
      final c1 = r.tools.firstWhere((t) => t.id == 'c1');
      expect(c1.status.toString(), contains('success'));
      expect(r.tools.where((t) => t.id == 'c2' || t.id == 'c3').every((t) => t.status.toString().contains('cancel')), isTrue);
    });

    test('8. no empty {} tool cards in final UI', () {
      final r = reduceConversation([
        _h('tool/call', {'callId': 'c1', 'name': 'skill', 'args': {}}, seq: 0),
        _h('turn/end', {'reason': {'kind': 'error', 'error': {'message': '401 error'}}}, seq: 1),
      ]);
      // Cancelled tools must not carry empty payloads as visible content
      for (final t in r.tools) {
        expect(t.args.isEmpty, isTrue);
        // Adapter is responsible for hiding empty args; reducer keeps args empty.
        // Ensure args is {} not "{'argsRaw': '{}'}"
      }
      // Friendly renderer check is in adapter; here we ensure no tool has a non-empty raw "{}" that would be shown.
    });

    test('9. raw backend JSON not shown as primary error message', () {
      final r = reduceConversation([
        _h('turn/end', {'reason': {'kind': 'error', 'error': {'type': 'ModelError', 'message': 'Free promotion has ended for DeepSeek V4 Flash Free'}}}, seq: 0),
      ]);
      expect(r.errorMessage, isNot(contains('ModelError')));
      expect(r.errorMessage, isNot(contains('"type"')));
      expect(r.rawError, contains('ModelError'));
    });

    test('10. retry/new message starts with clean tool state', () {
      final r1 = reduceConversation([
        _h('tool/call', {'callId': 'c1', 'name': 'read', 'args': {}}, seq: 0),
        _h('turn/end', {'reason': {'kind': 'error', 'error': {'message': 'fail'}}}, seq: 1),
      ]);
      expect(r1.tools.first.status.toString(), contains('cancel'));

      final r2 = reduceConversation([
        _h('user/message', {'content': 'retry'}, seq: 10),
        _h('assistant/message', {'content': 'ok'}, seq: 11),
      ]);
      expect(r2.tools, isEmpty);
      expect(r2.turnFailed, isFalse);
    });

    test('agentError surfaces as friendly error and cancels pending tools', () {
      final r = reduceConversation([
        _h('tool/call', {'callId': 'c1', 'name': 'read', 'args': {}}, seq: 0),
      ], agentError: '401 ModelError: Free promotion has ended for DeepSeek V4 Flash Free');
      expect(r.tools.first.status.toString(), contains('cancel'));
      expect(r.errorMessage, contains('promotion has ended'));
      expect(r.turnFailed, isTrue);
    });
  });
}
