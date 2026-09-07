/// Message feedback actions — thumbs up/down, copy, share.
///
/// Mirrors `packages/client/ui-message-feedback` + `MessageIconActions.tsx`
/// keyed list `conversation.chat.assistant-actions` (owner AssistantActionOwnerProps {messageId})
/// rendered below the closing assistant of a turn.
library;

import 'package:flutter/material.dart';

import '../../../platform/clipboard.dart';
import '../../../theme/app_theme.dart';

class MessageFeedbackRow extends StatefulWidget {
  const MessageFeedbackRow({
    super.key,
    required this.messageId,
    required this.text,
    this.onFeedback,
  });

  final String messageId;
  final String text;
  final ValueChanged<String>? onFeedback;

  @override
  State<MessageFeedbackRow> createState() => _MessageFeedbackRowState();
}

class _MessageFeedbackRowState extends State<MessageFeedbackRow> {
  String? _selected; // 'up' | 'down' | null

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return Row(
      children: [
        _IconAction(
          icon: Icons.content_copy_rounded,
          tooltip: 'Copy',
          color: aliases.labelTertiary,
          onTap: () => ClipboardHelper.copyWithFeedback(context, widget.text),
        ),
        const SizedBox(width: 6),
        _IconAction(
          icon: Icons.thumb_up_outlined,
          tooltip: 'Good response',
          color: _selected == 'up' ? aliases.stateBusinessPrimary : aliases.labelTertiary,
          onTap: () {
            setState(() => _selected = _selected == 'up' ? null : 'up');
            if (widget.onFeedback != null) widget.onFeedback!(_selected ?? 'none');
          },
        ),
        const SizedBox(width: 6),
        _IconAction(
          icon: Icons.thumb_down_outlined,
          tooltip: 'Bad response',
          color: _selected == 'down' ? aliases.stateBusinessPrimary : aliases.labelTertiary,
          onTap: () {
            setState(() => _selected = _selected == 'down' ? null : 'down');
            if (widget.onFeedback != null) widget.onFeedback!(_selected ?? 'none');
          },
        ),
        const SizedBox(width: 6),
        _IconAction(
          icon: Icons.share_outlined,
          tooltip: 'Share',
          color: aliases.labelTertiary,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share coming soon')));
          },
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.color, required this.onTap});
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
