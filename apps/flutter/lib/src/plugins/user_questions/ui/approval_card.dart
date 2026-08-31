/// The approval collaboration surface — Flutter port of
/// `packages/client/ui-conversation/src/client/skeleton/ApprovalPanel.tsx`:
/// an amber "waiting for approval" strip, the asker's reason as the headline
/// (falling back to the escalation-by-toolName line), and a refuse/allow
/// action row. One-shot: the buttons disable after a click and re-arm on a
/// failed answer; the card leaves only when the broadcast resolved frame
/// drops the wait from the store.
///
/// This card is the interaction plane's approval face; the question half of
/// the plane renders through `question_node_card.dart`. React additionally
/// shows the paired tool call's command line by reading the running call's
/// argsRaw; the Flutter node fold does not retain argument text, so that line
/// is absent rather than invented.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/session/session_provider.dart';
import '../approval_responder.dart';
import '../approval_state.dart';
import '../locales.dart';

ConnectionClient? _boundApprovalClient;

/// Binds the connection client decisions ride (plugin activation).
void bindApprovalClient(ConnectionClient? client) {
  _boundApprovalClient = client;
}

/// Renders the current session's pending-approval card, empty when none is
/// live (the chain entry mounts only while the store carries one).
Widget renderApprovalNode(BuildContext context) => const ApprovalCard();

/// Chain selector for the composer takeover: match only a pending-approval
/// carrier; anything else abdicates the entry's turn.
Object? approvalComposerSelect(Object? owner) =>
    owner is PendingApproval ? owner : null;

/// The pending-approval decision card bound to the current session's request.
class ApprovalCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const ApprovalCard({super.key});

  @override
  ConsumerState<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<ApprovalCard> {
  bool _answered = false;

  Future<void> _answer(PendingApproval pending, ApprovalAnswer outcome) async {
    setState(() => _answered = true);
    try {
      await ApprovalResponder(
        client: _clientOrThrow(),
        pending: pending,
      ).answer(outcome);
    } catch (_) {
      // A failed answer (rejected receipt / transport) re-arms the buttons —
      // the panel leaves only when the resolved frame lands.
      if (mounted) setState(() => _answered = false);
    }
  }

  ConnectionClient _clientOrThrow() {
    final client = _boundApprovalClient;
    if (client == null) {
      throw StateError('approval card has no bound connection client');
    }
    return client;
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = ref.watch(currentSessionIdProvider)?.value;
    if (sessionId == null) return const SizedBox.shrink();
    final pending = ref.watch(approvalsProvider)[sessionId];
    if (pending == null) return const SizedBox.shrink();

    return Card(
      key: const ValueKey('approval-card'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ref.bindLocale(kQuestionNamespace)('approval.header'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              pending.reason ?? 'Escalation: ${pending.toolName}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('approval-reject'),
                  onPressed: _answered
                      ? null
                      : () => _answer(pending, ApprovalAnswer.rejected),
                  child: Text(
                    ref.bindLocale(kQuestionNamespace)('approval.reject'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('approval-allow'),
                  onPressed: _answered
                      ? null
                      : () => _answer(pending, ApprovalAnswer.allowedOnce),
                  child: Text(
                    ref.bindLocale(kQuestionNamespace)('approval.allowOnce'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
