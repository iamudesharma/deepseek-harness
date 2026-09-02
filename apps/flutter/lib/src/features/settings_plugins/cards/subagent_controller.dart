/// Subagent model-selection controller — Dart port of
/// `packages/client/ui-settings-plugins/src/client/subagent-model-selection-card-controller.ts`.
library;

import 'package:flutter/foundation.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/settings/settings_scope.dart';
import '../../model_selection/model_directory.dart';

String subagentModelKey({required String provider, required String model}) => '$provider\x00$model';

class AllowedSubagentModel {
  const AllowedSubagentModel({required this.provider, required this.model});
  final String provider;
  final String model;

  Map<String, Object?> toJson() => {'provider': provider, 'model': model};

  @override
  bool operator ==(Object other) =>
      other is AllowedSubagentModel && other.provider == provider && other.model == model;
  @override
  int get hashCode => Object.hash(provider, model);
}

class SubagentModelCandidate extends AllowedSubagentModel {
  const SubagentModelCandidate({
    required super.provider,
    required super.model,
    required this.key,
    required this.providerName,
    required this.modelName,
    required this.available,
    required this.selected,
  });

  final String key;
  final String providerName;
  final String modelName;
  final bool available;
  final bool selected;
}

List<SubagentModelCandidate> subagentModelCandidates({
  required List<ModelProviderGroup> groups,
  required List<AllowedSubagentModel> stored,
  required Set<String> selected,
}) {
  final Map<String, AllowedSubagentModel> storedByKey = {
    for (final r in stored) subagentModelKey(provider: r.provider, model: r.model): r,
  };
  final List<SubagentModelCandidate> out = [];
  for (final group in groups) {
    for (final model in group.models) {
      final String key = subagentModelKey(provider: group.id, model: model.id);
      storedByKey.remove(key);
      out.add(SubagentModelCandidate(
        provider: group.id,
        model: model.id,
        key: key,
        providerName: group.name,
        modelName: model.name,
        available: true,
        selected: selected.contains(key),
      ));
    }
  }
  for (final route in storedByKey.values) {
    final String key = subagentModelKey(provider: route.provider, model: route.model);
    out.add(SubagentModelCandidate(
      provider: route.provider,
      model: route.model,
      key: key,
      providerName: route.provider,
      modelName: route.model,
      available: false,
      selected: selected.contains(key),
    ));
  }
  return out;
}

bool _sameRoutes(List<AllowedSubagentModel> a, List<AllowedSubagentModel> b) {
  if (a.length != b.length) return false;
  final Set<String> bKeys = {for (final r in b) subagentModelKey(provider: r.provider, model: r.model)};
  return a.every((r) => bKeys.contains(subagentModelKey(provider: r.provider, model: r.model)));
}

class SubagentCardState {
  const SubagentCardState({
    required this.available,
    required this.writable,
    required this.dirty,
    required this.invalid,
    required this.saving,
    required this.failed,
    required this.enabled,
    required this.candidates,
    required this.catalogStatus,
    required this.catalogPartial,
    required this.conflicted,
  });

  final bool available;
  final bool writable;
  final bool dirty;
  final bool invalid;
  final bool saving;
  final bool failed;
  final bool enabled;
  final List<SubagentModelCandidate> candidates;
  final String catalogStatus; // idle|loading|ready|error
  final bool catalogPartial;
  final bool conflicted;
}

class SubagentController extends ChangeNotifier {
  SubagentController({
    required SettingsScope<Map<String, Object?>> scope,
    required ConnectionClient client,
  })  : _scope = scope,
        _client = client {
    _unsubscribe = _scope.subscribe((_) {
      if (!_saving && _draftRoutes != null && _scope.snapshot.revision != _draftRevision) {
        if (_currentEnabled() == _enabled() && _sameRoutes(_currentRoutes(), _desiredRoutes())) {
          _clearDraft();
        } else {
          _conflicted = true;
        }
      }
      if (_enabled() && _catalogStatus == 'idle') {
        unawaited(_loadCatalog());
      }
      notifyListeners();
    });
    if (_enabled() && _catalogStatus == 'idle') {
      unawaited(_loadCatalog());
    }
  }

  final SettingsScope<Map<String, Object?>> _scope;
  final ConnectionClient _client;
  VoidCallback? _unsubscribe;

  List<ModelProviderGroup> _catalogGroups = const [];
  bool _catalogPartial = false;
  String _catalogStatus = 'idle';
  bool? _draftEnabled;
  Map<String, AllowedSubagentModel>? _draftRoutes;
  int? _draftRevision;
  bool _saving = false;
  bool _failed = false;
  bool _conflicted = false;
  bool _disposed = false;
  int _saveGeneration = 0;
  int _catalogGeneration = 0;

  SubagentCardState get state {
    final snap = _scope.snapshot;
    final List<AllowedSubagentModel> current = _currentRoutes();
    final List<AllowedSubagentModel> desired = _desiredRoutes();
    final bool enabled = _enabled();
    return SubagentCardState(
      available: snap.status == SettingsScopeStatus.ready,
      writable: snap.writable,
      dirty: _currentEnabled() != enabled || !_sameRoutes(current, desired),
      invalid: enabled && desired.isEmpty,
      saving: _saving,
      failed: _failed,
      enabled: enabled,
      candidates: _candidates(),
      catalogStatus: _catalogStatus,
      catalogPartial: _catalogPartial,
      conflicted: _conflicted,
    );
  }

  List<AllowedSubagentModel> _currentRoutes() {
    final Object? v = _scope.snapshot.value;
    if (v is Map) {
      final Object? allowed = v['allowedModels'];
      if (allowed is List) {
        return allowed
            .whereType<Map>()
            .map((e) => AllowedSubagentModel(
                  provider: e['provider'] as String? ?? '',
                  model: e['model'] as String? ?? '',
                ))
            .where((r) => r.provider.isNotEmpty && r.model.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  bool _currentEnabled() {
    final Object? v = _scope.snapshot.value;
    if (v is Map) {
      final Object? e = v['enabled'];
      if (e is bool) return e;
    }
    return false;
  }

  Set<String> _selected() => {
        for (final k in (_draftRoutes?.keys ?? _currentRoutes().map((r) => subagentModelKey(provider: r.provider, model: r.model))))
          k,
      };

  bool _enabled() => _draftEnabled ?? _currentEnabled();

  Map<String, AllowedSubagentModel> _beginDraft() {
    if (_draftRoutes == null) {
      final snap = _scope.snapshot;
      _draftEnabled = snap.value is Map ? (snap.value as Map)['enabled'] as bool? ?? false : false;
      final List<AllowedSubagentModel> cur = _currentRoutes();
      _draftRoutes = {for (final r in cur) subagentModelKey(provider: r.provider, model: r.model): r};
      _draftRevision = snap.revision;
    }
    return _draftRoutes!;
  }

  List<SubagentModelCandidate> _candidates() {
    final Map<String, AllowedSubagentModel> retained = {
      for (final r in _currentRoutes()) subagentModelKey(provider: r.provider, model: r.model): r,
    };
    if (_draftRoutes != null) {
      for (final e in _draftRoutes!.entries) retained[e.key] = e.value;
    }
    return subagentModelCandidates(
      groups: _catalogGroups,
      stored: retained.values.toList(),
      selected: _selected(),
    );
  }

  List<AllowedSubagentModel> _desiredRoutes() => _draftRoutes?.values.toList() ?? _currentRoutes();

  void toggleEnabled() {
    final snap = _scope.snapshot;
    if (_disposed || snap.status != SettingsScopeStatus.ready || !snap.writable || _saving) return;
    _beginDraft();
    _draftEnabled = !(_draftEnabled ?? _currentEnabled());
    _failed = false;
    if (_draftEnabled == true && _catalogStatus == 'idle') {
      unawaited(_loadCatalog());
    }
    notifyListeners();
  }

  void toggleModel(String key) {
    if (!_enabled() || _saving || !_scope.snapshot.writable) return;
    final candidate = _candidates().where((c) => c.key == key).firstOrNull;
    if (candidate == null) return;
    final Map<String, AllowedSubagentModel> routes = _beginDraft();
    if (routes.containsKey(key)) {
      routes.remove(key);
    } else {
      routes[key] = AllowedSubagentModel(provider: candidate.provider, model: candidate.model);
    }
    _failed = false;
    notifyListeners();
  }

  void _clearDraft() {
    _draftEnabled = null;
    _draftRoutes = null;
    _draftRevision = null;
    _failed = false;
    _conflicted = false;
  }

  void discard() {
    if (_saving) return;
    _clearDraft();
    notifyListeners();
  }

  Future<void> save() async {
    final snap = _scope.snapshot;
    final bool desiredEnabled = _enabled();
    final List<AllowedSubagentModel> desired = _desiredRoutes();
    if (_disposed ||
        snap.status != SettingsScopeStatus.ready ||
        !snap.writable ||
        _saving ||
        (_currentEnabled() == desiredEnabled && _sameRoutes(_currentRoutes(), desired)) ||
        (desiredEnabled && desired.isEmpty)) {
      return;
    }
    if (_draftRoutes != null && snap.revision != _draftRevision) {
      _conflicted = true;
      notifyListeners();
      return;
    }
    final int gen = _saveGeneration;
    _saving = true;
    _failed = false;
    _conflicted = false;
    notifyListeners();
    try {
      final int? rev = _draftRevision;
      await _scope.mutateBatch(
        [
          {'op': 'set', 'path': ['enabled'], 'value': desiredEnabled},
          {
            'op': 'set',
            'path': ['allowedModels'],
            'value': desired.map((r) => r.toJson()).toList(),
          },
        ],
        expectedRevision: rev,
      );
    } catch (_) {
      await _scope.refreshFromDescribe();
    }
    if (gen != _saveGeneration || _disposed) return;
    final bool landed = _currentEnabled() == desiredEnabled && _sameRoutes(_currentRoutes(), desired);
    _saving = false;
    _failed = !landed;
    if (landed) _clearDraft();
    notifyListeners();
  }

  void retryCatalog() => unawaited(_loadCatalog());

  Future<void> _loadCatalog() async {
    if (_disposed || _catalogStatus == 'loading') return;
    final int gen = _catalogGeneration;
    _catalogStatus = 'loading';
    _catalogPartial = false;
    notifyListeners();
    try {
      final Map<String, dynamic> catalog = await _client.sessionModelCatalog();
      if (gen != _catalogGeneration || _disposed) return;
      final List<dynamic> groupsRaw = catalog['groups'] as List<dynamic>? ?? const [];
      final List<dynamic> failuresRaw = catalog['failures'] as List<dynamic>? ?? const [];
      _catalogGroups = groupsRaw
          .whereType<Map>()
          .map((e) => ModelProviderGroup.fromJson(e.cast<String, dynamic>()))
          .toList();
      _catalogPartial = failuresRaw.isNotEmpty;
      _catalogStatus = 'ready';
    } catch (_) {
      if (gen != _catalogGeneration || _disposed) return;
      _catalogStatus = 'error';
    }
    notifyListeners();
  }

  void refreshCatalog() {
    if (_disposed) return;
    _catalogGeneration++;
    _catalogStatus = 'idle';
    _catalogPartial = false;
    if (_enabled()) unawaited(_loadCatalog());
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveGeneration++;
    _catalogGeneration++;
    _unsubscribe?.call();
    super.dispose();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

// Helper to avoid importing `dart:async` unawaited lint.
void unawaited(Future<void> f) {}
