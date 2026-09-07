/// Occupant widgets for the directory-flow holes — Dart ports of
/// `BrowseDirectoryFlow` and `NativeDirectoryFlow` from
/// `packages/client/ui-directory-picker-*`.
///
/// Each hole's owner conversation (`open`/`busy`/`onPicked`/`onCancel`/`onError`)
/// carries the whole exchange: the trigger surface owns `createWorkspace`,
/// the occupant owns everything between `open` and the picked path. The
/// browse occupant renders the Miller dialog; the native occupant is
/// renderless and drives `host.pickDirectory` once per open edge with
/// armed/alive guards mirroring the React flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/runtime_services.dart'
    show DirectoryListSignal, WorkspacesService, localeRevisionProvider;
import 'directory_browser.dart';

/// Localized copy for the Miller dialog — mirrors React's
/// `directory-browser` namespace `zh`/`en` dictionaries registered in
/// `BrowseDirectoryPickerPlugin.apply`. Kept here for the flow widget to
/// bind via `LocaleService.bind('directory-browser')` in the plugin; the
/// fallback English map remains in `DirectoryBrowser._t` for offline use.
const Map<String, String> kDirectoryBrowserEn = {
  'browser.title': 'Select Workspace Directory',
  'browser.home': 'Home',
  'browser.newFolder': 'New folder',
  'browser.folderName': 'Folder name',
  'browser.createIn': 'New folder in "{name}"',
  'browser.untitledFolder': 'Untitled folder',
  'browser.create': 'Create',
  'browser.cancel': 'Cancel',
  'browser.open': 'Open',
  'browser.editPath': 'Edit path',
  'browser.loading': 'Loading…',
  'browser.truncated': 'Too many folders to list; only the beginning is shown.',
  'browser.showHidden': 'Show hidden files',
};

const Map<String, String> kDirectoryBrowserZh = {
  'browser.title': '选择工作区目录',
  'browser.home': '主目录',
  'browser.newFolder': '新建文件夹',
  'browser.folderName': '文件夹名称',
  'browser.createIn': '在"{name}"中新建文件夹',
  'browser.untitledFolder': '未命名文件夹',
  'browser.create': '创建',
  'browser.cancel': '取消',
  'browser.open': '打开',
  'browser.editPath': '编辑路径',
  'browser.loading': '加载中…',
  'browser.truncated': '文件夹过多，仅显示开头部分。',
  'browser.showHidden': '显示隐藏文件',
};

/// Owner props for both directory-flow holes — mirrors
/// `DirectoryFlowOwnerProps` in `packages/client/ui-workspace/src/client/contract/slots.ts`.
///
/// The occupant reads `open` to run/render its interaction and reports exactly
/// one outcome per open via `onPicked`/`onCancel`/`onError`.
class DirectoryFlowOwnerProps {
  const DirectoryFlowOwnerProps({
    required this.open,
    required this.busy,
    required this.onPicked,
    required this.onCancel,
    required this.onError,
  });

  final bool open;
  final bool busy;
  final ValueChanged<String> onPicked;
  final VoidCallback onCancel;
  final ValueChanged<String> onError;
}

/// Injected browse face — mirrors `BrowseFlowInjected` in `flow.ts`.
///
/// Bound in `BrowseDirectoryPickerPlugin.apply`'s closure over
/// `ctx.workspaces` and `ctx.locale.bind('directory-browser')`.
class BrowseFlowInjected {
  const BrowseFlowInjected({
    required this.listDirectory,
    required this.createDirectory,
    required this.t,
  });

  final Future<DirectoryListing> Function({
    String? path,
    DirectoryListSignal? signal,
  })
  listDirectory;
  final Future<String> Function({required String path, required String name})
  createDirectory;
  final String Function(String key) t;
}

/// Browse occupant: adapts the hole's owner conversation onto the Miller dialog.
///
/// A confirmed directory is the picked path, dismissal is cancellation.
/// Browse failures stay inside the dialog's alert surfaces, so the owner's
/// `onError` is never driven by this occupant — mirrors React's contract
/// where the dialog owns its own error display.
class BrowseDirectoryFlow extends ConsumerWidget {
  const BrowseDirectoryFlow({
    super.key,
    required this.owner,
    required this.injected,
  });

  final DirectoryFlowOwnerProps owner;
  final BrowseFlowInjected injected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The injected `t` reads the live locale at call time (stable bind
    // function); this revision watch supplies the rebuild so dialog copy
    // re-renders on every registry/locale publish.
    ref.watch(localeRevisionProvider);
    return DirectoryBrowser(
      open: owner.open,
      busy: owner.busy,
      listDirectory: injected.listDirectory,
      createDirectory: injected.createDirectory,
      translate: injected.t,
      onOpen: owner.onPicked,
      onClose: owner.onCancel,
    );
  }
}

/// Injected native face — mirrors `NativeFlowInjected` in `flow.ts`.
class NativeFlowInjected {
  const NativeFlowInjected({required this.pick});
  final Future<String?> Function() pick;
}

/// Renderless native occupant: each rising `open` edge runs exactly one pick
/// and reports exactly one outcome.
///
/// Mirrors React `NativeDirectoryFlow`:
/// - `armed` once per open so re-renders / `busy` / `pick` identity change
///   don't relaunch.
/// - `outcome` tracks latest owner callbacks via ref so settlement reports
///   through the newest handlers, not the ones captured when chooser opened.
/// - `alive` false on unmount (HMR replacing occupant) discards settlements
///   wholesale; host chooser survives but answer lands nowhere; replacement
///   re-arms under still-open request.
/// - `open` withdrawn re-arms next request.
/// - Renders nothing — host display renders chooser.
class NativeDirectoryFlow extends StatefulWidget {
  const NativeDirectoryFlow({
    super.key,
    required this.owner,
    required this.injected,
  });

  final DirectoryFlowOwnerProps owner;
  final NativeFlowInjected injected;

  @override
  State<NativeDirectoryFlow> createState() => _NativeDirectoryFlowState();
}

class _NativeDirectoryFlowState extends State<NativeDirectoryFlow> {
  bool _armed = false;
  bool _alive = true;
  late DirectoryFlowOwnerProps _outcome;

  @override
  void initState() {
    super.initState();
    _outcome = widget.owner;
    _alive = true;
    _maybePick();
  }

  @override
  void didUpdateWidget(covariant NativeDirectoryFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _outcome = widget.owner;
    // Pick identity change alone keeps pending settlement — chooser still same
    // dialog. Only open rising edge or armed reset should relaunch.
    if (widget.owner.open != oldWidget.owner.open ||
        widget.injected.pick != oldWidget.injected.pick) {
      _maybePick();
    } else if (widget.owner.open) {
      // Busy/re-render without open change must not relaunch
    } else {
      // open withdrawn — re-arm next request
      _armed = false;
    }
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  void _maybePick() {
    if (!widget.owner.open) {
      _armed = false;
      return;
    }
    if (_armed) return;
    _armed = true;
    widget.injected.pick().then(
      (path) {
        if (!_alive || !mounted) return;
        if (path == null) {
          _outcome.onCancel();
        } else {
          _outcome.onPicked(path);
        }
      },
      onError: (Object error, StackTrace st) {
        if (!_alive || !mounted) return;
        final msg = error is Error ? error.toString() : '$error';
        _outcome.onError(msg);
      },
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// WorkspacesService adapter for the browse flow's injected face.
///
/// Provides `listDirectory` with signal threading and `createDirectory`.
BrowseFlowInjected browseInjectedFrom(
  WorkspacesService workspaces,
  String Function(String) t,
) {
  return BrowseFlowInjected(
    listDirectory: ({String? path, DirectoryListSignal? signal}) async {
      final map = await workspaces.listDirectory(path: path, signal: signal);
      return DirectoryListing.fromJson(map.cast<String, dynamic>());
    },
    createDirectory: ({required String path, required String name}) =>
        workspaces.createDirectory(path: path, name: name),
    t: t,
  );
}
