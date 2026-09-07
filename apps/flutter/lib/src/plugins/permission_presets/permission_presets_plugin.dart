/// The `ui-permission-presets` plugin — Flutter port of
/// `packages/client/ui-permission-presets/src/client/index.ts`.
///
/// React registers three faces: the `/permission` command decoration
/// (popupSelect over the session's permissions projection), a
/// `settings.general.item` row persisting the new-session default, and two
/// locale dictionaries. Of these, the Dart runtime can carry only the
/// dictionaries and the default-preset service today:
///
/// - The command-popup needs the `commandUi` popup shell (the ui-commands
///   overlay entry hosts it; the projection-fed chip presentation this
///   package ships — `ui/permission_seat.dart` — mounts in the COMPOSER TOOL
///   ROW, mounted by ui-conversation's composer exactly like React's
///   InputBar renders `PermissionSelect` inline in `.modes`
///   (InputBar.tsx:509-511, 711-714). No header seat exists in React.
/// - The settings row needs the settings shell's `settings.general.item`
///   hole (undeclared in any Dart ledger).
/// - The approval gate is NOT this package in React: the composer chain seat
///   and ApprovalPanel live in ui-conversation, and no keyed `approval`
///   chat-node renderer exists there to port. The chain seat is therefore
///   deferred with its declaration; this plugin exposes the presets service
///   (`permissionPresets`) as the consumed face meanwhile.
library;

import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import 'locales.dart';
import 'permission_presets_service.dart';

/// Plugin identity.
const String kPermissionPresetsPluginId = 'ui-permission-presets';

/// The `ui-permission-presets` plugin.
class PermissionPresetsPlugin extends DshPlugin {
  /// Creates the plugin.
  const PermissionPresetsPlugin();

  @override
  String get id => kPermissionPresetsPluginId;

  @override
  List<String> get inject => ['connection', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    // Per-namespace scope over the shared describe wire — the Dart analog of
    // ctx.settingsScope.bind({namespace: PERMISSION_SETTINGS_NS}).
    final service = PermissionPresetsService(
      PermissionPresetsService.wireScope(client),
    );
    ctx.provide(kPermissionPresetsServiceName, service);
    ctx.onDispose(service.dispose);

    // Both dictionaries land as one unit; registration failure of either
    // leaves with the plugin.
    ctx.onDispose(
      locale.register(kPermissionSettingsNamespace, {
        'zh': kPermissionSettingsZh,
        'en': kPermissionSettingsEn,
      }),
    );
    ctx.onDispose(
      locale.register(kPermissionAccessNamespace, {
        'zh': kPermissionAccessZh,
        'en': kPermissionAccessEn,
      }),
    );
  }
}
