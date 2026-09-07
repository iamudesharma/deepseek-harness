/// The question-composer chain entry — Flutter port of the selector-routed
/// `conversation.composer` registration in
/// `packages/client/ui-user-questions/src/client/index.ts`: the entry claims
/// the chain turn only while the session carries a pending-question carrier
/// (`select` narrows the owner's currency to [PendingQuestion]), taking over
/// the composer area with the shared question flow until the request
/// settles. One entry, two shapes: the card body already branches between
/// the plan-review decision surface and the generic flow, so the shape choice
/// stays inside the shared renderer exactly as in React.
library;

import 'package:flutter/widgets.dart';

import '../questions_state.dart';
import 'question_node_card.dart';

/// Chain selector: match only a pending-question carrier; anything else
/// abdicates the entry's turn (election continues down the chain).
Object? questionComposerSelect(Object? owner) =>
    owner is PendingQuestion ? owner : null;

/// The composer-area question surface (delegates to the shared node-card
/// body — one implementation, two mounts).
class QuestionComposerEntry extends StatelessWidget {
  /// Creates the entry.
  const QuestionComposerEntry({super.key});

  @override
  Widget build(BuildContext context) => const QuestionNodeCard();
}
