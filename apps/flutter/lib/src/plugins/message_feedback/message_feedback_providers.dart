/// Riverpod bridge over the message feedback plugin's per-session controller
/// map — the UI seat for Host-durable feedback.
///
/// Widgets never hold a [MessageFeedbackController] directly: they watch
/// [messageFeedbackSessionProvider] for one session's immutable view and reach
/// mutations through its notifier, so every surface in the session shares the
/// single controller the `'messageFeedback'` service owns (no second store
/// beside the controller map). Before plugin activation the seat falls back to
/// an unwired resolver whose calls settle as `unavailable` failures instead of
/// throwing, keeping standalone surfaces renderable.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'message_feedback_controller.dart';
import 'message_feedback_plugin.dart';

/// Remote face used until the plugin binds a live resolver: every call
/// reports a carrier failure instead of throwing, so UI stays renderable and
/// mutations settle visibly rather than vanishing.
class _UnwiredFeedbackRemote implements MessageFeedbackRemote {
  const _UnwiredFeedbackRemote();

  ReplyError<T> _err<T>() => ReplyError<T>(
        'unavailable',
        message: 'message feedback is not wired yet',
      );

  @override
  Future<FeedbackReply<List<MessageFeedbackItem>>> list({
    required String sessionId,
  }) async =>
      _err();

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> put({
    required String sessionId,
    required String messageId,
    required FeedbackRatingValue rating,
    String? note,
    required int? ifVersion,
  }) async =>
      _err();

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> delete({
    required String sessionId,
    required String messageId,
    required int ifVersion,
  }) async =>
      _err();
}

final _unwiredControllers =
    MessageFeedbackControllers(const _UnwiredFeedbackRemote());

/// The single controller resolver: the plugin-bound service once
/// [MessageFeedbackPlugin] activates, otherwise the unwired fallback.
/// Override with a fake-remote resolver in widget tests.
final messageFeedbackControllersProvider =
    Provider<MessageFeedbackControllers>(
  (ref) => activatedMessageFeedback ?? _unwiredControllers,
);

/// One session's live feedback view plus its mutation verbs, backed by the
/// session's [MessageFeedbackController] from [messageFeedbackControllersProvider].
final messageFeedbackSessionProvider = NotifierProvider.family<
    MessageFeedbackSessionNotifier, MessageFeedbackView, String>(
  MessageFeedbackSessionNotifier.new,
);

/// Subscribes to one session's controller view and forwards the settled
/// mutation verbs (CAS, serialized inside the controller).
class MessageFeedbackSessionNotifier
    extends FamilyNotifier<MessageFeedbackView, String> {
  MessageFeedbackController? _controller;
  void Function()? _unsubscribe;

  /// The session's controller; usable once the provider has built.
  MessageFeedbackController get controller => _controller!;

  @override
  MessageFeedbackView build(String sessionId) {
    final controllers = ref.watch(messageFeedbackControllersProvider);
    final controller = controllers.forSession(sessionId);
    _controller = controller;
    _unsubscribe = controller.subscribe(() {
      state = controller.view;
    });
    ref.onDispose(() {
      _unsubscribe?.call();
      _unsubscribe = null;
    });
    return controller.view;
  }

  /// Loads once; a failed load stays retryable.
  Future<FeedbackActionResult> ensure() => controller.ensure();

  /// Re-reads the authoritative list.
  Future<FeedbackActionResult> refresh() => controller.refresh();

  /// Creates or replaces one message's feedback against the observed version.
  Future<FeedbackActionResult> rate(
    String messageId,
    FeedbackRatingValue rating, [
    String? note,
  ]) =>
      controller.rate(messageId, rating, note: note);

  /// Applies [rating], retracting instead when the committed rating already
  /// matches.
  Future<FeedbackActionResult> toggle(
    String messageId,
    FeedbackRatingValue rating,
  ) =>
      controller.toggle(messageId, rating);

  /// Drops the note while keeping the rating.
  Future<FeedbackActionResult> clearNote(String messageId) =>
      controller.clearNote(messageId);

  /// Removes feedback for one message.
  Future<FeedbackActionResult> clear(String messageId) =>
      controller.clear(messageId);
}
