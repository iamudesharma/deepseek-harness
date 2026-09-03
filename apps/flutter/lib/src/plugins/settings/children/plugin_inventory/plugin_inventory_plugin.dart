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
  'tab': '插件列表',
  'loading': '正在读取插件…',
  'error': '暂时无法读取插件。',
  'retry': '重试',
  'search': '搜索插件',
  'catalog': '插件列表',
  'empty': '暂无插件。',
  'emptySearch': '没有匹配的插件。',
  'presetTitle': '会话插件',
  'presetSubtitle': '由 Agent 预设按会话组成',
  'countUnit': '个',
  'switcherLabel': '选择要查看的 Agent 预设',
  'presetOptionDefault': '{name}（默认）',
  'presetOptionBroken': '{name}（加载失败）',
  'globalTitle': '全局插件',
  'globalSubtitle': '系统与所有会话共用',
  'presetProvidedDetail': '全局已停用，由 Agent 预设按会话提供',
  'enabledIn': '启用于',
  'viewInPreset': '去预设分组查看',
  'matchesInOtherPresets': '其他预设中还有 {count} 个匹配：',
  'failedCountLabel': '个失败',
  'enabledTag': '已启用',
  'disabledTag': '已停用',
  'conditionalTag': '条件启用',
  'presetEnabledTag': '预设中启用',
  'failedTag': '启动失败',
  'moduleLabel': '完整名称',
  'fromPreset': '来自',
  'condition': '禁用条件',
  'configuration': '配置状态',
  'runtime': '运行状态',
  'cordis': 'Cordis 状态',
  'unobserved': '未运行',
  'pending': '等待依赖',
  'loadingPhase': '加载中',
  'active': '运行中',
  'failed': '启动失败',
  'unloading': '卸载中',
};

const Map<String, String> kInventoryEn = {
  'nav': 'Inventory',
  'tab': 'Plugin list',
  'loading': 'Reading plugins…',
  'error': 'Plugins are temporarily unavailable.',
  'retry': 'Retry',
  'search': 'Search plugins',
  'catalog': 'Plugin list',
  'empty': 'No plugins are available.',
  'emptySearch': 'No matching plugins.',
  'presetTitle': 'Session plugins',
  'presetSubtitle': 'Composed per session by agent presets',
  'countUnit': 'plugins',
  'switcherLabel': 'Choose the agent preset to inspect',
  'presetOptionDefault': '{name} (default)',
  'presetOptionBroken': '{name} (failed to load)',
  'globalTitle': 'Global plugins',
  'globalSubtitle': 'Shared by the system and every session',
  'presetProvidedDetail': 'Disabled globally; agent presets provide it per session',
  'enabledIn': 'Enabled in',
  'viewInPreset': 'View in the preset group',
  'matchesInOtherPresets': '{count} more matches in other presets: ',
  'failedCountLabel': 'failed',
  'enabledTag': 'Enabled',
  'disabledTag': 'Disabled',
  'conditionalTag': 'Conditional',
  'presetEnabledTag': 'Enabled via presets',
  'failedTag': 'Failed',
  'moduleLabel': 'Module',
  'fromPreset': 'From',
  'condition': 'Disabled when',
  'configuration': 'Configuration',
  'runtime': 'Status',
  'cordis': 'Cordis status',
  'unobserved': 'Not running',
  'pending': 'Waiting for dependencies',
  'loadingPhase': 'Loading',
  'active': 'Mounted',
  'failed': 'Mount failed',
  'unloading': 'Unloading',
};
