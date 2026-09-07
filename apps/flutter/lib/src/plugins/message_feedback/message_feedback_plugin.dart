/// Message Feedback Plugin — Flutter port of the `ui-message-feedback`
/// package boundary (`packages/client/ui-message-feedback/src/client/index.ts`):
/// one controller per session backing every per-message control.
///
/// React injects `remote.messageFeedback` (the generated Remote namespace) and
/// registers into `conversation.chat.assistant-actions`; the live Host wire
/// rides [ConnectionClientMessageFeedbackRemote] and the assistant-actions
/// hole is still undeclared, so the ledger entry lands with that seam. The
/// plugin provides service `'messageFeedback'`: the per-session
/// [MessageFeedbackController] resolver, plus the reconnect resync posture
/// over the `'remote'` bus when present.
library;

import '../../core/api/rpc_envelope.dart';
import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import 'locales.dart';
import 'message_feedback_controller.dart';

/// Currently bound per-session controller resolver (null before first
/// activation); the UI bridge reads this instead of reaching into the plugin
/// host, mirroring the conversation hub's activated-hub seat.
MessageFeedbackControllers? _activatedMessageFeedback;

/// Currently bound resolver, or null when the plugin has not activated.
MessageFeedbackControllers? get activatedMessageFeedback =>
    _activatedMessageFeedback;

/// Binds (or clears) the activated resolver.
void bindActivatedMessageFeedback(MessageFeedbackControllers? controllers) {
  _activatedMessageFeedback = controllers;
}

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
    // Product copy rides the locale registry when it is present; the plugin
    // stays activatable without it (activation order is unchanged — no new
    // inject edge).
    final LocaleService? locale = ctx.get<LocaleService>('locale');
    final void Function()? unregisterLocale = locale?.register(
      kMessageFeedbackNamespace,
      {'zh': kMessageFeedbackZh, 'en': kMessageFeedbackEn},
    );
    if (unregisterLocale != null) ctx.onDispose(unregisterLocale);
    // Prefer an explicitly bound face (tests), then the live Host wire,
    // otherwise stay renderable via _AbsentRemote.
    final explicit = ctx.get<MessageFeedbackRemote>('remote.messageFeedback');
    final client = ctx.get<ConnectionClient>('connection');
    final MessageFeedbackRemote remote = explicit ??
        (client != null
            ? ConnectionClientMessageFeedbackRemote(client)
            : _AbsentRemote());

    final controllers = MessageFeedbackControllers(remote);
    ctx.provide('messageFeedback', controllers);
    // Bridge for the feedback UI — widgets resolve per-session controllers
    // through the Riverpod seat over this binding.
    bindActivatedMessageFeedback(controllers);
    ctx.onDispose(() {
      controllers.disposeAll();
      if (identical(_activatedMessageFeedback, controllers)) {
        bindActivatedMessageFeedback(null);
      }
    });
  }
}

/// Live Host remote over [ConnectionClient.callMethod] — slash wires
/// `messageFeedback/list|put|delete` with `{sessionId, messageId, rating,
/// note?, ifVersion}` matching `packages/feedback/message-feedback/src/types.ts`.
/// Business failures map to [ReplyError] with the Host code string;
/// `version-conflict` carries the authoritative row from `details.current`.
class ConnectionClientMessageFeedbackRemote implements MessageFeedbackRemote {
  ConnectionClientMessageFeedbackRemote(this._client);

  final ConnectionClient _client;

  static String _ratingWire(FeedbackRatingValue rating) =>
      rating == FeedbackRatingValue.positive ? 'positive' : 'negative';

  static FeedbackRatingValue _ratingFromWire(String wire) =>
      wire == 'negative' ? FeedbackRatingValue.negative : FeedbackRatingValue.positive;

  static MessageFeedbackItem _itemFromJson(Map<String, dynamic> json) {
    final versionRaw = json['version'];
    final int version = versionRaw is int
        ? versionRaw
        : (versionRaw as num).toInt();
    return MessageFeedbackItem(
      messageId: json['messageId'] as String,
      rating: _ratingFromWire(json['rating'] as String),
      note: json['note'] as String?,
      version: version,
    );
  }

  static MessageFeedbackItem? _currentFromDetails(Map<String, Object?> details) {
    final current = details['current'];
    if (current == null) return null;
    if (current is Map) {
      return _itemFromJson(Map<String, dynamic>.from(current));
    }
    return null;
  }

  @override
  Future<FeedbackReply<List<MessageFeedbackItem>>> list({
    required String sessionId,
  }) async {
    try {
      final value = await _client.callMethod('messageFeedback/list', {
        'sessionId': sessionId,
      });
      final raw = value['items'] as List<dynamic>? ?? const [];
      final items = raw
          .whereType<Map>()
          .map((e) => _itemFromJson(Map<String, dynamic>.from(e)))
          .toList();
      return ReplyOk<List<MessageFeedbackItem>>(items);
    } on RemoteMethodException catch (e) {
      return ReplyError<List<MessageFeedbackItem>>(
        e.code.wire,
        message: e.message,
        current: null,
      );
    } catch (e) {
      return ReplyError<List<MessageFeedbackItem>>('internal', message: '$e');
    }
  }

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> put({
    required String sessionId,
    required String messageId,
    required FeedbackRatingValue rating,
    String? note,
    required int? ifVersion,
  }) async {
    try {
      final value = await _client.callMethod('messageFeedback/put', {
        'sessionId': sessionId,
        'messageId': messageId,
        'rating': _ratingWire(rating),
        if (note != null) 'note': note,
        'ifVersion': ifVersion,
      });
      return ReplyOk<MessageFeedbackItem?>(_itemFromJson(value));
    } on RemoteMethodException catch (e) {
      return ReplyError<MessageFeedbackItem?>(
        e.code.wire,
        message: e.message,
        current: _currentFromDetails(e.details),
      );
    } catch (e) {
      return ReplyError<MessageFeedbackItem?>('internal', message: '$e');
    }
  }

  @override
  Future<FeedbackReply<MessageFeedbackItem?>> delete({
    required String sessionId,
    required String messageId,
    required int ifVersion,
  }) async {
    try {
      await _client.callMethod('messageFeedback/delete', {
        'sessionId': sessionId,
        'messageId': messageId,
        'ifVersion': ifVersion,
      });
      return const ReplyOk<MessageFeedbackItem?>(null);
    } on RemoteMethodException catch (e) {
      return ReplyError<MessageFeedbackItem?>(
        e.code.wire,
        message: e.message,
        current: _currentFromDetails(e.details),
      );
    } catch (e) {
      return ReplyError<MessageFeedbackItem?>('internal', message: '$e');
    }
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
