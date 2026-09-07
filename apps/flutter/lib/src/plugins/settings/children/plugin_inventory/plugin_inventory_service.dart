/// Plugin-inventory service — the `ui-settings-plugin-inventory` face sliced
/// to the Dart runtime: the read-only Host plugin inventory list over the
/// `pluginInventory/list` Typert method (mirrors ctx.remote.pluginInventory.list
/// and its wire contract in packages/host/plugin-inventory).
library;

import '../../../../core/connection/connection_client.dart';

/// Service name the inventory face is published under.
const String kPluginInventoryServiceName = 'settings.pluginInventory';

/// One read-only row of the Host plugin inventory.
class PluginInventoryRow {
  /// Creates one row.
  const PluginInventoryRow({required this.name, this.version, this.enabled});

  /// Parses one snapshot entry (tolerant: display-only rows).
  factory PluginInventoryRow.fromJson(Map<String, dynamic> json) =>
      PluginInventoryRow(
        name: json['name'] as String? ?? '',
        version: json['version'] as String?,
        enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
      );

  /// Plugin manifest name.
  final String name;

  /// Resolved version, when the host reports one.
  final String? version;

  /// Enabled state, when the host reports one.
  final bool? enabled;
}

/// Read-only inventory list face.
class PluginInventoryService {
  /// Creates the service around one client.
  PluginInventoryService(this._client);

  final ConnectionClient _client;

  /// Fetches the Host plugin inventory snapshot.
  Future<List<PluginInventoryRow>> list() async {
    final value = await _client.callMethod('pluginInventory/list', {});
    final items = value['items'] ?? value['plugins'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => PluginInventoryRow.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }
}
