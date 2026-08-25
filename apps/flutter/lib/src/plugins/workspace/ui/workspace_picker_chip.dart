/// Conversation hero workspace picker — the `conversation.hero.workspace`
/// occupant, port of `WorkspacePicker.tsx` sliced to the Dart hub: a chip on
/// the blank-session hero listing real Host workspaces (`workspace.list`)
/// with the trailing add action. Adding a workspace picks a host directory
/// (native chooser via `host.pickDirectory`, or the platform seam on web) and
/// adopts it through `workspace.create`; failures surface in the flow's own
/// error dialog, never as a silent no-op.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/connection/connection_controller.dart'
    show connectionClientProvider;
import '../../../core/services/runtime_services.dart';
import '../../../features/workspace/workspace_provider.dart'
    show selectedWorkspaceProvider, workspaceListProvider;
import '../../../theme/app_theme.dart';
import '../../directory_picker/directory_browser.dart';
import '../../directory_picker/directory_picker_plugin.dart'
    show activatedPickDirectory;
import '../../directory_picker/directory_picker_service.dart'
    show DirectoryPickFace;
import '../locales.dart';

/// Hero picker over the shared workspace providers.
class WorkspacePickerChip extends ConsumerStatefulWidget {
  /// Creates the hero chip.
  const WorkspacePickerChip({super.key, this.picker});

  /// Optional directory-pick override (tests); null resolves the activated
  /// directory-picker service bridge.
  final DirectoryPickFace? picker;

  @override
  ConsumerState<WorkspacePickerChip> createState() =>
      _WorkspacePickerChipState();
}

class _WorkspacePickerChipState extends ConsumerState<WorkspacePickerChip> {
  final OverlayPortalController _portal = OverlayPortalController();
  bool _busy = false;
  String? _error;

  Future<void> _addWorkspace() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? path;
      if (kIsWeb) {
        // Web: Miller-column browse over host primitives.
        final client = ref.read(connectionClientProvider);
        final svc = WorkspacesService(client);
        Future<DirectoryListing> list({String? path, DirectoryListSignal? signal}) async {
          final map = await svc.listDirectory(path: path, signal: signal);
          return DirectoryListing.fromJson(map.cast<String, dynamic>());
        }

        Future<String> create({required String path, required String name}) =>
            svc.createDirectory(path: path, name: name);
        if (!mounted) return;
        path = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => DirectoryBrowser(
            open: true,
            listDirectory: list,
            createDirectory: create,
            onOpen: (p) => Navigator.pop(ctx, p),
            onClose: () => Navigator.pop(ctx),
          ),
        );
      } else {
        final DirectoryPickFace? picker = widget.picker ?? activatedPickDirectory;
        path = await picker?.pick();
      }
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        // Cancelled — nothing to adopt.
        return;
      }
      final client = ref.read(connectionClientProvider);
      await client.workspaceCreate(path: path);
      ref.invalidate(workspaceListProvider);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
            (theme.brightness == Brightness.dark
                ? DswTokens.darkAliases
                : DswTokens.lightAliases);
    // bindLocale watches localeRevisionProvider, so a Language-row switch
    // rebuilds the chip and its overlay copy together.
    final t = ref.bindLocale(kWorkspaceNamespace);
    final workspaces = ref.watch(workspaceListProvider);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (BuildContext overlayContext) => Stack(children: [
        // Dismiss barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_portal.isShowing) _portal.hide();
            },
          ),
        ),
        Positioned(
          left: DswTokens.spaceLg,
          top: kToolbarHeight + DswTokens.spaceSm,
          child: Material(
            color: aliases.specificMenu,
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: workspaces.maybeWhen(
                    data: (items) => ListView(shrinkWrap: true, children: [
                      for (final workspace in items)
                        ListTile(
                          dense: true,
                          leading:
                              Icon(Icons.folder_outlined, size: 16, color: aliases.labelTertiary),
                          title: Text(workspace.name,
                              style: TextStyle(
                                  fontSize: DswTokens.fontSizeS14,
                                  color: aliases.labelPrimary)),
                          onTap: () {
                            ref.read(selectedWorkspaceProvider.notifier).state =
                                workspace.workspaceId;
                            if (_portal.isShowing) _portal.hide();
                          },
                        ),
                    ]),
                    orElse: () => Padding(
                      padding: const EdgeInsets.all(DswTokens.spaceMd),
                      child: Text(t('picker.loading'),
                          style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              color: aliases.labelSecondary)),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  enabled: !_busy,
                  leading: _busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: aliases.labelTertiary))
                      : Icon(Icons.add, size: 16, color: aliases.labelSecondary),
                  title: Text(t('menu.addWorkspace'),
                      style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          color: aliases.labelPrimary)),
                  onTap: _addWorkspace,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(DswTokens.spaceSm),
                    child: Text('${t('folderError.title')}\n$_error',
                        style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: aliases.stateErrorPrimary)),
                  ),
              ]),
            ),
          ),
        ),
      ]),
      child: ActionChip(
        backgroundColor: aliases.bgOverlay,
        side: BorderSide(color: aliases.borderL2),
        avatar: Icon(Icons.workspaces_outlined,
            size: 14, color: aliases.labelSecondary),
        label: Text(t('section.workspaces'),
            style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                fontWeight: FontWeight.w600,
                color: aliases.labelSecondary)),
        onPressed: () {
          if (_portal.isShowing) {
            _portal.hide();
          } else {
            _portal.show();
          }
        },
      ),
    );
  }
}
