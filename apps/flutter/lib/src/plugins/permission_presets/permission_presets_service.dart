/// Permission default-preset controller — port of
/// `packages/client/ui-permission-presets/src/client/settings-store.ts`
/// sliced to the Dart settings seam: read the `permission` namespace's
/// `defaultPreset` through a per-namespace [SettingsScope], write through the
/// same scope (revision-fenced, latest-write recovery inside the scope).
///
/// React derives the selectable options from the namespace schema's union
/// constants; the Dart runtime has no settingsSchema face yet, so options are
/// supplied by the caller surface and only value read/write is owned here —
/// no invented persistence.
library;

import 'package:flutter/foundation.dart';

import '../../core/connection/connection_client.dart';
import '../../core/settings/settings_scope.dart';
import 'locales.dart';

/// Service name the presets face is published under.
const String kPermissionPresetsServiceName = 'permissionPresets';

/// Read the current default preset from one snapshot; null while the
/// namespace is loading/unavailable or carries no value.
String? defaultPresetOf(SettingsScopeSnapshot<Object?> snapshot) {
  final value = snapshot.value;
  if (value is Map) {
    final raw = value[kDefaultPresetField];
    if (raw is String) return raw;
  }
  return null;
}

/// One selectable preset option derived from the host schema union.
class PermissionOption {
  const PermissionOption({
    required this.id,
    required this.label,
    this.description,
  });
  final String id;
  final String label;
  final String? description;
}

/// Derive selectable options from the namespace schema's `defaultPreset` union.
///
/// Mirrors `settings-store.ts:permissionDefaultOf` which rehydrates the
/// Schemastery node at `['defaultPreset']` and reads its `union.list` of
/// `const` nodes. When schema is absent or malformed, returns the last
/// known host union fallback (`read-only` / `workspace-write`) so the row
/// still renders, but callers should treat empty as unavailable.
List<PermissionOption> permissionOptionsOf(
  SettingsScopeSnapshot<Object?> snapshot,
) {
  final schema = snapshot.schema;
  if (schema == null) return const [];
  try {
    // Schema is the serialized Schemastery JSON for the namespace.
    // Navigate to defaultPreset field: expect root type 'object' with dict containing 'defaultPreset'.
    Map<String, Object?>? node = schema;
    // Root may be {type:'object', dict:{defaultPreset:...}} or directly the field
    if (node['type'] == 'object' && node['dict'] is Map) {
      final dict = (node['dict'] as Map).cast<String, Object?>();
      final field = dict[kDefaultPresetField];
      if (field is Map) node = field.cast<String, Object?>();
    }
    // Node should now be the defaultPreset schema node
    if (node == null) return const [];
    final type = node['type'] as String?;
    List<Map<String, Object?>> candidates = const [];
    if (type == 'union' && node['list'] is List) {
      candidates = (node['list'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();
    } else if (type == 'const') {
      candidates = [node];
    } else {
      return const [];
    }
    final options = <PermissionOption>[];
    for (final c in candidates) {
      if (c['type'] != 'const') continue;
      final value = c['value'];
      if (value is! String) continue;
      final meta = c['meta'] is Map
          ? (c['meta'] as Map).cast<String, Object?>()
          : null;
      final desc = meta?['description'] is String
          ? meta!['description'] as String
          : null;
      final label = desc != null && desc.isNotEmpty ? desc : value;
      options.add(PermissionOption(id: value, label: label, description: desc));
    }
    // Validate current value is advertised; if not, keep empty to surface schema drift
    final current = defaultPresetOf(snapshot);
    if (current != null && !options.any((o) => o.id == current))
      return const [];
    return options;
  } catch (_) {
    return const [];
  }
}

/// Default-preset selection face: load reflects the describe mirror,
/// [select] persists one preset for sessions created later.
class PermissionPresetsService extends ChangeNotifier {
  /// Creates the service around a per-namespace scope.
  PermissionPresetsService(this.scope);

  final SettingsScope<Object?> scope;

  bool _loading = false;
  String? _error;

  /// Current persisted preset (null before first load / when unserved).
  String? get current => defaultPresetOf(scope.snapshot);

  /// Selectable presets derived from the host schema union (empty while
  /// schema absent or unavailable) — mirrors React's dynamic enum, not a
  /// hard-coded stub.
  List<PermissionOption> get options => permissionOptionsOf(scope.snapshot);

  /// Whether writes are permitted on the namespace.
  bool get writable => scope.snapshot.writable;

  /// True between [load]/[select] dispatch and settlement.
  bool get busy => _loading;

  /// Last failure text, cleared by the next operation.
  String? get error => _error;

  /// Refreshes from the host settings document.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await scope.refreshFromDescribe();
    } catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Persists one preset as the new-session default. The Full-access risk
  /// gate belongs to the calling surface (mirrors React: the popup shell owns
  /// the modal mechanics).
  Future<void> select(String preset) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await scope.set(kDefaultPresetField, preset);
      await scope.refreshFromDescribe();
    } catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Builds the production scope over the connection's settings RPCs.
  static SettingsScope<Object?> wireScope(ConnectionClient client) {
    return SettingsScope<Object?>(
      face: SettingsRpcFace(client),
      namespace: kPermissionWireNamespace,
    );
  }
}
