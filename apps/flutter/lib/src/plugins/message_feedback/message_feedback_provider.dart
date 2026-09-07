import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rating — like/dislike pair.
enum FeedbackRating { none, positive, negative }

/// One message feedback row.
class FeedbackItem {
  const FeedbackItem({
    required this.messageId,
    this.rating = FeedbackRating.none,
    this.note,
  });
  final String messageId;
  final FeedbackRating rating;
  final String? note;
  FeedbackItem copyWith({FeedbackRating? rating, String? note}) => FeedbackItem(
    messageId: messageId,
    rating: rating ?? this.rating,
    note: note ?? this.note,
  );
}

/// Per-message feedback rows (the store is empty until a rating lands; there
/// are no fixtures).
///
/// Superseded by the Host-durable [MessageFeedbackController] seat
/// (`message_feedback_providers.dart`): new surfaces watch
/// `messageFeedbackSessionProvider` and route mutations through its notifier
/// so ratings reach Host durability. Kept for compat; do not extend.
@Deprecated(
  'Use messageFeedbackSessionProvider (Host-durable controller seat) instead.',
)
final messageFeedbackProvider =
    StateNotifierProvider<MessageFeedbackNotifier, Map<String, FeedbackItem>>(
      (ref) => MessageFeedbackNotifier(),
    );

class MessageFeedbackNotifier extends StateNotifier<Map<String, FeedbackItem>> {
  MessageFeedbackNotifier() : super({});
  void rate(String id, FeedbackRating rating) {
    final existing = state[id];
    final next = existing?.rating == rating ? FeedbackRating.none : rating;
    state = {
      ...state,
      id: FeedbackItem(messageId: id, rating: next, note: existing?.note),
    };
  }

  void setNote(String id, String note) {
    final existing = state[id];
    state = {
      ...state,
      id: FeedbackItem(
        messageId: id,
        rating: existing?.rating ?? FeedbackRating.none,
        note: note.isEmpty ? null : note,
      ),
    };
  }

  void clearNote(String id) {
    final existing = state[id];
    if (existing == null) return;
    state = {
      ...state,
      id: FeedbackItem(messageId: id, rating: existing.rating),
    };
  }
}
