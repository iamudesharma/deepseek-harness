/// The `ui-settings-general` plugin — Flutter port of
/// `packages/client/ui-settings-general/src/client/index.ts`, sliced to the
/// Dart runtime.
///
/// React occupies `sidebar.settings` (declaring the whole settings subtree),
/// registers the chrome entries, and contributes the General section row.
/// The Dart settings shell declares no settings holes yet, so the section
/// registration is deferred with those declarations; this activation
/// publishes the per-namespace scope service (`settings.general`) and the
/// `settings` dictionaries. Section presentation stays with the existing
/// General rows until the shell workstream re-homes them here.
library;

import '../../../../core/connection/connection_client.dart';
import '../../../../core/plugin/plugin_contract.dart';
import '../../../../core/services/runtime_services.dart';
import 'general_settings_service.dart';

/// Plugin identity.
const String kGeneralSettingsPluginId = 'ui-settings-general';

/// Locale namespace owned by this plugin (shell chrome + General copy).
const String kSettingsNamespace = 'settings';

/// The `ui-settings-general` plugin.
class GeneralSettingsPlugin extends DshPlugin {
  /// Creates the plugin.
  const GeneralSettingsPlugin();

  @override
  String get id => kGeneralSettingsPluginId;

  @override
  List<String> get inject => ['connection', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    final service = GeneralSettingsService(client);
    ctx.provide(kGeneralSettingsServiceName, service);
    ctx.onDispose(service.dispose);

    // Dictionaries land with the plugin; the section row waits for the
    // settings shell's hole declarations.
    ctx.onDispose(
      locale.register(kSettingsNamespace, {
        'zh': kSettingsZh,
        'en': kSettingsEn,
      }),
    );
  }
}

/// Shell/General copy from `packages/client/ui-settings-general/src/client/locales.ts`
/// (`trigger`, `title`, `close`, `openDocument.*` verbatim) plus this
/// surface's section headers and row copy (Flutter-surface additions; React
/// renders them inside its own General section components). The Appearance
/// row's keys ride here too — React files them under ui-theme's separate
/// `settings.theme` namespace, whose Dart owner sits outside this surface.
const Map<String, String> kSettingsZh = {
  'appearance.title': '外观',
  'appearance.light': '浅色',
  'appearance.dark': '深色',
  'appearance.system': '跟随系统',
  'trigger': '设置',
  'title': '设置',
  'general.nav': '通用',
  'general.title': '本设备的语言与外观。',
  'section.notifications': '通知',
  'notifications.enable': '启用系统通知',
  'notifications.enableDesc': '回合完成时显示系统通知。',
  'section.workspace': '工作区',
  'workspace.directory': '工作区目录',
  'workspace.selectFolder': '选择工作区文件夹',
  'section.about': '关于',
  'about.tagline': '基于 vendored Cordis 的插件化代理 Harness：一切皆插件。',
};

const Map<String, String> kSettingsEn = {
  'appearance.title': 'Appearance',
  'appearance.light': 'Light',
  'appearance.dark': 'Dark',
  'appearance.system': 'System',
  'trigger': 'Settings',
  'title': 'Settings',
  'general.nav': 'General',
  'general.title': 'Language and appearance for this device.',
  'section.notifications': 'Notifications',
  'notifications.enable': 'Enable notifications',
  'notifications.enableDesc': 'Show system notifications for turn completions.',
  'section.workspace': 'Workspace',
  'workspace.directory': 'Workspace directory',
  'workspace.selectFolder': 'Select workspace folder',
  'section.about': 'About',
  'about.tagline':
      'Plugin-based agent harness on vendored Cordis. Everything is a plugin.',
};
