/// Plugins settings service — the `ui-settings-plugins` faces sliced to the
/// Dart settings seam. React binds each configurable card to its namespace
/// scope (`shell`, `agent-loop`, `web-search-deepseek`); this service owns
/// the three scopes over the shared describe wire.
library;

import 'package:flutter/foundation.dart';

import '../../../../core/connection/connection_client.dart';
import '../../../../core/settings/settings_scope.dart';

/// Service name the plugins face is published under.
const String kPluginsSettingsServiceName = 'settings.plugins';

/// Shell card namespace (mirrors bash-card-controller.ts SHELL_NS).
const String kShellNamespace = 'shell';

/// Agent-loop card namespace (mirrors agent-loop-card-controller.ts).
const String kAgentLoopNamespace = 'agent-loop';

/// Web-search card namespace (mirrors web-search-card-controller.ts).
const String kWebSearchNamespace = 'web-search-deepseek';

/// One card's scope face: read a scalar field, write it back revision-fenced.
class PluginCardScope extends ChangeNotifier {
  /// Creates one card scope for [namespace].
  PluginCardScope(ConnectionClient client, this.namespace)
    : _scope = SettingsScope<Object?>(
        face: SettingsRpcFace(client),
        namespace: namespace,
      ) {
    _scope.subscribe((_) => notifyListeners());
  }

  /// Host settings namespace this card binds.
  final String namespace;

  final SettingsScope<Object?> _scope;

  /// Reads one scalar field from the namespace value.
  Object? field(String name) {
    final value = _scope.snapshot.value;
    if (value is Map) return value[name];
    return null;
  }

  /// Writes one scalar field.
  Future<void> setField(String name, Object? value) => _scope.set(name, value);

  /// Refreshes from the host settings document.
  Future<void> load() => _scope.refreshFromDescribe();

  /// Whether writes are permitted on the namespace.
  bool get writable => _scope.snapshot.writable;
}

/// The three configurable-plugin card scopes shipped by the package.
class PluginsSettingsService extends ChangeNotifier {
  /// Creates the service around one client.
  PluginsSettingsService(ConnectionClient client)
    : shell = PluginCardScope(client, kShellNamespace),
      agentLoop = PluginCardScope(client, kAgentLoopNamespace),
      webSearch = PluginCardScope(client, kWebSearchNamespace);

  /// Shell card scope (`shell`).
  final PluginCardScope shell;

  /// Agent-loop card scope (`agent-loop`).
  final PluginCardScope agentLoop;

  /// Web-search card scope (`web-search-deepseek`).
  final PluginCardScope webSearch;

  /// Refreshes all card scopes from the shared describe answer.
  Future<void> load() async {
    await Future.wait([shell.load(), agentLoop.load(), webSearch.load()]);
  }
}
