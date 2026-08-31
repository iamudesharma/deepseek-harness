/// Message Feedback Plugin — Flutter port of the `ui-message-feedback`
/// package boundary (`packages/client/ui-message-feedback/src/client/index.ts`):
/// one controller per session backing every per-message control.
///
/// React injects `remote.messageFeedback` (the generated Remote namespace) and
/// registers into `conversation.chat.assistant-actions`; no Dart service
/// carries that namespace and the assistant-actions hole is undeclared, so the
/// ledger entry lands with those seams. The plugin provides service
/// `'messageFeedback'`: the per-session [MessageFeedbackController] resolver,
/// plus the reconnect resync posture over the `'remote'` bus when present.
library;

import '../../core/plugin/plugin_contract.dart';
import 'message_feedback_controller.dart';

/// Per-session controller resolver — the Dart slice of the React closure over
/// `controllers: Map<SessionId, MessageFeedbackController>`.
class MessageFeedbackControllers {
  final MessageFeedbackRemote _remote;
  final Map<String, MessageFeedbackController> _bySession = {};

  /// Creates the resolver over one Remote face.
  MessageFeedbackControllers(this._remote);

  /// The session's controller, created on first use; disposal rides plugin
  /// deactivation.
  MessageFeedbackController forSession(String sessionId) =>
      _bySession.putIfAbsent(
        sessionId,
        () => MessageFeedbackController(_remote, sessionId),
      );

  /// Disposes every live controller (plugin deactivation).
  void disposeAll() {
    for (final controller in _bySession.values) {
      controller.dispose();
    }
    _bySession.clear();
  }
}

/// The `ui-message-feedback` plugin.
class MessageFeedbackPlugin extends DshPlugin {
  @override
  String get id => 'ui-message-feedback';

  @override
  List<String> get inject => ['slots'];

  @override
  Future<void> apply(DshContext ctx) async {
    ctx.require<Object>('slots'); // pin declared edge
    final remote = ctx.get<MessageFeedbackRemote>('remote.messageFeedback');

    final controllers = MessageFeedbackControllers(remote ?? _AbsentRemote());
    ctx.provide('messageFeedback', controllers);
    ctx.onDispose(controllers.disposeAll);
  }
}

/// Stands in until the generated `remote.messageFeedback` namespace exists;
/// every call reports a carrier failure instead of throwing, so UI stays
/// renderable and mutations settle visibly rather than vanishing.
class _AbsentRemote implements MessageFeedbackRemote {
  ReplyError<T> _err<T>() => ReplyError<T>(
    'unavailable',
    message: 'message feedback remote is not wired yet',
  );

  @override
  Future<FeedbackReply<List<MessageFeedbackItem>>> list({
    required String sessionId,
  }) async => _err();

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> put({
    required String sessionId,
    required String messageId,
    required FeedbackRatingValue rating,
    String? note,
    required int? ifVersion,
  }) async => _err();

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> delete({
    required String sessionId,
    required String messageId,
    required int ifVersion,
  }) async => _err();
}
