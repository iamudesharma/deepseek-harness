import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../features/conversation/composer_controller.dart';
import '../../../platform/drag_drop.dart';
import '../../../platform/layout.dart' show isMobileShell;
import '../../../theme/app_theme.dart';
import '../../attachment/attachment_limits.dart';
import '../../attachment/ui/document_drop_scope.dart';
import 'column.dart';
import 'composer.dart' show intakeComposerImages;
import 'mobile_shell.dart';

/// Conversation screen — composes [MessageList] + [ToolCallTree] + [ConversationComposer]
/// in a [Column] with [SessionId] param. Handles empty / blank session guard
/// (like detailsSession blank check) and loading / error states.
///
/// ONE tree for every session state: both restored and blank sessions render
/// [ConversationColumn] (the plugin shell); blank is a hero PHASE of that
/// shell, mirroring React's resident ConversationRoot skeleton — never a
/// parallel hand-rolled tree. Mirrors web `ConversationScreen` session scoping
/// via `:sessionId` param + [sessionByIdProvider].
class ConversationScreen extends ConsumerStatefulWidget {
  /// Creates the conversation screen.
  const ConversationScreen({super.key, required this.sessionId});

  /// Session id from route param (raw string) — branded as [SessionId] for
  /// provider reads.
  final String sessionId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  late DragDropController _dropController;

  @override
  void initState() {
    super.initState();
    _dropController = DragDropController(
      onAddImages: (files) => intakeComposerImages(
        staged: ref
            .read(composerControllerProvider(widget.sessionId))
            .attachments,
        limits: ref.read(imageLimitsProvider),
        add: (items) => ref
            .read(composerControllerProvider(widget.sessionId).notifier)
            .addAttachments(items),
        files: files,
      ),
      onRejected: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  @override
  void didUpdateWidget(ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _dropController.dispose();
      _dropController = DragDropController(
        onAddImages: (files) => intakeComposerImages(
          staged: ref
              .read(composerControllerProvider(widget.sessionId))
              .attachments,
          limits: ref.read(imageLimitsProvider),
          add: (items) => ref
              .read(composerControllerProvider(widget.sessionId).notifier)
              .addAttachments(items),
          files: files,
        ),
        onRejected: (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        },
      );
    }
  }

  @override
  void dispose() {
    _dropController.dispose();
    super.dispose();
  }

  /// Gate mirrors React `canAcceptDrop = !locked && !machineBusy && …`:
  /// `enabled` covers locked, running session covers machine busy. Runs
  /// post-frame so the controller notification never lands mid-build.
  void _configureDropGate(bool enabled, bool machineBusy) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dropController.configure(
        canAcceptDrop: enabled && !machineBusy,
        limits: ref.read(imageLimitsProvider),
      );
      final staged = ref
          .read(composerControllerProvider(widget.sessionId))
          .attachments;
      _dropController.stagedCount = staged.length;
      _dropController.stagedTotalBytes = staged.fold<int>(
        0,
        (sum, a) => sum + (a.size ?? 0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch limits so drop gate reconfigures when host projection lands.
    ref.watch(imageLimitsProvider);
    final String sessionId = widget.sessionId;
    final SessionId id = SessionId(sessionId);
    final SessionSummary? summary = ref.watch(sessionByIdProvider(id));

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Empty / missing session guard — mirrors detailsSession blank guard
    // (AppFrame.tsx:94 blank check + details close on switch).
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Session $sessionId')),
        body: _GuardState(
          icon: Icons.search_off,
          title: 'Session not found',
          subtitle:
              'No session matches "$sessionId". It may have been removed.',
          aliases: aliases,
        ),
      );
    }

    // Gate mirrors React `canAcceptDrop = !locked && !machineBusy && …`:
    // `enabled` covers locked, running session covers machine busy.
    final bool machineBusy = summary.running;
    _configureDropGate(true, machineBusy);

    // Native mobile: the mobile shell (header + shared body) ONLY when
    // width <768. Wider native windows keep the desktop column inside AppFrame.
    final Widget conversation = isMobileShell(context)
        ? MobileConversationShell(sessionId: sessionId)
        : ConversationColumn(sessionId: sessionId);

    return Scaffold(
      body: SafeArea(
        child: DocumentDropScope(
          controller: _dropController,
          onAddImages: _dropController.onAddImages,
          child: conversation,
        ),
      ),
    );
  }
}

class _GuardState extends StatelessWidget {
  const _GuardState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.aliases,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DswAliases aliases;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 36, color: aliases.labelCaption),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: DswTokens.spaceLg),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
