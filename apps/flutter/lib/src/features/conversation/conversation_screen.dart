import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_models.dart';
import '../../core/session/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primitives/fish_logo.dart';
import 'widgets/conversation_composer.dart';
import 'widgets/harness_ai_chat.dart';

/// Conversation screen — composes [MessageList] + [ToolCallTree] + [ConversationComposer]
/// in a [Column] with [SessionId] param. Handles empty / blank session guard
/// (like detailsSession blank check) and loading / error states.
///
/// Keep simple but functional; uses [ConsumerWidget]; does not mutate backend
/// beyond the composer's local stub.
///
/// Mirrors web `ConversationScreen` session scoping via `:sessionId` param +
/// [sessionByIdProvider]. Blank sessions show the empty-state CTA.
class ConversationScreen extends ConsumerWidget {
  /// Creates the conversation screen.
  const ConversationScreen({super.key, required this.sessionId});

  /// Session id from route param (raw string) — branded as [SessionId] for
  /// provider reads.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionId id = SessionId(sessionId);
    final SessionSummary? summary = ref.watch(sessionByIdProvider(id));

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
            (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);

    // Empty / missing session guard — mirrors detailsSession blank guard
    // (AppFrame.tsx:94 blank check + details close on switch).
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Session $sessionId')),
        body: _GuardState(
          icon: Icons.search_off,
          title: 'Session not found',
          subtitle: 'No session matches "$sessionId". It may have been removed.',
          aliases: aliases,
        ),
      );
    }

    if (summary.blank) {
      // Blank session hero — mirrors React ConversationRoot hero phase (blank + open):
      // fish headline + workspace chip (cwd basename) + composer.
      // Workspace remains switchable before first message via chip (like heroWorkspaceRow).
      final String workspaceLabel = summary.cwd == null || summary.cwd!.isEmpty
          ? 'Choose workspace'
          : summary.cwd!.split('/').where((String s) => s.isNotEmpty).last;
      return Scaffold(
        appBar: AppBar(title: Text(summary.title ?? summary.sessionId.value)),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        children: [
                          const DsFishLogo(size: 34),
                          Text('Into the Unknown',
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: aliases.labelPrimary, letterSpacing: -0.3)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: aliases.stateBusinessTertiary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: aliases.stateBusinessPrimary.withValues(alpha: 0.18)),
                            ),
                            child: Text('Preview',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: aliases.stateBusinessPrimary, letterSpacing: 0.2)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: aliases.bgLayer1,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: aliases.borderL2),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(summary.cwd == null ? Icons.folder_outlined : Icons.folder_open, size: 16, color: aliases.labelSecondary),
                          const SizedBox(width: 6),
                          Text(workspaceLabel, style: TextStyle(fontSize: 13, color: aliases.labelPrimary, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 4),
                          Icon(Icons.expand_more, size: 14, color: aliases.labelTertiary),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Text('Blank session — your first message will initialize this session.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: aliases.labelSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            // Composer pinned to bottom — sends to this blank session (no new session creation).
            ConversationComposer(sessionId: sessionId),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(summary.title ?? summary.sessionId.value),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: HarnessAiChat(sessionId: sessionId),
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
              style: TextStyle(fontSize: DswTokens.fontSizeS14, color: aliases.labelSecondary),
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