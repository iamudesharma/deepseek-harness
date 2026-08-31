/// Activation lifecycle for [DshPlugin]s: fixpoint service-wait activation,
/// effect-tracked disposal, and loud unsatisfied-injection failure. The
/// Flutter analog of the cordis client runner's register/dispose fiber
/// discipline ([plugin.client-lifecycle] in migration/migration-tracker.json).
library;

import 'plugin_contract.dart';
import '../slots/slot_registry.dart';

class _Activation {
  _Activation(this.plugin);
  final DshPlugin plugin;
  final List<Disposer> disposers = [];
  final List<String> providedServices = [];
  bool applied = false;
}

/// Activation record exposed after [PluginHost.activateAll] for diagnostics.
class ActivatedPlugin {
  /// Wraps one activated plugin.
  const ActivatedPlugin({required this.id, required this.order});

  /// Plugin id.
  final String id;

  /// Zero-based position in the activation sequence.
  final int order;
}

/// Activates plugins in service-dependency order, mirroring cordis fiber
/// waiting: a plugin applies only once every injected service has a provider;
/// providers may arrive from earlier activations in the same pass.
///
/// At quiescence any unsatisfied plugin is a loud failure naming the missing
/// services and any cycle among them — the AOT analog of cordis staying
/// PENDING forever, made fail-loud because a desktop/web app boots once.
class PluginHost {
  final SlotRegistry _slots = SlotRegistry();
  final Map<String, Object> _services = {};
  final Map<String, _Activation> _activations = {};
  final List<DshPlugin> _registered = [];

  /// The ledger every plugin composes through.
  SlotRegistry get slots => _slots;

  /// Registers a plugin for the next [activateAll]; duplicate ids throw.
  void register(DshPlugin plugin) {
    if (_activations.containsKey(plugin.id) ||
        _registered.any((p) => p.id == plugin.id)) {
      throw StateError('plugin "${plugin.id}" is already registered');
    }
    _registered.add(plugin);
  }

  /// Publishes a host-level service before activation (shell-provided).
  void provide(String name, Object service) {
    if (_services.containsKey(name)) {
      throw StateError('service "$name" already provided');
    }
    _services[name] = service;
  }

  /// Whether [name] currently has a provider.
  bool hasService(String name) => _services.containsKey(name);

  /// Reads an activated service (diagnostics/tests): the same table
  /// [DshContext.get] reads.
  T? service<T>(String name) => _services[name] as T?;

  /// Runs the fixpoint activation pass over registered plugins.
  ///
  /// Returns activation records in application order. Throws [StateError]
  /// listing unsatisfied injections when no progress remains possible.
  Future<List<ActivatedPlugin>> activateAll() async {
    final pending = List.of(_registered);
    while (pending.isNotEmpty) {
      var progress = false;
      for (final plugin in List.of(pending)) {
        final missing = plugin.inject
            .where((name) => !_services.containsKey(name))
            .toList();
        if (missing.isNotEmpty) continue;
        await plugin.apply(_HostContext(this, _activationFor(plugin)));
        _activations[plugin.id]!.applied = true;
        pending.remove(plugin);
        progress = true;
      }
      if (!progress) {
        throw StateError(_unsatisfiedMessage(pending));
      }
    }
    return [
      for (final (index, activation) in _activations.values.indexed)
        ActivatedPlugin(id: activation.plugin.id, order: index),
    ];
  }

  _Activation _activationFor(DshPlugin plugin) =>
      _activations.putIfAbsent(plugin.id, () => _Activation(plugin));

  String _unsatisfiedMessage(List<DshPlugin> pending) {
    final lines = <String>[
      'plugin host: ${pending.length} plugin(s) could not activate:',
    ];
    for (final plugin in pending) {
      final missing = plugin.inject
          .where((name) => !_services.containsKey(name))
          .toList();
      lines.add(
        '  - "${plugin.id}" waits on '
        '${missing.isEmpty ? '(cycle among pending plugins)' : missing.map((m) => '"$m"').join(', ')}',
      );
    }
    return lines.join('\n');
  }

  /// Deactivates [pluginId] in reverse order: its disposers run, its
  /// contributions leave the ledger, and its provided services are removed —
  /// dependents keep running but a later `require` fails loud, mirroring
  /// fiber unload.
  void deactivate(String pluginId) {
    final activation = _activations.remove(pluginId);
    if (activation == null) return;
    for (final disposer in activation.disposers.reversed) {
      disposer();
    }
    for (final name in activation.providedServices) {
      _services.remove(name);
    }
  }

  /// Deactivates everything, last-activated first.
  void deactivateAll() {
    for (final id in _activations.keys.toList().reversed) {
      deactivate(id);
    }
  }
}

class _HostContext implements DshContext {
  _HostContext(this._host, this._activation);

  final PluginHost _host;
  final _Activation _activation;

  @override
  T require<T>(String name) {
    final service = get<T>(name);
    if (service == null) {
      throw StateError(
        'service "$name" is not provided (declare it in inject)',
      );
    }
    return service;
  }

  @override
  T? get<T>(String name) => _host._services[name] as T?;

  @override
  void provide(String name, Object service) {
    _host.provide(name, service);
    _activation.providedServices.add(name);
  }

  @override
  bool hasService(String name) => _host._services.containsKey(name);

  @override
  SlotRegistry get slots => _host._slots;

  @override
  void onDispose(Disposer disposer) => _activation.disposers.add(disposer);
}
