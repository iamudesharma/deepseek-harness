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
  'nav': '清单',
  'tab': '全部插件',
  'loading': '正在读取插件…',
  'error': '暂时无法读取插件。',
  'retry': '重试',
  'search': '搜索插件',
  'catalog': '插件列表',
  'empty': '暂无插件。',
  'emptySearch': '没有匹配的插件。',
  'enabledTag': '已启用',
  'disabledTag': '已停用',
  'configuration': '配置状态',
  'cordis': 'Cordis 状态',
  'unobserved': '未挂载',
  'pending': '等待依赖',
  'loadingPhase': '加载中',
  'active': '已挂载',
  'failed': '挂载失败',
  'unloading': '卸载中',
};

const Map<String, String> kInventoryEn = {
  'nav': 'Inventory',
  'tab': 'All plugins',
  'loading': 'Reading plugins…',
  'error': 'Plugins are temporarily unavailable.',
  'retry': 'Retry',
  'search': 'Search plugins',
  'catalog': 'Plugin list',
  'empty': 'No plugins are available.',
  'emptySearch': 'No matching plugins.',
  'enabledTag': 'Enabled',
  'disabledTag': 'Disabled',
  'configuration': 'Configuration',
  'cordis': 'Cordis status',
  'unobserved': 'Not mounted',
  'pending': 'Waiting for dependencies',
  'loadingPhase': 'Loading',
  'active': 'Mounted',
  'failed': 'Mount failed',
  'unloading': 'Unloading',
};
