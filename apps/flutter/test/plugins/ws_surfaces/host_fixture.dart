import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_contract.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/attachment/attachment_plugin.dart';
import 'package:dsh_flutter/src/plugins/attachment/attachment_service.dart';
import 'package:dsh_flutter/src/plugins/brand_official/brand_official_plugin.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_picker_plugin.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_picker_service.dart';
import 'package:dsh_flutter/src/plugins/model_selection/model_directory_service.dart';
import 'package:dsh_flutter/src/plugins/model_selection/model_selection_plugin.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/permission_presets_plugin.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/permission_presets_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/general/general_settings_plugin.dart';
import 'package:dsh_flutter/src/plugins/settings/children/general/general_settings_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/models/models_settings_plugin.dart';
import 'package:dsh_flutter/src/plugins/settings/children/models/models_settings_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugin_inventory/plugin_inventory_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugins/plugins_settings_plugin.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugins/plugins_settings_service.dart';
import 'package:dsh_flutter/src/plugins/workspace/workspace_plugin.dart';
import 'package:flutter/widgets.dart';

export 'package:dsh_flutter/src/plugins/attachment/attachment_plugin.dart'
    show AttachmentPlugin, kAttachmentPluginId;
export 'package:dsh_flutter/src/plugins/brand_official/brand_official_plugin.dart'
    show BrandOfficialPlugin;
export 'package:dsh_flutter/src/plugins/directory_picker/directory_picker_service.dart'
    show DirectoryPickFace, kNativePickerServiceName, kBrowsePickerServiceName;
export 'package:dsh_flutter/src/plugins/model_selection/model_selection_plugin.dart'
    show ModelSelectionPlugin;
export 'package:dsh_flutter/src/plugins/settings/children/general/general_settings_plugin.dart'
    show GeneralSettingsPlugin;
export 'package:dsh_flutter/src/plugins/settings/children/models/models_settings_plugin.dart'
    show ModelsSettingsPlugin;
export 'package:dsh_flutter/src/plugins/settings/children/plugin_inventory/plugin_inventory_plugin.dart'
    show PluginInventoryPlugin;
export 'package:dsh_flutter/src/plugins/settings/children/plugins/plugins_settings_plugin.dart'
    show PluginsSettingsPlugin;
export 'package:dsh_flutter/src/plugins/workspace/workspace_plugin.dart'
    show WorkspacePlugin;

/// Connection fake: records Typert method calls and answers from a table.
class FakeClient extends ConnectionClient {
  /// Creates the fake.
  FakeClient() : super(baseUrl: '');

  /// Every `callMethod` invocation, in order.
  final List<String> calls = [];

  /// Canned answers per method (unlisted methods answer `{}`).
  final Map<String, Map<String, Object?>> answers = {};

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    calls.add(method);
    return answers[method] ?? const <String, dynamic>{};
  }
}

class _NoopFace implements SettingsFace {
  @override
  Future<Map<String, Object?>> describe() async => const {};

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) async =>
      const {};
}

/// Host carrying every service the WS-Surfaces plugins declare, so
/// activation runs against the real DI fixpoint without booting the app
/// shell. Mirrors ws_agent/host_fixture.dart.
PluginHost wsSurfacesHost({FakeClient? client}) {
  final c = client ?? FakeClient();
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.provide('connection', c);
  host.provide('workspaces', WorkspacesService(c));
  host.provide('locale', LocaleService());
  host.provide(
    'settingsScope',
    SettingsScope<Object?>(face: _NoopFace(), namespace: 'ui-conversation'),
  );
  return host;
}

/// Declares the conversation anchor's child holes the surfaces fill —
/// the fixture-shell pattern: an entry on the built-in `'root'` slot whose
/// children table mirrors kConversationChildSlots' surface holes.
void declareSurfaceHoles(PluginHost host) {
  host.slots.register(
    const RegistrationOptions(
      name: 'root',
      children: {
        'conversation.hero.brand.mark':
            SlotSpec(kind: SlotKind.single, scope: SlotScope.root),
        'conversation.hero.workspace':
            SlotSpec(kind: SlotKind.single, scope: SlotScope.root),
        'conversation.input.model':
            SlotSpec(kind: SlotKind.single, scope: SlotScope.session),
      },
    ),
    (context, props) => const SizedBox.shrink(),
  );
}

/// All eleven WS-Surfaces plugins in registration order.
List<DshPlugin> wsSurfacePlugins() => [
      const BrandOfficialPlugin(),
      const WorkspacePlugin(),
      const ModelSelectionPlugin(),
      const PermissionPresetsPlugin(),
      const AttachmentPlugin(),
      const BrowseDirectoryPickerPlugin(),
      const NativeDirectoryPickerPlugin(),
      const GeneralSettingsPlugin(),
      const ModelsSettingsPlugin(),
      const PluginsSettingsPlugin(),
      const PluginInventoryPlugin(),
    ];

/// Service names the suite asserts after activation.
const surfaceServices = [
  kModelDirectoriesServiceName,
  kPermissionPresetsServiceName,
  kAttachmentsServiceName,
  kBrowsePickerServiceName,
  kNativePickerServiceName,
  kGeneralSettingsServiceName,
  kModelsSettingsServiceName,
  kPluginsSettingsServiceName,
  kPluginInventoryServiceName,
];
