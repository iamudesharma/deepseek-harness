import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../message_feedback_provider.dart';

/// MessageFeedbackActions view — rating + note.
///
/// Mirrors `MessageFeedbackActions` (ui-message-feedback): Like/Dislike pair
/// plus note editor. Rendered as a standalone screen listing the session's
/// recorded feedback rows (ConsumerWidget, Theme + DswTokens, empty state);
/// it moves into the assistant message actions row when that hole lands.
class MessageFeedbackScreen extends ConsumerWidget {
  const MessageFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Message Feedback',
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: const _FeedbackList(),
    );
  }
}

class _FeedbackList extends ConsumerWidget {
  const _FeedbackList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    // The store is empty until a rating lands — no fixtures; an unseeded
    // surface shows the empty state (React renders nothing until a recorded
    // item exists).
    final List<FeedbackItem> data =
        ref.watch(messageFeedbackProvider).values.toList()
          ..sort((a, b) => a.messageId.compareTo(b.messageId));
    if (data.isEmpty) return _EmptyFeedback(aliases: aliases);
    return ListView.separated(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      itemCount: data.length,
      separatorBuilder: (_, _) => const SizedBox(height: DswTokens.spaceSm),
      itemBuilder: (BuildContext context, int index) =>
          MessageFeedbackActionsView(item: data[index], aliases: aliases),
    );
  }
}

/// Reusable actions view — like/dislike + note editor (popover via dialog/bottom sheet).
class MessageFeedbackActionsView extends ConsumerStatefulWidget {
  const MessageFeedbackActionsView({
    super.key,
    required this.item,
    required this.aliases,
  });
  final FeedbackItem item;
  final DswAliases aliases;

  @override
  ConsumerState<MessageFeedbackActionsView> createState() =>
      _MessageFeedbackActionsViewState();
}

class _MessageFeedbackActionsViewState
    extends ConsumerState<MessageFeedbackActionsView> {
  @override
  Widget build(BuildContext context) {
    final FeedbackItem item = widget.item;
    final DswAliases aliases = widget.aliases;
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: aliases.labelCaption,
              ),
              const SizedBox(width: 6),
              Text(
                item.messageId,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelCaption,
                ),
              ),
              const Spacer(),
              if (item.note != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: aliases.bgOverlay,
                    borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                  ),
                  child: Text(
                    item.note!,
                    style: TextStyle(
                      fontSize: 11,
                      color: aliases.labelSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DswTokens.spaceSm),
          Row(
            children: [
              _RateButton(
                icon: Icons.thumb_up_outlined,
                activeIcon: Icons.thumb_up,
                active: item.rating == FeedbackRating.positive,
                aliases: aliases,
                onTap: () => ref
                    .read(messageFeedbackProvider.notifier)
                    .rate(item.messageId, FeedbackRating.positive),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              _RateButton(
                icon: Icons.thumb_down_outlined,
                activeIcon: Icons.thumb_down,
                active: item.rating == FeedbackRating.negative,
                aliases: aliases,
                onTap: () => ref
                    .read(messageFeedbackProvider.notifier)
                    .rate(item.messageId, FeedbackRating.negative),
              ),
              const Spacer(),
              if (item.rating != FeedbackRating.none)
                TextButton.icon(
                  onPressed: () => _openNoteEditor(item),
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: aliases.labelSecondary,
                  ),
                  label: Text(
                    item.note == null ? 'Add note' : 'Edit note',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openNoteEditor(FeedbackItem item) {
    final TextEditingController ctrl = TextEditingController(
      text: item.note ?? '',
    );
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final DswAliases aliases = widget.aliases;
        return AlertDialog(
          backgroundColor: aliases.bgLayer2,
          title: Text(
            'Feedback note',
            style: TextStyle(
              fontSize: DswTokens.fontSizeBase16,
              color: aliases.labelPrimary,
            ),
          ),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add context for this rating…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DswTokens.radiusSm),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String trimmed = ctrl.text.trim();
                if (trimmed.isEmpty) {
                  ref
                      .read(messageFeedbackProvider.notifier)
                      .clearNote(item.messageId);
                } else {
                  ref
                      .read(messageFeedbackProvider.notifier)
                      .setNote(item.messageId, trimmed);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.aliases,
    required this.onTap,
  });
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final DswAliases aliases;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? aliases.stateBusinessTertiary : aliases.bgOverlay,
      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DswTokens.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DswTokens.radiusFull),
            border: Border.all(
              color: active ? aliases.stateBusinessPrimary : aliases.borderL2,
            ),
          ),
          child: Icon(
            active ? activeIcon : icon,
            size: 16,
            color: active
                ? aliases.stateBusinessPrimary
                : aliases.labelTertiary,
          ),
        ),
      ),
    );
  }
}

class _EmptyFeedback extends StatelessWidget {
  const _EmptyFeedback({required this.aliases});
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.feedback_outlined,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              'No feedback yet',
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Like or dislike messages to leave feedback.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
