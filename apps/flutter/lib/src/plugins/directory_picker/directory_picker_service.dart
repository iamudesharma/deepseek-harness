/// Directory-pick seam — the Dart analog of the composed
/// `ui-directory-picker-browse` / `ui-directory-picker-native` pair: one pick
/// face with two backends, chosen by platform. Native (desktop/macOS) drives
/// the host's own chooser through `host.pickDirectory` via the shared
/// [WorkspacesService]; browse (web) is the Miller-column in-app browser over
/// host `listDirectory` / `createDirectory` primitives ([DirectoryBrowser]).
///
/// The React packages additionally register occupants into ui-workspace's two
/// directory-flow holes; those child holes are not declared in the Dart ledger
/// yet, so registration is deferred with them and this service is the consumed
/// face meanwhile.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/services/runtime_services.dart';
import 'directory_browser.dart';

export 'directory_browser.dart'
    show DirectoryEntry, DirectoryListing, DirectoryBrowseError;

/// Service names the two backend faces are published under.
const String kBrowsePickerServiceName = 'directoryPicker.browse';
const String kNativePickerServiceName = 'directoryPicker.native';

/// One directory pick: absolute path on success, null on cancel. Failures
/// throw; the caller owns the error surface (the flow contract's
/// picked/cancelled/error triple).
abstract interface class DirectoryPickFace {
  /// Opens the chooser and resolves the outcome.
  Future<String?> pick();
}

/// Browse backend: the Miller-column in-app browser over host primitives.
///
/// Drives `host.listDirectory` / `host.createDirectory` via [WorkspacesService];
/// UI consumers render [DirectoryBrowser] directly, but this pick-face remains
/// for service-registry parity and for tests that drive a headless pick.
/// The web fallback is not `file_picker` — Miller is the contract; file_picker
/// lives only in the adaptive fallback seam.
class BrowseDirectoryPicker implements DirectoryPickFace {
  /// Creates the browse picker around the workspace wire face.
  BrowseDirectoryPicker(this._workspaces);

  final WorkspacesService _workspaces;

  /// List one directory level (absent = Host home).
  ///
  /// [signal] mirrors the React `AbortSignal` wired through
  /// `DirectoryBrowser.listDirectory(path, signal)` — the caller's
  /// supersession aborts the host scan via [DirectoryListSignal].
  Future<DirectoryListing> listDirectory({
    String? path,
    DirectoryListSignal? signal,
  }) async {
    final map = await _workspaces.listDirectory(path: path, signal: signal);
    return DirectoryListing.fromJson(map.cast<String, dynamic>());
  }

  /// Create one child directory under an existing parent.
  Future<String> createDirectory({
    required String path,
    required String name,
  }) => _workspaces.createDirectory(path: path, name: name);

  @override
  Future<String?> pick() async {
    // Headless pick has no BuildContext to show the Miller dialog; in
    // non-UI tests this is not used (callers construct DirectoryBrowser directly).
    // Return null to signal cancellation rather than invent a path.
    return null;
  }
}

/// Native backend: the host channel (`host.pickDirectory` OS chooser).
class NativeDirectoryPicker implements DirectoryPickFace {
  /// Creates the native picker around the workspace wire face.
  const NativeDirectoryPicker(this._workspaces);

  final WorkspacesService _workspaces;

  @override
  Future<String?> pick() => _workspaces.pickDirectory();
}

/// Platform-chosen default backend, mirroring which React package a
/// deployment composes for its surface. Web and any RemoteTarget (mobile)
/// both need the browse Miller dialog; only local desktop uses the native
/// OS chooser. Tests construct a concrete class instead.
DirectoryPickFace defaultDirectoryPicker(WorkspacesService workspaces) {
  if (kIsWeb || workspaces.isRemote) return BrowseDirectoryPicker(workspaces);
  return NativeDirectoryPicker(workspaces);
}
