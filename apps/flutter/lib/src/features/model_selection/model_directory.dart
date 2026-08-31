import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';

/// Model selection for next step — mirrors `ModelSelection` in `dsh-api-remotes/client`.
class ModelSelection {
  final String provider;
  final String model;
  final String? reasoningEffort;
  const ModelSelection({
    required this.provider,
    required this.model,
    this.reasoningEffort,
  });
}

/// One provider group from `session.models` — `groups` entry.
class ModelProviderGroup {
  final String id;
  final String name;
  final List<ModelInfo> models;
  const ModelProviderGroup({
    required this.id,
    required this.name,
    required this.models,
  });
  factory ModelProviderGroup.fromJson(Map<String, dynamic> json) =>
      ModelProviderGroup(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? json['id'] as String? ?? '',
        models: (json['models'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((e) => ModelInfo.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

/// One reasoning-effort level advertised by a model.
class ModelReasoningEffort {
  final String id;
  final String name;
  final String? description;
  const ModelReasoningEffort({
    required this.id,
    required this.name,
    this.description,
  });
  factory ModelReasoningEffort.fromJson(Map<String, dynamic> json) =>
      ModelReasoningEffort(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? json['id'] as String? ?? '',
        description: json['description'] as String?,
      );
}

/// Reasoning metadata for a model — absent means no selectable effort.
class ModelReasoning {
  final List<ModelReasoningEffort> efforts;
  final String? defaultEffort;
  const ModelReasoning({required this.efforts, this.defaultEffort});
  factory ModelReasoning.fromJson(Map<String, dynamic> json) => ModelReasoning(
    efforts: (json['efforts'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => ModelReasoningEffort.fromJson(e.cast<String, dynamic>()))
        .toList(),
    defaultEffort: json['defaultEffort'] as String?,
  );
}

/// One model inside a provider group.
class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final ModelReasoning? reasoning;
  const ModelInfo({
    required this.id,
    required this.name,
    this.description,
    this.reasoning,
  });
  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? json['id'] as String? ?? '',
    description: json['description'] as String?,
    reasoning: json['reasoning'] is Map
        ? ModelReasoning.fromJson(
            (json['reasoning'] as Map).cast<String, dynamic>(),
          )
        : null,
  );
}

/// Directory snapshot both entries render from — mirrors `ModelDirectoryState`.
class ModelDirectoryState {
  final ModelSelection? current;
  final bool? routable;
  final List<ModelProviderGroup> groups;
  final List<dynamic> failures;
  final String status; // idle|loading|ready|selecting|error
  final String? error;
  const ModelDirectoryState({
    this.current,
    this.routable,
    this.groups = const [],
    this.failures = const [],
    this.status = 'idle',
    this.error,
  });
  ModelDirectoryState copyWith({
    ModelSelection? current,
    bool? clearCurrent,
    bool? routable,
    List<ModelProviderGroup>? groups,
    List<dynamic>? failures,
    String? status,
    String? error,
    bool clearError = false,
  }) => ModelDirectoryState(
    current: clearCurrent == true ? null : (current ?? this.current),
    routable: routable ?? this.routable,
    groups: groups ?? this.groups,
    failures: failures ?? this.failures,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Per-session shared directory — mirrors `ModelDirectory` in `directory.ts`.
class ModelDirectory extends StateNotifier<ModelDirectoryState> {
  final ConnectionClient _client;
  final SessionId _sessionId;
  int _generation = 0;
  bool _disposed = false;

  ModelDirectory(this._client, this._sessionId)
    : super(const ModelDirectoryState());

  Future<Map<String, dynamic>> load() async {
    if (_disposed) return <String, dynamic>{};
    final gen = ++_generation;
    if (_disposed) return <String, dynamic>{};
    state = state.copyWith(status: 'loading', clearError: true);
    try {
      // New global catalog (session/modelCatalog) + per-session current is now
      // derived from the modelSelection projection, but the old session.models
      // with sessionId still returns the per-session directory for backward compat
      // on hosts that haven't yet migrated. Try the new global catalog first,
      // fall back to the old per-session call.
      late Map<String, dynamic> value;
      try {
        final catalog = await _client.sessionModelCatalog();
        // catalog has {default, groups, failures, routableProviders}
        // For per-session current, we need the session's modelSelection projection.
        // If the host still supports the old session.models, prefer it for current.
        try {
          final perSession = await _client.sessionModels(sessionId: _sessionId.value);
          if (perSession.containsKey('current') || perSession.containsKey('groups')) {
            value = perSession;
          } else {
            value = {
              'current': catalog['default'],
              'groups': catalog['groups'],
              'failures': catalog['failures'],
              'routable': (catalog['routableProviders'] as List?)?.isNotEmpty ?? false,
            };
          }
        } catch (_) {
          value = {
            'current': catalog['default'],
            'groups': catalog['groups'],
            'failures': catalog['failures'],
            'routable': (catalog['routableProviders'] as List?)?.isNotEmpty ?? false,
          };
        }
      } catch (_) {
        // Fallback to old per-session endpoint if global catalog is not yet available
        value = await _client.sessionModels(sessionId: _sessionId.value);
      }
      if (_disposed || gen != _generation) return value;
      final currentJson = value['current'] as Map?;
      final current = currentJson == null
          ? null
          : ModelSelection(
              provider: currentJson['provider'] as String? ?? '',
              model: currentJson['model'] as String? ?? '',
              reasoningEffort: currentJson['reasoningEffort'] as String?,
            );
      final groups = (value['groups'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => ModelProviderGroup.fromJson(e.cast<String, dynamic>()))
          .toList();
      final failures = value['failures'] as List<dynamic>? ?? [];
      final routable = value['routable'] as bool?;
      state = state.copyWith(
        current: current,
        clearCurrent: current == null,
        routable: routable,
        groups: groups,
        failures: failures,
        status: 'ready',
        clearError: true,
      );
      return value;
    } catch (e) {
      if (_disposed || gen != _generation) rethrow;
      state = state.copyWith(status: 'error', error: e.toString());
      rethrow;
    }
  }

  Future<void> select(ModelSelection selection) async {
    if (_disposed) return;
    final gen = ++_generation;
    if (_disposed) return;
    state = state.copyWith(status: 'selecting', clearError: true);
    try {
      final value = await _client.sessionSelectModel(
        sessionId: _sessionId.value,
        provider: selection.provider,
        model: selection.model,
        reasoningEffort: selection.reasoningEffort,
      );
      if (_disposed || gen != _generation) return;
      final selected = value['selected'] as Map?;
      final ModelSelection next = selected == null
          ? selection
          : ModelSelection(
              provider: selected['provider'] as String? ?? selection.provider,
              model: selected['model'] as String? ?? selection.model,
              reasoningEffort:
                  selected['reasoningEffort'] as String? ??
                  selection.reasoningEffort,
            );
      state = state.copyWith(
        current: next,
        routable: true,
        status: 'ready',
        clearError: true,
      );
    } catch (e) {
      if (_disposed || gen != _generation) rethrow;
      state = state.copyWith(status: 'error', error: e.toString());
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

ModelSelection? _parseModelSelectionValue(Map<String, dynamic> json) {
  // Host `modelSelection` projection is `{lastUsed, next}` — show `next ?? lastUsed`.
  Map<String, dynamic>? pick(Map<String, dynamic>? node) {
    if (node == null) return null;
    final provider = node['provider'] as String?;
    final model = node['model'] as String?;
    if (provider == null || provider.isEmpty || model == null || model.isEmpty) return null;
    return {
      'provider': provider,
      'model': model,
      if (node['reasoningEffort'] is String) 'reasoningEffort': node['reasoningEffort'],
    };
  }

  final next = pick(json['next'] as Map<String, dynamic>?);
  if (next != null) {
    return ModelSelection(
      provider: next['provider'] as String,
      model: next['model'] as String,
      reasoningEffort: next['reasoningEffort'] as String?,
    );
  }
  final last = pick(json['lastUsed'] as Map<String, dynamic>?);
  if (last != null) {
    return ModelSelection(
      provider: last['provider'] as String,
      model: last['model'] as String,
      reasoningEffort: last['reasoningEffort'] as String?,
    );
  }
  // Fallback for direct ModelSelection shape (some test fixtures)
  final direct = pick(json);
  if (direct != null) {
    return ModelSelection(
      provider: direct['provider'] as String,
      model: direct['model'] as String,
      reasoningEffort: direct['reasoningEffort'] as String?,
    );
  }
  return null;
}

/// Authoritative per-session model selection from live projections.
///
/// Updated by `live_sync` from `session/follow` snapshot `projections.modelSelection`
/// and live `session/projection key:modelSelection` frames, matching React's
/// `session.projections.modelSelection` fold. Composer's model seat watches this
/// as the source of truth; `ModelDirectory` remains the catalog.
final modelSelectionProjectionProvider =
    StateProvider.family<ModelSelection?, String>((ref, sessionId) => null);

/// Resolver — one directory per session, like `ModelDirectoryResolver`.
final modelDirectoryProvider =
    StateNotifierProvider.family<ModelDirectory, ModelDirectoryState, String>((
      ref,
      sessionId,
    ) {
      final client = ref.watch(connectionClientProvider);
      final dir = ModelDirectory(client, SessionId(sessionId));
      ref.onDispose(dir.dispose);
      // Auto-load on first watch like React's `load()` on open.
      Future.microtask(() => dir.load().then((_) {}, onError: (_) {}));
      return dir;
    });
