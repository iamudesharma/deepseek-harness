/// Shared console-terminal views: tab strip, per-session emulator view,
/// toolbar, error banner, and empty state. One composition serves both the
/// full-screen route and the in-session dock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../core/services/runtime_services.dart' show Translate;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/state_dot.dart';
import '../terminal_models.dart';

/// Confirm dialog behind every session-close affordance.
Future<bool> confirmSessionClose(BuildContext context, Translate t) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('close.confirm')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t('close.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t('close.confirm.action')),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Session tab strip with a per-tab status dot.
class TerminalTabStrip extends StatelessWidget {
  /// Creates the tab strip.
  const TerminalTabStrip({
    super.key,
    required this.pool,
    required this.aliases,
    required this.t,
    required this.focusNode,
    required this.onSelect,
  });

  /// The console pool.
  final TerminalPoolState pool;

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// Focus node handed to the emulator view on selection.
  final FocusNode focusNode;

  /// Selection callback.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (pool.sessions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
        itemCount: pool.sessions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final session = pool.sessions[index];
          final selected = session.sessionId == pool.selected?.sessionId;
          return ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StateDot(
                  state: session.exited
                      ? StateDotState.done
                      : StateDotState.ongoing,
                ),
                const SizedBox(width: 6),
                Text(session.label(t('tab.untitled'))),
              ],
            ),
            selected: selected,
            onSelected: (_) {
              onSelect(session.sessionId);
              focusNode.requestFocus();
            },
          );
        },
      ),
    );
  }
}

/// Inline host-failure banner with dismiss.
class TerminalErrorBanner extends StatelessWidget {
  /// Creates the banner.
  const TerminalErrorBanner({
    super.key,
    required this.message,
    required this.aliases,
    required this.onDismiss,
  });

  /// The failure text.
  final String message;

  /// Theme aliases.
  final DswAliases aliases;

  /// Dismiss callback.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(DswTokens.spaceSm),
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceSm,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: aliases.stateErrorPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
        border: Border.all(color: aliases.stateErrorPrimary),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.stateErrorPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Empty pool state with an optional retry action.
class TerminalEmptyState extends StatelessWidget {
  /// Creates the empty state.
  const TerminalEmptyState({
    super.key,
    required this.aliases,
    required this.t,
    this.opening = false,
    this.onOpen,
  });

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// True while an open is in flight.
  final bool opening;

  /// Open callback; rendered as the retry button when provided.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal_rounded,
              size: 40,
              color: aliases.labelTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              t('empty.title'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t('empty.hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.labelSecondary,
              ),
            ),
            if (onOpen != null) ...<Widget>[
              const SizedBox(height: DswTokens.spaceMd),
              FilledButton.icon(
                onPressed: opening ? null : onOpen,
                icon: opening
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add, size: 16),
                label: Text(t('new.action')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One live session: emulator view plus the session toolbar.
class TerminalSessionView extends ConsumerWidget {
  /// Creates the session view.
  const TerminalSessionView({
    super.key,
    required this.session,
    required this.aliases,
    required this.t,
    required this.focusNode,
    required this.onClose,
  });

  /// The live session.
  final ConsoleSession session;

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// Focus node for the emulator view.
  final FocusNode focusNode;

  /// Close callback.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(terminalSessionsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TerminalSessionToolbar(
          session: session,
          aliases: aliases,
          t: t,
          onRefresh: () => notifier.readTail(session),
          onInterrupt: () =>
              notifier.handleOutput(session, String.fromCharCode(0x03)),
          onClose: onClose,
        ),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceSm,
            ),
            child: Text(
              session.error!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.stateErrorPrimary,
              ),
            ),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(DswTokens.spaceSm),
            decoration: BoxDecoration(
              color: aliases.markdownCodeBlock,
              borderRadius: BorderRadius.circular(DswTokens.radiusSm),
              border: Border.all(color: aliases.borderL2),
            ),
            clipBehavior: Clip.antiAlias,
            child: TerminalView(
              session.terminal,
              controller: session.viewController,
              focusNode: focusNode,
              autofocus: true,
              theme: terminalThemeFor(aliases),
              textStyle: const TerminalStyle(
                fontFamily: 'SF Mono',
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (session.exited)
          Padding(
            padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
            child: Text(
              t('closed.note'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.labelTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

/// Session toolbar: refresh, interrupt, close.
class TerminalSessionToolbar extends StatelessWidget {
  /// Creates the toolbar.
  const TerminalSessionToolbar({
    super.key,
    required this.session,
    required this.aliases,
    required this.t,
    required this.onRefresh,
    required this.onInterrupt,
    required this.onClose,
  });

  /// The live session.
  final ConsoleSession session;

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// Refresh callback.
  final VoidCallback onRefresh;

  /// Interrupt callback.
  final VoidCallback onInterrupt;

  /// Close callback.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bool live = !session.exited;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
      child: Row(
        children: [
          StateDot(
            state: session.exited
                ? StateDotState.done
                : StateDotState.ongoing,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              session.exited
                  ? t('status.exited')
                  : t('status.running'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.labelSecondary,
              ),
            ),
          ),
          IconButton(
            tooltip: t('toolbar.refresh'),
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: live ? onRefresh : null,
          ),
          IconButton(
            tooltip: t('toolbar.interrupt.tooltip'),
            icon: const Icon(Icons.keyboard_double_arrow_down, size: 18),
            // Enabled while busy too: interrupting an in-flight foreground
            // send is the button's whole purpose.
            onPressed: live ? onInterrupt : null,
          ),
          IconButton(
            tooltip: t('toolbar.close'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
