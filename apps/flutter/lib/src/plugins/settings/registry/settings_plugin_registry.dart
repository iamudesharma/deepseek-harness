/// Lightweight registry mirroring the React `settings.plugin.item` slot.
///
/// Any plugin can `register` a card descriptor keyed by its settings namespace;
/// the configurable tab renders `served ∩ registered` in [order].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/settings_plugins/card_form.dart';
import '../../../core/settings/settings_scope.dart';

/// Context passed to a card builder — the resolved [CardForm] for this
/// namespace plus helpers to read field state.
class PluginCardContext {
  const PluginCardContext({required this.form, required this.namespace});
  final CardForm<Map<String, Object?>> form;
  final String namespace;
}

/// Descriptor for one configurable card.
class SettingsPluginCardDescriptor {
  const SettingsPluginCardDescriptor({
    required this.namespace,
    required this.order,
    required this.title,
    required this.description,
    required this.fieldSpecs,
    this.secretSpecs = const [],
  });

  /// Settings namespace key — matches Host `settings.describe` entry.
  final String namespace;

  /// Visual order; lower first.
  final int order;

  final String title;
  final String description;

  /// Section fields this card edits.
  final List<CardFieldSpec> fieldSpecs;

  /// Write-only credential controls.
  final List<CardSecretSpec> secretSpecs;

  /// Build the card's body widget from [context].
  ///
  /// Default builder shows generic fields; callers can supply a custom builder
  /// by wrapping descriptor in a `customBuilder` variant if needed. For now,
  /// the built-in cards use this via `buildDefaultBody`.
  Widget buildDefaultBody(PluginCardContext ctx, void Function() onChanged) {
    // Implemented in consuming widget; keep descriptor pure.
    return const SizedBox.shrink();
  }
}

/// Global registry — single instance provided via Provider.
class SettingsPluginRegistry extends ChangeNotifier {
  final List<SettingsPluginCardDescriptor> _cards = [];

  void register(SettingsPluginCardDescriptor descriptor) {
    // Replace existing with same namespace.
    _cards.removeWhere((c) => c.namespace == descriptor.namespace);
    _cards.add(descriptor);
    _cards.sort((a, b) => a.order.compareTo(b.order));
    notifyListeners();
  }

  void unregister(String namespace) {
    _cards.removeWhere((c) => c.namespace == namespace);
    notifyListeners();
  }

  List<SettingsPluginCardDescriptor> get cards => List.unmodifiable(_cards);

  /// Visible namespaces: served ∩ registered, in registration order.
  List<SettingsPluginCardDescriptor> visibleFor(Set<String> served) =>
      _cards.where((c) => served.contains(c.namespace)).toList();
}

/// Factory for per-namespace scopes + forms keyed by namespace.
///
/// Keeps one [SettingsScope] per namespace and one [CardForm] over it.
class PluginCardFormStore {
  PluginCardFormStore({required this.settingsFaceFactory});

  /// Creates a SettingsScope for [namespace] using the provided factory.
  final SettingsScope<Map<String, Object?>> Function(String namespace) settingsFaceFactory;

  final Map<String, SettingsScope<Map<String, Object?>>> _scopes = {};
  final Map<String, CardForm<Map<String, Object?>>> _forms = {};

  SettingsScope<Map<String, Object?>> scopeFor(String namespace) =>
      _scopes.putIfAbsent(
        namespace,
        () {
          final scope = settingsFaceFactory(namespace);
          // Fire-and-forget initial describe so available is resolved.
          // ignore: discarded_futures
          scope.refreshFromDescribe();
          return scope;
        },
      );

  CardForm<Map<String, Object?>> formFor(SettingsPluginCardDescriptor descriptor) =>
      _forms.putIfAbsent(descriptor.namespace, () {
        final scope = scopeFor(descriptor.namespace);
        return CardForm<Map<String, Object?>>(
          scope: scope,
          specs: descriptor.fieldSpecs,
          secrets: descriptor.secretSpecs,
        );
      });

  Future<void> refreshAll() async {
    await Future.wait(_scopes.values.map((s) => s.refreshFromDescribe()));
  }

  void dispose() {
    _scopes.clear();
    _forms.clear();
  }
}

/// Provider for the global plugin-card registry (third-party extensibility).
///
/// Stock cards (shell/agent-loop/web-search/subagent) are hardcoded in
/// `PluginsTab` for now; this registry hosts additional cards that a plugin
/// outside the repo can register at runtime via
/// `ref.read(settingsPluginRegistryProvider).register(descriptor)`.
final settingsPluginRegistryProvider = Provider<SettingsPluginRegistry>((ref) {
  final registry = SettingsPluginRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});
