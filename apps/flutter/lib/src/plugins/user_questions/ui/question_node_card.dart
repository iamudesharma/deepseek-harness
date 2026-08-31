/// The keyed `question` chat-node renderer: renders the session's pending
/// question set (generic option flow and plan-review card) and submits whole
/// batch answers echoing the requested frame's rpcId.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate, kCommonNamespace;
import '../../../core/session/session_provider.dart';
import '../../conversation/hub.dart' show ChatNodeData;
import '../locales.dart';
import '../question_models.dart';
import '../question_responder.dart';
import '../questions_state.dart';

ConnectionClient? _boundClient;

/// Binds the connection client answers ride (plugin activation).
void bindQuestionClient(ConnectionClient? client) {
  _boundClient = client;
}

/// Renders one `question` node: the current session's pending-request card,
/// empty when none is live.
Widget renderQuestionNode(BuildContext context, ChatNodeData data) =>
    const QuestionNodeCard();

/// The pending-question card bound to the current session's request.
class QuestionNodeCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const QuestionNodeCard({super.key});

  @override
  ConsumerState<QuestionNodeCard> createState() => _QuestionNodeCardState();
}

class _QuestionNodeCardState extends ConsumerState<QuestionNodeCard> {
  final Map<String, List<String>> _selected = {};
  final Map<String, TextEditingController> _custom = {};

  @override
  void dispose() {
    for (final c in _custom.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(PendingQuestion pending) async {
    if (_boundClient == null) return;
    final responder = QuestionResponder(
      client: _boundClient!,
      pending: pending,
    );
    final answers = <QuestionAnswerItem>[
      for (final q in pending.questions)
        QuestionAnswerItem(
          id: q.id,
          selected: _selected[q.id] ?? const [],
          custom: _custom[q.id]?.text.trim(),
        ),
    ];
    await responder.answer(QuestionAnswerBatch(answers: answers));
  }

  Future<void> _cancel(PendingQuestion pending) async {
    if (_boundClient == null) return;
    await QuestionResponder(client: _boundClient!, pending: pending).cancel();
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = ref.watch(currentSessionIdProvider)?.value;
    if (sessionId == null) return const SizedBox.shrink();
    final pending = ref.watch(pendingQuestionsProvider)[sessionId];
    if (pending == null) return const SizedBox.shrink();

    final review = planReviewOf(pending.questions);
    if (review != null) {
      return _PlanReviewCard(
        review: review,
        onDecide: (label) async {
          _selected[review.id] = [label];
          await _submit(pending);
        },
      );
    }
    return _GenericFlow(
      pending: pending,
      selected: _selected,
      onToggle: (q, label) {
        setState(() {
          final list = _selected.putIfAbsent(q.id, () => []);
          if (q.multiSelect) {
            list.contains(label) ? list.remove(label) : list.add(label);
          } else {
            _selected[q.id] = [label];
          }
        });
      },
      onSubmit: () => _submit(pending),
      onCancel: () => _cancel(pending),
    );
  }
}

class _PlanReviewCard extends StatelessWidget {
  const _PlanReviewCard({required this.review, required this.onDecide});

  final PlanReviewNarrowed review;
  final Future<void> Function(String label) onDecide;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              review.question,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(review.plan, maxLines: 8, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onDecide(review.approve.label),
                  child: Text(review.approve.label),
                ),
                if (review.decline != null)
                  TextButton(
                    onPressed: () => onDecide(review.decline!.label),
                    child: Text(review.decline!.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GenericFlow extends ConsumerWidget {
  const _GenericFlow({
    required this.pending,
    required this.selected,
    required this.onToggle,
    required this.onSubmit,
    required this.onCancel,
  });

  final PendingQuestion pending;
  final Map<String, List<String>> selected;
  final void Function(QuestionItem q, String label) onToggle;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kQuestionNamespace);
    final Translate tcommon = ref.bindLocale(kCommonNamespace);
    return Card(
      key: const ValueKey('question-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final q in pending.questions) ...[
              Text(q.question, style: Theme.of(context).textTheme.titleSmall),
              Wrap(
                spacing: 6,
                children: [
                  for (final option in q.options)
                    ChoiceChip(
                      key: ValueKey('option-${q.id}-${option.label}'),
                      label: Text(option.label),
                      selected: selected[q.id]?.contains(option.label) ?? false,
                      onSelected: (_) => onToggle(q, option.label),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onCancel, child: Text(tcommon('cancel'))),
                FilledButton(
                  key: const ValueKey('question-submit'),
                  onPressed: onSubmit,
                  child: Text(tcommon('submit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
