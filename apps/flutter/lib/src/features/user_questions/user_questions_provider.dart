import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestionOption {
  const QuestionOption({required this.label, this.description});
  final String label;
  final String? description;
}

class Question {
  const Question({
    required this.id,
    required this.question,
    this.detail,
    this.options = const [],
    this.multiSelect = false,
    this.header,
  });
  final String id;
  final String question;
  final String? detail;
  final List<QuestionOption> options;
  final bool multiSelect;
  final String? header;
}

class PlanReview {
  const PlanReview({
    required this.id,
    required this.question,
    required this.plan,
    required this.approve,
    this.decline,
  });
  final String id;
  final String question;
  final String plan;
  final QuestionOption approve;
  final QuestionOption? decline;
}

final userQuestionsProvider = StateProvider<List<Question>>(
  (ref) => const [
    Question(
      id: 'q1',
      header: 'Clarify',
      question: 'Which framework should we use?',
      detail: 'We support React and Flutter.',
      options: [
        QuestionOption(label: 'React (recommended)', description: 'Web first'),
        QuestionOption(label: 'Flutter', description: 'Mobile first'),
      ],
    ),
    Question(id: 'q2', question: 'Any custom instructions?', options: []),
  ],
);

final planReviewProvider = StateProvider<PlanReview?>(
  (ref) => const PlanReview(
    id: 'pr1',
    question: 'Plan review',
    plan: '# Plan\n- Add login\n- Add tests',
    approve: QuestionOption(label: 'Approve', description: 'Looks good'),
    decline: QuestionOption(label: 'Decline', description: 'Needs work'),
  ),
);

final userQuestionsLoadingProvider = FutureProvider<void>((ref) async {
  await Future.delayed(const Duration(milliseconds: 300));
});

final draftAnswersProvider = StateProvider<Map<String, List<String>>>(
  (ref) => {},
);
