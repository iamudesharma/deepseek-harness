/// The `ui-settings-plugins` plugin — Flutter port of
/// `packages/client/ui-settings-plugins/src/client/index.ts`, sliced to the
/// Dart runtime.
///
/// React registers the Plugins settings section (declaring
/// `settings.plugins.tab` / `settings.plugin.item`) and the three shipped
/// cards. The Dart settings shell declares no section holes yet, so the
/// section/tab registration is deferred with those declarations; this
/// activation publishes the per-card scope service (`settings.plugins`) and
/// the `settings.plugins` dictionaries.
library;

import '../../../../core/connection/connection_client.dart';
import '../../../../core/plugin/plugin_contract.dart';
import '../../../../core/services/runtime_services.dart';
import 'plugins_settings_service.dart';

/// Plugin identity.
const String kPluginsSettingsPluginId = 'ui-settings-plugins';

/// Locale namespace owned by this plugin.
const String kPluginsNamespace = 'settings.plugins';

/// The `ui-settings-plugins` plugin.
class PluginsSettingsPlugin extends DshPlugin {
  /// Creates the plugin.
  const PluginsSettingsPlugin();

  @override
  String get id => kPluginsSettingsPluginId;

  @override
  List<String> get inject => ['connection', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    final service = PluginsSettingsService(client);
    ctx.provide(kPluginsSettingsServiceName, service);
    ctx.onDispose(service.dispose);

    ctx.onDispose(
      locale.register(kPluginsNamespace, {'zh': kPluginsZh, 'en': kPluginsEn}),
    );
  }
}

const Map<String, String> kPluginsZh = {
  'nav': '插件',
  'title': '插件',
  'description': '配置宿主插件的运行参数。',
};

const Map<String, String> kPluginsEn = {
  'nav': 'Plugins',
  'title': 'Plugins',
  'description': 'Configure host plugin runtime options.',
};
