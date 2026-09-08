import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One preset option in the permissions projection — mirrors
/// `PresetOption {value, name, description}` in
/// `packages/interaction/permission-presets/src/types.ts`.
class PresetOption {
  final String value;
  final String name;
  final String? description;
  const PresetOption({
    required this.value,
    required this.name,
    this.description,
  });

  factory PresetOption.fromJson(Map<String, dynamic> json) => PresetOption(
    value: json['value'] as String? ?? '',
    name: json['name'] as String? ?? json['value'] as String? ?? '',
    description: json['description'] as String?,
  );
}

/// Session's permission selection — mirrors `PermissionSelect`
/// `{options, currentValue}`. Null means capability not composed
/// (projection key absent) — control hidden.
class PermissionSelect {
  final List<PresetOption> options;
  final String currentValue;
  const PermissionSelect({required this.options, required this.currentValue});

  factory PermissionSelect.fromJson(Map<String, dynamic> json) =>
      PermissionSelect(
        options: (json['options'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((e) => PresetOption.fromJson(e.cast<String, dynamic>()))
            .toList(),
        currentValue: json['currentValue'] as String? ?? '',
      );

  bool get isCustom => currentValue == 'custom';
}

/// Per-session permission projection — higher-seq-wins like the host's
/// `ProjectionValueStore`. Null means no capability or not yet seeded
/// (blank session before first title etc.).
final permissionSelectProvider =
    StateProvider.family<PermissionSelect?, String>((ref, sessionId) => null);

/// Service-layer read mirror of the live permissions projection.
///
/// Riverpod state is unreachable from the command pipeline (`CommandUiService`
/// decorations resolve service-side), so `live_sync` mirrors every
/// `permissionSelectProvider` write here. Null means absent — exactly the
/// `selectOf(session) === undefined` gate React's `/permission` decoration
/// checks. Entries are tiny projection copies keyed by session id.
class PermissionSnapshotCache {
  /// Creates an empty cache.
  PermissionSnapshotCache();

  final Map<String, PermissionSelect?> _snapshots = {};

  /// Latest snapshot for [sessionId], or null when absent.
  PermissionSelect? read(String sessionId) => _snapshots[sessionId];

  /// Record [select] (null clears back to absent).
  void write(String sessionId, PermissionSelect? select) {
    if (select == null) {
      _snapshots.remove(sessionId);
    } else {
      _snapshots[sessionId] = select;
    }
  }

  /// Drop everything (tests / teardown).
  void clear() => _snapshots.clear();
}

/// Shared mirror fed by `live_sync` beside every provider write.
final PermissionSnapshotCache permissionSnapshotCache =
    PermissionSnapshotCache();
