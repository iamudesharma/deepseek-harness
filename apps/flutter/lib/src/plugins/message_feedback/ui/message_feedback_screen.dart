import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../core/services/runtime_services.dart';
import '../../../core/session/session_provider.dart';
import '../locales.dart';
import '../message_feedback_controller.dart';
import '../message_feedback_providers.dart';

/// Message feedback surface — one session's recorded rows from Host durability.
///
/// Backed by the session's [MessageFeedbackController] through
/// [messageFeedbackSessionProvider] (single list read seeds every row;
/// mutations ride the controller's CAS, serialized). Rendered as a standalone
/// screen listing the session's recorded feedback rows; it moves into the
/// assistant message actions row when the
/// `conversation.chat.assistant-actions` hole lands.
class MessageFeedbackScreen extends ConsumerStatefulWidget {
  const MessageFeedbackScreen({super.key, this.sessionId});

  /// Session owning the feedback. Falls back to the current session; without
  /// any session there is nothing addressable, so the empty state shows.
  final String? sessionId;

  @override
  ConsumerState<MessageFeedbackScreen> createState() =>
      _MessageFeedbackScreenState();
}

class _MessageFeedbackScreenState extends ConsumerState<MessageFeedbackScreen> {
  /// Seeds the bound controller once per resolver/session pair; the controller
  /// itself dedups concurrent reads and mutations self-seed regardless.
  String? _seededKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(kMessageFeedbackNamespace);
    final Translate common = ref.bindLocale(kCommonNamespace);
    final String? sessionId =
        widget.sessionId ?? ref.watch(currentSessionIdProvider)?.value;

    Widget body;
    if (sessionId == null) {
      body = _EmptyFeedback(aliases: aliases, t: t);
    } else {
      final controllers = ref.watch(messageFeedbackControllersProvider);
      final String seedKey = '${identityHashCode(controllers)}/$sessionId';
      if (seedKey != _seededKey) {
        _seededKey = seedKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(messageFeedbackSessionProvider(sessionId).notifier).ensure();
          }
        });
      }
      body = _FeedbackBody(
        sessionId: sessionId,
        aliases: aliases,
        t: t,
        common: common,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          t('screen.title'),
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
      body: body,
    );
  }
}

class _FeedbackBody extends ConsumerWidget {
  const _FeedbackBody({
    required this.sessionId,
    required this.aliases,
    required this.t,
    required this.common,
  });

  final String sessionId;
  final DswAliases aliases;
  final Translate t;
  final Translate common;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MessageFeedbackView view = ref.watch(
      messageFeedbackSessionProvider(sessionId),
    );
    switch (view.status) {
      case MessageFeedbackStatus.cold:
      case MessageFeedbackStatus.loading:
        return _LoadingFeedback(aliases: aliases, common: common);
      case MessageFeedbackStatus.error:
        if (view.items.isEmpty) {
          return _ErrorFeedback(
            sessionId: sessionId,
            aliases: aliases,
            message: view.error ?? t('error.load'),
            retryLabel: common('retry'),
          );
        }
      case MessageFeedbackStatus.ready:
        break;
    }
    // Ready, or a failed reload over previously loaded rows: the recorded
    // rows stay visible (React renders nothing until a recorded item exists).
    final List<MessageFeedbackItem> data = view.items.values.toList()
      ..sort((a, b) => a.messageId.compareTo(b.messageId));
    if (data.isEmpty) return _EmptyFeedback(aliases: aliases, t: t);
    return ListView.separated(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      itemCount:
          data.length + (view.status == MessageFeedbackStatus.error ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: DswTokens.spaceSm),
      itemBuilder: (BuildContext context, int index) {
        if (view.status == MessageFeedbackStatus.error && index == 0) {
          return _LoadFailureBanner(
            sessionId: sessionId,
            aliases: aliases,
            message: view.error ?? t('error.load'),
            retryLabel: common('retry'),
          );
        }
        final MessageFeedbackItem item =
            data[index - (view.status == MessageFeedbackStatus.error ? 1 : 0)];
        return MessageFeedbackActionsView(
          sessionId: sessionId,
          messageId: item.messageId,
          aliases: aliases,
        );
      },
    );
  }
}

/// Reusable actions view — like/dislike + note editor over one recorded row.
///
/// Reads its row from the session view (vanishes when a retract commits) and
/// routes every mutation through the session notifier: rating buttons toggle,
/// a non-empty note saves via rate, an emptied editor clears via clearNote.
/// A settled `version-conflict` reports through [describeFeedbackFailure];
/// the reply's authoritative row is already committed by the controller.
class MessageFeedbackActionsView extends ConsumerStatefulWidget {
  const MessageFeedbackActionsView({
    super.key,
    required this.sessionId,
    required this.messageId,
    required this.aliases,
  });
  final String sessionId;
  final String messageId;
  final DswAliases aliases;

  @override
  ConsumerState<MessageFeedbackActionsView> createState() =>
      _MessageFeedbackActionsViewState();
}

class _MessageFeedbackActionsViewState
    extends ConsumerState<MessageFeedbackActionsView> {
  bool _pending = false;
  String? _rowFailure;

  MessageFeedbackSessionNotifier get _notifier =>
      ref.read(messageFeedbackSessionProvider(widget.sessionId).notifier);

  Future<void> _toggle(FeedbackRatingValue rating) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _rowFailure = null;
    });
    // The controller decides retract-vs-replace from the committed item, so a
    // tap that lands before the first list read still toggles stored state.
    final FeedbackActionResult result = await _notifier.toggle(
      widget.messageId,
      rating,
    );
    if (!mounted) return;
    setState(() {
      _pending = false;
      if (!result.ok) {
        _rowFailure = describeFeedbackFailure(result.code ?? 'unknown');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = widget.aliases;
    final Translate t = ref.bindLocale(kMessageFeedbackNamespace);
    final MessageFeedbackItem? item = ref.watch(
      messageFeedbackSessionProvider(widget.sessionId),
    ).items[widget.messageId];
    // A retract commits removal; the row leaves with the recorded item.
    if (item == null) return const SizedBox.shrink();
    final FeedbackRatingValue rating = item.rating;
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
            ],
          ),
          const SizedBox(height: DswTokens.spaceSm),
          Row(
            children: [
              Tooltip(
                message: rating == FeedbackRatingValue.positive
                    ? t('action.likeActive')
                    : t('action.like'),
                child: _RateButton(
                  icon: Icons.thumb_up_outlined,
                  activeIcon: Icons.thumb_up,
                  active: rating == FeedbackRatingValue.positive,
                  aliases: aliases,
                  onTap: _pending
                      ? null
                      : () => _toggle(FeedbackRatingValue.positive),
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Tooltip(
                message: rating == FeedbackRatingValue.negative
                    ? t('action.dislikeActive')
                    : t('action.dislike'),
                child: _RateButton(
                  icon: Icons.thumb_down_outlined,
                  activeIcon: Icons.thumb_down,
                  active: rating == FeedbackRatingValue.negative,
                  aliases: aliases,
                  onTap: _pending
                      ? null
                      : () => _toggle(FeedbackRatingValue.negative),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _pending ? null : () => _openNoteEditor(item, t),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: aliases.labelSecondary,
                ),
                label: Text(
                  item.note == null ? t('note.open') : item.note!,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (_rowFailure != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Semantics(
              liveRegion: true,
              child: Text(
                _rowFailure!,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.stateErrorPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openNoteEditor(MessageFeedbackItem item, Translate t) {
    // Captured before the dialog opens: the route outlives nothing it needs
    // from this state, and the save below must not read a defunct ref.
    final MessageFeedbackSessionNotifier notifier = _notifier;
    setState(() => _pending = true);
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => _NoteEditorDialog(
        initialNote: item.note ?? '',
        aliases: widget.aliases,
        t: t,
        onSave: (String trimmed) async {
          // An emptied editor removes the note explicitly; `rate` alone
          // preserves a stored note, so it cannot express deletion.
          final FeedbackActionResult result = trimmed.isEmpty
              ? await notifier.clearNote(item.messageId)
              : await notifier.rate(item.messageId, item.rating, trimmed);
          if (!mounted) return '';
          return result.ok
              ? null
              : describeFeedbackFailure(result.code ?? 'unknown');
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _pending = false);
    });
  }
}

/// Note editor dialog — a save belongs to this editing session: the panel
/// stays open on failure so the draft survives to be corrected, and closes
/// only on success. Owns its [TextEditingController] so disposal lands with
/// the route (after the pop transition), never under a rebuilding TextField.
class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({
    required this.initialNote,
    required this.aliases,
    required this.t,
    required this.onSave,
  });

  final String initialNote;
  final DswAliases aliases;

  /// Bound translate face for the feedback namespace.
  final Translate t;

  /// Saves [trimmed]; returns the failure text, or null when the save landed.
  /// Returning `''` (owner gone) keeps the panel open without labeling the
  /// draft with another attempt's error.
  final Future<String?> Function(String trimmed) onSave;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialNote,
  );
  bool _saving = false;
  String? _failure;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String trimmed = _ctrl.text.trim();
    setState(() {
      _saving = true;
      _failure = null;
    });
    final String? failure = await widget.onSave(trimmed);
    if (!mounted) return;
    if (failure == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      // An empty failure means the owner is gone; hold the panel open without
      // mislabeling the draft.
      _failure = failure.isEmpty ? null : failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = widget.aliases;
    final Translate t = widget.t;
    return AlertDialog(
      backgroundColor: aliases.bgLayer2,
      title: Text(
        t('note.dialog'),
        style: TextStyle(
          fontSize: DswTokens.fontSizeBase16,
          color: aliases.labelPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 3,
            enabled: !_saving,
            decoration: InputDecoration(
              hintText: t('note.placeholder'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DswTokens.radiusSm),
              ),
            ),
          ),
          if (_failure != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Semantics(
              liveRegion: true,
              child: Text(
                _failure!,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.stateErrorPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(t('note.cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(t('note.save')),
        ),
      ],
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
  final VoidCallback? onTap;

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

class _LoadingFeedback extends StatelessWidget {
  const _LoadingFeedback({required this.aliases, required this.common});
  final DswAliases aliases;
  final Translate common;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: DswTokens.spaceMd),
          Text(
            common('loading'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              color: aliases.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorFeedback extends ConsumerWidget {
  const _ErrorFeedback({
    required this.sessionId,
    required this.aliases,
    required this.message,
    required this.retryLabel,
  });
  final String sessionId;
  final DswAliases aliases;
  final String message;
  final String retryLabel;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  color: aliases.stateErrorPrimary,
                ),
              ),
            ),
            const SizedBox(height: DswTokens.spaceMd),
            FilledButton.tonal(
              onPressed: () => ref
                  .read(messageFeedbackSessionProvider(sessionId).notifier)
                  .refresh(),
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailureBanner extends ConsumerWidget {
  const _LoadFailureBanner({
    required this.sessionId,
    required this.aliases,
    required this.message,
    required this.retryLabel,
  });
  final String sessionId;
  final DswAliases aliases;
  final String message;
  final String retryLabel;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceMd,
        vertical: DswTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.stateErrorPrimary,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(messageFeedbackSessionProvider(sessionId).notifier)
                .refresh(),
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeedback extends StatelessWidget {
  const _EmptyFeedback({required this.aliases, required this.t});
  final DswAliases aliases;
  final Translate t;
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
              t('screen.empty.title'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('screen.empty.hint'),
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
