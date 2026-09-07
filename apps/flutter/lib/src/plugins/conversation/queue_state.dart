import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-session transient inbox snapshot from the authoritative
/// `session/queue` frames (whole-snapshot semantics: latest write wins).
class QueueController
    extends StateNotifier<Map<String, List<QueuedInboxItem>>> {
  QueueController() : super(const {});

  /// Replaces [sessionId]'s pending set with the frame's authoritative list.
  void replace(String sessionId, List<QueuedInboxItem> items) {
    state = {...state, sessionId: List.unmodifiable(items)};
  }

  /// Drops a session's entry entirely (session removed).
  void clear(String sessionId) {
    final next = {...state}..remove(sessionId);
    state = next;
  }
}

/// Pending inbox per session id.
final queueProvider =
    StateNotifierProvider<QueueController, Map<String, List<QueuedInboxItem>>>(
      (ref) => QueueController(),
    );
