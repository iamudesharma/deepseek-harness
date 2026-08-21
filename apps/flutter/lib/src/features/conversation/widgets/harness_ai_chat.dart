import 'package:flutter/material.dart';
import 'package:flutter_gen_ai_chat_ui/flutter_gen_ai_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../theme/app_theme.dart';
import '../../tool/tool_models.dart';
import '../chat_ui_adapter.dart';
import '../composer_controller.dart';
import '../conversation_reducer.dart';
import '../message_provider.dart';

/// Conversation chat UI on top of `flutter_gen_ai_chat_ui`.
///
/// Syncs the normalized [ReducedConversation] (reducer pipeline) into a
/// `ChatMessagesController` so thinking collapses, tool calls render as rich
/// cards with correct lifecycle, and provider/model failures surface as one
/// concise error with Details — never orphaned `running` cards.
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

  void _syncMessages(List<Message> messages, List<ToolCall> tools) {
    syncMessagesToController(messages, tools, _controller, aiUser: _aiUser, currentUser: _currentUser);
  }

  void _syncWithError(List<Message> messages, List<ToolCall> tools, String friendly, String? raw) {
    final List<ChatMessage> base = <ChatMessage>[];
    for (final m in messages) {
      base.addAll(harnessMessageToChatMessages(m, aiUser: _aiUser, currentUser: _currentUser));
    }
    for (final t in tools) {
      base.add(toolCallToChatMessage(t, _aiUser));
    }
    base.add(ChatMessage.rich(
      user: _aiUser,
      resultKind: 'error',
      data: {'text': friendly, 'rawError': raw ?? friendly},
      id: 'turn-error',
    ));
    for (final chat in base) {
      _controller.updateMessage(chat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HistoryEntry> history = ref.watch(liveHistoryProvider(widget.sessionId));
    final String? agentError = ref.watch(agentErrorProvider(widget.sessionId));
    final AsyncValue<List<Message>> asyncMessages = ref.watch(messageListProvider(widget.sessionId));
    final bool isRunning = ref.watch(sessionsProvider.select((s) => s.byId[SessionId(widget.sessionId)]?.running ?? false));
    // Always watch fallback providers (Riverpod requires unconditional watches).
    final List<Message> liveMessages = ref.watch(liveMessageListProvider(widget.sessionId));
    final List<ToolCall> liveTools = ref.watch(liveToolCallsProvider(widget.sessionId));

    final bool hasHistory = history.isNotEmpty;

    if (hasHistory) {
      final ReducedConversation r = reduceConversation(history, isRunning: isRunning, agentError: agentError);

      if (asyncMessages.hasError && r.messages.isEmpty && r.tools.isEmpty && r.errorMessage == null) {
        return _errorState(asyncMessages.error.toString());
      }

      ref.listen<List<HistoryEntry>>(liveHistoryProvider(widget.sessionId), (prev, next) {
        final bool running = ref.read(sessionsProvider.select((s) => s.byId[SessionId(widget.sessionId)]?.running ?? false));
        final String? err = ref.read(agentErrorProvider(widget.sessionId));
        final ReducedConversation nr = reduceConversation(next, isRunning: running, agentError: err);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nr.turnFailed && nr.errorMessage != null) {
            _syncWithError(nr.messages, nr.tools, nr.errorMessage!, nr.rawError);
          } else {
            _syncMessages(nr.messages, nr.tools);
          }
        });
      });

      if (_controller.messages.isEmpty && (r.messages.isNotEmpty || r.tools.isNotEmpty || r.errorMessage != null)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (r.errorMessage != null) {
            _syncWithError(r.messages, r.tools, r.errorMessage!, r.rawError);
          } else {
            _syncMessages(r.messages, r.tools);
          }
        });
      }

      return _buildChat(tools: r.tools, messages: r.messages, friendlyError: r.errorMessage, rawError: r.rawError);
    }

    // Fallback: liveHistory empty (page refresh before live populated) — use
    // the legacy message/tool providers which are already correct for
    // non-failed turns. Agent errors still surface via friendly mapping.
    final List<Message> asyncList = asyncMessages.valueOrNull ?? const <Message>[];
    final List<Message> effectiveMessages = liveMessages.isNotEmpty ? liveMessages : asyncList;
    final List<ToolCall> effectiveTools = liveTools;

    if (asyncMessages.hasError && effectiveMessages.isEmpty && effectiveTools.isEmpty) {
      return _errorState(asyncMessages.error.toString());
    }

    ref.listen<List<Message>>(liveMessageListProvider(widget.sessionId), (prev, next) {
      final List<ToolCall> curTools = ref.read(liveToolCallsProvider(widget.sessionId));
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncMessages(next, curTools));
    });
    ref.listen<List<ToolCall>>(liveToolCallsProvider(widget.sessionId), (prev, next) {
      final List<Message> curMsgs = ref.read(liveMessageListProvider(widget.sessionId));
      final List<Message> base = curMsgs.isNotEmpty ? curMsgs : (ref.read(messageListProvider(widget.sessionId)).valueOrNull ?? const <Message>[]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncMessages(base, next));
    });

    if (_controller.messages.isEmpty && (effectiveMessages.isNotEmpty || effectiveTools.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncMessages(effectiveMessages, effectiveTools));
    }

    return _buildChat(tools: effectiveTools, messages: effectiveMessages, friendlyError: null, rawError: null);
  }

  Widget _errorState(String error) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 28, color: aliases.stateErrorPrimary),
          const SizedBox(height: 8),
          Text('Failed to load messages', style: TextStyle(color: aliases.labelPrimary)),
          const SizedBox(height: 4),
          SelectableText(error, style: TextStyle(fontSize: 12, color: aliases.labelSecondary)),
        ]),
      ),
    );
  }

  Widget _buildChat({
    required List<ToolCall> tools,
    required List<Message> messages,
    required String? friendlyError,
    required String? rawError,
  }) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);

    return AiChatWidget(
      currentUser: _currentUser,
      aiUser: _aiUser,
      controller: _controller,
      onSendMessage: (ChatMessage chatMessage) {
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
          final String status = (data['status'] as String?) ?? 'pending';
          final String displayStatus = status == 'cancelled' ? 'Not executed' : status;
          final dynamic raw = data['argsRaw'] ?? data['args'];
          String args = '';
          if (raw is String) {
            final String t = raw.trim();
            args = (t.isEmpty || t == '{}' || t == '[]') ? '' : t;
          } else if (raw is Map) {
            final Map<dynamic, dynamic> m = raw as Map<dynamic, dynamic>;
            args = m.isEmpty ? '' : m.toString();
            if (args == '{}') args = '';
          }
          final dynamic result = data['result'];
          final bool isCancelled = status == 'cancelled';
          return _ToolCallCard(
            toolName: name,
            status: displayStatus,
            argsRaw: isCancelled ? '' : args,
            result: isCancelled ? null : result,
            isCancelled: isCancelled,
          );
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
          final String? raw = data['rawError'] as String?;
          final bool hasRaw = raw != null && raw.trim().isNotEmpty && raw.trim() != text.trim();
          return _ErrorCard(text: text, rawError: hasRaw ? raw : null);
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

  String _summary(String text) {
    final String trimmed = text.trimRight();
    // Running tail follows the latest line; settled preview follows the first line (React parity).
    // For a collapsed card we show the first line so the bubble is never blank.
    final int nl = trimmed.indexOf('\n');
    return nl == -1 ? trimmed : trimmed.substring(0, nl);
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final String summary = _summary(widget.text);
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
              if (summary.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: aliases.labelCaption, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
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
  const _ToolCallCard({required this.toolName, required this.status, required this.argsRaw, this.result, this.isCancelled = false});
  final String toolName;
  final String status;
  final String argsRaw;
  final dynamic result;
  final bool isCancelled;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final bool showArgs = !isCancelled && argsRaw.trim().isNotEmpty && argsRaw.trim() != '{}';
    return Container(
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: aliases.borderL2),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isCancelled ? Icons.block_outlined : Icons.build_outlined, size: 14, color: aliases.labelTertiary),
          const SizedBox(width: 6),
          Text(toolName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aliases.labelPrimary)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: aliases.bgOverlay, borderRadius: BorderRadius.circular(10)),
            child: Text(status, style: TextStyle(fontSize: 10, color: aliases.labelCaption)),
          ),
        ]),
        if (showArgs) ...[
          const SizedBox(height: 6),
          SelectableText(argsRaw, style: TextStyle(fontSize: 11, color: aliases.labelSecondary, fontFamily: 'SF Mono')),
        ],
        if (result != null && !isCancelled) ...[
          const SizedBox(height: 6),
          Divider(height: 1, color: aliases.borderL2),
          const SizedBox(height: 6),
          SelectableText(result.toString(), style: TextStyle(fontSize: 11, color: aliases.labelSecondary, fontFamily: 'SF Mono')),
        ],
      ]),
    );
  }
}

class _ErrorCard extends StatefulWidget {
  const _ErrorCard({required this.text, this.rawError});
  final String text;
  final String? rawError;
  @override
  State<_ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<_ErrorCard> {
  bool _showDetails = false;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: aliases.stateErrorPrimary.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: aliases.stateErrorPrimary),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.text, style: TextStyle(fontSize: 12, color: aliases.stateErrorPrimary, height: 1.4))),
        ]),
        if (widget.rawError != null) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _showDetails = !_showDetails),
            child: Row(children: [
              Icon(_showDetails ? Icons.expand_less : Icons.expand_more, size: 12, color: aliases.labelTertiary),
              const SizedBox(width: 4),
              Text(_showDetails ? 'Hide details' : 'Details', style: TextStyle(fontSize: 11, color: aliases.labelCaption)),
            ]),
          ),
          if (_showDetails)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(widget.rawError!, style: TextStyle(fontSize: 10, color: aliases.labelSecondary, fontFamily: 'SF Mono')),
            ),
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
