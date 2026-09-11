/// The keyed `question` chat-node renderer — Flutter port of React
/// `QuestionComposer` (`packages/client/ui-user-questions/src/client/`):
/// the pending request renders as a composer-takeover card that branches on
/// the declared presentation intent — the generic paged question flow, or
/// the plan-review decision card — and submits whole batch answers echoing
/// the requested frame's rpcId.
///
/// Generic flow (React `QuestionFlow`): one question per page with a
/// numbered (single-select) or checkbox (multi-select) option list, the
/// recommended-label split, a custom answer field, and a footer pager with
/// Skip / Next / Submit. Copy resolves through the `question` dictionaries
/// plus the shared `common` namespace (`submit` / `submitting` / `cancel`).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate, kCommonNamespace;
import '../../../core/session/live_sync.dart'
    show reconcileSessionPendingStatus;
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/ds_button.dart';
import '../../../widgets/primitives/markdown.dart';
import '../../conversation/hub.dart' show ChatNodeData;
import '../approval_state.dart';
import '../locales.dart' show kQuestionNamespace;
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

/// Splits the conventional recommendation suffix without changing the answer
/// value (React `parseRecommendedLabel`): the suffix is presentation only and
/// the stripped label is still what a selection sent back.
/// @param label - original option label returned if selected.
/// @returns display label plus recommendation state.
({String label, bool recommended}) parseRecommendedLabel(String label) {
  final suffix = RegExp(
    r'\s*(?:\((?:recommended|推荐)\)|（(?:recommended|推荐)）)\s*$',
    caseSensitive: false,
  );
  if (!suffix.hasMatch(label)) return (label: label, recommended: false);
  return (label: label.replaceFirst(suffix, ''), recommended: true);
}

/// One in-progress answer (React `QuestionDraftAnswer`).
class _DraftAnswer {
  /// Creates an empty draft.
  _DraftAnswer();

  /// Offered labels currently selected.
  final List<String> selected = [];

  /// Human-authored alternative or additional answer.
  String custom = '';

  /// Whether the user explicitly skipped this question.
  bool skipped = false;
}

/// The pending-question card bound to the current session's request.
class QuestionNodeCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const QuestionNodeCard({super.key});

  @override
  ConsumerState<QuestionNodeCard> createState() => _QuestionNodeCardState();
}

class _QuestionNodeCardState extends ConsumerState<QuestionNodeCard> {
  String? _requestKey;
  int _index = 0;
  List<_DraftAnswer> _drafts = const [];
  final Map<String, TextEditingController> _controllers = {};
  bool _submitting = false;
  bool _minimized = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String questionId) =>
      _controllers.putIfAbsent(questionId, TextEditingController.new);

  /// Drops the settled wait locally and recomputes the session marker — the
  /// Dart face of React `answerQuestion`'s `finally { remove() }`: the
  /// composer unmounts when the waterfall settles locally, not on a host
  /// frame. The host never emits `question/resolved` for an answered
  /// request (no such emission exists in `packages/`), so waiting for one
  /// leaves the card visible forever. Id-guarded like the frame arm, so a
  /// late or duplicate settlement is a no-op.
  void _settleLocally(PendingQuestion pending, String outcome) {
    final container = ref;
    container
        .read(pendingQuestionsProvider.notifier)
        .resolved(pending.sessionId, pending.rpcId, outcome);
    reconcileSessionPendingStatus(
      container.read(pendingQuestionsProvider.notifier),
      container.read(approvalsProvider.notifier),
      container.read(sessionsProvider.notifier),
      pending.sessionId,
    );
  }

  bool _answered(_DraftAnswer draft) =>
      draft.selected.isNotEmpty || draft.custom.trim().isNotEmpty;

  bool _completed(_DraftAnswer draft) => _answered(draft) || draft.skipped;

  /// Sends the whole batch (React `submitDrafts`): skipped questions answer
  /// empty, a custom answer replaces a single-select choice while a
  /// multi-select keeps its checked labels.
  Future<void> _submit(PendingQuestion pending) async {
    if (_boundClient == null || _submitting) return;
    final missing = _drafts.indexWhere((d) => !_completed(d));
    if (missing >= 0) {
      setState(() {
        _index = missing;
        _error = ref.bindLocale(kQuestionNamespace)('error.incomplete');
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final responder = QuestionResponder(
        client: _boundClient!,
        pending: pending,
      );
      final answers = <QuestionAnswerItem>[
        for (var i = 0; i < pending.questions.length; i++)
          _answerFor(pending.questions[i], _drafts[i]),
      ];
      await responder.answer(QuestionAnswerBatch(answers: answers));
    } catch (e) {
      // React parity (`submitDrafts` catch): a rejected receipt keeps the
      // question open with the failure shown, so the user can retry. Never
      // hide a request the host refused.
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString();
        });
      }
      return;
    }
    if (!mounted) return;
    _settleLocally(pending, 'answered');
  }

  QuestionAnswerItem _answerFor(QuestionItem question, _DraftAnswer draft) {
    if (draft.skipped) {
      return QuestionAnswerItem(id: question.id, selected: const []);
    }
    final custom = draft.custom.trim();
    return QuestionAnswerItem(
      id: question.id,
      selected: custom.isEmpty || question.multiSelect
          ? List<String>.unmodifiable(draft.selected)
          : const [],
      custom: custom.isEmpty ? null : custom,
    );
  }

  Future<void> _cancel(PendingQuestion pending) async {
    if (_boundClient == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await QuestionResponder(client: _boundClient!, pending: pending).cancel();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString();
        });
      }
      return;
    }
    if (!mounted) return;
    // React parity (`cancelFlow` → `pending.cancel()` → the listener's
    // `finally remove()`): a settled cancellation closes the surface.
    _settleLocally(pending, 'cancelled');
  }

  void _choose(QuestionItem question, String label) {
    if (_submitting) return;
    setState(() {
      final draft = _drafts[_index];
      if (question.multiSelect) {
        draft.selected.contains(label)
            ? draft.selected.remove(label)
            : draft.selected.add(label);
      } else {
        draft.selected
          ..clear()
          ..add(label);
        draft.custom = '';
        _controllerFor(question.id).clear();
        // Single-select answers advance like React `choose`: the next
        // question follows immediately unless this was the last page.
        if (_index < _drafts.length - 1) _index += 1;
      }
      draft.skipped = false;
      _error = null;
    });
  }

  void _customChanged(QuestionItem question, String value) {
    if (_submitting) return;
    setState(() {
      final draft = _drafts[_index];
      draft.custom = value;
      draft.skipped = false;
      if (!question.multiSelect) draft.selected.clear();
      _error = null;
    });
  }

  void _goTo(int index) {
    setState(() {
      _index = index.clamp(0, _drafts.length - 1);
      _error = null;
    });
  }

  void _skip(PendingQuestion pending) {
    if (_submitting) return;
    setState(() {
      final draft = _drafts[_index];
      draft.selected.clear();
      draft.custom = '';
      _controllerFor(pending.questions[_index].id).clear();
      draft.skipped = true;
      _error = null;
      if (_index < _drafts.length - 1) {
        _index += 1;
      }
    });
    if (_index >= _drafts.length - 1) {
      // React `skipQuestion`: skipping the last page submits the batch.
      unawaited(_submit(pending));
    }
  }

  void _continue(PendingQuestion pending) {
    if (_submitting) return;
    if (!_answered(_drafts[_index])) {
      setState(() {
        _error = ref.bindLocale(kQuestionNamespace)('error.unanswered');
      });
      return;
    }
    if (_index < _drafts.length - 1) {
      _goTo(_index + 1);
      return;
    }
    _submit(pending);
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = ref.watch(currentSessionIdProvider)?.value;
    if (sessionId == null) return const SizedBox.shrink();
    final pending = ref.watch(pendingQuestionsProvider)[sessionId];
    if (pending == null) return const SizedBox.shrink();

    // A fresh request resets navigation, drafts, and custom fields (React
    // keys the flow by `pending.key`; field controllers are per question id
    // here, so they are cleared explicitly when the request changes).
    if (_requestKey != pending.rpcId) {
      _requestKey = pending.rpcId;
      _index = 0;
      _minimized = false;
      _error = null;
      _drafts = [for (final _ in pending.questions) _DraftAnswer()];
      for (final c in _controllers.values) {
        c.clear();
      }
    }

    final review = planReviewOf(pending.questions);
    final Translate t = ref.bindLocale(kQuestionNamespace);
    final Translate tcommon = ref.bindLocale(kCommonNamespace);
    if (review != null) {
      return _PlanReviewCard(
        review: review,
        t: t,
        busy: _submitting,
        error: _error,
        onDiscuss: () => _cancel(pending),
        onDecide: (label) async {
          _drafts[0].selected
            ..clear()
            ..add(label);
          await _submit(pending);
        },
      );
    }
    return _QuestionFlow(
      pending: pending,
      index: _index,
      drafts: _drafts,
      controllerFor: _controllerFor,
      minimized: _minimized,
      busy: _submitting,
      error: _error,
      t: t,
      tcommon: tcommon,
      onToggleMinimized: () =>
          setState(() => _minimized = !_minimized),
      onChoose: (question, label) => _choose(question, label),
      onCustomChanged: _customChanged,
      onPrev: () => _goTo(_index - 1),
      onNextPage: () => _goTo(_index + 1),
      onSkip: () => _skip(pending),
      onContinue: () => _continue(pending),
      onCancel: () => _cancel(pending),
    );
  }
}

/// The composer-takeover frame: centered on the composer axis at the shared
/// content width (React `.frame`: `padding: 6px calc(clearance + 16px) 10px`).
class _QuestionFrame extends StatelessWidget {
  const _QuestionFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 6, 32, 10),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 748),
        child: child,
      ),
    ),
  );
}

/// The generic paged question flow (React `QuestionFlow`).
class _QuestionFlow extends StatelessWidget {
  const _QuestionFlow({
    required this.pending,
    required this.index,
    required this.drafts,
    required this.controllerFor,
    required this.minimized,
    required this.busy,
    required this.t,
    required this.tcommon,
    required this.onToggleMinimized,
    required this.onChoose,
    required this.onCustomChanged,
    required this.onPrev,
    required this.onNextPage,
    required this.onSkip,
    required this.onContinue,
    required this.onCancel,
    this.error,
  });

  final PendingQuestion pending;
  final int index;
  final List<_DraftAnswer> drafts;
  final TextEditingController Function(String questionId) controllerFor;
  final bool minimized;
  final bool busy;
  final String? error;

  /// Question-namespace copy.
  final Translate t;

  /// Shared-namespace copy (`submit` / `submitting`).
  final Translate tcommon;
  final VoidCallback onToggleMinimized;
  final void Function(QuestionItem question, String label) onChoose;
  final void Function(QuestionItem question, String value) onCustomChanged;
  final VoidCallback onPrev;
  final VoidCallback onNextPage;
  final VoidCallback onSkip;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final question = pending.questions[index];
    final draft = drafts[index];
    final bool hasOptions = question.options.isNotEmpty;
    final double maxHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.6,
      520,
    );
    final bool isLast = index == pending.questions.length - 1;

    return _QuestionFrame(
      child: Container(
        key: const ValueKey('question-card'),
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: minimized ? double.infinity : maxHeight,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: aliases.specificInputMajor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: aliases.borderL2DarkmodeThin),
          boxShadow: DswTokens.shadowLv2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, aliases, question, t),
            if (!minimized) ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (question.detail != null &&
                          question.detail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                          child: DsMarkdown(
                            data: question.detail!,
                            selectable: true,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < question.options.length; i++)
                              _OptionRow(
                                key: ValueKey(
                                  'option-${question.id}-'
                                  '${question.options[i].label}',
                                ),
                                number: i + 1,
                                label: question.options[i].label,
                                description: question.options[i].description,
                                multiSelect: question.multiSelect,
                                selected: draft.selected.contains(
                                  question.options[i].label,
                                ),
                                enabled: !busy,
                                recommendedLabel: t('option.recommended'),
                                onTap: () => onChoose(
                                  question,
                                  question.options[i].label,
                                ),
                              ),
                            if (hasOptions)
                              _CustomRow(
                                controller: controllerFor(question.id),
                                multiSelect: question.multiSelect,
                                checked: draft.custom.trim().isNotEmpty,
                                enabled: !busy,
                                placeholder: t('custom.placeholder'),
                                onChanged: (value) =>
                                    onCustomChanged(question, value),
                                onSubmit: onContinue,
                              )
                            else
                              _BlockField(
                                key: ValueKey('question-custom-${question.id}'),
                                controller: controllerFor(question.id),
                                enabled: !busy,
                                placeholder: t('custom.placeholder'),
                                onChanged: (value) =>
                                    onCustomChanged(question, value),
                                onSubmit: onContinue,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _footer(
                context,
                aliases,
                t,
                tcommon,
                isLast: isLast,
                canContinue: !busy && _answered(draft),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _answered(_DraftAnswer draft) =>
      draft.selected.isNotEmpty || draft.custom.trim().isNotEmpty;

  Widget _header(
    BuildContext context,
    DswAliases aliases,
    QuestionItem question,
    Translate t,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 16, minimized ? 14 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (question.header != null && question.header!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      question.header!,
                      style: TextStyle(
                        fontSize: 11,
                        height: 16 / 11,
                        color: aliases.labelTertiary,
                      ),
                    ),
                  ),
                Text(
                  question.question,
                  style: TextStyle(
                    fontSize: 16,
                    height: 22 / 16,
                    fontWeight: FontWeight.w500,
                    color: aliases.labelPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconAction(
                key: const ValueKey('question-minimize'),
                icon: minimized
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                tooltip: t(minimized ? 'nav.maximize' : 'nav.minimize'),
                enabled: !busy,
                onPressed: onToggleMinimized,
              ),
              const SizedBox(width: 4),
              _IconAction(
                key: const ValueKey('question-cancel'),
                icon: Icons.close,
                iconSize: 16,
                tooltip: t('nav.cancel'),
                enabled: !busy,
                onPressed: onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(
    BuildContext context,
    DswAliases aliases,
    Translate t,
    Translate tcommon, {
    required bool isLast,
    required bool canContinue,
  }) {
    final Widget pager = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconAction(
          key: const ValueKey('question-prev'),
          icon: Icons.chevron_left,
          tooltip: t('nav.prev'),
          enabled: !busy && index > 0,
          onPressed: onPrev,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${index + 1} / ${pending.questions.length}',
            style: TextStyle(
              fontSize: 14,
              height: 24 / 14,
              fontWeight: FontWeight.w500,
              color: aliases.labelSecondary,
              wordSpacing: -2,
            ),
          ),
        ),
        _IconAction(
          key: const ValueKey('question-next'),
          icon: Icons.chevron_right,
          tooltip: t('nav.next'),
          enabled: !busy && !isLast,
          onPressed: onNextPage,
        ),
      ],
    );
    final Widget feedback = Text(
      error ?? '',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 11,
        height: 16 / 11,
        color: aliases.stateErrorPrimary,
      ),
    );
    final Widget skipButton = DsButton(
      key: const ValueKey('question-skip'),
      variant: DsButtonVariant.elevated,
      label: t('action.skip'),
      onPressed: busy ? null : onSkip,
    );
    final Widget submitButton = DsButton(
      key: const ValueKey('question-submit'),
      variant: DsButtonVariant.primary,
      label: busy
          ? tcommon('submitting')
          : isLast
          ? tcommon('submit')
          : t('action.next'),
      onPressed: canContinue ? onContinue : null,
    );
    final Widget actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        skipButton,
        const SizedBox(width: 12),
        submitButton,
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 0),
      child: Padding(
        // The card's own 10px bottom padding (React `.card { padding: 0 0 10px }`).
        padding: const EdgeInsets.only(bottom: 10),
        // React keeps one footer row (`.footer`, plus its ≤720px media query);
        // a phone card is too narrow for pager + feedback + two buttons, so
        // the actions drop to their own right-aligned row below the pager.
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      pager,
                      const SizedBox(width: 12),
                      Expanded(child: feedback),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 8,
                      children: [skipButton, submitButton],
                    ),
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                pager,
                const SizedBox(width: 12),
                Expanded(child: feedback),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One option row (React `.option`): 20px indicator seat, label, optional
/// recommended badge and description; hover/selected surface; 12px radius.
class _OptionRow extends StatefulWidget {
  const _OptionRow({
    super.key,
    required this.number,
    required this.label,
    required this.multiSelect,
    required this.selected,
    required this.enabled,
    required this.recommendedLabel,
    required this.onTap,
    this.description,
  });

  final int number;
  final String label;
  final String? description;
  final bool multiSelect;
  final bool selected;
  final bool enabled;

  /// Localized `option.recommended` badge copy.
  final String recommendedLabel;
  final VoidCallback onTap;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final display = parseRecommendedLabel(widget.label);
    final bool lit = widget.selected || _hovered;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 40),
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            color: lit ? aliases.interactiveBgHover : DswTokens.transparent,
            border: Border.all(
              color: widget.selected
                  ? aliases.borderL2
                  : DswTokens.transparent,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.multiSelect)
                _CheckboxSeat(checked: widget.selected)
              else
                _NumberSeat(number: widget.number),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      display.label,
                      style: TextStyle(
                        fontSize: 14,
                        height: 24 / 14,
                        fontWeight: FontWeight.w500,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    if (display.recommended)
                      _RecommendedBadge(label: widget.recommendedLabel),
                    if (widget.description != null &&
                        widget.description!.isNotEmpty)
                      Text(
                        widget.description!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 24 / 14,
                          color: aliases.labelTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-select leading indicator (React `.number`): 20×20 radius-6 overlay
/// seat showing the option number.
class _NumberSeat extends StatelessWidget {
  const _NumberSeat({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(top: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: 12,
          height: 18 / 12,
          fontWeight: FontWeight.w500,
          color: aliases.labelSecondary,
        ),
      ),
    );
  }
}

/// Multi-select checkbox seat (React `.checkbox`): 14×14 radius-4 box in the
/// 20px indicator seat, checked = label-primary fill with a foreground check.
class _CheckboxSeat extends StatelessWidget {
  const _CheckboxSeat({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: checked ? aliases.labelPrimary : DswTokens.transparent,
            border: Border.all(
              color: checked ? aliases.labelPrimary : aliases.borderL4,
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: checked
              ? Icon(
                  Icons.check,
                  size: 11,
                  color: aliases.labelPrimaryForeground,
                )
              : null,
        ),
      ),
    );
  }
}

/// Recommended badge (React `.badge`): accent fill, info-fill ink.
class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: aliases.specificSidebarNavItemActiveAccent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 18 / 11,
          fontWeight: FontWeight.w600,
          color: aliases.buttonInfoFill,
        ),
      ),
    );
  }
}

/// The custom-answer row inside an option list (React `.customRow`): an
/// option-shaped row whose copy is the inline answer field; focus or a typed
/// draft lifts it to the selected look.
class _CustomRow extends StatefulWidget {
  const _CustomRow({
    required this.controller,
    required this.multiSelect,
    required this.checked,
    required this.enabled,
    required this.placeholder,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool multiSelect;
  final bool checked;
  final bool enabled;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<_CustomRow> createState() => _CustomRowState();
}

class _CustomRowState extends State<_CustomRow> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool lifted = _focus.hasFocus || widget.checked;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: lifted ? aliases.interactiveBgHover : DswTokens.transparent,
        border: Border.all(
          color: lifted ? aliases.borderL2 : DswTokens.transparent,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.multiSelect)
            _CheckboxSeat(checked: widget.checked)
          else
            const _EditSeat(),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              maxLines: 6,
              minLines: 1,
              cursorColor: aliases.stateBusinessPrimary,
              style: TextStyle(
                fontSize: 14,
                height: 24 / 14,
                color: aliases.labelPrimary,
              ),
              // Every border slot is pinned: the shared theme's
              // `inputDecorationTheme` would otherwise leak its outline and
              // fill through the unset slots onto the transparent row.
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.placeholder,
                hintStyle: TextStyle(
                  fontSize: 14,
                  height: 24 / 14,
                  color: aliases.labelCaption,
                ),
              ),
              textInputAction: TextInputAction.done,
              onChanged: widget.onChanged,
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The custom row's single-select indicator (React `.number` with the pencil
/// glyph): a 20×20 overlay seat carrying a 12px edit icon.
class _EditSeat extends StatelessWidget {
  const _EditSeat();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(top: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.edit_outlined,
        size: 12,
        color: aliases.labelSecondary,
      ),
    );
  }
}

/// Optionless free-form answer (React `.customBlock`): the whole body is the
/// framed field; focus turns the border business-primary.
class _BlockField extends StatefulWidget {
  const _BlockField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.placeholder,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<_BlockField> createState() => _BlockFieldState();
}

class _BlockFieldState extends State<_BlockField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: aliases.bgModulePlatform,
        border: Border.all(
          color: _focus.hasFocus
              ? aliases.stateBusinessPrimary
              : aliases.borderL4,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        enabled: widget.enabled,
        autofocus: true,
        maxLines: 6,
        minLines: 1,
        cursorColor: aliases.stateBusinessPrimary,
        style: TextStyle(
          fontSize: 14,
          height: 24 / 14,
          color: aliases.labelPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: widget.placeholder,
          hintStyle: TextStyle(
            fontSize: 14,
            height: 24 / 14,
            color: aliases.labelCaption,
          ),
        ),
        textInputAction: TextInputAction.done,
        onChanged: widget.onChanged,
        onSubmitted: (_) => widget.onSubmit(),
      ),
    );
  }
}

/// Plan-review decision card — Flutter port of React `PlanReviewPanel`: warn
/// strip, scrollable plan body, and the discuss / refuse / approve actions.
class _PlanReviewCard extends StatelessWidget {
  const _PlanReviewCard({
    required this.review,
    required this.t,
    required this.busy,
    required this.onDiscuss,
    required this.onDecide,
    this.error,
  });

  final PlanReviewNarrowed review;

  /// Question-namespace copy.
  final Translate t;
  final bool busy;

  /// Failure of the last submission, kept visible for retry.
  final String? error;
  final VoidCallback onDiscuss;
  final Future<void> Function(String label) onDecide;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final double maxHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.6,
      520,
    );
    final decline = review.decline;
    return _QuestionFrame(
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: aliases.specificInputMajor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: aliases.stateWarnSecondary),
          boxShadow: DswTokens.shadowLv2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: aliases.stateWarnTertiary,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: aliases.stateWarnPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t('plan.header'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: aliases.stateWarnPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DsMarkdown(data: review.plan, selectable: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      error ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        height: 16 / 11,
                        color: aliases.stateErrorPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DsButton(
                    key: const ValueKey('plan-discuss'),
                    variant: DsButtonVariant.ghost,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: aliases.labelSecondary,
                    ),
                    label: t('plan.discuss'),
                    onPressed: busy ? null : onDiscuss,
                  ),
                  const SizedBox(width: 8),
                  if (decline != null)
                    DsButton(
                      key: const ValueKey('plan-decline'),
                      variant: DsButtonVariant.elevated,
                      label: t('plan.decline'),
                      onPressed: busy ? null : () => onDecide(decline.label),
                    ),
                  const SizedBox(width: 8),
                  DsButton(
                    key: const ValueKey('plan-approve'),
                    variant: DsButtonVariant.primary,
                    label: t('plan.approve'),
                    onPressed: busy
                        ? null
                        : () => onDecide(review.approve.label),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared 24×24 round icon action (React `.iconButton`): tertiary at
/// rest, hover surface and primary ink, dimmed when disabled.
class _IconAction extends StatefulWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.iconSize = 14,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final double iconSize;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Color color = !widget.enabled
        ? aliases.labelDimmed
        : _hovered
        ? aliases.labelPrimary
        : aliases.labelTertiary;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hovered && widget.enabled
                  ? aliases.interactiveBgHover
                  : DswTokens.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: color),
          ),
        ),
      ),
    );
  }
}
