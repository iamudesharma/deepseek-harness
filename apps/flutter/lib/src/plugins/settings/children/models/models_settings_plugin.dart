/// The `ui-settings-models` plugin — Flutter port of
/// `packages/client/ui-settings-models/src/client/index.ts`, sliced to the
/// Dart runtime.
///
/// React registers the Models settings section (into `settings.section`),
/// the internal-testing and official-DeepSeek onboarding dialogs, and keeps
/// its store fresh on pushed invalidations. The Dart settings shell declares
/// no section holes yet and there is no `settingsSchema` face, so the
/// section registration is deferred with those declarations; this activation
/// publishes the onboarding scope service (`settings.models`) and the
/// `settings.models` dictionaries. The provider-editor store stays with the
/// existing screen until re-homed at integration.
library;

import '../../../../core/connection/connection_client.dart';
import '../../../../core/plugin/plugin_contract.dart';
import '../../../../core/services/runtime_services.dart';
import 'models_settings_service.dart';

/// Plugin identity.
const String kModelsSettingsPluginId = 'ui-settings-models';

/// Locale namespace owned by this plugin.
const String kModelsNamespace = 'settings.models';

/// The `ui-settings-models` plugin.
class ModelsSettingsPlugin extends DshPlugin {
  /// Creates the plugin.
  const ModelsSettingsPlugin();

  @override
  String get id => kModelsSettingsPluginId;

  @override
  List<String> get inject => ['connection', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    final service = ModelsSettingsService(client);
    ctx.provide(kModelsSettingsServiceName, service);
    ctx.onDispose(service.dispose);

    ctx.onDispose(
      locale.register(kModelsNamespace, {'zh': kModelsZh, 'en': kModelsEn}),
    );
  }
}

/// Keys below mirror `packages/client/ui-settings-models/src/client/locales.ts`
/// for the subset the Dart Models settings surface renders.
const Map<String, String> kModelsZh = {
  'nav': '模型',
  'title': '模型',
  'description': '配置可用的模型提供方。',
  'intro': '填入各提供方的 API 密钥即可使用其模型。',
  'edit': '编辑',
  'remove': '删除',
  'deleteTitle': '删除 {provider}？',
  'deleteDescription': '删除 {provider} 会移除其配置；其使用的凭证（如有）由其他位置管理，将会保留。',
  'deleteDescriptionWithCredential': '删除 {provider} 会移除其配置和存储的 API 密钥。',
  'deleteConfirm': '删除 {provider}',
  'deleting': '正在删除 {provider}…',
  'add': '添加提供方',
  'provider': '提供方',
  'close': '关闭',
  'cancel': '取消',
  'savedProvider': '已保存 {provider}。',
  'credentialConfigured': 'API 密钥已配置',
  'credentialMissing': 'API 密钥缺失',
  'readOnly': '当前部署的设置文档为只读。',
  'loadFailed': '加载提供方目录失败',
  'retry': '重试',
  'customAdd': '添加自定义提供方',
  'customTag': '自定义',
};

const Map<String, String> kModelsEn = {
  'nav': 'Models',
  'title': 'Models',
  'description': 'Configure available model providers.',
  'intro': 'Enter your API keys to use models from the following providers.',
  'edit': 'Edit',
  'remove': 'Delete',
  'deleteTitle': 'Delete {provider}?',
  'deleteDescription': 'Deleting {provider} removes its configuration. Any credential it uses is managed elsewhere and will be kept.',
  'deleteDescriptionWithCredential':
      'Deleting {provider} removes its configuration and stored API key.',
  'deleteConfirm': 'Delete {provider}',
  'deleting': 'Deleting {provider}…',
  'add': 'Add provider',
  'provider': 'Provider',
  'close': 'Close',
  'cancel': 'Cancel',
  'savedProvider': 'Saved {provider}.',
  'credentialConfigured': 'API key configured',
  'credentialMissing': 'API key missing',
  'readOnly': 'The settings document is read-only in this deployment.',
  'loadFailed': 'Loading the provider directory failed',
  'retry': 'Retry',
  'customAdd': 'Add a custom provider',
  'customTag': 'Custom',
};
