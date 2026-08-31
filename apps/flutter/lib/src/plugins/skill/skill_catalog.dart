/// Session-keyed skill catalog — the `'/'` source's data face, Dart port of
/// the fetch/cache half of `ui-skill/src/client/index.ts` `apply()`.
///
/// Catalog fetches are cached per session (single flight per key): the
/// per-keystroke candidate reads re-poll filters over a settled snapshot
/// locally, so one session costs one `skill.list` RPC. A failed fetch must
/// not poison its key — the entry is dropped so the next consumer retries.
/// Invalidation clears exactly one session key (a preset switch drops that
/// key: the catalog is the preset's); [clearAll] drops every key.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';

/// One catalog row (the slice the '/' menu renders).
class SkillEntry {
  /// Creates an entry.
  const SkillEntry({required this.name, this.description, this.modelInvocable});

  /// Decodes one host `skills[]` row; unknown shapes yield null entries that
  /// callers skip.
  static SkillEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final name = map['name'];
    if (name is! String || name.isEmpty) return null;
    final description = map['description'];
    return SkillEntry(
      name: name,
      description: description is String ? description : null,
      modelInvocable: map['modelInvocable'] is bool
          ? map['modelInvocable'] as bool
          : null,
    );
  }

  /// Skill name — the `/name` reference literal's source.
  final String name;

  /// Host description text.
  final String? description;

  /// Whether the model-side catalog lists it; false means user-only.
  final bool? modelInvocable;

  /// Menu secondary line: the user-only marker rides the description (the
  /// React `menu.userOnly` decision).
  String get menuDescription {
    final String base = description ?? '';
    if (modelInvocable == false) {
      const marker = 'user-only';
      return base.isEmpty ? marker : '$marker · $base';
    }
    return base;
  }
}

/// Per-session skill candidates with single-flight caching and lexicon
/// listeners. Provided as the `'skills'` service.
class SkillCatalog {
  /// Creates the catalog over the typed host client.
  SkillCatalog({required ConnectionClient connection}) : _client = connection;

  final ConnectionClient _client;

  final Map<SessionId, Future<List<SkillEntry>>> _fetches = {};
  final Map<SessionId, List<SkillEntry>> _settled = {};
  final Map<SessionId, Set<VoidCallback>> _lexiconListeners = {};

  /// Candidates for [sessionId] whose name starts with [query]. Superseded
  /// keystrokes share the in-flight fetch; each caller filters independently.
  Future<List<SkillEntry>> candidates(
    SessionId sessionId, {
    String query = '',
  }) async {
    final entries = await _catalog(sessionId);
    return entries
        .where((e) => e.name.startsWith(query))
        .toList(growable: false);
  }

  /// The settled snapshot for synchronous lexicon reads; null while the
  /// catalog is in flight or after a failure.
  List<String>? lexicon(SessionId sessionId) =>
      _settled[sessionId]?.map((e) => e.name).toList(growable: false);

  /// Subscribes to settlement/invalidation notifications for one session key.
  VoidCallback subscribeLexicon(SessionId sessionId, VoidCallback listener) {
    _lexiconListeners
        .putIfAbsent(sessionId, () => <VoidCallback>{})
        .add(listener);
    return () {
      final listeners = _lexiconListeners[sessionId];
      if (listeners == null) return;
      listeners.remove(listener);
      if (listeners.isEmpty) _lexiconListeners.remove(sessionId);
    };
  }

  /// The pick lands the literal `/name ` text and the prompt ships the same
  /// literal (plain-text-reference decision; determinism lives host-side in
  /// dsh-tool-skill).
  String pickText(SkillEntry entry) => '/${entry.name} ';

  /// Drops one session's cache and notifies lexicon readers.
  void invalidate(SessionId key) {
    _fetches.remove(key);
    if (_settled.remove(key) != null) _notify(key);
  }

  /// Drops every cached catalog (connection-reset posture).
  void clearAll() {
    for (final key in List.of(_fetches.keys)) {
      invalidate(key);
    }
  }

  Future<List<SkillEntry>> _catalog(SessionId sessionId) {
    final existing = _fetches[sessionId];
    if (existing != null) return existing;
    final future = _fetch(sessionId);
    _fetches[sessionId] = future;
    unawaited(
      future.then(
        (entries) {
          _settled[sessionId] = entries;
          // Settlement notifies even when the key was invalidated mid-flight:
          // late readers see the settled list, invalidation already dropped it.
          if (_settled.containsKey(sessionId)) _notify(sessionId);
        },
        onError: (_) {
          // A failed fetch must not poison the key: the next consumer retries.
          if (identical(_fetches[sessionId], future))
            _fetches.remove(sessionId);
        },
      ),
    );
    return future;
  }

  Future<List<SkillEntry>> _fetch(SessionId sessionId) async {
    final value = await _client.skillList(sessionId: sessionId.value);
    final raw = value['skills'] as List<dynamic>? ?? const [];
    return raw
        .map(SkillEntry.fromJson)
        .whereType<SkillEntry>()
        .toList(growable: false);
  }

  void _notify(SessionId sessionId) {
    for (final listener in List.of(
      _lexiconListeners[sessionId] ?? const <VoidCallback>{},
    )) {
      listener();
    }
  }
}
