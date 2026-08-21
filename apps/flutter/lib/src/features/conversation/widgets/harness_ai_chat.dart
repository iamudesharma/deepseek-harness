import 'package:flutter/material.dart';
import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../tool/tool_models.dart';
import '../composer_controller.dart';
import '../message_provider.dart';
import '../chat_ui_adapter.dart';

/// Conversation chat UI on top of `flutter_gen_ai_chat_ui`.
///
/// Syncs harness `Message`/`ToolCall` streams into a `ChatMessagesController`
/// so thinking collapses, tool calls render as rich cards, and retries
/// disclose — fixing the screenshot bugs where thinking was a plain
/// markdown paragraph and tool calls printed the literal
/// `Tool: \${call.toolName}` template.
class HarnessAiChat extends ConsumerStatefulWidget {
  const HarnessAiChat({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<HarnessAiChat> createState() => _HarnessAiChatState();
}

class _HarnessAiChatState extends ConsumerState<HarnessAiChat> {
  late final ChatMessagesController _controller;
  final ChatUser _currentUser = const ChatUser(id: 'user', firstName: 'You');
  final ChatUser _aiUser = const ChatUser(id: 'ai', firstName: 'Assistant');

  @override
  void initState() {
    super.initState();
    _controller = ChatMessagesController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sync(List<Message> messages, List<ToolCall> toolCalls) {
    syncMessagesToController(messages, toolCalls, _controller, aiUser: _aiUser, currentUser: _currentUser);
  }

  @override
  Widget build(BuildContext context) {
    final List<Message> messages = ref.watch(liveMessageListProvider(widget.sessionId));
    final List<ToolCall> toolCalls = ref.watch(liveToolCallsProvider(widget.sessionId));
    final String? agentError = ref.watch(agentErrorProvider(widget.sessionId));
    final AsyncValue<List<Message>> asyncMessages = ref.watch(messageListProvider(widget.sessionId));

    // Surface fetch failures like the previous _LiveChatView error branch.
    if (asyncMessages.hasError && messages.isEmpty && toolCalls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 28, color: Theme.of(context).extension<DswThemeExtension>()?.aliases.stateErrorPrimary),
            const SizedBox(height: 8),
            Text('Failed to load messages', style: TextStyle(color: Theme.of(context).extension<DswThemeExtension>()?.aliases.labelPrimary)),
            const SizedBox(height: 4),
            SelectableText(asyncMessages.error.toString(), style: TextStyle(fontSize: 12, color: Theme.of(context).extension<DswThemeExtension>()?.aliases.labelSecondary)),
          ]),
        ),
      );
    }

    // Sync harness transcript → controller outside the build frame so
    // `notifyListeners` doesn't trigger a consistency error, and guard
    // so controllers that never change don't keep scheduling frames (which
    // would leave pumpAndSettle hanging forever in tests).
    ref.listen<List<Message>>(liveMessageListProvider(widget.sessionId), (previous, next) {
      final String? err = ref.read(agentErrorProvider(widget.sessionId));
      final List<Message> withError = err == null
          ? next
          : [
              ...next,
              Message(id: 'agent-error', role: MessageRole.system, content: err, time: DateTime.now().millisecondsSinceEpoch),
            ];
      final List<ToolCall> currentTools = ref.read(liveToolCallsProvider(widget.sessionId));
      _sync(withError, currentTools);
    });
    ref.listen<List<ToolCall>>(liveToolCallsProvider(widget.sessionId), (previous, next) {
      _sync(messages, next);
    });

    // One-shot initial sync on first build.
    if (_controller.messages.isEmpty && (messages.isNotEmpty || toolCalls.isNotEmpty || messages.isNotEmpty)) {
      final List<Message> withError = agentError == null
          ? messages
          : [
              ...messages,
              Message(id: 'agent-error', role: MessageRole.system, content: agentError, time: DateTime.now().millisecondsSinceEpoch),
            ];
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync(withError, toolCalls));
    }

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);

    return AiChatWidget(
      currentUser: _currentUser,
      aiUser: _aiUser,
      controller: _controller,
      onSendMessage: (ChatMessage chatMessage) {
        // Bridge the package's send into the harness prompt surface.
        final String text = chatMessage.text.trim();
        if (text.isEmpty) return;
        final composer = ref.read(composerControllerProvider(widget.sessionId).notifier);
        composer.setText(text);
        composer.submit();
      },
      enableMarkdownStreaming: true,
      streamingWordByWord: true,
      inputOptions: InputOptions(
        sendOnEnter: true,
        decoration: const InputDecoration(hintText: 'Ask anything…'),
      ),
      messageOptions: MessageOptions(
        showTime: false,
        bubbleStyle: BubbleStyle(
          userBubbleColor: aliases.specificBubble,
          aiBubbleColor: aliases.bgLayer2,
          userNameColor: aliases.labelPrimary,
          aiNameColor: aliases.labelSecondary,
          enableShadow: false,
        ),
      ),
      resultRenderers: <String, ResultBuilder>{
        'reasoning': (BuildContext context, Map<String, dynamic> data) {
          final String text = (data['text'] as String?) ?? '';
          return _ReasoningCard(text: text);
        },
        'tool-call': (BuildContext context, Map<String, dynamic> data) {
          final String name = (data['toolName'] as String?) ?? (data['callId'] as String?) ?? 'tool';
          final String status = (data['status'] as String?) ?? 'running';
          final dynamic raw = data['argsRaw'] ?? data['args'];
          final String args = raw is String ? raw : (raw is Map ? raw.toString() : '');
          final dynamic result = data['result'];
          return _ToolCallCard(toolName: name, status: status, argsRaw: args, result: result);
        },
        'retry': (BuildContext context, Map<String, dynamic> data) {
          final int retry = (data['retry'] as int?) ?? 0;
          final int maxRetries = (data['maxRetries'] as int?) ?? 0;
          final int delayMs = (data['delayMs'] as int?) ?? 0;
          final String msg = (data['failureMessage'] as String?) ?? '';
          final String mode = (data['retryMode'] as String?) ?? 'normal';
          return _RetryCard(retry: retry, maxRetries: maxRetries, delayMs: delayMs, failureMessage: msg, retryMode: mode);
        },
        'error': (BuildContext context, Map<String, dynamic> data) {
          final String text = (data['text'] as String?) ?? '';
          return Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: aliases.bgOverlay,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: aliases.stateErrorPrimary.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, size: 14, color: aliases.stateErrorPrimary),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: aliases.stateErrorPrimary))),
            ]),
          );
        },
      },
    );
  }
}

class _ReasoningCard extends StatefulWidget {
  const _ReasoningCard({required this.text});
  final String text;
  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Container(
      decoration: BoxDecoration(
        color: aliases.bgOverlay.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(_open ? Icons.expand_less : Icons.expand_more, size: 14, color: aliases.labelTertiary),
              const SizedBox(width: 6),
              Icon(Icons.lightbulb_outline, size: 14, color: aliases.labelTertiary),
              const SizedBox(width: 6),
              Text('Thinking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aliases.labelTertiary)),
              const Spacer(),
              Text(_open ? 'Hide' : 'Show', style: TextStyle(fontSize: 11, color: aliases.labelCaption)),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(widget.text, style: TextStyle(fontSize: 12, color: aliases.labelSecondary, fontStyle: FontStyle.italic, height: 1.4)),
          ),
      ]),
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({required this.toolName, required this.status, required this.argsRaw, this.result});
  final String toolName;
  final String status;
  final String argsRaw;
  final dynamic result;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Container(
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: aliases.borderL2),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.build_outlined, size: 14, color: aliases.labelTertiary),
          const SizedBox(width: 6),
          Text(toolName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aliases.labelPrimary)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: aliases.bgOverlay, borderRadius: BorderRadius.circular(10)),
            child: Text(status, style: TextStyle(fontSize: 10, color: aliases.labelCaption)),
          ),
        ]),
        if (argsRaw.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(argsRaw, style: TextStyle(fontSize: 11, color: aliases.labelSecondary, fontFamily: 'SF Mono')),
        ],
        if (result != null) ...[
          const SizedBox(height: 6),
          Divider(height: 1, color: aliases.borderL2),
          const SizedBox(height: 6),
          SelectableText(result.toString(), style: TextStyle(fontSize: 11, color: aliases.labelSecondary, fontFamily: 'SF Mono')),
        ],
      ]),
    );
  }
}

class _RetryCard extends StatelessWidget {
  const _RetryCard({required this.retry, required this.maxRetries, required this.delayMs, required this.failureMessage, required this.retryMode});
  final int retry;
  final int maxRetries;
  final int delayMs;
  final String failureMessage;
  final String retryMode;
  int _retrySeconds(int ms) => (ms / 1000).ceil().clamp(1, 999);
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final int seconds = _retrySeconds(delayMs);
    final String max = retryMode == 'always' ? '∞' : '$maxRetries';
    return Container(
      decoration: BoxDecoration(color: aliases.bgLayer2, borderRadius: BorderRadius.circular(12), border: Border.all(color: aliases.borderL2)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: aliases.labelTertiary,
          collapsedIconColor: aliases.labelTertiary,
          title: Text('Retried model request ($retry/$max) · ${seconds}s',
              style: TextStyle(fontSize: 14, color: aliases.labelSecondary)),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Retry delay: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aliases.labelTertiary)),
              Text('${delayMs}ms', style: TextStyle(fontSize: 12, color: aliases.labelSecondary)),
            ]),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Failure reason: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aliases.labelTertiary)),
              Expanded(child: SelectableText(failureMessage.isEmpty ? '(unknown)' : failureMessage, style: TextStyle(fontSize: 12, color: aliases.labelSecondary))),
            ]),
          ],
        ),
      ),
    );
  }
}
