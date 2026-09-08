/// The `ui-permission-presets` plugin — Flutter port of
/// `packages/client/ui-permission-presets/src/client/index.ts`.
///
/// React registers three faces: the `/permission` command decoration
/// (popupSelect over the session's permissions projection), a
/// `settings.general.item` row persisting the new-session default, and two
/// locale dictionaries. The Dart runtime carries the dictionaries, the
/// default-preset service, and the decoration:
///
/// - The decoration opens the shared popupSelect shell over the live
///   projection mirror (`permissionSnapshotCache`, fed by `live_sync`
///   beside every provider write); settling posts `/permission <preset>`
///   through the canonical command channel, and the pushed projection frame
///   is the confirmation. Argued lines keep the existing claim path.
/// - The projection-fed chip presentation (`ui/permission_seat.dart`)
///   mounts in the COMPOSER TOOL ROW, mounted by ui-conversation's composer
///   exactly like React's InputBar renders `PermissionSelect` inline in
///   `.modes` (InputBar.tsx:509-511, 711-714). No header seat exists in React.
/// - The settings row needs the settings shell's `settings.general.item`
///   hole (undeclared in any Dart ledger).
/// - The approval gate is NOT this package in React: the composer chain seat
///   and ApprovalPanel live in ui-conversation, and no keyed `approval`
///   chat-node renderer exists there to port. The chain seat is therefore
///   deferred with its declaration; this plugin exposes the presets service
///   (`permissionPresets`) as the consumed face meanwhile.
library;

import '../commands/command_service.dart' show CommandUiService;
import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import 'locales.dart';
import 'permission_command.dart';
import 'permission_presets_service.dart';
import 'permission_session_provider.dart' show permissionSnapshotCache;

/// Plugin identity.
const String kPermissionPresetsPluginId = 'ui-permission-presets';

/// The `ui-permission-presets` plugin.
class PermissionPresetsPlugin extends DshPlugin {
  /// Creates the plugin.
  const PermissionPresetsPlugin();

  @override
  String get id => kPermissionPresetsPluginId;

  @override
  List<String> get inject => ['commandUi', 'connection', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final CommandUiService commandUi = ctx.require<CommandUiService>(
      'commandUi',
    );
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

    // Bare `/permission` opens the picker shell over the live projection
    // (React `command.decorate` parity). The risk-gate copy snapshots the
    // locale at registration, like the `/model` row description.
    final accessCopy = locale.bind(kPermissionAccessNamespace);
    final stopPermissionCommand = commandUi.decorate(
      buildPermissionDecoration(
        snapshots: permissionSnapshotCache,
        execute: commandUi.execute,
        confirm: PermissionConfirmCopy(
          title: accessCopy('confirm.title'),
          description: accessCopy('confirm.description'),
          acknowledge: accessCopy('confirm.acknowledge'),
          cancel: accessCopy('confirm.cancel'),
          enable: accessCopy('confirm.enable'),
        ),
      ),
    );
    ctx.onDispose(stopPermissionCommand);
  }
}
