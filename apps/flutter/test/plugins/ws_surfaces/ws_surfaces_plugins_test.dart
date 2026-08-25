import 'package:dsh_flutter/src/core/renderer/slot_outlet.dart'
    show SlotComponentProps;
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/features/attachment/attachment_provider.dart'
    show ComposerAttachment;
import 'package:dsh_flutter/src/plugins/attachment/attachment_service.dart';
import 'package:dsh_flutter/src/plugins/directory_picker/directory_picker_plugin.dart';
import 'package:dsh_flutter/src/plugins/model_selection/model_directory_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/general/general_settings_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/models/models_settings_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugin_inventory/plugin_inventory_service.dart';
import 'package:dsh_flutter/src/plugins/settings/children/plugins/plugins_settings_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'host_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eleven WS-Surfaces plugins activate and publish their services', () async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);

    for (final plugin in wsSurfacePlugins()) {
      host.register(plugin);
    }
    await host.activateAll();

    for (final name in surfaceServices) {
      expect(host.hasService(name), isTrue, reason: 'service "$name" missing');
    }
  });

  test('hero contributions wait-and-follow their hole declarations', () async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);

    // No shell yet: brand mark and workspace picker stay queued.
    host.register(const BrandOfficialPlugin());
    host.register(const WorkspacePlugin());
    await host.activateAll();
    expect(host.slots.isDeclared('conversation.hero.brand.mark'), isFalse);
    expect(host.slots.winnersOfSlot('conversation.hero.brand.mark'), isEmpty);
    expect(host.slots.winnersOfSlot('conversation.hero.workspace'), isEmpty);

    declareSurfaceHoles(host);

    expect(host.slots.winnersOfSlot('conversation.hero.brand.mark'), hasLength(1));
    expect(host.slots.winnersOfSlot('conversation.hero.workspace'), hasLength(1));
  });

  test('model seat occupies the declared input.model hole', () async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);

    host.register(const ModelSelectionPlugin());
    await host.activateAll();

    final directories =
        host.service<ModelDirectoryService>(kModelDirectoriesServiceName)!;
    expect(activatedModelDirectories, same(directories));

    declareSurfaceHoles(host);
    expect(host.slots.winnersOfSlot('conversation.input.model'), hasLength(1));

    // The seat component renders (a real SlotWidgetBuilder).
    final entry = host.slots.winnersOfSlot('conversation.input.model').single;
    expect(entry.component as Widget Function(BuildContext, SlotComponentProps),
        isNotNull);
  });

  test('workspace service records workspace.list/create wire methods', () async {
    final client = FakeClient()
      ..answers['workspace.list'] = {
        'items': [
          {'workspaceId': 'ws-1', 'title': 'Main', 'path': '/work/main'},
        ],
      }
      ..answers['workspace.create'] = {
        'workspace': {'workspaceId': 'ws-2', 'title': '/work/new'},
      };
    final host = wsSurfacesHost(client: client);
    addTearDown(host.deactivateAll);

    final workspaces = host.service<WorkspacesService>('workspaces')!;
    final rows = await workspaces.list();
    expect(rows.single['workspaceId'], 'ws-1');

    final created = await workspaces.create(path: '/work/new');
    expect(created['title'], '/work/new');

    expect(
      client.calls,
      containsAllInOrder(['workspace.list', 'workspace.create']),
    );
  });

  test('directory-picker backends resolve pick through the recorded seam',
      () async {
    final client = FakeClient()
      ..answers['host.pickDirectory'] = {'path': '/work/picked'};
    final host = wsSurfacesHost(client: client);
    addTearDown(host.deactivateAll);

    host.register(const NativeDirectoryPickerPlugin());
    await host.activateAll();

    final picker = host.service<DirectoryPickFace>(kNativePickerServiceName)!;
    await expectLater(picker.pick(), completion('/work/picked'));
    expect(client.calls, contains('host.pickDirectory'));

    host.deactivate(kNativePickerPluginId);
    expect(activatedPickDirectory, isNull);
  });

  test('attachment staging adds once, removes, and clears with teardown',
      () async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);

    host.register(const AttachmentPlugin());
    await host.activateAll();

    final staging = host.service<AttachmentStagingService>(
        kAttachmentsServiceName)!;
    var notified = 0;
    void listener() => notified++;
    staging.addListener(listener);

    staging.add(ComposerAttachment(id: 'a1', name: 'shot.png'));
    staging.add(ComposerAttachment(id: 'a1', name: 'shot.png')); // id dedupe
    expect(staging.items.map((item) => item.id), ['a1']);
    expect(notified, 1);
    staging.remove('a1');
    expect(staging.items, isEmpty);
    staging.removeListener(listener);

    host.deactivate(kAttachmentPluginId);
    expect(host.hasService(kAttachmentsServiceName), isFalse);
  });

  test('settings children expose scope-backed services over the wire face',
      () async {
    final client = FakeClient();
    final host = wsSurfacesHost(client: client);
    addTearDown(host.deactivateAll);

    host.register(const GeneralSettingsPlugin());
    host.register(const ModelsSettingsPlugin());
    host.register(const PluginsSettingsPlugin());
    host.register(const PluginInventoryPlugin());
    await host.activateAll();

    final general =
        host.service<GeneralSettingsService>(kGeneralSettingsServiceName)!;
    await general.load();
    general.setLanguage('en');
    expect(general.languagePreference, isNull); // noop face answers empty

    final plugins =
        host.service<PluginsSettingsService>(kPluginsSettingsServiceName)!;
    expect(plugins.shell.namespace, 'shell');
    expect(plugins.agentLoop.namespace, 'agent-loop');
    expect(plugins.webSearch.namespace, 'web-search-deepseek');

    final models =
        host.service<ModelsSettingsService>(kModelsSettingsServiceName)!;
    expect(models.welcome.needsShow, isTrue); // unserved namespace → show

    final inventory = host.service<PluginInventoryService>(
        kPluginInventoryServiceName)!;
    client.answers['pluginInventory.list'] = {
      'items': [
        {'name': 'ui-tool', 'version': '0.0.0', 'enabled': true},
      ],
    };
    final rows = await inventory.list();
    expect(rows.single.name, 'ui-tool');
    expect(client.calls, contains('pluginInventory.list'));
  });
}
