/// The approval collaboration surface — Flutter port of
/// `packages/client/ui-approval/src/client/ApprovalPanel.tsx`:
/// an amber "waiting for approval" strip, the asker's reason as the headline
/// (falling back to the escalation-by-toolName line), and a refuse/allow
/// action row. One-shot: the buttons disable after a click and re-arm on a
/// failed answer; the card leaves when the decision settles locally (the
/// host never broadcasts a resolution for a decided request), with late
/// frames and cancellations reconciled idempotently through the store.
///
/// Copy rides the `approval` namespace (waiting/detail.aria/escalation/
/// reject/allowOnce), verbatim port of `ui-approval`'s dictionaries.
///
/// The Tool-owned detail hole (`conversation.approval.detail`, rendered by
/// React per `callId`) has no Dart declaration yet: no Flutter Tool
/// contributor exists to fill it, so the card folds the paired call's
/// command line inline via [approvalCommandOf] instead of an empty slot.
/// Declaring the hole lands with the first Tool detail contributor.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/session/live_sync.dart'
    show reconcileSessionPendingStatus;
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../theme/app_theme.dart' show DswTokens;
import '../../tool/tool_models.dart' show ToolCall, liveToolCallsProvider;
import '../approval_responder.dart';
import '../approval_state.dart';
import '../questions_state.dart';
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

/// Command text of the tool call correlated with an approval — port of
/// React `ApprovalCommand.commandOf`: the `command` string in the call's
/// arguments, or null for absent, malformed, or unrelated arguments.
String? approvalCommandOf(ToolCall? call) {
  if (call == null) return null;
  Map<String, dynamic> args = call.args;
  if (args.isEmpty && call.argsRaw.isNotEmpty) {
    try {
      final parsed = jsonDecode(call.argsRaw);
      if (parsed is Map<String, dynamic>) {
        args = parsed;
      } else if (parsed is Map) {
        args = parsed.cast<String, dynamic>();
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }
  }
  final command = args['command'];
  return command is String ? command : null;
}

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
    if (_answered) return;
    setState(() => _answered = true);
    try {
      await ApprovalResponder(
        client: _clientOrThrow(),
        pending: pending,
      ).answer(outcome);
    } catch (_) {
      // A failed answer (rejected receipt / transport) re-arms the buttons —
      // the panel leaves only when the wait settles.
      if (mounted) setState(() => _answered = false);
      return;
    }
    if (!mounted) return;
    // React parity (the approval listener's `finally remove()`): the panel
    // leaves when the waterfall settles locally. The host never broadcasts
    // `approval/resolved` for a decided request (no such emission exists in
    // `packages/`; only cancellations synthesize one), so waiting for a
    // frame strands the card exactly like the question bug. Id-guarded like
    // the frame arm, so a late settlement is a no-op.
    final container = ref;
    container
        .read(approvalsProvider.notifier)
        .resolved(pending.sessionId, pending.approvalId);
    reconcileSessionPendingStatus(
      container.read(pendingQuestionsProvider.notifier),
      container.read(approvalsProvider.notifier),
      container.read(sessionsProvider.notifier),
      pending.sessionId,
    );
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
    final t = ref.bindLocale(kApprovalNamespace);
    // Paired tool-call command line (React `ApprovalCommand`): resolve the
    // running call by `callId` from the live fold; absent without a command.
    ToolCall? correlated;
    if (pending.callId != null) {
      for (final call in ref.watch(liveToolCallsProvider(sessionId))) {
        if (call.id == pending.callId) {
          correlated = call;
          break;
        }
      }
    }
    final command = approvalCommandOf(correlated);

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
                  t('waiting'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: t('detail.aria'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pending.reason ??
                        t('escalation').replaceAll(
                          '{toolName}',
                          pending.toolName,
                        ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  // React `.command`: 13/20 tertiary code text, breaks anywhere.
                  if (command != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      command,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXs13,
                        height: 20 / 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: DswTokens.fontFamilyCode,
                        fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                      ),
                    ),
                  ],
                ],
              ),
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
                  child: Text(t('reject')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('approval-allow'),
                  onPressed: _answered
                      ? null
                      : () => _answer(pending, ApprovalAnswer.allowedOnce),
                  child: Text(t('allowOnce')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
