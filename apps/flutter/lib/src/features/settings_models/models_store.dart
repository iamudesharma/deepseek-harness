import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/connection_controller.dart';

/// Status of the models settings page load.
enum ModelsSettingsStatus { idle, loading, ready, error }

/// Credential view returned by `credentials.describe`.
class CredentialView {
  const CredentialView({
    required this.configured,
    this.source,
    required this.writable,
  });

  final bool configured;
  final String? source;
  final bool writable;

  factory CredentialView.fromJson(Map<String, dynamic> json) => CredentialView(
    configured: json['configured'] as bool? ?? false,
    source: json['source'] as String?,
    writable: json['writable'] as bool? ?? false,
  );
}

/// One namespace view from `settings.describe`.
class SettingsNamespaceView {
  const SettingsNamespaceView({
    required this.ns,
    this.schema,
    this.value,
    this.base,
    this.user,
    required this.revision,
    this.applies = 'live',
    this.secrets = const [],
  });

  final String ns;
  final dynamic schema;
  final dynamic value;
  final dynamic base;
  final dynamic user;
  final int revision;
  final String applies;
  final List<dynamic> secrets;

  factory SettingsNamespaceView.fromJson(Map<String, dynamic> json) =>
      SettingsNamespaceView(
        ns: json['ns'] as String? ?? '',
        schema: json['schema'],
        value: json['value'],
        base: json['base'],
        user: json['user'],
        revision: json['revision'] as int? ?? 0,
        applies: json['applies'] as String? ?? 'live',
        secrets: json['secrets'] as List<dynamic>? ?? const [],
      );
}

/// One row from `llm.providers` — configurable provider directory entry.
class ConfigurableProviderView {
  const ConfigurableProviderView({
    required this.provider,
    required this.displayName,
    required this.settingsNs,
    required this.settingsPath,
    required this.active,
    this.declared,
  });

  final String provider;
  final String displayName;
  final String settingsNs;
  final List<String> settingsPath;
  final bool active;
  final bool? declared;

  factory ConfigurableProviderView.fromJson(Map<String, dynamic> json) =>
      ConfigurableProviderView(
        provider: json['provider'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        settingsNs: json['settingsNs'] as String? ?? '',
        settingsPath:
            (json['settingsPath'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        active: json['active'] as bool? ?? false,
        declared: json['declared'] as bool?,
      );
}

/// One provider row the page renders — mirrors `ProviderRow` in `store.ts`.
class ProviderRow {
  const ProviderRow({
    required this.entry,
    required this.configured,
    required this.removable,
    this.apiKeyEnv,
    this.credential,
  });

  final ConfigurableProviderView entry;
  final bool configured;
  final bool removable;
  final String? apiKeyEnv;
  final CredentialView? credential;

  ProviderRow copyWith({CredentialView? credential}) => ProviderRow(
    entry: entry,
    configured: configured,
    removable: removable,
    apiKeyEnv: apiKeyEnv,
    credential: credential ?? this.credential,
  );
}

/// Page snapshot — mirrors `ModelsSettingsState` in `store.ts`.
class ModelsSettingsState {
  const ModelsSettingsState({
    this.status = ModelsSettingsStatus.idle,
    this.error,
    this.credentialError,
    this.writable = false,
    this.rows = const [],
    this.namespaces = const {},
  });

  final ModelsSettingsStatus status;
  final String? error;
  final String? credentialError;
  final bool writable;
  final List<ProviderRow> rows;
  final Map<String, SettingsNamespaceView> namespaces;

  ModelsSettingsState copyWith({
    ModelsSettingsStatus? status,
    String? error,
    String? credentialError,
    bool? writable,
    List<ProviderRow>? rows,
    Map<String, SettingsNamespaceView>? namespaces,
  }) => ModelsSettingsState(
    status: status ?? this.status,
    error: error,
    credentialError: credentialError,
    writable: writable ?? this.writable,
    rows: rows ?? this.rows,
    namespaces: namespaces ?? this.namespaces,
  );
}

// ---------------------------------------------------------------------------
// Helpers — mirrors `store.ts` utilities
// ---------------------------------------------------------------------------

String messageOf(Object error) =>
    error is Exception ? error.toString() : error.toString();

String deriveKeyRef(String provider) =>
    '${provider.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_')}_API_KEY';

bool providerUsable(ProviderRow row) {
  if (!row.entry.active) return false;
  if (row.apiKeyEnv == null) return true;
  return row.credential?.configured == true;
}

/// Get nested path from a dynamic JSON root (mirrors `schema.getPath`).
dynamic getPath(dynamic root, List<String> path) {
  dynamic cur = root;
  for (final key in path) {
    if (cur is Map<String, dynamic>) {
      if (!cur.containsKey(key)) return null;
      cur = cur[key];
    } else if (cur is Map) {
      if (!cur.containsKey(key)) return null;
      cur = cur[key];
    } else {
      return null;
    }
  }
  return cur;
}

bool hasPath(dynamic root, List<String> path) => getPath(root, path) != null;

String? apiKeyEnvOf(SettingsNamespaceView? namespace, List<String> path) {
  if (namespace == null) return null;
  final profile = getPath(namespace.value, path);
  if (profile is Map) {
    final ref = profile['apiKeyEnv'];
    if (ref is String && ref.isNotEmpty) return ref;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class ModelsSettingsController extends Notifier<ModelsSettingsState> {
  ModelsSettingsController();

  int _generation = 0;

  @override
  ModelsSettingsState build() {
    // Invalidation: llm/adapters-updated, settings/document-updated,
    // credentials/reference-updated, and connection/reset all refresh the
    // provider directory if it has been loaded once (idle guard).
    // ignore: unused_local_variable
    final client = ref.read(connectionClientProvider);
    void refreshIfLoaded() {
      if (state.status == ModelsSettingsStatus.idle) return;
      // ignore: discarded_futures
      load();
    }

    // Listen to $events emit via RemoteEventBus for the three push invalidations.
    // In new remote.mux, these are forwarded as `emit` frames with same event names.
    // For now, also refresh on any remote-event; the bus is fed by connection_controller's
    // _handleRemoteEmit which already dispatches via onHostEnvelope synthetic host/remote-event.
    // Keep a no-op subscription to preserve lifecycle; actual refresh is via connectionState.
    // TODO: wire to RemoteEventBus.$on('llm/adapters-updated' ...) when bus is exposed here.
    // For now, rely on connectionState connected to refresh.
    ref.onDispose(() {});

    // Also refresh on reconnect (connection/reset equivalent) — when the
    // FlutterConnectionController goes connected, the host may have new
    // provider topology.
    ref.listen(connectionStateProvider, (prev, next) {
      if (next == ConnectionState.connected) refreshIfLoaded();
    });

    return const ModelsSettingsState();
  }

  /// Join live + configurable providers — mirrors store.ts joinProviderDirectory.
  List<ConfigurableProviderView> _joinProviderDirectory(
    List<Map<String, dynamic>> live,
    List<Map<String, dynamic>> configurable,
  ) {
    final activeIds = live.map((e) => e['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();
    final declaredIds = configurable.map((e) => e['provider'] as String? ?? '').where((id) => id.isNotEmpty).toSet();
    final rows = <ConfigurableProviderView>[];
    // Declared first (declaration order)
    for (final entry in configurable) {
      final provider = entry['provider'] as String? ?? '';
      rows.add(ConfigurableProviderView(
        provider: provider,
        displayName: entry['displayName'] as String? ?? provider,
        settingsNs: entry['settingsNs'] as String? ?? '',
        settingsPath: (entry['settingsPath'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
        active: activeIds.contains(provider),
        declared: entry['declared'] as bool?,
      ));
    }
    // Live-only (not declared)
    for (final entry in live) {
      final id = entry['id'] as String? ?? '';
      if (declaredIds.contains(id)) continue;
      rows.add(ConfigurableProviderView(
        provider: id,
        displayName: entry['name'] as String? ?? id,
        settingsNs: '',
        settingsPath: const [],
        active: true,
        declared: null,
      ));
    }
    return rows;
  }

  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(status: ModelsSettingsStatus.loading, error: null);

    final client = ref.read(connectionClientProvider);

    List<ConfigurableProviderView> providers;
    bool writable;
    List<SettingsNamespaceView> views;

    try {
      // Parallel: live + configurable + settings.describe (like store.ts)
      final results = await Future.wait([
        client.llmListProviders(),
        client.llmListConfigurableProviders(),
        client.settingsDescribe(),
      ]);

      final liveMaps = results[0] as List<Map<String, dynamic>>;
      final configurableMaps = results[1] as List<Map<String, dynamic>>;
      final describeValue = results[2] as Map<String, dynamic>;

      providers = _joinProviderDirectory(liveMaps, configurableMaps);

      writable = describeValue['writable'] as bool? ?? false;
      final namespacesRaw = describeValue['namespaces'] as List<dynamic>? ?? [];
      views = namespacesRaw
          .whereType<Map>()
          .map((e) => SettingsNamespaceView.fromJson(e.cast<String, dynamic>()))
          .toList();

      if (views.isEmpty && providers.isEmpty) {
        // Keep empty but treat as ready — mirrors mirror hold path.
        if (kDebugMode) debugPrint('[ModelsStore] empty describe + providers');
      }
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        status: ModelsSettingsStatus.error,
        error: messageOf(error),
      );
      return;
    }

    final namespaces = <String, SettingsNamespaceView>{
      for (final v in views) v.ns: v,
    };

    final rows = providers.map((entry) {
      final ns = namespaces[entry.settingsNs];
      final configured =
          ns != null &&
          (entry.settingsPath.isEmpty ||
              getPath(ns.value, entry.settingsPath) != null);
      final removable =
          ns != null &&
          entry.settingsPath.isNotEmpty &&
          hasPath(ns.user, entry.settingsPath) &&
          !hasPath(ns.base, entry.settingsPath);
      return ProviderRow(
        entry: entry,
        configured: configured,
        removable: removable,
        apiKeyEnv: apiKeyEnvOf(ns, entry.settingsPath),
        credential: null,
      );
    }).toList();

    // Batched credential describe over every referenced ref.
    final refs = <String>{
      for (final r in rows)
        if (r.apiKeyEnv != null) r.apiKeyEnv!,
    }.toList();
    Map<String, CredentialView> credentials = {};
    String? credentialError;
    if (refs.isNotEmpty) {
      try {
        final credValue = await client.credentialsDescribe(refs);
        final credsRaw = credValue['credentials'] as Map? ?? {};
        credsRaw.forEach((key, value) {
          if (value is Map) {
            credentials[key as String] = CredentialView.fromJson(
              value.cast<String, dynamic>(),
            );
          }
        });
      } catch (error) {
        credentialError = messageOf(error);
      }
    }

    if (generation != _generation) return;
    state = ModelsSettingsState(
      status: ModelsSettingsStatus.ready,
      error: null,
      credentialError: credentialError,
      writable: writable,
      rows: rows
          .map(
            (row) => row.apiKeyEnv != null && credentials[row.apiKeyEnv] != null
                ? row.copyWith(credential: credentials[row.apiKeyEnv])
                : row,
          )
          .toList(),
      namespaces: namespaces,
    );
  }
}

final modelsSettingsControllerProvider =
    NotifierProvider<ModelsSettingsController, ModelsSettingsState>(
      ModelsSettingsController.new,
    );
