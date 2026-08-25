import 'message_provider.dart';
import '../tool/tool_models.dart';

class ChatUser {
  const ChatUser({required this.id, this.firstName});
  final String id;
  final String? firstName;
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.user,
    this.createdAt,
    this.customProperties,
    this.isMarkdown = false,
  });

  ChatMessage.rich({
    required this.user,
    required String resultKind,
    required Map<String, dynamic> data,
    required String id,
  })  : text = '',
        createdAt = null,
        isMarkdown = false,
        customProperties = {
          'id': id,
          'resultKind': resultKind,
          'resultData': data,
        };

  ChatMessage.loading({
    required this.user,
    required String id,
    required String text,
  })  : createdAt = null,
        isMarkdown = false,
        customProperties = {
          'id': id,
          'isLoading': true,
        },
        text = text;

  final String text;
  final ChatUser user;
  final DateTime? createdAt;
  final Map<String, dynamic>? customProperties;
  final bool isMarkdown;
}

class ChatMessagesController {
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  void updateMessage(ChatMessage msg) {
    final String? id = msg.customProperties?['id'] as String? ?? msg.text;
    final int idx = _messages.indexWhere((m) => (m.customProperties?['id'] as String?) == id || m.text == msg.text && m.user.id == msg.user.id);
    if (idx != -1) {
      _messages[idx] = msg;
    } else {
      _messages.add(msg);
    }
  }

  void dispose() {}
}

/// Convert one harness [Message] into one or more package [ChatMessage]s.
///
/// A harness assistant message with mixed blocks (reasoning + text +
/// tool-call) becomes multiple chat bubbles so the package can render
/// thinking collapsible, streamed markdown, and rich tool-call cards
/// with the right resultKinds.
List<ChatMessage> harnessMessageToChatMessages(
  Message msg, {
  required ChatUser aiUser,
  required ChatUser currentUser,
}) {
  Map<String, dynamic> _citations() => {
    if (msg.citations.isNotEmpty)
      'citations': msg.citations.map((c) => {'label': c.label, 'url': c.url, 'title': c.title}).toList(),
  };

  // Retry disclosure — non-message chat node.
  if (msg.isRetry) {
    return [
      ChatMessage.rich(
        user: aiUser,
        resultKind: 'retry',
        data: {
          'retry': msg.retry,
          'maxRetries': msg.maxRetries,
          'delayMs': msg.delayMs,
          'failureMessage': msg.failureMessage,
          'retryMode': msg.retryMode,
          ..._citations(),
        },
        id: 'retry-${msg.id}',
      ),
    ];
  }

  if (msg.role == MessageRole.user) {
    return [
      ChatMessage(
        text: msg.content,
        user: currentUser,
        createdAt: DateTime.fromMillisecondsSinceEpoch(msg.time),
        customProperties: {'id': msg.id, ..._citations()},
      ),
    ];
  }

  if (msg.role == MessageRole.system) {
    return [
      ChatMessage.rich(
        user: aiUser,
        resultKind: 'error',
        data: {'text': msg.content, 'time': msg.time, ..._citations()},
        id: 'sys-${msg.id}',
      ),
    ];
  }

  if (msg.content.trim().isEmpty && !msg.streaming && msg.citations.isEmpty) {
    final List<AssistantBlock>? b = msg.blocks;
    // React AssistantMarkdown parity: an assistant message whose blocks carry
    // no renderable text (tool-call-only or fully empty) emits nothing — tool
    // rows come only from real tool/call events.
    final bool hasRenderable =
        b != null && b.any((block) => (block.text ?? '').trim().isNotEmpty || block.kind != 'tool-call');
    if (!hasRenderable) {
      return const <ChatMessage>[];
    }
  }

  // Assistant — look at blocks for rich rendering.
  final blocks = msg.blocks;
  if (blocks != null && blocks.isNotEmpty) {
    // Streaming reasoning-only (partial thought before text arrives): show
    // the loading morph so the user sees "Thinking…" immediately.
    final bool isStreaming = msg.streaming;
    final repo = blocks.whereType<AssistantBlock>().toList();
    final bool allReasoning = repo.isNotEmpty && repo.every((b) => b.kind == 'reasoning');
    if (isStreaming && allReasoning) {
      return [
        ChatMessage.loading(
          user: aiUser,
          id: msg.id,
          text: 'Thinking…',
        ),
      ];
    }

    final List<ChatMessage> out = [];
    bool emittedRich = false;
    for (final block in blocks) {
      switch (block.kind) {
        case 'reasoning':
          final String reasonText = (block.text ?? '').trim();
          if (reasonText.isEmpty) break;
          out.add(ChatMessage.rich(
            user: aiUser,
            resultKind: 'reasoning',
            data: {'text': reasonText},
            id: '${msg.id}-reasoning',
          ));
          emittedRich = true;
          break;
        case 'tool-call':
          // React parity: assistant-message tool-call heads are skipped in
          // AssistantMarkdown; tool cards render only from the tool list
          // (real tool/call + tool/result events). Emit nothing here.
          break;
        case 'text':
          out.add(ChatMessage(
            text: block.text ?? '',
            user: aiUser,
            createdAt: DateTime.fromMillisecondsSinceEpoch(msg.time),
            isMarkdown: true,
            customProperties: {
              'id': '${msg.id}-text',
              if (isStreaming) 'isStreaming': true,
              ..._citations(),
            },
          ));
          break;
        default:
          out.add(ChatMessage(
            text: msg.content,
            user: aiUser,
            createdAt: DateTime.fromMillisecondsSinceEpoch(msg.time),
            isMarkdown: true,
            customProperties: {
              'id': msg.id,
              if (isStreaming) 'isStreaming': true,
              ..._citations(),
            },
          ));
      }
    }
    // If we emitted at least one rich bubble above, callers expected the
    // answer bubble to come from text blocks. When blocks produced only
    // rich bubbles (tool-call only), still emit a fallback if content present.
    if (emittedRich && blocks.every((b) => b.kind != 'text') && msg.content.isNotEmpty) {
      out.add(ChatMessage(
        text: msg.content,
        user: aiUser,
        createdAt: DateTime.fromMillisecondsSinceEpoch(msg.time),
        isMarkdown: true,
        customProperties: {'id': '${msg.id}-text', ..._citations()},
      ));
    }
    return out.isEmpty
        ? [
          ChatMessage(
            text: msg.content,
            user: aiUser,
            createdAt: DateTime.fromMillisecondsSinceEpoch(msg.time),
            isMarkdown: true,
            customProperties: {'id': msg.id, ..._citations()},
          ),
        ]
        : out;
  }

  // Suppress empty assistant bubbles (mirrors React AssistantMarkdown hasVisible:
  // nothing to paint when streaming is false and the only visible block kinds
  // are missing/empty — prevents the blank "Assistant" headers in screenshot 2).
  if (msg.content.trim().isEmpty && !msg.streaming && msg.citations.isEmpty) {
    return const <ChatMessage>[];
  }
  return [
    ChatMessage(
      text: msg.content,
      user: aiUser,
      createdAt: DateTime.fromMillisecondsSinceEpoch(msg.time),
      isMarkdown: true,
      customProperties: {
        'id': msg.id,
        if (msg.streaming) 'isStreaming': true,
        ..._citations(),
      },
    ),
  ];
}

/// Convert one harness [ToolCall] into a rich tool-call bubble.
ChatMessage toolCallToChatMessage(ToolCall call, ChatUser aiUser) {
  return ChatMessage.rich(
    user: aiUser,
    resultKind: 'tool-call',
    data: {
      'toolName': call.toolName,
      'callId': call.id,
      'status': call.status.name,
      'kind': call.kind.name,
      'args': call.args,
      'result': call.result,
      'time': call.time,
    },
    id: 'tool-${call.id}',
  );
}

/// Sync a desired set of harness messages/tool-calls into a package
/// [ChatMessagesController] by stable id.
///
/// Adds new bubbles and updates existing ones in place so the package's
/// streaming animation is preserved. Stale ids not in `desired` are left
/// in place (transcripts are append-only; removals are handled by a
/// page reload or `clearMessages()` elsewhere).
void syncMessagesToController(
  List<Message> messages,
  List<ToolCall> toolCalls,
  ChatMessagesController controller, {
  required ChatUser aiUser,
  required ChatUser currentUser,
}) {
  final List<ChatMessage> desired = [];
  for (final m in messages) {
    desired.addAll(harnessMessageToChatMessages(m, aiUser: aiUser, currentUser: currentUser));
  }
  for (final c in toolCalls) {
    desired.add(toolCallToChatMessage(c, aiUser));
  }
  for (final chat in desired) {
    controller.updateMessage(chat);
  }
}
