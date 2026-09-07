/// Plugin contract face mirroring the browser-side cordis model of
/// `packages/client/*`: a plugin declares `apply(ctx)` plus the service names
/// it injects; activation waits on services, never on import order (the Dart
/// analog of the cordis fiber-wait — see `packages/client/AGENTS.md`,
/// "The module graph sits below cordis DI").
///
/// This is the Flutter replacement for the `dsh.client` capability registry
/// ([modules.client-plugin-loading] in migration/migration-tracker.json):
/// AOT compilation removes dynamic loading, so what remains is the declared
/// contract every plugin satisfies and the service table it composes through.
library;

import '../slots/slot_registry.dart';

/// Service table handed to [DshPlugin.apply]. Services are named exactly like
/// their React counterparts (`'slots'`, `'sessions'`, …) so cross-referencing
/// a plugin's `inject` list against the React source is mechanical.
abstract interface class DshContext {
  /// Reads a required service; throws [StateError] when absent. Only call for
  /// names this plugin declared in its inject list.
  T require<T>(String name);

  /// Reads an optional service, mirroring `ctx.get(name)` semantics.
  T? get<T>(String name);

  /// Publishes a service under [name] (cordis `ctx.provide`).
  void provide(String name, Object service);

  /// Whether [name] currently has a provider.
  bool hasService(String name);

  /// The composition ledger this host installs; equivalent to `ctx.slots`.
  SlotRegistry get slots;

  /// Registers a disposer that runs when this plugin deactivates — the fiber
  /// `ctx.effect` analog: every contribution a plugin makes during [DshPlugin.apply]
  /// must ride this so deactivation removes it.
  void onDispose(Disposer disposer);
}

/// One UI/business plugin: the Dart face of a client package's `apply` +
/// `inject` exports.
abstract class DshPlugin {
  /// Creates a plugin.
  const DshPlugin();

  /// Stable identifier (the React package name by convention).
  String get id;

  /// Service names this plugin waits on before [apply] runs.
  List<String> get inject => const [];

  /// Contributes registrations and services. Everything created here that must
  /// leave with the plugin registers through [DshContext.onDispose].
  Future<void> apply(DshContext ctx);
}
