/// Conversation column: the hub's visible composition — header, chat view,
/// docks, composer. Rendered inside AppFrame's center track via
/// `layout.center`; every piece arrives from plugin state/seams, no direct
/// feature imports.
///
/// The blank-session hero is a PHASE of this one column (React
/// ConversationRoot keeps a single resident skeleton): hero chrome, the
/// workspace row (with the agent-preset chip seat), AND the resident
/// composer form one stack centered in the scroll body
/// (`ConversationRoot.module.css .composerHero` +
/// `.root[data-phase='hero'] .scrollBody { justify-content: center }`) —
/// never a second layout tree and never a full-height dead-space column.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/slots/slot_registry.dart' show SlotRegistry;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/fish_logo.dart';
import '../hub.dart'
    show activatedHub, hubControllerProvider, composerSubmitHookProvider;
import 'slots/hole_outlet.dart';
import 'composer.dart' show ConversationComposer;
import 'chat_view.dart';
import 'composer_chain_outlet.dart';
import '../queue_hook.dart';
import 'conversation_shortcuts.dart';
import 'docks.dart';
import 'session_header.dart';

/// Full conversation column for one session. Blank sessions render the hero
/// phase of the same shell: fish headline + workspace row + the resident
/// composer, centered as one stack exactly like React's hero phase of
/// ConversationRoot.
class ConversationColumn extends ConsumerWidget {
  /// Creates the column.
  const ConversationColumn({super.key, required this.sessionId});

  /// Owning session id.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionSummary? summary = ref.watch(
      sessionByIdProvider(SessionId(sessionId)),
    );
    // Hero phase = blank summary (no messages yet). A missing summary renders
    // the docked posture; ConversationScreen guards not-found before mounting.
    final bool hero = summary?.blank ?? false;
    return Column(
      children: [
        // Header chrome hides while blank — React
        // ConversationSession.tsx:72-77 `hideChrome && css.headerHidden`
        // keeps the strict header mounted without taking column space.
        if (!hero) ...<Widget>[
          SessionHeaderView(sessionId: sessionId),
          const Divider(height: 1),
        ],
        Expanded(child: ConversationBody(sessionId: sessionId)),
      ],
    );
  }
}

/// Session body without the desktop header chrome: active transcript +
/// docks + composer, or the blank-session hero phase. Shared by the desktop
/// [ConversationColumn] and the mobile conversation shell so every surface
/// mounts ONE transcript/composer composition.
class ConversationBody extends ConsumerWidget {
  /// Creates the body.
  const ConversationBody({super.key, required this.sessionId});

  /// Owning session id.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionSummary? summary = ref.watch(
      sessionByIdProvider(SessionId(sessionId)),
    );
    final bool hero = summary?.blank ?? false;
    debugPrint(
      '[conversationBody] sid=$sessionId summaryBlank=${summary?.blank} hero=$hero hasSummary=${summary != null}',
    );
    return hero
        ? _HeroPhase(sessionId: sessionId)
        : _ActiveBody(sessionId: sessionId, ref: ref);
  }
}

/// Active phase body — React `.root[data-phase='active']`: the transcript
/// fills the scroll area above the docks and the composer seat pinned at the
/// column bottom (sticky footer posture).
class _ActiveBody extends StatelessWidget {
  const _ActiveBody({required this.sessionId, required this.ref});

  final String sessionId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: ChatView(sessionId: sessionId)),
        // Pending-interaction takeover (approval/question) — elected from the
        // conversation.composer chain, rendered above the composer exactly
        // like React's ApprovalPanel seat.
        const ComposerChainOutlet(),
        DocksRow(sessionId: sessionId),
        QueueSteerHook(sessionId: sessionId),
        // Existing composer wrapped by the platform shortcut seam:
        // Enter submits (policy mode), Escape cancels, Shift+Enter newlines.
        ConversationShortcuts(
          onSubmit: () =>
              ref.read(composerSubmitHookProvider(sessionId))?.call(),
          onCancel: () =>
              ref.read(hubControllerProvider)?.cancelTurn(SessionId(sessionId)),
          child: ConversationComposer(sessionId: sessionId),
        ),
      ],
    );
  }
}

/// Blank-session hero phase — React `ConversationRoot.composerBar`: ONE
/// stack holding the hero chrome (fish headline +
/// `conversation.hero.brand.mark`), the workspace row riding the
/// `conversation.hero.workspace` seat with the agent-preset chip beside it
/// (`conversation.hero.agentPreset` — ConversationRoot.tsx:100-124), and the
/// RESIDENT composer card. The whole stack centers vertically in the scroll
/// body with a 32px foot pad floating it above true center
/// (ConversationRoot.module.css `.composerHero` + hero scrollBody
/// `justify-content: center`), so the composer never separates from the hero
/// content it belongs to.
///
/// Geometry per `.composerHero`: one centered column, gap 8, width =
/// the composer card cap + side clearances (780 + 2×16).
class _HeroPhase extends ConsumerWidget {
  const _HeroPhase({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final SlotRegistry slots = activatedHub?.slots ?? SlotRegistry();
    // Hero stack centered in the viewport, scrolls when it does not fit.
    // Replaces the previous SliverFillRemaining which required tight height
    // from the parent and caused LayoutBuilder intrinsic errors on some
    // Xiaomi/MIUI routes. This version uses a simple SingleChildScrollView
    // with Center, which works with the outer Center+ConstrainedBox without
    // needing LayoutBuilder.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: DswTokens.space2xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glow backdrop behind the stack — simplified to a centered
              // container with radial gradient, not Positioned.fill, to avoid
              // Stack + Sliver complexity.
              Stack(
                alignment: Alignment.center,
                children: [
                  IgnorePointer(
                    child: Container(
                      width: 720,
                      height: 320,
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          colors: [Color(0x146187D8), Color(0x006187D8)],
                          center: Alignment.center,
                          radius: 0.8,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        children: [
                          HoleOutlet(
                            registry: slots,
                            slotKey: 'conversation.hero.brand.mark',
                            fallback: const DsFishLogo(size: 34),
                          ),
                          Text(
                            'Into the Unknown',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: aliases.labelPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: aliases.stateBusinessTertiary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: aliases.stateBusinessPrimary.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            child: Text(
                              'Preview',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: aliases.stateBusinessPrimary,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DswTokens.spaceSm),
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HoleOutlet(
                              registry: slots,
                              slotKey: 'conversation.hero.workspace',
                            ),
                            const SizedBox(width: DswTokens.spaceSm),
                            HoleOutlet(
                              registry: slots,
                              slotKey: 'conversation.hero.agentPreset',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: DswTokens.spaceSm),
                      ConversationShortcuts(
                        onSubmit: () => ref
                            .read(composerSubmitHookProvider(sessionId))
                            ?.call(),
                        onCancel: () => ref
                            .read(hubControllerProvider)
                            ?.cancelTurn(SessionId(sessionId)),
                        child: ConversationComposer(sessionId: sessionId),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
