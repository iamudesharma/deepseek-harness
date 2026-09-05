/// Console terminal panel — one xterm view per host console session.
///
/// Each tab owns an emulator buffer fed by the line-mode bridge in
/// [TerminalSessionsNotifier]: the MOTD on open, each settled send viewport
/// after Enter, and scrollback pages on manual refresh. Keystrokes never
/// leave the device except through the six `terminal/*` verbs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/state_dot.dart';

import '../locales.dart';
import '../terminal_models.dart';

/// Console terminal screen — the host's console session pool.
///
/// Shows session tabs, the selected session's emulator view, and a toolbar
/// with refresh, interrupt, and close. An empty pool renders the empty state
/// with a session opener; host failures surface inline.
class TerminalScreen extends ConsumerStatefulWidget {
  /// Creates the terminal screen.
  const TerminalScreen({super.key, this.sessionId});

  /// Chat session scoping for the route; the console pool is host-global,
  /// so this only keeps the route consistent with sibling screens.
  final String? sessionId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _nameController = TextEditingController();
  bool _opening = false;
  String? _error;

  @override
  void dispose() {
    _focusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final name = _nameController.text.trim();
      await ref
          .read(terminalSessionsProvider.notifier)
          .open(name: name.isEmpty ? null : name);
      _nameController.clear();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _close(ConsoleSession session, Translate t) async {
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(terminalSessionsProvider.notifier).close(session.sessionId);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(kTerminalNamespace);
    final TerminalPoolState pool = ref.watch(terminalSessionsProvider);
    final ConsoleSession? selected = pool.selected;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          t('list.aria'),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionTabs(
            pool: pool,
            aliases: aliases,
            t: t,
            focusNode: _focusNode,
            onSelect: (id) =>
                ref.read(terminalSessionsProvider.notifier).select(id),
          ),
          if (_error != null)
            _ErrorBanner(
              message: _error!,
              aliases: aliases,
              onDismiss: () => setState(() => _error = null),
            ),
          Expanded(
            child: selected == null
                ? _EmptyTerminal(
                    aliases: aliases,
                    t: t,
                    opening: _opening,
                    nameController: _nameController,
                    onOpen: _open,
                  )
                : _SessionView(
                    session: selected,
                    aliases: aliases,
                    t: t,
                    focusNode: _focusNode,
                    onClose: () => _close(selected, t),
                  ),
          ),
          _OpenerRow(
            aliases: aliases,
            t: t,
            opening: _opening,
            nameController: _nameController,
            onOpen: _open,
          ),
        ],
      ),
    );
  }
}

/// Session tab strip with a per-tab status dot.
class _SessionTabs extends StatelessWidget {
  /// Creates the tab strip.
  const _SessionTabs({
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
class _ErrorBanner extends StatelessWidget {
  /// Creates the banner.
  const _ErrorBanner({
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

/// Empty pool state with an inline session opener.
class _EmptyTerminal extends StatelessWidget {
  /// Creates the empty state.
  const _EmptyTerminal({
    required this.aliases,
    required this.t,
    required this.opening,
    required this.nameController,
    required this.onOpen,
  });

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// True while an open is in flight.
  final bool opening;

  /// Optional session name input.
  final TextEditingController nameController;

  /// Open callback.
  final VoidCallback onOpen;

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
          ],
        ),
      ),
    );
  }
}

/// One live session: emulator view plus the session toolbar.
class _SessionView extends ConsumerWidget {
  /// Creates the session view.
  const _SessionView({
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
        _SessionToolbar(
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
class _SessionToolbar extends StatelessWidget {
  /// Creates the toolbar.
  const _SessionToolbar({
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
            onPressed: live && !session.busy ? onInterrupt : null,
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

/// Bottom opener row: optional name plus a new-session button.
class _OpenerRow extends StatelessWidget {
  /// Creates the opener row.
  const _OpenerRow({
    required this.aliases,
    required this.t,
    required this.opening,
    required this.nameController,
    required this.onOpen,
  });

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// True while an open is in flight.
  final bool opening;

  /// Optional session name input.
  final TextEditingController nameController;

  /// Open callback.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceSm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: aliases.borderL2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: nameController,
              enabled: !opening,
              decoration: InputDecoration(
                hintText: t('new.name.hint'),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                ),
              ),
              onSubmitted: (_) => onOpen(),
            ),
          ),
          const SizedBox(width: 8),
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
      ),
    );
  }
}
