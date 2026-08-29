/// Settings namespace scopes mirrored from
/// `packages/client/ui-settings/src/client/settings-scope.ts` +
/// `settings-mirror.ts`.
///
/// One shared describe mirror feeds per-namespace [SettingsScope] views;
/// writes are serialized per scope, carry the latest known revision as a
/// fence, fold their settlement back into the snapshot, and recover via a
/// fresh read when another writer (another tab, editor, external edit) moves
/// the revision first (`settings-conflict`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/connection_client.dart';

/// Settings wire face — implemented over the P0 protocol contracts by
/// [SettingsRpcFace]; tests supply fakes.
abstract interface class SettingsFace {
  /// Full document describe: `{ namespaces: { ns: { value, base?, user?,
  /// revision?, writable? } } }` shaped per `settings.describe`.
  Future<Map<String, Object?>> describe();

  /// Applies one mutation batch against [expectedRevision].
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  });
}

/// Production face riding the existing [ConnectionClient] methods.
class SettingsRpcFace implements SettingsFace {
  /// Creates the face around one client.
  SettingsRpcFace(this._client);

  final ConnectionClient _client;

  @override
  Future<Map<String, Object?>> describe() => _client.settingsDescribe();

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) => _client.settingsMutate(
    ns: ns,
    ops: ops,
    expectedRevision: expectedRevision,
  );
}

/// Snapshot status of one namespace scope.
enum SettingsScopeStatus {
  /// Describe has not answered yet.
  loading,

  /// The namespace section is available and derived.
  ready,

  /// Settings RPC is unreachable or refused the namespace.
  unavailable,
}

/// Immutable view of one settings namespace.
@immutable
class SettingsScopeSnapshot<T> {
  /// Creates a snapshot.
  const SettingsScopeSnapshot({
    required this.status,
    required this.value,
    this.base,
    this.user,
    this.revision,
    required this.writable,
    this.schema,
  });

  /// Current lifecycle status.
  final SettingsScopeStatus status;

  /// Decoded namespace value (already narrowed by the owner's decoder).
  final T? value;

  /// Built-in defaults layer (raw).
  final Map<String, Object?>? base;

  /// User overrides layer (raw).
  final Map<String, Object?>? user;

  /// Namespace revision used as the next write's fence.
  final int? revision;

  /// Whether writes are permitted (read-only providers report false).
  final bool writable;

  /// Serialized Schemastery node for this namespace (host `schema` field),
  /// used to derive selectable union constants (e.g. permission `defaultPreset`).
  final Map<String, Object?>? schema;

  @override
  bool operator ==(Object other) =>
      other is SettingsScopeSnapshot<T> &&
      other.status == status &&
      other.revision == revision &&
      other.writable == writable &&
      other.schema == schema;

  @override
  int get hashCode => Object.hash(status, revision, writable, schema);
}

/// Per-namespace controller: derive-from-describe reads plus serialized,
/// revision-fenced set/unset writes with latest-write recovery.
class SettingsScope<T> {
  /// Creates a scope for one namespace.
  SettingsScope({
    required SettingsFace face,
    required String namespace,
    T? Function(Map<String, Object?> raw)? decode,
  }) : _face = face,
       _namespace = namespace,
       _decode = decode {
    _snapshot = SettingsScopeSnapshot<T>(
      status: SettingsScopeStatus.loading,
      value: null,
      writable: false,
    );
  }

  final SettingsFace _face;
  final String _namespace;
  final T? Function(Map<String, Object?> raw)? _decode;

  SettingsScopeSnapshot<T> _snapshot = const SettingsScopeSnapshot(
    status: SettingsScopeStatus.loading,
    value: null,
    writable: false,
  );
  final List<void Function(SettingsScopeSnapshot<T>)> _listeners = [];
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  int? _pendingRevision;
  bool _disposed = false;

  SettingsScopeSnapshot<T> get snapshot => _snapshot;

  /// Observes snapshot replacements; returns an unsubscriber.
  VoidCallback subscribe(void Function(SettingsScopeSnapshot<T>) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _publish(SettingsScopeSnapshot<T> next) {
    _snapshot = next;
    for (final listener in List.of(_listeners)) {
      listener(next);
    }
  }

  /// Refreshes from the shared describe answer (the whole-document map).
  Future<void> refreshFromDescribe() {
    return _enqueue(_refreshNow);
  }

  Future<void> _refreshNow() async {
    try {
      final doc = await _face.describe();
      final sections = (doc['namespaces'] as Map?) ?? doc;
      final section = sections[_namespace];
      if (section is! Map) {
        _publish(
          SettingsScopeSnapshot<T>(
            status: SettingsScopeStatus.unavailable,
            value: null,
            writable: false,
          ),
        );
        return;
      }
      _publish(_derive(section.cast<String, Object?>()));
    } catch (_) {
      if (!_disposed) {
        _publish(
          SettingsScopeSnapshot<T>(
            status: SettingsScopeStatus.unavailable,
            value: null,
            writable: false,
          ),
        );
      }
    }
  }

  SettingsScopeSnapshot<T> _derive(Map<String, Object?> section) {
    final rawValue = (section['value'] ?? section['user']) ?? section['base'];
    final decoded = _decode != null && rawValue is Map
        ? _decode!(rawValue.cast<String, Object?>())
        : rawValue as T?;
    final schemaRaw = section['schema'];
    final schemaMap = schemaRaw is Map
        ? schemaRaw.cast<String, Object?>()
        : null;
    return SettingsScopeSnapshot<T>(
      status: SettingsScopeStatus.ready,
      value: decoded,
      base: section['base'] is Map
          ? (section['base'] as Map).cast<String, Object?>()
          : null,
      user: section['user'] is Map
          ? (section['user'] as Map).cast<String, Object?>()
          : null,
      revision: section['revision'] is int ? section['revision'] as int : null,
      writable: section['writable'] == true,
      schema: schemaMap,
    );
  }

  /// Sets one scalar field inside the namespace.
  Future<void> set(String field, Object? value) => _write([
    {
      'op': 'set',
      'path': [field],
      'value': value,
    },
  ]);

  /// Clears one field back toward its base/default.
  Future<void> unset(String field) => _write([
    {
      'op': 'unset',
      'path': [field],
    },
  ]);

  Future<void> _write(List<Map<String, Object?>> ops) {
    return _enqueue(() async {
      final generation = ++_generation;
      final revision = _pendingRevision ?? _snapshot.revision;
      try {
        final result = await _face.mutate(
          ns: _namespace,
          ops: ops,
          expectedRevision: revision,
        );
        // A newer queued write supersedes this answer's mirror fold.
        if (generation != _generation || _disposed) return;
        final section = (result['namespace'] ?? result[_namespace]) as Map?;
        if (section != null) {
          _pendingRevision = section['revision'] is int
              ? section['revision'] as int
              : _pendingRevision;
          _publish(_derive(section.cast<String, Object?>()));
        } else {
          await refreshFromDescribe();
        }
      } catch (_) {
        // Latest-write recovery: re-describe so the next write fences fresh.
        // Inline (not via refreshFromDescribe): we are already inside the
        // serialized tail, and re-entering the queue would deadlock on self.
        if (!_disposed) await _refreshNow();
      }
    });
  }

  /// Serializes every operation on this scope; each runs only after the
  /// previous settled (ordering contract of SettingsScope.set/unset).
  Future<void> _enqueue(Future<void> Function() operation) {
    final run = _tail.then((_) => operation());
    _tail = run.catchError((Object _) {});
    return run;
  }
}
