/// The `ui-workspace` plugin — Flutter port of
/// `packages/client/ui-workspace/src/client/index.ts` `apply()`, sliced to
/// the Dart hub: the conversation hero's picker hole. The sidebar browsing
/// region needs the `sidebar.workspaces` hole, which no Dart plugin declares
/// yet; its registration is deferred with that shell.
///
/// List/create ride the host-provided `workspaces` service (real
/// `workspace.list` / `workspace.create` / `host.pickDirectory` RPCs);
/// directory picking stays behind the directory-picker seam this workstream
/// also owns (`ui-directory-picker-*`).
library;

import 'package:flutter/material.dart';

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'locales.dart';
import 'ui/workspace_picker_chip.dart';

/// Plugin identity.
const String kWorkspacePluginId = 'ui-workspace';

/// Hero hole this plugin fills (declared by the conversation anchor).
const String kWorkspaceHeroSlot = 'conversation.hero.workspace';

/// The `ui-workspace` plugin.
class WorkspacePlugin extends DshPlugin {
  /// Creates the plugin.
  const WorkspacePlugin();

  @override
  String get id => kWorkspacePluginId;

  @override
  List<String> get inject => ['slots', 'workspaces', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin the declared injection edges: list/create/pickDirectory all run
    // through the shared WorkspacesService wire face.
    ctx.require<WorkspacesService>('workspaces');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    ctx.onDispose(
      locale.register(kWorkspaceNamespace, {
        'zh': kWorkspaceZh,
        'en': kWorkspaceEn,
      }),
    );

    // Hero picker waits for the conversation-owned hero hole, installs
    // atomically, and leaves with this plugin. Mirrors React's
    // WorkspaceBrowser/WorkspacePicker registrations that declare their
    // directory-flow child holes (`single` root) in the same call — the slot
    // ledger's children table is both declaration and authorization.
    final stopInject = ctx.slots.inject(kWorkspaceHeroSlot, () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: kWorkspaceHeroSlot,
            children: {
              'conversation.hero.workspace.directoryFlow': SlotSpec(
                kind: SlotKind.single,
                scope: SlotScope.root,
              ),
            },
          ),
          (context, props) => const WorkspacePickerChip(),
        ),
      ];
    });
    ctx.onDispose(stopInject);

    // Sidebar browsing region — declares the directoryFlow child hole
    // inside the sidebar.workspaces entry (mirrors React WorkspaceBrowser).
    // SidebarPlugin already declared `sidebar.workspaces` as child of
    // `layout.sidebar`; this entry provides the workspace-browser occupancy
    // and its child hole for the directory picker.
    final stopSidebarInject = ctx.slots.inject('sidebar.workspaces', () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: 'sidebar.workspaces',
            children: {
              'sidebar.workspaces.directoryFlow': SlotSpec(
                kind: SlotKind.single,
                scope: SlotScope.root,
              ),
            },
          ),
          (context, props) => const SizedBox.shrink(),
        ),
      ];
    });
    ctx.onDispose(stopSidebarInject);
  }
}
