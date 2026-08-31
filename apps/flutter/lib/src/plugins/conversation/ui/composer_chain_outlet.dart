/// Composer-chain outlet — the missing render seat for the
/// `conversation.composer` chain slot. Elects one entry per turn: entries
/// sorted by priority (desc), each `ChainSelect` either claims the owner's
/// currency (the session's pending interaction) or abdicates; the first
/// claim renders. This is what makes pending approvals/questions visible
/// above the composer (React ApprovalPanel / QuestionCard parity) on every
/// surface that mounts the shared conversation body.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/renderer/slot_outlet.dart'
    show SlotComponentProps, SlotWidgetBuilder;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/slots/slot_registry.dart';
import '../../user_questions/approval_state.dart';
import '../../user_questions/questions_state.dart';
import '../hub.dart' show activatedHub;

/// The conversation-owned composer chain key.
const String kComposerChainSlot = 'conversation.composer';

/// Election outlet for [kComposerChainSlot]. Renders nothing when no entry
/// claims the turn.
class ComposerChainOutlet extends ConsumerWidget {
  /// Creates the outlet.
  const ComposerChainOutlet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SlotRegistry? registry = activatedHub?.slots;
    if (registry == null || !registry.isDeclared(kComposerChainSlot)) {
      return const SizedBox.shrink();
    }
    final List<SlotEntry> entries = registry.entries(kComposerChainSlot);
    if (entries.isEmpty) return const SizedBox.shrink();

    // Owner currency: the current session's pending interaction.
    // Precedence mirrors SessionSummary sessionStatuses: approval → plan-review
    // → question → subagents. The approval entry outranks question when both
    // wait, so a pending approval alone still elects.
    final SessionId? sid = ref.watch(currentSessionIdProvider);
    if (sid == null) return const SizedBox.shrink();
    final PendingQuestion? question = ref.watch(
      pendingQuestionsProvider,
    )[sid.value];
    final PendingApproval? approval = ref.watch(approvalsProvider)[sid.value];
    final Object? currency = approval ?? question;
    if (currency == null) return const SizedBox.shrink();

    final List<SlotEntry> sorted = List<SlotEntry>.of(entries)
      ..sort((SlotEntry a, SlotEntry b) => a.priority.compareTo(b.priority));
    for (final SlotEntry entry in sorted) {
      final ChainSelect? select = entry.options.select;
      if (select == null) continue;
      if (select(currency) == null) continue;
      assert(
        entry.component is SlotWidgetBuilder,
        'chain entry "${entry.options.id ?? entry.options.registrant}" is not '
        'a SlotWidgetBuilder',
      );
      return (entry.component as SlotWidgetBuilder)(
        context,
        SlotComponentProps(
          slotKey: kComposerChainSlot,
          cellId: entry.options.id,
          priority: entry.priority,
          order: entry.options.order,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
