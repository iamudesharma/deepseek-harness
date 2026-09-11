import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a session's queue rows may be edited, removed, or steered.
/// Mirrors React `queueMutable` (`QueueDock.tsx`): root sessions are always
/// mutable; a subagent-owned session is mutable only while its durable
/// address mode is `continuable` (one-shot children are terminal).
/// Unknown modes (loading, error, missing parent) are fail-closed immutable,
/// matching the Host ownership gate, which rejects non-continuable edits.
/// @param origin - session `origin` (`'subagent'` for owned children).
/// @param parentSessionId - owning parent session, if any.
/// @param sessionId - the queue's own session id.
/// @param childModes - durable child modes by session id for the parent
/// (null while unresolved).
bool isQueueMutable({
  required String? origin,
  required String? parentSessionId,
  required String sessionId,
  required Map<String, String>? childModes,
}) {
  if (origin != 'subagent') return true;
  if (parentSessionId == null || parentSessionId.isEmpty) return false;
  if (childModes == null) return false;
  return childModes[sessionId] == 'continuable';
}

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
