import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-session background-jobs snapshot from the authoritative
/// `session/jobs` frames (whole-snapshot semantics; empty list still sent
/// when the set empties). Unlocks the WS-Tasks jobs surface.
class JobsController
    extends StateNotifier<Map<String, List<Map<String, Object?>>>> {
  JobsController() : super(const {});

  /// Replaces [sessionId]'s job set with the frame's authoritative list.
  void replace(String sessionId, List<Map<String, Object?>> jobs) {
    state = {...state, sessionId: List.unmodifiable(jobs)};
  }

  void clear(String sessionId) {
    final next = {...state}..remove(sessionId);
    state = next;
  }
}

/// Background jobs per session id (raw JobView maps until WS-Tasks types them).
final jobsProvider =
    StateNotifierProvider<
      JobsController,
      Map<String, List<Map<String, Object?>>>
    >((ref) => JobsController());
