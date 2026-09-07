import 'package:dsh_flutter/src/features/conversation/chat_ui_adapter.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/features/tool/tool_models.dart';
import 'package:flutter_test/flutter_test.dart';

ChatUser _aiUser = const ChatUser(id: 'ai', firstName: 'Assistant');
ChatUser _currentUser = const ChatUser(id: 'user', firstName: 'You');

void main() {
  group('harnessMessageToChatMessages', () {
    test('maps user message to plain bubble', () {
      final msg = const Message(
        id: 'user-1',
        role: MessageRole.user,
        content: 'hi there',
        time: 1,
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list, hasLength(1));
      expect(list.first.user.id, 'user');
      expect(list.first.text, 'hi there');
      expect(list.first.customProperties!['id'], 'user-1');
    });

    test('maps plain assistant text to markdown bubble', () {
      final msg = const Message(
        id: 'assistant-1',
        role: MessageRole.assistant,
        content: 'Hello **world**',
        time: 1,
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list, hasLength(1));
      expect(list.first.user.id, 'ai');
      expect(list.first.isMarkdown, isTrue);
      expect(list.first.text, contains('world'));
    });

    test('splits reasoning/text blocks into two bubbles (reasoning collapsible + answer)', () {
      final msg = Message(
        id: 'assistant-2',
        role: MessageRole.assistant,
        content: 'final answer',
        time: 1,
        blocks: [
          AssistantBlock.reasoning('the thought process'),
          AssistantBlock.text('final answer'),
        ],
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list, hasLength(2));
      expect(list.first.customProperties!['resultKind'], 'reasoning');
      expect(
        list.first.customProperties!['resultData']['text'],
        'the thought process',
      );
      expect(list.last.isMarkdown, isTrue);
      expect(list.last.text, 'final answer');
    });

    test('streaming reasoning emits loading bubble', () {
      final msg = Message(
        id: 'assistant-3',
        role: MessageRole.assistant,
        content: '',
        time: 1,
        streaming: true,
        blocks: [AssistantBlock.reasoning('partial thought')],
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list, hasLength(1));
      expect(list.first.customProperties!['isLoading'], isTrue);
      expect(list.first.text, contains('Thinking'));
    });

    test('tool-call blocks in assistant message are not rendered as bubbles (React parity)', () {
      // React AssistantMarkdown skips tool-call heads (case 'tool-call': break).
      // Tool rows are rendered only from the ToolCall list (tool/call events).
      final msg = Message(
        id: 'assistant-4',
        role: MessageRole.assistant,
        content: '',
        time: 1,
        blocks: [
          AssistantBlock.toolCall(
            callId: 'call-1',
            name: 'read',
            argsRaw: '{"path":"README.md"}',
          ),
        ],
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list, isEmpty);
    });

    test('retry message becomes rich retry bubble', () {
      final msg = Message(
        id: 'retry-1',
        role: MessageRole.system,
        content: '',
        time: 1,
        retry: 1,
        maxRetries: 3,
        delayMs: 1200,
        failureMessage: 'timeout',
        retryMode: 'normal',
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list, hasLength(1));
      expect(list.first.customProperties!['resultKind'], 'retry');
    });

    test('system turn/error becomes rich error bubble', () {
      final msg = const Message(
        id: 'err-1',
        role: MessageRole.system,
        content: 'Model not supported',
        time: 1,
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list.first.customProperties!['resultKind'], 'error');
    });

    test('streaming text bubble carries isStreaming flag for animation', () {
      final msg = const Message(
        id: 'assistant-5',
        role: MessageRole.assistant,
        content: 'partial…',
        time: 1,
        streaming: true,
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(list.first.customProperties!['isStreaming'], isTrue);
    });

    test('citations in customProperties survive', () {
      final msg = Message(
        id: 'assistant-6',
        role: MessageRole.assistant,
        content: 'see below',
        time: 1,
        citations: const [Citation(label: '[1]', url: 'https://example.com')],
      );
      final list = harnessMessageToChatMessages(
        msg,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect((list.first.customProperties!['citations'] as List).length, 1);
    });
  });

  group('toolCallToChatMessage', () {
    test('maps ToolCall to rich tool-call bubble', () {
      const call = ToolCall(
        id: 'c1',
        toolName: 'bash',
        kind: ToolCallKind.bash,
        status: ToolCallStatus.running,
        args: {'command': 'ls'},
        time: 99,
      );
      final msg = toolCallToChatMessage(call, _aiUser);
      expect(msg.customProperties!['resultKind'], 'tool-call');
      expect(msg.customProperties!['resultData']['toolName'], 'bash');
      expect(msg.customProperties!['resultData']['status'], 'running');
    });
  });

  group('syncMessagesToController', () {
    test('adds and updates by stable id', () {
      final controller = ChatMessagesController();
      addTearDown(controller.dispose);
      final msgs = [
        const Message(
          id: 'user-1',
          role: MessageRole.user,
          content: 'hi',
          time: 1,
        ),
        const Message(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'hello',
          time: 2,
        ),
      ];
      syncMessagesToController(
        msgs,
        const [],
        controller,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(controller.messages.length, 2);

      // Update in place: change text
      final updated = [
        const Message(
          id: 'user-1',
          role: MessageRole.user,
          content: 'hi',
          time: 1,
        ),
        const Message(
          id: 'assistant-1',
          role: MessageRole.assistant,
          content: 'hello world',
          time: 2,
        ),
      ];
      syncMessagesToController(
        updated,
        const [],
        controller,
        aiUser: _aiUser,
        currentUser: _currentUser,
      );
      expect(controller.messages.length, 2);
      expect(
        controller.messages
            .firstWhere(
              (m) => (m.customProperties?['id'] as String?) == 'assistant-1',
            )
            .text,
        contains('world'),
      );
    });
  });
}
