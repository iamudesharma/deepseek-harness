/// Per-session projection value store (push model) — the Dart face of
/// `packages/client/runtime/src/client/sessions/projection-store.ts`
/// ([runtime.projection-store] in migration/migration-tracker.json).
///
/// The host is the only computation site; this store holds finished whole
/// values per key — `key → {value, seq}` — seeded from a history tail page's
/// `projections` block and updated by `session/projection` push frames, under
/// the single rule **higher seq wins**: a lower-or-equal seq loses, so a
/// replayed frame cannot regress a value and a stale baseline cannot
/// overwrite a newer frame. No client-side domain folding lives here — a
/// domain ships projection support with zero client code; reactive surfaces
/// (summary title, plan chip, permission select) subscribe through their own
/// providers and consult this store as the sequencing authority.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_models.dart';

/// One key's stored row: the latest finished value and the seq it is
/// consistent with.
class ProjectionRow {
  /// Creates a row.
  const ProjectionRow({required this.value, required this.seq});

  /// Whole current value for the key.
  final Object? value;

  /// Unit watermark the value is consistent with.
  final int seq;
}

/// One session's projection values.
class SessionProjectionStore {
  final Map<String, ProjectionRow> _rows = {};

  /// Current row for [key], or null while the key has never carried a value
  /// (capability absent).
  ProjectionRow? rowOf(String key) => _rows[key];

  /// Current whole value for [key], or null while absent.
  Object? valueOf(String key) => _rows[key]?.value;

  /// Offers one finished value for [key] at watermark [seq].
  ///
  /// Accepted iff no row stands yet or [seq] is strictly greater than the
  /// standing row's seq; lower-or-equal loses. Returns whether the value was
  /// taken — callers fold an accepted value into their reactive surfaces and
  /// skip a rejected one entirely.
  bool offer(String key, Object? value, int seq) {
    final row = _rows[key];
    if (row != null && seq <= row.seq) return false;
    _rows[key] = ProjectionRow(value: value, seq: seq);
    return true;
  }

  /// Seeds from a history tail page's projections [block].
  ///
  /// Each key enters at the block's [SessionProjectionsBlock.asOfSeq]; keys a
  /// concurrent push already advanced past that seq keep the pushed value
  /// (a stale baseline cannot overwrite a newer frame). Returns the key set
  /// this client may still publish — exactly the keys whose values were
  /// taken; withheld keys must not reach reactive surfaces.
  Set<String> seed(SessionProjectionsBlock block) {
    final accepted = <String>{};
    for (final entry in block.values.entries) {
      if (offer(entry.key, entry.value, block.asOfSeq)) accepted.add(entry.key);
    }
    return accepted;
  }
}

/// One [SessionProjectionStore] per session id; rows persist for the
/// container lifetime so seq memory survives reconnect resyncs.
final sessionProjectionStores =
    Provider.family<SessionProjectionStore, String>(
  (ref, sessionId) => SessionProjectionStore(),
);
