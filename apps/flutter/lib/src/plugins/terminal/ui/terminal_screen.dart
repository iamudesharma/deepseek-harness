/// Console terminal screen — the host's console session pool as a full-page
/// route (mobile shells and deep links).
///
/// One empty pool auto-opens a session at the owning chat session's working
/// directory without a name prompt; the opener row spawns further sessions.
/// The docked in-session panel (`TerminalDock`) shares this composition
/// through `terminal_views.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';

import '../locales.dart';
import '../terminal_models.dart';
import 'terminal_views.dart';

/// Console terminal screen.
///
/// Shows session tabs, the selected session's emulator view, and a toolbar
/// with refresh, interrupt, and close. An empty pool auto-opens one session;
/// host failures surface inline.
class TerminalScreen extends ConsumerStatefulWidget {
  /// Creates the terminal screen.
  const TerminalScreen({super.key, this.sessionId});

  /// Chat session scoping for the route; also resolves the cwd new sessions
  /// spawn in. The console pool is host-global, so this only scopes cwd.
  final String? sessionId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureOpen());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Owning session's working directory, when the route carries a session id.
  String? get _cwd => widget.sessionId == null
      ? null
      : ref
            .read(sessionByIdProvider(SessionId(widget.sessionId!)))
            ?.cwd;

  /// Spawn one session at [_cwd], without an owner name.
  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await ref.read(terminalSessionsProvider.notifier).open(cwd: _cwd);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Auto-open the empty pool on mount so the screen lands on a live shell.
  Future<void> _ensureOpen() async {
    if (!mounted) return;
    if (ref.read(terminalSessionsProvider).sessions.isNotEmpty) return;
    await _open();
  }

  Future<void> _close(ConsoleSession session, Translate t) async {
    final confirmed = await confirmSessionClose(context, t);
    if (!confirmed || !mounted) return;
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
          TerminalTabStrip(
            pool: pool,
            aliases: aliases,
            t: t,
            focusNode: _focusNode,
            onSelect: (id) =>
                ref.read(terminalSessionsProvider.notifier).select(id),
          ),
          if (_error != null)
            TerminalErrorBanner(
              message: _error!,
              aliases: aliases,
              onDismiss: () => setState(() => _error = null),
            ),
          Expanded(
            child: selected == null
                ? TerminalEmptyState(aliases: aliases, t: t)
                : TerminalSessionView(
                    session: selected,
                    aliases: aliases,
                    t: t,
                    focusNode: _focusNode,
                    onClose: () => _close(selected, t),
                  ),
          ),
          _OpenerRow(aliases: aliases, t: t, opening: _opening, onOpen: _open),
        ],
      ),
    );
  }
}

/// Bottom opener row: spawns one more unnamed session at the route's cwd.
class _OpenerRow extends StatelessWidget {
  /// Creates the opener row.
  const _OpenerRow({
    required this.aliases,
    required this.t,
    required this.opening,
    required this.onOpen,
  });

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// True while an open is in flight.
  final bool opening;

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
          const Spacer(),
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
