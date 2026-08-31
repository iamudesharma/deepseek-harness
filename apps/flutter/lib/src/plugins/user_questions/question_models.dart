/// Question domain models — Dart mirrors of the wire vocabulary
/// (`@deepseek-ai/dsh-user-questions/types`): `AskUserQuestionItem` frames in,
/// `AskUserQuestionAnswer` batches out, plus the `plan-review` presentation
/// narrowing (port of `ui-user-questions/src/client/contract/slots.ts:
/// planReviewOf`).
library;

import 'package:meta/meta.dart';

/// One selectable answer offered to the user.
@immutable
class QuestionOption {
  /// Creates an option.
  const QuestionOption({required this.label, this.description});

  /// Decodes one wire option.
  static QuestionOption? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    if (label is! String) return null;
    final description = raw['description'];
    return QuestionOption(
      label: label,
      description: description is String ? description : null,
    );
  }

  /// User-facing label.
  final String label;

  /// Optional extra context.
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is QuestionOption &&
      other.label == label &&
      other.description == description;

  @override
  int get hashCode => Object.hash(label, description);
}

/// A caller-declared presentation intent; an intent changes presentation
/// only, never the protocol.
@immutable
class QuestionIntent {
  /// Creates an intent.
  const QuestionIntent({required this.kind, required this.approve});

  /// Decodes one wire intent; null for kinds this client does not know (the
  /// generic flow owns those requests). `approve` carries the exact option
  /// label the intent nominates — React's `planReviewOf` matches options
  /// against it, so dropping it would disable plan-review narrowing.
  static QuestionIntent? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['kind'] != 'plan-review') return null;
    final approve = raw['approve'];
    if (approve is! String || approve.isEmpty) return null;
    return QuestionIntent(kind: 'plan-review', approve: approve);
  }

  /// Intent discriminant (`'plan-review'`).
  final String kind;

  /// The approving option label.
  final String approve;
}

/// One question of a user-questions request (`AskUserQuestionItem`).
@immutable
class QuestionItem {
  /// Creates a question item.
  const QuestionItem({
    required this.id,
    required this.question,
    this.detail,
    this.header,
    this.options = const [],
    this.multiSelect = false,
    this.intent,
  });

  /// Decodes one raw frame question; throws [ArgumentError] on a malformed
  /// row (frames are host-validated upstream, so a bad shape means a broken
  /// peer, not a variant to skip).
  factory QuestionItem.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final question = json['question'];
    if (id is! String || id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must be a non-empty string');
    }
    if (question is! String) {
      throw ArgumentError.value(question, 'question', 'must be a string');
    }
    final detail = json['detail'] is String ? json['detail'] as String : null;
    final header = json['header'] is String ? json['header'] as String : null;
    final multiSelect = json['multiSelect'] == true;
    final optionsRaw = json['options'];
    final options = optionsRaw is List
        ? optionsRaw
              .map(QuestionOption.tryFromJson)
              .whereType<QuestionOption>()
              .toList()
        : <QuestionOption>[];
    return QuestionItem(
      id: id,
      question: question,
      detail: detail,
      header: header,
      options: options,
      multiSelect: multiSelect,
      intent: QuestionIntent.tryFromJson(json['intent']),
    );
  }

  /// Stable caller-provided question id, echoed in the answer.
  final String id;

  /// The question to display.
  final String question;

  /// Supporting detail kept out of option labels.
  final String? detail;

  /// Short heading/group label.
  final String? header;

  /// Offered choices.
  final List<QuestionOption> options;

  /// Whether more than one option may be selected. Defaults single-select.
  final bool multiSelect;

  /// Presentation intent when declared.
  final QuestionIntent? intent;
}

/// One structured answer item (`AskUserQuestionAnswerItem`).
@immutable
class QuestionAnswerItem {
  /// Creates an answer item.
  const QuestionAnswerItem({
    required this.id,
    required this.selected,
    this.custom,
  });

  /// Wire form.
  Map<String, Object?> toJson() => {
    'id': id,
    'selected': selected,
    if (custom != null && custom!.isNotEmpty) 'custom': custom,
  };

  /// The answered question id.
  final String id;

  /// Selected option labels.
  final List<String> selected;

  /// Free-text "Other" answer.
  final String? custom;
}

/// The whole answer batch (`AskUserQuestionAnswer`).
@immutable
class QuestionAnswerBatch {
  /// Creates a batch.
  const QuestionAnswerBatch({required this.answers});

  /// Wire form (the result value slot of the responding client-response).
  Map<String, Object?> toJson() => {
    'answers': [for (final a in answers) a.toJson()],
  };

  /// Structured answers keyed by question id order.
  final List<QuestionAnswerItem> answers;
}

/// A request narrowed to the plan-review presentation intent: everything the
/// decision card renders and answers with.
@immutable
class PlanReviewNarrowed {
  /// Creates a narrowing.
  const PlanReviewNarrowed({
    required this.id,
    required this.question,
    required this.plan,
    required this.approve,
    this.decline,
  });

  /// The reviewed question's id, echoed in the answer.
  final String id;

  /// The question text.
  final String question;

  /// The plan markdown under review.
  final String plan;

  /// The option that approves the plan.
  final QuestionOption approve;

  /// The option that declines it; absent when none was offered.
  final QuestionOption? decline;
}

/// Narrow a request to a renderable plan review, or null when the generic
/// flow owns it. The card claims a request only when it can send every answer
/// that request allows: one question declaring the intent, carrying the plan
/// as its detail, offering the approve label, and binary single-choice.
PlanReviewNarrowed? planReviewOf(List<QuestionItem> questions) {
  if (questions.length != 1) return null;
  final question = questions.first;
  final intent = question.intent;
  if (intent?.kind != 'plan-review' || question.detail == null) return null;
  if (question.multiSelect) return null;
  if (question.options.length > 2) return null;
  QuestionOption? approve;
  QuestionOption? decline;
  for (final option in question.options) {
    if (option.label == intent!.approve) {
      approve = option;
    } else {
      decline = option;
    }
  }
  if (approve == null) return null;
  return PlanReviewNarrowed(
    id: question.id,
    question: question.question,
    plan: question.detail!,
    approve: approve,
    decline: decline,
  );
}
