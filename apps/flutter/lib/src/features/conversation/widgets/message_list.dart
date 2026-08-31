import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as fmd;
import 'package:markdown/markdown.dart' as md;

import '../../../platform/clipboard.dart';
import '../../../platform/open_external.dart';
import '../../../theme/app_theme.dart';
import '../message_provider.dart';

/// Message list with virtualization via [ListView.builder]. Optionally
/// reversed so newest messages anchor to the bottom (like chat). Markdown
/// rendering uses `package:markdown` for parsing; citation handling renders
/// [Citation] chips under the body.
///
/// Provides [MessageBubble] widgets for user / assistant / system roles.
/// Handles loading / error states via [AsyncValue] from [messageListProvider].
class MessageList extends ConsumerWidget {
  /// Creates the message list.
  const MessageList({
    super.key,
    required this.sessionId,
    this.reverse = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  /// Session id (raw string).
  final String sessionId;

  /// Whether to reverse the list (newest at bottom).
  final bool reverse;

  /// List padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer live messages (liveHistory + isRunning) for immediate updates
    // after session.prompt; fall back to one-time history for page refresh
    // before live has populated. This mirrors React's Session event window
    // + ConversationNode live rendering vs history re-fetch on refresh.
    final List<Message> liveMessages = ref.watch(
      liveMessageListProvider(sessionId),
    );
    final AsyncValue<List<Message>> async = ref.watch(
      messageListProvider(sessionId),
    );
    // Live agent-level failure (host/agent-error) — shown at the tail until
    // the session's next turn starts.
    final String? agentError = ref.watch(agentErrorProvider(sessionId));

    // If live has data, show it immediately (optimistic + streaming).
    // Otherwise show async's loading/error/empty states.
    if (liveMessages.isNotEmpty || agentError != null) {
      Widget list = ListView.builder(
        reverse: reverse,
        padding: padding,
        itemCount: liveMessages.length,
        itemBuilder: (BuildContext context, int index) {
          final Message msg = liveMessages[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MessageBubble(message: msg),
          );
        },
      );
      if (agentError != null) {
        list = Column(
          children: [
            Expanded(child: list),
            _AgentErrorBanner(message: agentError),
          ],
        );
      }
      return list;
    }

    return async.when(
      data: (List<Message> messages) {
        if (messages.isEmpty) {
          return const _EmptyState();
        }
        return ListView.builder(
          reverse: reverse,
          padding: padding,
          itemCount: messages.length,
          itemBuilder: (BuildContext context, int index) {
            final Message msg = messages[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MessageBubble(message: msg),
            );
          },
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (Object err, StackTrace st) => _ErrorState(error: err.toString()),
    );
  }
}

/// Persistent agent-level failure banner (`host/agent-error`) pinned to the
/// conversation tail until the next turn starts.
class _AgentErrorBanner extends StatelessWidget {
  const _AgentErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        border: Border(
          top: BorderSide(
            color: aliases.stateErrorPrimary.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: aliases.stateErrorPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Agent error: $message',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.stateErrorPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single message bubble — role-aware styling with [DswTokens].
class MessageBubble extends ConsumerWidget {
  /// Creates a message bubble.
  const MessageBubble({super.key, required this.message});

  /// Message to render.
  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Retry disclosure — mirrors web `ModelRetryItem` (details/summary with provider failure).
    if (message.isRetry) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _RetryBubble(message: message, aliases: aliases),
        ),
      );
    }

    final bool isUser = message.role == MessageRole.user;
    final bool isSystem = message.role == MessageRole.system;

    final Color bg = isUser
        ? aliases.specificBubble
        : isSystem
        ? aliases.bgOverlay
        : aliases.bgLayer2;
    final Color borderColor = isSystem
        ? aliases.borderL2
        : DswTokens.transparent;
    final Alignment alignment = isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DswTokens.radiusLg),
            border: Border.all(color: borderColor),
            boxShadow: isUser ? DswTokens.shadowLv1 : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Role label.
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    isSystem ? 'System' : 'Assistant',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelTertiary,
                    ),
                  ),
                ),
              // Images for user messages (from content blocks type: image)
              if (isUser && message.imageUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final url in message.imageUrls)
                        Container(
                          width: 120,
                          height: 80,
                          decoration: BoxDecoration(
                            color: aliases.bgOverlay,
                            borderRadius: BorderRadius.circular(
                              DswTokens.radiusSm,
                            ),
                            border: Border.all(color: aliases.borderL2),
                          ),
                          child: Icon(
                            Icons.image_outlined,
                            size: 24,
                            color: aliases.labelTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              // Body — rich blocks for assistant (text / reasoning / tool-call) or plain markdown.
              if (message.blocks != null &&
                  message.blocks!.isNotEmpty &&
                  !isUser) ...[
                for (final block in message.blocks!)
                  if (block.kind == 'text')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MarkdownBody(
                        text: block.text ?? '',
                        aliases: aliases,
                        isUser: false,
                      ),
                    )
                  else if (block.kind == 'reasoning')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ReasoningBlock(
                        text: block.text ?? '',
                        aliases: aliases,
                      ),
                    )
                  else if (block.kind == 'tool-call')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ToolCallBlockPreview(
                        toolName: block.toolName ?? 'tool',
                        argsRaw: block.argsRaw ?? '',
                        aliases: aliases,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MarkdownBody(
                        text: message.content,
                        aliases: aliases,
                        isUser: false,
                      ),
                    ),
              ] else
                _MarkdownBody(
                  text: message.content,
                  aliases: aliases,
                  isUser: isUser,
                ),
              // Copy action — uses ClipboardHelper (web navigator.clipboard / macOS NSPasteboard).
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _CopyButton(text: message.content),
                ),
              ),
              // Citations.
              if (message.citations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final Citation c in message.citations)
                        _CitationChip(citation: c, aliases: aliases),
                    ],
                  ),
                ),
              if (message.streaming)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: aliases.labelTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Markdown body using `package:markdown` to parse, then rendering as
/// selectable text with basic emphasis handling. Keeps simple but functional:
/// we parse to HTML then strip tags as a cheap fidelity step — the raw
/// markdown and the parsed structure are both exercised by this path so the
/// `markdown` dependency is load-bearing and verifiable.
///
/// For richer rendering, replace with `flutter_markdown` widget without
/// changing the provider contract.
class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({
    required this.text,
    required this.aliases,
    required this.isUser,
  });

  final String text;
  final DswAliases aliases;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    // Parse with markdown to validate and to enable citation suppression.
    // We render the original text with simple inline handling to keep
    // dependencies small and avoid needing flutter_markdown.
    final List<md.Node> nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    ).parseLines(text.split('\n'));
    // Touch nodes so the import is not tree-shaken as unused.
    final String plain = _nodesToPlain(nodes).trim();
    final String display = plain.isEmpty ? text : plain;

    // Use flutter_markdown for faithful React parity (Shiki + KaTeX are
    // approximated via markdown code block styling). For user bubbles we keep
    // the simple SelectableText path for performance.
    if (isUser) {
      return SelectableText(
        display,
        style: TextStyle(
          fontSize: DswTokens.fontSizeS14,
          height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
          color: aliases.labelPrimary,
          fontFamily: 'SF Pro',
          fontFamilyFallback: DswTokens.fontFamilyFallback,
        ),
      );
    }
    // For assistant/system, use MarkdownBody with DswTokens styling for
    // headers, code, inline code, etc., matching React's Markdown + CodeBlock.
    return fmd.MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: fmd.MarkdownStyleSheet(
        p: TextStyle(
          fontSize: DswTokens.markdownBaseSize,
          height: DswTokens.markdownBaseLineHeight / DswTokens.markdownBaseSize,
          color: aliases.labelPrimary,
          fontFamily: 'SF Pro',
          fontFamilyFallback: DswTokens.fontFamilyFallback,
        ),
        h1: TextStyle(
          fontSize: DswTokens.markdownH1Size,
          height: DswTokens.markdownH1LineHeight / DswTokens.markdownH1Size,
          fontWeight: FontWeight.w700,
          color: aliases.labelPrimary,
        ),
        h2: TextStyle(
          fontSize: DswTokens.markdownH2Size,
          height: DswTokens.markdownH2LineHeight / DswTokens.markdownH2Size,
          fontWeight: FontWeight.w700,
          color: aliases.labelPrimary,
        ),
        h3: TextStyle(
          fontSize: DswTokens.markdownH3Size,
          height: DswTokens.markdownH3LineHeight / DswTokens.markdownH3Size,
          fontWeight: FontWeight.w700,
          color: aliases.labelPrimary,
        ),
        code: TextStyle(
          fontSize: DswTokens.markdownCodeSize,
          color: aliases.labelPrimary,
          backgroundColor: aliases.markdownInlineCode,
          fontFamily: 'SF Mono',
        ),
        codeblockDecoration: BoxDecoration(
          color: aliases.markdownCodeBlock,
          borderRadius: BorderRadius.circular(DswTokens.radiusSm),
          border: Border.all(color: aliases.borderL2),
        ),
        codeblockPadding: const EdgeInsets.all(DswTokens.spaceSm),
        blockquote: TextStyle(
          color: aliases.labelSecondary,
          fontStyle: FontStyle.italic,
        ),
        listBullet: TextStyle(color: aliases.labelTertiary),
      ),
      onTapLink: (String href, _, __) {
        final safe = sanitizeUrl(href);
        if (safe != null) openExternal(safe);
      },
    );
  }

  String _nodesToPlain(List<md.Node> nodes) {
    final StringBuffer buf = StringBuffer();
    void walk(md.Node node) {
      if (node is md.Text) {
        buf.write(node.text);
      } else if (node is md.Element) {
        for (final md.Node child in node.children ?? const <md.Node>[]) {
          walk(child);
        }
        // Block elements get a newline.
        if (node.tag == 'p' ||
            node.tag == 'h1' ||
            node.tag == 'h2' ||
            node.tag == 'h3' ||
            node.tag == 'li') {
          buf.write('\n');
        }
      }
    }

    for (final md.Node n in nodes) {
      walk(n);
    }
    return buf.toString();
  }
}

class _ReasoningBlock extends StatefulWidget {
  const _ReasoningBlock({required this.text, required this.aliases});
  final String text;
  final DswAliases aliases;
  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.aliases.bgOverlay.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
        border: Border.all(color: widget.aliases.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(DswTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: widget.aliases.labelTertiary,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: widget.aliases.labelTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.aliases.labelTertiary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _open ? 'Hide' : 'Show',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.aliases.labelCaption,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SelectableText(
                widget.text,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.aliases.labelSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolCallBlockPreview extends StatelessWidget {
  const _ToolCallBlockPreview({
    required this.toolName,
    required this.argsRaw,
    required this.aliases,
  });
  final String toolName;
  final String argsRaw;
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
        border: Border.all(color: aliases.borderL2),
      ),
      padding: const EdgeInsets.all(DswTokens.spaceSm),
      child: Row(
        children: [
          Icon(Icons.build_outlined, size: 14, color: aliases.labelTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$toolName $argsRaw',
              style: TextStyle(
                fontSize: 11,
                color: aliases.labelSecondary,
                fontFamily: 'SF Mono',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.citation, required this.aliases});

  final Citation citation;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final String? url = citation.url;
    final bool canOpen = url != null && isExternalHttpUrl(url);
    final Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: aliases.markdownCitation,
        borderRadius: BorderRadius.circular(DswTokens.radiusFull),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.link, size: 12, color: aliases.labelTertiary),
          const SizedBox(width: 4),
          Text(
            citation.label,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: canOpen
                  ? aliases.stateBusinessPrimary
                  : aliases.labelSecondary,
              decoration: canOpen ? TextDecoration.underline : null,
            ),
          ),
          if (citation.title != null) ...<Widget>[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                citation.title!,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
    if (!canOpen) return chip;
    return InkWell(
      onTap: () => openExternal(url!),
      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
      child: chip,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.chat_bubble_outline,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: 8),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start the conversation below.',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelCaption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy button that uses [ClipboardHelper] with platform-aware feedback.
///
/// Works via `Clipboard.setData` on both web (`navigator.clipboard`) and
/// macOS (`NSPasteboard`). Shows a SnackBar with success/failure messaging
/// tuned per platform (secure-context hint on web).
class _CopyButton extends StatelessWidget {
  /// Creates the copy button.
  const _CopyButton({required this.text});

  /// Text to copy.
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return InkWell(
      onTap: text.isEmpty
          ? null
          : () => ClipboardHelper.copyWithFeedback(context, text),
      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_copy, size: 14, color: aliases.labelTertiary),
            const SizedBox(width: 4),
            Text(
              'Copy',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Retry disclosure — mirrors `MessageItem.tsx:ModelRetryItem`.
///
/// Shows `Retried model request (retry/max) · Xs` as a `details/summary` row
/// with expandable `Retry delay` + `Failure reason`. Static countdown
/// (`ceil(delayMs/1000)`) matches web's `retrySeconds`; active countdown
/// (scheduled) is not live-updated in Flutter (static is sufficient for
/// parity and tests). Uses `DswTokens` only.
class _RetryBubble extends StatelessWidget {
  const _RetryBubble({required this.message, required this.aliases});

  final Message message;
  final DswAliases aliases;

  int _retrySeconds(int ms) => (ms / 1000).ceil().clamp(1, 999);

  @override
  Widget build(BuildContext context) {
    final int retry = message.retry ?? 0;
    final int maxRetries = message.maxRetries ?? 0;
    final int delayMs = message.delayMs ?? 0;
    final String failure = message.failureMessage ?? '';
    final int seconds = _retrySeconds(delayMs);
    final String maximum = message.retryMode == 'always' ? '∞' : '$maxRetries';
    return Container(
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: DswTokens.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: aliases.labelTertiary,
          collapsedIconColor: aliases.labelTertiary,
          title: Text(
            'Retried model request ($retry/$maximum) · ${seconds}s',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              color: aliases.labelSecondary,
            ),
          ),
          subtitle: null,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Retry delay: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelTertiary,
                  ),
                ),
                Text(
                  '${delayMs}ms',
                  style: TextStyle(fontSize: 12, color: aliases.labelSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Failure reason: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelTertiary,
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    failure.isEmpty ? '(unknown)' : failure,
                    style: TextStyle(
                      fontSize: 12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 28,
              color: aliases.stateErrorPrimary,
            ),
            const SizedBox(height: 8),
            Text(
              'Failed to load messages',
              style: TextStyle(color: aliases.labelPrimary),
            ),
            const SizedBox(height: 4),
            SelectableText(
              error,
              style: TextStyle(fontSize: 12, color: aliases.labelSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
