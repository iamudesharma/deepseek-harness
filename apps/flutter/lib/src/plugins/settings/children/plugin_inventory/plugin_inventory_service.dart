/// Plugin-inventory service — the `ui-settings-plugin-inventory` face sliced
/// to the Dart runtime: the read-only Host plugin inventory list over the
/// `pluginInventory/list` Typert method (mirrors ctx.remote.pluginInventory.list
/// and its wire contract in packages/host/plugin-inventory).
library;

import '../../../../core/connection/connection_client.dart';

/// Service name the inventory face is published under.
const String kPluginInventoryServiceName = 'settings.pluginInventory';

/// One read-only row of the Host plugin inventory.
///
/// Mirrors `PluginInventoryEntry` in `packages/host/plugin-inventory/src/types.ts`:
/// the Loader order entry id, manifest module name, enabled state, and runtime
/// fiber phase. There is no version field on the wire.
class PluginInventoryRow {
  /// Creates one row.
  const PluginInventoryRow({
    required this.entryId,
    required this.moduleName,
    required this.enabled,
    this.fiberPhase,
  });

  /// Parses one snapshot entry (tolerant: display-only rows).
  factory PluginInventoryRow.fromJson(Map<String, dynamic> json) =>
      PluginInventoryRow(
        entryId: json['entryId'] as String? ?? '',
        moduleName: json['moduleName'] as String? ?? '',
        enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
        fiberPhase: json['fiberPhase'] as String?,
      );

  /// Loader entry id.
  final String entryId;

  /// Plugin manifest module name.
  final String moduleName;

  /// Enabled state.
  final bool enabled;

  /// Runtime fiber phase, when the host reports one.
  final String? fiberPhase;
}

/// Read-only inventory list face.
class PluginInventoryService {
  /// Creates the service around one client.
  PluginInventoryService(this._client);

  final ConnectionClient _client;

  /// Fetches the Host plugin inventory snapshot.
  Future<List<PluginInventoryRow>> list() async {
    final value = await _client.callMethod('pluginInventory/list', {});
    final entries = value['entries'];
    if (entries is List) {
      return entries
          .whereType<Map>()
          .map((e) => PluginInventoryRow.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }
}
