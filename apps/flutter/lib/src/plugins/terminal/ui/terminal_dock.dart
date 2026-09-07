/// In-session terminal dock — the host console pool seated at the bottom of
/// the conversation column, above the composer (the VS Code panel posture).
///
/// Revealing the dock auto-opens one unnamed console session at the owning
/// chat session's working directory; an existing pool is shown as-is. Hidden
/// by default; the session-header terminal action toggles
/// [terminalPanelVisibleProvider].
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

/// Fixed dock height; resize handling stays out until it is actually needed.
const double _kTerminalDockHeight = 320;

/// The docked terminal panel for one chat session.
class TerminalDock extends ConsumerStatefulWidget {
  /// Creates the dock.
  const TerminalDock({super.key, required this.sessionId});

  /// Owning chat session id — resolves the cwd new sessions spawn in.
  final String sessionId;

  @override
  ConsumerState<TerminalDock> createState() => _TerminalDockState();
}

class _TerminalDockState extends ConsumerState<TerminalDock> {
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

  /// Owning session's working directory, when the summary is loaded.
  String? get _cwd =>
      ref.read(sessionByIdProvider(SessionId(widget.sessionId)))?.cwd;

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

  /// Auto-open the empty pool on reveal so the dock lands on a live shell.
  /// Hidden docks spawn nothing — the open happens only when the panel is
  /// actually shown.
  Future<void> _ensureOpen() async {
    if (!mounted) return;
    if (!ref.read(terminalPanelVisibleProvider)) return;
    if (ref.read(terminalSessionsProvider).sessions.isNotEmpty) return;
    await _open();
  }

  Future<void> _closeSession(ConsoleSession session, Translate t) async {
    final confirmed = await confirmSessionClose(context, t);
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(terminalSessionsProvider.notifier)
          .close(session.sessionId);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reveal triggers the auto-open; the initState callback covers mounting
    // while already visible. Both are idempotent.
    ref.listen(terminalPanelVisibleProvider, (previous, next) {
      if (next) _ensureOpen();
    });
    final bool visible = ref.watch(terminalPanelVisibleProvider);
    if (!visible) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(kTerminalNamespace);
    final TerminalPoolState pool = ref.watch(terminalSessionsProvider);
    final ConsoleSession? selected = pool.selected;
    final String? cwd = _cwd;

    return Container(
      height: _kTerminalDockHeight,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: aliases.borderL2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DockHeader(
            cwd: cwd,
            aliases: aliases,
            t: t,
            onHide: () =>
                ref.read(terminalPanelVisibleProvider.notifier).state = false,
          ),
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
                ? TerminalEmptyState(
                    aliases: aliases,
                    t: t,
                    opening: _opening,
                    onOpen: _open,
                  )
                : TerminalSessionView(
                    session: selected,
                    aliases: aliases,
                    t: t,
                    focusNode: _focusNode,
                    onClose: () => _closeSession(selected, t),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Dock title row: panel name, the cwd new sessions spawn in, and hide.
class _DockHeader extends StatelessWidget {
  /// Creates the header row.
  const _DockHeader({
    required this.cwd,
    required this.aliases,
    required this.t,
    required this.onHide,
  });

  /// Working directory new sessions spawn in; null before the summary loads.
  final String? cwd;

  /// Theme aliases.
  final DswAliases aliases;

  /// Terminal translations.
  final Translate t;

  /// Hide callback.
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final String? path = cwd;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DswTokens.spaceSm,
        DswTokens.spaceSm,
        DswTokens.spaceSm,
        0,
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, size: 14, color: aliases.labelTertiary),
          const SizedBox(width: 6),
          Text(
            t('list.aria'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeXs13,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
            ),
          ),
          if (path != null && path.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXs13,
                  color: aliases.labelTertiary,
                ),
              ),
            ),
          ] else
            const Spacer(),
          IconButton(
            tooltip: t('dock.hide'),
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            onPressed: onHide,
          ),
        ],
      ),
    );
  }
}
