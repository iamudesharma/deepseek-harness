/// Mobile conversation shell — the phone/tablet posture of the ONE
/// conversation composition. Reuses [ConversationBody] (ChatView +
/// docks + composer, or the blank hero phase) so Web, macOS, Android, and
/// iOS mount the same transcript/composer semantics; only the chrome
/// differs: SafeArea → header (back, title, connection, actions) →
/// scrollport → resident composer. No desktop AppFrame columns here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/connection/connection_controller.dart' as conn;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../core/slots/slot_registry.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/connection_banner.dart';
import '../hub.dart';
import 'column.dart' show ConversationBody;
import 'slots/hole_outlet.dart';

/// Content width cap for tablet postures — phone widths stay full-bleed,
/// tablet widths center the transcript/composer column (React caps the
/// conversation at the same order of magnitude; no desktop fixed widths).
const double kMobileConversationMaxWidth = 760;

/// Mobile conversation shell for one session.
class MobileConversationShell extends ConsumerWidget {
  /// Creates the shell.
  const MobileConversationShell({super.key, required this.sessionId});

  /// Owning session id (route param).
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn.ConnectionState connection = ref.watch(
      conn.connectionStateProvider,
    );
    return Scaffold(
      // Default resizeToAvoidBottomInset keeps the resident composer visible
      // above the keyboard; ChatView's clamp logic keeps a bottom pin pinned
      // when the viewport shrinks.
      body: SafeArea(
        child: Column(
          children: [
            MobileSessionHeader(sessionId: sessionId),
            if (connection != conn.ConnectionState.connected &&
                connection != conn.ConnectionState.idle)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: DsConnectionBanner(state: connection),
              ),
            if (connection == conn.ConnectionState.needsReauth)
              const _RePairAction(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kMobileConversationMaxWidth,
                  ),
                  child: ConversationBody(sessionId: sessionId),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile session header: back to the sessions list, run-state dot +
/// display title, dependent actions hole, cancel-while-running.
class MobileSessionHeader extends ConsumerWidget {
  /// Creates the header.
  const MobileSessionHeader({super.key, required this.sessionId});

  /// Owning session id.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final SessionSummary? summary = ref.watch(
      sessionByIdProvider(SessionId(sessionId)),
    );
    final bool running = summary?.running ?? false;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: aliases.borderL2)),
      ),
      child: Row(
        children: [
          // Back to the mobile sessions list (the canonical mobile entry).
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/sessions'),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: running
                  ? aliases.stateWarnPrimary
                  : aliases.stateSuccessPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary == null
                  ? sessionId
                  : summary.blank
                  ? 'New session'
                  : summary.displayTitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
          ),
          // Same dependent-actions hole the desktop header exposes.
          HoleOutlet(
            registry: activatedHub?.slots ?? SlotRegistry(),
            slotKey: 'conversation.session.header.actions',
          ),
          if (running)
            IconButton(
              tooltip: 'Cancel turn',
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              onPressed: () =>
                  activatedHub?.controller.cancelTurn(SessionId(sessionId)),
            ),
        ],
      ),
    );
  }
}

/// Revoked/expired posture: stop remote actions, offer re-pair.
class _RePairAction extends StatelessWidget {
  const _RePairAction();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Authentication required'),
          subtitle: const Text(
            'Access expired, revoked, or host identity changed.',
          ),
          trailing: FilledButton(
            onPressed: () => context.go('/devices/add'),
            child: const Text('Re-pair'),
          ),
        ),
      ),
    );
  }
}
