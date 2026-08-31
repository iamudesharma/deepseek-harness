/// The `ui-settings-plugin-inventory` plugin — Flutter port of
/// `packages/client/ui-settings-plugin-inventory/src/client/index.ts`.
///
/// React contributes the lazy read-only inventory tab into
/// `settings.plugins.tab`; the Dart settings shell declares no section/tab
/// holes yet, so the tab registration is deferred with those declarations.
/// This activation publishes the inventory list service
/// (`settings.pluginInventory`) and the `settings.pluginInventory`
/// dictionaries.
library;

import '../../../../core/connection/connection_client.dart';
import '../../../../core/plugin/plugin_contract.dart';
import '../../../../core/services/runtime_services.dart';
import 'plugin_inventory_service.dart';

/// Plugin identity.
const String kPluginInventoryPluginId = 'ui-settings-plugin-inventory';

/// Locale namespace owned by this plugin.
const String kInventoryNamespace = 'settings.pluginInventory';

/// The `ui-settings-plugin-inventory` plugin.
class PluginInventoryPlugin extends DshPlugin {
  /// Creates the plugin.
  const PluginInventoryPlugin();

  @override
  String get id => kPluginInventoryPluginId;

  @override
  List<String> get inject => ['connection', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    ctx.provide(kPluginInventoryServiceName, PluginInventoryService(client));

    ctx.onDispose(
      locale.register(kInventoryNamespace, {
        'zh': kInventoryZh,
        'en': kInventoryEn,
      }),
    );
  }
}

const Map<String, String> kInventoryZh = {
  // Flutter-surface addition: the Dart settings shell's fourth tab label
  // (React nests inventory under the plugins nav without its own label).
  'nav': '清单',
  'tab': '全部插件',
};

const Map<String, String> kInventoryEn = {
  'nav': 'Inventory',
  'tab': 'All plugins',
};
