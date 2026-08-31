import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'user_questions_provider.dart';

/// User questions screen — QuestionComposer + PlanReviewPanel.
///
/// Mirrors `QuestionComposer` routing (plan-review vs generic) + `QuestionFlow`
/// + `PlanReviewPanel` decision card. ConsumerWidget, Theme + DswTokens,
/// empty/loading.
class UserQuestionsScreen extends ConsumerWidget {
  const UserQuestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final AsyncValue<void> loading = ref.watch(userQuestionsLoadingProvider);
    final PlanReview? review = ref.watch(planReviewProvider);
    final List<Question> questions = ref.watch(userQuestionsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Questions',
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
      body: loading.when(
        data: (_) {
          if (review != null) {
            return ListView(
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              children: [
                PlanReviewPanel(review: review, aliases: aliases),
                const SizedBox(height: DswTokens.spaceLg),
                Text(
                  'Pending questions',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceSm),
                QuestionComposer(questions: questions, aliases: aliases),
              ],
            );
          }
          if (questions.isEmpty) return _EmptyQuestions(aliases: aliases);
          return ListView(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            children: [
              QuestionComposer(questions: questions, aliases: aliases),
            ],
          );
        },
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: aliases.labelTertiary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceMd),
              Text(
                'Loading questions…',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  color: aliases.labelSecondary,
                ),
              ),
            ],
          ),
        ),
        error: (Object err, StackTrace st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 28,
                  color: aliases.stateErrorPrimary,
                ),
                const SizedBox(height: DswTokens.spaceSm),
                Text(
                  'Failed to load questions',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(userQuestionsLoadingProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// QuestionComposer — paged generic question flow.
class QuestionComposer extends ConsumerStatefulWidget {
  const QuestionComposer({
    super.key,
    required this.questions,
    required this.aliases,
  });
  final List<Question> questions;
  final DswAliases aliases;

  @override
  ConsumerState<QuestionComposer> createState() => _QuestionComposerState();
}

class _QuestionComposerState extends ConsumerState<QuestionComposer> {
  int _index = 0;
  final Map<String, List<String>> _selected = {};
  final Map<String, String> _custom = {};
  bool _busy = false;
  bool _minimized = false;
  String? _error;

  Question get _q => widget.questions[_index];

  bool _answered(String id) {
    final List<String> sel = _selected[id] ?? const [];
    final String cust = (_custom[id] ?? '').trim();
    return sel.isNotEmpty || cust.isNotEmpty;
  }

  void _choose(String label) {
    final String id = _q.id;
    setState(() {
      _error = null;
      if (_q.multiSelect) {
        final List<String> cur = List<String>.from(_selected[id] ?? []);
        if (cur.contains(label)) {
          cur.remove(label);
        } else {
          cur.add(label);
        }
        _selected[id] = cur;
      } else {
        _selected[id] = [label];
        _custom[id] = '';
        if (_index < widget.questions.length - 1) _index += 1;
      }
    });
  }

  void _submit() {
    final int missing = widget.questions.indexWhere((q) {
      final List<String> sel = _selected[q.id] ?? const [];
      final String cust = (_custom[q.id] ?? '').trim();
      final bool skipped = sel.isEmpty && cust.isEmpty;
      // treat empty + not multi as missing unless we add skip semantics
      return skipped;
    });
    if (missing >= 0 && !_answered(widget.questions[missing].id)) {
      setState(() {
        _index = missing;
        _error = 'Please answer all questions';
      });
      return;
    }
    setState(() => _busy = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Submitted — stub')));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();
    final Question q = _q;
    final List<String> sel = _selected[q.id] ?? const [];
    return Container(
      decoration: BoxDecoration(
        color: widget.aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: widget.aliases.borderL2),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(DswTokens.spaceMd),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (q.header != null)
                        Text(
                          q.header!,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: widget.aliases.labelCaption,
                            letterSpacing: 0.4,
                          ),
                        ),
                      Text(
                        q.question,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          fontWeight: FontWeight.w600,
                          color: widget.aliases.labelPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _minimized ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: widget.aliases.labelTertiary,
                  ),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _minimized = !_minimized),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: widget.aliases.labelTertiary,
                  ),
                  onPressed: _busy
                      ? null
                      : () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cancel — stub')),
                        ),
                ),
              ],
            ),
          ),
          if (!_minimized) ...[
            Divider(height: 1, color: widget.aliases.borderL2),
            Padding(
              padding: const EdgeInsets.all(DswTokens.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (q.detail != null) ...[
                    Text(
                      q.detail!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        color: widget.aliases.labelSecondary,
                      ),
                    ),
                    const SizedBox(height: DswTokens.spaceMd),
                  ],
                  for (int i = 0; i < q.options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
                      child: _OptionRow(
                        option: q.options[i],
                        index: i,
                        selected: sel.contains(q.options[i].label),
                        multi: q.multiSelect,
                        aliases: widget.aliases,
                        onTap: () => _choose(q.options[i].label),
                      ),
                    ),
                  const SizedBox(height: DswTokens.spaceSm),
                  TextField(
                    enabled: !_busy,
                    decoration: InputDecoration(
                      hintText: 'Custom answer…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                      ),
                    ),
                    onChanged: (String v) => setState(() {
                      _custom[q.id] = v;
                      if (!_q.multiSelect) _selected[q.id] = [];
                      _error = null;
                    }),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: DswTokens.spaceSm),
                    Text(
                      _error!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: widget.aliases.stateErrorPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: widget.aliases.borderL2),
            Padding(
              padding: const EdgeInsets.all(DswTokens.spaceMd),
              child: Row(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 18),
                        onPressed: _index == 0 || _busy
                            ? null
                            : () => setState(() {
                                _index -= 1;
                                _error = null;
                              }),
                      ),
                      Text(
                        '${_index + 1} / ${widget.questions.length}',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: widget.aliases.labelCaption,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 18),
                        onPressed:
                            _index == widget.questions.length - 1 || _busy
                            ? null
                            : () => setState(() {
                                _index += 1;
                                _error = null;
                              }),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              _selected[q.id] = [];
                              _custom[q.id] = '';
                              if (_index < widget.questions.length - 1) {
                                _index += 1;
                              } else {
                                _submit();
                              }
                            });
                          },
                    child: const Text('Skip'),
                  ),
                  const SizedBox(width: DswTokens.spaceSm),
                  FilledButton(
                    onPressed: _busy || !_answered(q.id)
                        ? null
                        : () {
                            if (_index < widget.questions.length - 1) {
                              setState(() => _index += 1);
                            } else {
                              _submit();
                            }
                          },
                    child: _busy
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.aliases.labelPrimaryForeground,
                            ),
                          )
                        : Text(
                            _index == widget.questions.length - 1
                                ? 'Submit'
                                : 'Next',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.index,
    required this.selected,
    required this.multi,
    required this.aliases,
    required this.onTap,
  });
  final QuestionOption option;
  final int index;
  final bool selected;
  final bool multi;
  final DswAliases aliases;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected && !multi
          ? aliases.specificSidebarNavItemActive
          : aliases.bgOverlay,
      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DswTokens.spaceMd,
            vertical: DswTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            border: Border.all(
              color: selected
                  ? aliases.buttonGhostActiveBorder
                  : aliases.borderL1,
            ),
          ),
          child: Row(
            children: [
              multi
                  ? Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: selected
                            ? aliases.stateBusinessPrimary
                            : DswTokens.transparent,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: selected
                              ? aliases.stateBusinessPrimary
                              : aliases.borderL2,
                        ),
                      ),
                      child: selected
                          ? Icon(
                              Icons.check,
                              size: 12,
                              color: aliases.labelPrimaryForeground,
                            )
                          : null,
                    )
                  : Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: aliases.bgLayer2,
                        shape: BoxShape.circle,
                        border: Border.all(color: aliases.borderL2),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            color: aliases.labelSecondary,
                          ),
                        ),
                      ),
                    ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    if (option.description != null)
                      Text(
                        option.description!,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              if (option.label.contains('recommended'))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: aliases.stateSuccessTertiary,
                    borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                  ),
                  child: Text(
                    'recommended',
                    style: TextStyle(
                      fontSize: 10,
                      color: aliases.stateSuccessPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// PlanReviewPanel — waiting-approval card for plan-review intent.
class PlanReviewPanel extends StatefulWidget {
  const PlanReviewPanel({
    super.key,
    required this.review,
    required this.aliases,
  });
  final PlanReview review;
  final DswAliases aliases;

  @override
  State<PlanReviewPanel> createState() => _PlanReviewPanelState();
}

class _PlanReviewPanelState extends State<PlanReviewPanel> {
  bool _busy = false;
  String? _error;

  void _settle(Future<void> Function() send) {
    setState(() {
      _busy = true;
      _error = null;
    });
    send().catchError((Object e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlanReview r = widget.review;
    final DswAliases a = widget.aliases;
    return Container(
      decoration: BoxDecoration(
        color: a.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: a.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceMd,
              vertical: DswTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: a.stateBusinessTertiary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DswTokens.radiusLg),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: a.stateBusinessPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Text(
                  'Plan review',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    fontWeight: FontWeight.w600,
                    color: a.stateBusinessPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DswTokens.spaceMd),
            child: SelectableText(
              r.plan,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: a.labelPrimary,
              ),
            ),
          ),
          Divider(height: 1, color: a.borderL2),
          Padding(
            padding: const EdgeInsets.all(DswTokens.spaceMd),
            child: Row(
              children: [
                if (_error != null)
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: a.stateErrorPrimary,
                      ),
                    ),
                  ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _settle(() async {
                          await Future.delayed(
                            const Duration(milliseconds: 400),
                          );
                          if (!mounted) return;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Discuss — stub')),
                          );
                        }),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Discuss'),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                if (r.decline != null)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _settle(() async {
                            await Future.delayed(
                              const Duration(milliseconds: 400),
                            );
                            if (!mounted) return;
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Decline: ${r.decline!.label}'),
                              ),
                            );
                          }),
                    child: const Text('Decline'),
                  ),
                const SizedBox(width: DswTokens.spaceSm),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _settle(() async {
                          await Future.delayed(
                            const Duration(milliseconds: 400),
                          );
                          if (!mounted) return;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Approve — stub')),
                          );
                        }),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQuestions extends StatelessWidget {
  const _EmptyQuestions({required this.aliases});
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 32, color: aliases.labelCaption),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              'No questions',
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Questions from the agent will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
