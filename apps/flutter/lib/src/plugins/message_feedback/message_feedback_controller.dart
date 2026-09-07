/// Per-session feedback object layer — compact Dart port of
/// `ui-message-feedback/src/client/controller.ts`. One controller backs every
/// per-message control in a session, so a single list read seeds them all.
///
/// The Host owns per-item compare-and-set: every mutation carries the version
/// this controller last observed, and a `version-conflict` reply carries the
/// authoritative item, so a lost race reconciles from the reply itself instead
/// of refetching the whole session. Mutations serialize behind one tail future
/// so queued operations always compare against the committed version, and a
/// click that lands before the first list read still toggles stored state.
library;

import 'dart:async';

/// Rating judgment carried on the wire (`MessageFeedbackRating`).
enum FeedbackRatingValue { positive, negative }

/// One durable feedback row (`MessageFeedbackItem`); [version] drives CAS.
class MessageFeedbackItem {
  const MessageFeedbackItem({
    required this.messageId,
    required this.rating,
    required this.version,
    this.note,
  });

  final String messageId;
  final FeedbackRatingValue rating;
  final String? note;
  final int version;
}

/// Load state of the one list read that seeds every per-message control.
enum MessageFeedbackStatus { cold, loading, ready, error }

/// Immutable view published to every per-message control in one session.
class MessageFeedbackView {
  const MessageFeedbackView._({
    required this.status,
    required this.items,
    this.error,
  });

  final MessageFeedbackStatus status;

  /// Current item per message, keyed by the addressed message id.
  final Map<String, MessageFeedbackItem> items;

  /// Reason the last load failed, cleared by the next successful load.
  final String? error;
}

/// Settled action shape rendered by the message-level controls.
class FeedbackActionResult {
  const FeedbackActionResult.ok() : ok = true, code = null, message = null;
  const FeedbackActionResult.error(this.code, this.message) : ok = false;

  final bool ok;
  final String? code;
  final String? message;
}

/// One remote reply branch: carried value or failure (business code plus the
/// authoritative current item on `version-conflict`).
sealed class FeedbackReply<T> {
  const FeedbackReply();
}

class ReplyOk<T> extends FeedbackReply<T> {
  const ReplyOk(this.value);
  final T value;
}

class ReplyError<T> extends FeedbackReply<T> {
  const ReplyError(this.code, {this.current, this.message});
  final String code;

  /// Authoritative row on a `version-conflict` business failure.
  final MessageFeedbackItem? current;
  final String? message;
}

/// The three Remote calls this controller needs. Carrier failures surface as
/// [ReplyError] rather than thrown exceptions, mirroring `RemoteResult`.
abstract interface class MessageFeedbackRemote {
  Future<FeedbackReply<List<MessageFeedbackItem>>> list({
    required String sessionId,
  });
  Future<FeedbackReply<MessageFeedbackItem?>> put({
    required String sessionId,
    required String messageId,
    required FeedbackRatingValue rating,
    String? note,
    required int? ifVersion,
  });
  Future<FeedbackReply<MessageFeedbackItem?>> delete({
    required String sessionId,
    required String messageId,
    required int ifVersion,
  });
}

/// Human-readable text for one business failure code.
String describeFeedbackFailure(String code) => switch (code) {
  'session-not-found' => 'this session is no longer persisted',
  'target-not-found' => 'this message is not a persisted assistant message',
  'version-conflict' => 'feedback changed elsewhere',
  'note-blank' => 'a note must contain a non-whitespace character',
  'note-too-large' => 'the note is too long',
  _ => code,
};

const _ok = FeedbackActionResult.ok();

/// Per-session feedback object layer over the durable sidecar.
class MessageFeedbackController {
  /// Creates the controller for one session's sidecar.
  MessageFeedbackController(this._remote, this.sessionId)
    : view = const MessageFeedbackView._(
        status: MessageFeedbackStatus.cold,
        items: {},
      );

  final MessageFeedbackRemote _remote;
  final String sessionId;

  /// Current immutable view; replaced wholesale by every publish.
  MessageFeedbackView view;

  final List<void Function()> _listeners = [];
  Future<FeedbackActionResult>? _loadPromise;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  /// Subscribes to view replacement; returns the unsubscriber.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Loads once; a failed load stays retryable. Concurrent callers share the
  /// in-flight read.
  Future<FeedbackActionResult> ensure() async {
    if (_disposed) return _disposedResult;
    if (view.status == MessageFeedbackStatus.ready) return _ok;
    return refresh();
  }

  Future<FeedbackActionResult> refresh() {
    if (_disposed) return Future.value(_disposedResult);
    final pending = _loadPromise;
    if (pending != null) return pending;
    _publish(
      MessageFeedbackView._(
        status: MessageFeedbackStatus.loading,
        items: view.items,
      ),
    );
    final load = _load();
    _loadPromise = load;
    return load.whenComplete(() => _loadPromise = null);
  }

  /// Creates or replaces one message's feedback against the observed version.
  /// An omitted [note] keeps whatever is stored; only [clearNote] removes one.
  Future<FeedbackActionResult> rate(
    String messageId,
    FeedbackRatingValue rating, {
    String? note,
  }) {
    return _mutate(() async {
      final observed = view.items[messageId];
      return _putCommitted(messageId, rating, note ?? observed?.note, observed);
    });
  }

  /// Applies [rating], retracting instead when the committed rating already
  /// matches. The decision reads the committed item inside the serialized
  /// mutation, so a click before the first list read still toggles storage.
  Future<FeedbackActionResult> toggle(
    String messageId,
    FeedbackRatingValue rating,
  ) {
    return _mutate(() async {
      final observed = view.items[messageId];
      if (observed?.rating == rating) {
        return _deleteCommitted(messageId, observed!);
      }
      return _putCommitted(messageId, rating, observed?.note, observed);
    });
  }

  /// Drops the note while keeping the rating. Absent feedback needs no call.
  Future<FeedbackActionResult> clearNote(String messageId) {
    return _mutate(() async {
      final observed = view.items[messageId];
      if (observed == null || observed.note == null) return _ok;
      return _putCommitted(messageId, observed.rating, null, observed);
    });
  }

  /// Removes feedback for one message. No known item is already the goal.
  Future<FeedbackActionResult> clear(String messageId) {
    return _mutate(() async {
      final observed = view.items[messageId];
      if (observed == null) return _ok;
      return _deleteCommitted(messageId, observed);
    });
  }

  /// Drops subscribers and refuses further work when the owner unloads.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }

  Future<FeedbackActionResult> _putCommitted(
    String messageId,
    FeedbackRatingValue rating,
    String? note,
    MessageFeedbackItem? observed,
  ) async {
    final carried = await _remote.put(
      sessionId: sessionId,
      messageId: messageId,
      rating: rating,
      note: note,
      ifVersion: observed?.version,
    );
    switch (carried) {
      case ReplyError<MessageFeedbackItem?>():
        return _carried(messageId, carried);
      case ReplyOk<MessageFeedbackItem?>():
        _commit(messageId, carried.value);
        return _ok;
    }
  }

  Future<FeedbackActionResult> _deleteCommitted(
    String messageId,
    MessageFeedbackItem observed,
  ) async {
    final carried = await _remote.delete(
      sessionId: sessionId,
      messageId: messageId,
      ifVersion: observed.version,
    );
    switch (carried) {
      case ReplyError<MessageFeedbackItem?>():
        // A conflict reply carries the surviving row; commit it either way.
        return _carried(messageId, carried);
      case ReplyOk<MessageFeedbackItem?>():
        _commit(messageId, null);
        return _ok;
    }
  }

  /// Carrier/business failure; a `version-conflict` reply carries the
  /// authoritative row, which the controller commits before reporting.
  FeedbackActionResult _carried(
    String messageId,
    ReplyError<MessageFeedbackItem?> error,
  ) {
    final message = error.message ?? describeFeedbackFailure(error.code);
    if (error.code == 'version-conflict') {
      _commit(messageId, error.current);
    }
    return FeedbackActionResult.error(error.code, message);
  }

  Future<FeedbackActionResult> _load() async {
    final carried = await _remote.list(sessionId: sessionId);
    if (_disposed) return _ok;
    if (carried is ReplyError<List<MessageFeedbackItem>>) {
      _publish(
        MessageFeedbackView._(
          status: MessageFeedbackStatus.error,
          items: view.items,
          error: carried.message ?? describeFeedbackFailure(carried.code),
        ),
      );
      return FeedbackActionResult.error(
        carried.code,
        carried.message ?? describeFeedbackFailure(carried.code),
      );
    }
    final items = <String, MessageFeedbackItem>{
      for (final item in (carried as ReplyOk<List<MessageFeedbackItem>>).value)
        item.messageId: item,
    };
    _publish(
      MessageFeedbackView._(status: MessageFeedbackStatus.ready, items: items),
    );
    return _ok;
  }

  /// Serializes one mutation behind the prior mutation of this session.
  Future<FeedbackActionResult> _mutate(
    Future<FeedbackActionResult> Function() operation,
  ) {
    // The operation starts only once the tail settles, so queued mutations
    // always read the committed state of the ones before them.
    Future<FeedbackActionResult> guarded() async {
      if (_disposed) return _disposedResult;
      final seeded = await ensure();
      if (!seeded.ok) return seeded;
      if (_disposed) return _disposedResult;
      try {
        return await operation();
      } catch (error) {
        return FeedbackActionResult.error('transport', error.toString());
      }
    }

    final result = _tail.then((_) => guarded(), onError: (_) => guarded());
    // `guarded` settles every failure as a result and never rethrows, so the
    // tail cannot reject and needs no rejection handler.
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Replaces one entry, keeping every other entry's identity.
  void _commit(String messageId, MessageFeedbackItem? item) {
    final items = Map.of(view.items);
    if (item == null) {
      items.remove(messageId);
    } else {
      items[messageId] = item;
    }
    _publish(
      MessageFeedbackView._(status: MessageFeedbackStatus.ready, items: items),
    );
  }

  void _publish(MessageFeedbackView next) {
    view = next;
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (_) {
        // A broken subscriber must not take down publish; contain at the
        // observable boundary like controller.ts.
      }
    }
  }

  static const _disposedResult = FeedbackActionResult.error(
    'disposed',
    'feedback controller is disposed',
  );
}
