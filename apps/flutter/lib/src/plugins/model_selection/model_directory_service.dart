/// `ModelDirectoryResolver` (`ctx.modelDirectories`) — the root owner of
/// per-session [ModelDirectory] instances, port of
/// `packages/client/ui-model-selection/src/client/service.ts` sliced to the
/// Dart runtime: both selection entries (the composer seat registered here
/// and any later popup) resolve their session's directory through this one
/// service, so a switch made in either surface is what the other shows.
///
/// The directory type itself is the existing contract-matching port in
/// `features/model_selection/model_directory.dart` (same wire methods:
/// `session.models` load, `session.selectModel` select); this service adds
/// the per-session lazy map and teardown that the resolver owned in React.
library;

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';
import '../../features/model_selection/model_directory.dart';

/// Service name the resolver face is published under (React service name).
const String kModelDirectoriesServiceName = 'modelDirectories';

ModelDirectoryService? _activatedDirectories;

/// Currently bound directory service (null before first activation).
ModelDirectoryService? get activatedModelDirectories => _activatedDirectories;

/// Binds (or clears) the activated directory service — the widget bridge for
/// slot-occupant widgets, mirroring [bindActivatedHub] in the conversation
/// hub: UI reads this instead of reaching into a bootstrap module.
void bindActivatedModelDirectories(ModelDirectoryService? service) {
  _activatedDirectories = service;
}

/// Per-session model-directory owner. Entries are created lazily on first
/// [directoryFor] and dropped by [drop]; there is no global layer to merge.
class ModelDirectoryService {
  /// Creates the service around one client.
  ModelDirectoryService(this._client);

  final ConnectionClient _client;
  final Map<String, ModelDirectory> _directories = {};

  /// Resolves (and lazily creates) the session's shared directory.
  ///
  /// Unknown sessions are allowed — the seat loads on first open, matching
  /// React's load-on-first-read; failures surface on the directory state.
  ModelDirectory directoryFor(SessionId sessionId) {
    return _directories.putIfAbsent(
      sessionId.value,
      () => ModelDirectory(_client, sessionId),
    );
  }

  /// Drops one session's directory (session close / host reset).
  void drop(SessionId sessionId) {
    final directory = _directories.remove(sessionId.value);
    directory?.dispose();
  }

  /// Drops every directory (connection reset).
  void clearAll() {
    for (final directory in _directories.values) {
      directory.dispose();
    }
    _directories.clear();
  }
}
